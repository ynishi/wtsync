# wtsync

A tool that automatically manages `workspace/` symlinks for git worktrees.

When you create a worktree with `git worktree add`, wtsync automatically creates and repairs symlinks pointing to the main repository's `workspace/` directory. It also supports persistent monitoring — FSEvents on macOS, inotify on Linux.

## Installation

```bash
nimble build
cp bin/wtsync ~/.local/bin/
```

Or:

```bash
nimble install_local
```

**Requirements**: Nim >= 2.2.6, and either macOS (FSEvents) or Linux (inotify)

## Usage

```bash
# Check/fix a single directory
wtsync check [path]

# Scan and fix all worktrees under ~/projects
wtsync fix [root]

# Show status of all worktrees (read-only)
wtsync status [root]

# Watch for new worktrees via FSEvents and auto-link
wtsync watch [root]
```

Default `root` is `~/projects`.

## Daemon

The same subcommands drive a launchd user agent on macOS and a systemd user unit on Linux.

```bash
wtsync daemon install      # Install and start
wtsync daemon uninstall    # Stop and remove
wtsync daemon restart      # Restart (after binary update)
wtsync daemon status       # Show running status
wtsync daemon log          # Show logs
```

| | macOS | Linux |
|---|---|---|
| Service file | `~/Library/LaunchAgents/com.wtsync.watch.plist` | `~/.config/systemd/user/wtsync.service` |
| Manager | `launchctl` | `systemctl --user` |
| Logs | `~/.local/var/log/wtsync.log` | `journalctl --user -u wtsync.service` |

On Linux, a user unit stops when your last login session ends. To keep it running:

```bash
loginctl enable-linger "$USER"
```

## How It Works

1. Reads the `gitdir:` entry from the worktree's `.git` file to resolve the main repository path
2. If the main repo has a `workspace/` directory, creates a symlink in the worktree
3. In `watch` mode, monitors creation events and links in real-time

### Watch Backends

| Platform | API | Notes |
|----------|-----|-------|
| macOS | FSEvents | Recursive by nature — one stream covers the whole root |
| Linux | inotify | One watch per directory. Watches are seeded from the existing tree and added as new directories appear; a fresh directory is also scanned once so entries written before its watch was installed (such as the `.git` file `git worktree add` writes) are not missed |

### State Definitions

| State | Meaning |
|-------|---------|
| `wsAlreadyLinked` | Correct symlink exists |
| `wsNeedsLink` | Symlink missing — `fix` will create it |
| `wsBrokenLink` | Symlink target is wrong — `fix` will recreate it |
| `wsRealDirExists` | A real directory exists (warning only) |
| `wsNoWorkspace` | Main repo has no workspace/ (skipped) |

## License

MIT
