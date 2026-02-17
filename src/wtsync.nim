## wtsync - auto-sync workspace/ symlinks for git worktrees
##
## watch モードで ~/projects/ を FSEvents 監視し、
## ディレクトリ作成時に自動で workspace/ symlink を作成する。

import std/[os, strutils, osproc]
import wtsync/[core, fsevents]

const Version = "0.1.0"

# ============================================================================
# watch コマンド - FSEvents 監視
# ============================================================================

type
  WatchContext = object
    root: string

proc onFSEvent(
  streamRef: ConstFSEventStreamRef,
  clientCallBackInfo: pointer,
  numEvents: csize_t,
  eventPaths: pointer,
  eventFlags: ptr FSEventStreamEventFlags,
  eventIds: ptr FSEventStreamEventId
) {.cdecl, gcsafe.} =
  # SAFETY: WatchContext はスタック上に生存（startWatch がブロッキング）。
  # Nim ORC/ARC は非移動GCのため raw pointer 経由のアクセスは安全。
  let root = cast[ptr WatchContext](clientCallBackInfo).root
  let paths = cast[ptr UncheckedArray[cstring]](eventPaths)
  let flags = cast[ptr UncheckedArray[FSEventStreamEventFlags]](eventFlags)

  for i in 0..<numEvents:
    let eventFlag = flags[i]
    let eventPath = $paths[i]
    let isCreated = (eventFlag and kFSEventStreamEventFlagItemCreated) != 0

    when defined(debug):
      let hexFlag = "0x" & cast[uint32](eventFlag).toHex(8)
      stderr.writeLine "[debug] ", eventPath, " flags=", hexFlag

    if not isCreated:
      continue

    let isDir = (eventFlag and kFSEventStreamEventFlagItemIsDir) != 0
    let isFile = (eventFlag and kFSEventStreamEventFlagItemIsFile) != 0
    let name = eventPath.extractFilename

    # Case 1: .git ファイルが作成された → Worktree 完成の合図
    # git worktree add は dir作成 → .git ファイル書き込みの順で動く
    if isFile and name == ".git":
      let worktreeDir = eventPath.parentDir
      if isWorktree(worktreeDir):
        let r = check(worktreeDir)
        if fix(r):
          echo "linked: ", worktreeDir.extractFilename, "/workspace -> ", r.mainRepo, "/workspace"
      continue

    # Case 2: workspace/ ディレクトリが作られた → 本体リポの workspace/ 新規作成
    # → その本体リポに属する全 Worktree に symlink を貼る
    if isDir and name == "workspace":
      let parentDir = eventPath.parentDir
      if dirExists(parentDir / ".git"):
        let worktrees = findWorktreesForMainRepo(parentDir, root)
        for wt in worktrees:
          let r = check(wt)
          if fix(r):
            echo "linked: ", wt.extractFilename, "/workspace -> ", r.mainRepo, "/workspace"

proc cmdWatch(root: string) =
  let resolvedRoot = expandFilename(root)
  var ctx = WatchContext(root: resolvedRoot)
  echo "wtsync: watching ", resolvedRoot
  startWatch(resolvedRoot, onFSEvent, addr ctx, latency = 0.3)

# ============================================================================
# CLI コマンド
# ============================================================================

proc cmdCheck(path: string) =
  let absPath = if path.isAbsolute: path else: getCurrentDir() / path
  let r = check(absPath.normalizedPath)
  if fix(r):
    echo "linked: ", r.path, "/workspace -> ", r.mainRepo, "/workspace"

proc cmdFix(root: string) =
  var fixed, scanned = 0
  for dir in findAllDirs(root):
    scanned.inc
    let r = check(dir)
    if fix(r):
      fixed.inc
      let label = if r.state == wsBrokenLink: "relinked" else: "linked"
      echo label, ": ", dir.extractFilename, " -> ", r.mainRepo, "/workspace"
    elif r.state == wsRealDirExists:
      echo "WARN: ", dir.extractFilename, " has real workspace/ dir (not symlink)"
  echo fixed, " fixed / ", scanned, " scanned"

proc cmdStatus(root: string) =
  for dir in findAllDirs(root):
    if not isWorktree(dir):
      continue
    let r = check(dir)
    let name = dir.extractFilename
    case r.state
    of wsAlreadyLinked:
      echo "[OK]      ", name
    of wsNeedsLink:
      echo "[MISSING] ", name, " -> ", r.mainRepo, "/workspace"
    of wsRealDirExists:
      echo "[WARN]    ", name, " (real dir, not symlink)"
    of wsBrokenLink:
      echo "[BROKEN]  ", name, " (symlink target mismatch)"
    of wsNoWorkspace:
      echo "[SKIP]    ", name, " (main has no workspace/)"
    else:
      echo "[SKIP]    ", name

# ============================================================================
# daemon コマンド - launchd 管理
# ============================================================================

const
  plistLabel = "com.wtsync.watch"
  plistDir = ".local/share/wtsync"
  plistName = "com.wtsync.watch.plist"
  logDir = ".local/var/log"

proc plistPath(): string =
  getHomeDir() / plistDir / plistName

proc agentPath(): string =
  getHomeDir() / "Library/LaunchAgents" / plistName

proc xmlEscape(s: string): string =
  s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

proc generatePlist(): string =
  let bin = getAppFilename()
  let logBase = getHomeDir() / logDir
  result = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>""" & xmlEscape(plistLabel) & """</string>
    <key>ProgramArguments</key>
    <array>
        <string>""" & xmlEscape(bin) & """</string>
        <string>watch</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>""" & xmlEscape(logBase / "wtsync.log") & """</string>
    <key>StandardErrorPath</key>
    <string>""" & xmlEscape(logBase / "wtsync.err") & """</string>
</dict>
</plist>
"""

proc launchctl(args: varargs[string]): int =
  let p = startProcess("launchctl", args = @args, options = {poUsePath})
  result = p.waitForExit
  p.close()

proc cmdDaemon(sub: string) =
  case sub
  of "install":
    # plist生成・配置・ロード
    createDir(getHomeDir() / plistDir)
    createDir(getHomeDir() / logDir)
    writeFile(plistPath(), generatePlist())
    # LaunchAgents にシンボリックリンク
    let agent = agentPath()
    if symlinkExists(agent) or fileExists(agent):
      removeFile(agent)
    createSymlink(plistPath(), agent)
    if launchctl("load", agent) == 0:
      echo "installed and started"
    else:
      echo "installed but failed to start"

  of "uninstall":
    let agent = agentPath()
    if fileExists(agent) or symlinkExists(agent):
      discard launchctl("unload", agent)
      removeFile(agent)
    let plist = plistPath()
    if fileExists(plist):
      removeFile(plist)
    echo "uninstalled"

  of "restart":
    let agent = agentPath()
    discard launchctl("unload", agent)
    # plist再生成（バイナリパス更新に対応）
    createDir(getHomeDir() / plistDir)
    createDir(getHomeDir() / logDir)
    writeFile(plistPath(), generatePlist())
    if not symlinkExists(agent) and not fileExists(agent):
      createSymlink(plistPath(), agent)
    if launchctl("load", agent) == 0:
      echo "restarted"
    else:
      echo "failed to restart"

  of "status":
    let (output, exitCode) = execCmdEx("launchctl list")
    if exitCode == 0:
      for line in output.splitLines:
        if plistLabel in line:
          let parts = line.strip().split('\t')
          if parts.len >= 1 and parts[0] != "-":
            echo "running (pid ", parts[0], ")"
          else:
            echo "loaded but not running"
          return
    echo "not running"

  of "log":
    let logFile = getHomeDir() / logDir / "wtsync.log"
    if fileExists(logFile):
      echo readFile(logFile)
    else:
      echo "no log file"

  else:
    echo "Usage: wtsync daemon {install|uninstall|restart|status|log}"
    quit(1)

# ============================================================================
# main
# ============================================================================

proc printUsage() =
  echo "wtsync - auto-sync workspace/ symlinks for git worktrees"
  echo ""
  echo "Usage:"
  echo "  wtsync check [path]          Check/fix single directory (default: cwd)"
  echo "  wtsync fix [root]            Scan and fix all worktrees under root"
  echo "  wtsync status [root]         Show status of all worktrees (read-only)"
  echo "  wtsync watch [root]          Watch for new worktrees and auto-link"
  echo "  wtsync daemon install        Install and start launchd daemon"
  echo "  wtsync daemon uninstall      Stop and remove daemon"
  echo "  wtsync daemon restart        Restart daemon (reflects binary updates)"
  echo "  wtsync daemon status         Show daemon status"
  echo "  wtsync daemon log            Show daemon log"
  echo ""
  echo "Default root: ~/projects"

proc main() =
  let args = commandLineParams()

  if args.len == 0:
    printUsage()
    quit(0)

  let cmd = args[0]

  if cmd in ["-h", "--help"]:
    printUsage()
    quit(0)

  if cmd in ["-V", "--version"]:
    echo "wtsync ", Version
    quit(0)

  let defaultRoot = getHomeDir() / "projects"

  case cmd
  of "check":
    let path = if args.len > 1: args[1] else: getCurrentDir()
    cmdCheck(path)
  of "fix":
    let root = if args.len > 1: args[1] else: defaultRoot
    cmdFix(root)
  of "status":
    let root = if args.len > 1: args[1] else: defaultRoot
    cmdStatus(root)
  of "watch":
    let root = if args.len > 1: args[1] else: defaultRoot
    cmdWatch(root)
  of "daemon":
    let sub = if args.len > 1: args[1] else: ""
    cmdDaemon(sub)
  else:
    echo "Unknown command: ", cmd
    quit(1)

when isMainModule:
  main()
