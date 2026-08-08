## Daemon management
##
## - macOS: launchd user agent (~/Library/LaunchAgents)
## - Linux: systemd user unit (~/.config/systemd/user)

import std/[os, osproc, strutils]

when defined(macosx):
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

  proc cmdDaemon*(sub: string) =
    case sub
    of "install":
      # Generate, place, and load plist
      createDir(getHomeDir() / plistDir)
      createDir(getHomeDir() / logDir)
      writeFile(plistPath(), generatePlist())
      # Symlink into LaunchAgents
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
      # Regenerate plist (handles binary path updates)
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

elif defined(linux):
  const
    unitName = "wtsync.service"
    unitDirRel = ".config/systemd/user"

  proc unitDir(): string =
    getHomeDir() / unitDirRel

  proc unitPath(): string =
    unitDir() / unitName

  proc generateUnit(): string =
    let bin = getAppFilename()
    result = """[Unit]
Description=wtsync - auto-sync workspace/ symlinks for git worktrees

[Service]
Type=simple
ExecStart=""" & bin & """ watch
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
"""

  proc systemctl(args: varargs[string]): int =
    let p = startProcess("systemctl", args = @["--user"] & @args,
                         options = {poUsePath, poParentStreams})
    result = p.waitForExit
    p.close()

  proc writeUnit() =
    createDir(unitDir())
    writeFile(unitPath(), generateUnit())
    discard systemctl("daemon-reload")

  proc lingerHint() =
    ## Without linger, a user unit is stopped when the last session of the
    ## user ends, which is not what a background watcher wants.
    let user = getEnv("USER", getEnv("LOGNAME"))
    if user.len > 0:
      echo "hint: `loginctl enable-linger ", user,
           "` keeps it running without an active login session"

  proc cmdDaemon*(sub: string) =
    case sub
    of "install":
      writeUnit()
      if systemctl("enable", "--now", unitName) == 0:
        echo "installed and started"
        lingerHint()
      else:
        echo "installed but failed to start"

    of "uninstall":
      discard systemctl("disable", "--now", unitName)
      if fileExists(unitPath()):
        removeFile(unitPath())
      discard systemctl("daemon-reload")
      echo "uninstalled"

    of "restart":
      # Regenerate the unit (handles binary path updates)
      writeUnit()
      if systemctl("restart", unitName) == 0:
        echo "restarted"
      else:
        echo "failed to restart"

    of "status":
      let (output, exitCode) = execCmdEx(
        "systemctl --user show " & unitName &
        " --property=ActiveState --property=MainPID")
      if exitCode != 0:
        echo "not running"
        return
      var activeState, mainPid = ""
      for line in output.splitLines:
        if line.startsWith("ActiveState="):
          activeState = line.split('=', 1)[1].strip()
        elif line.startsWith("MainPID="):
          mainPid = line.split('=', 1)[1].strip()
      case activeState
      of "active":
        if mainPid.len > 0 and mainPid != "0":
          echo "running (pid ", mainPid, ")"
        else:
          echo "active"
      of "activating", "deactivating", "failed":
        echo activeState
      else:
        echo "not running"

    of "log":
      let (output, exitCode) = execCmdEx(
        "journalctl --user -u " & unitName & " -n 200 --no-pager")
      if exitCode == 0 and output.strip().len > 0:
        echo output
      else:
        echo "no log"

    else:
      echo "Usage: wtsync daemon {install|uninstall|restart|status|log}"
      quit(1)

else:
  proc cmdDaemon*(sub: string) =
    quit("daemon is only supported on macOS and Linux", 1)
