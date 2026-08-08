## wtsync - auto-sync workspace/ symlinks for git worktrees
##
## Monitors ~/projects/ in watch mode (FSEvents on macOS, inotify on Linux),
## automatically creating workspace/ symlinks on directory creation.

import std/os
import wtsync/[core, daemon, watcher]

const Version = "0.1.0"

# ============================================================================
# watch command - filesystem monitoring
# ============================================================================

proc onCreated(root, path: string, isDir: bool) =
  let name = path.extractFilename

  # Case 1: .git file was created — signals worktree completion
  # git worktree add creates the dir first, then writes the .git file
  if not isDir and name == ".git":
    let worktreeDir = path.parentDir
    if isWorktree(worktreeDir):
      let r = check(worktreeDir)
      if fix(r):
        echo "linked: ", worktreeDir.extractFilename, "/workspace -> ", r.mainRepo, "/workspace"
        flushFile(stdout)
    return

  # Case 2: workspace/ directory was created — new workspace/ in the main repo
  # → Create symlinks in all worktrees belonging to that main repo
  if isDir and name == "workspace":
    let parentDir = path.parentDir
    if dirExists(parentDir / ".git"):
      let worktrees = findWorktreesForMainRepo(parentDir, root)
      for wt in worktrees:
        let r = check(wt)
        if fix(r):
          echo "linked: ", wt.extractFilename, "/workspace -> ", r.mainRepo, "/workspace"
          flushFile(stdout)

proc cmdWatch(root: string) =
  let resolvedRoot = expandFilename(root)
  echo "wtsync: watching ", resolvedRoot
  flushFile(stdout)
  watch(resolvedRoot, proc(path: string, isDir: bool) =
    onCreated(resolvedRoot, path, isDir), latency = 0.3)

# ============================================================================
# CLI commands
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
  echo "  wtsync daemon install        Install and start daemon (launchd/systemd)"
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
