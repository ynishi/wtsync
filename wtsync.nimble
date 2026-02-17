# Package

version       = "0.1.0"
author        = "Yutaka Nishimura"
description   = "Auto-sync workspace/ symlinks for git worktrees"
license       = "MIT"
srcDir        = "src"
bin           = @["wtsync"]
binDir        = "bin"


# Dependencies

requires "nim >= 2.2.6"

task test, "Run tests":
  exec "nim c -r --path:src tests/test_wtsync.nim"

task build, "Build binary":
  exec "nim c -d:release --path:src -o:bin/wtsync src/wtsync.nim"

task install_local, "Build and copy to ~/.local/bin":
  exec "nim c -d:release --path:src -o:bin/wtsync src/wtsync.nim"
  exec "cp bin/wtsync ~/.local/bin/wtsync"
