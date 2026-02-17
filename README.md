# wtsync

A tool that automatically manages `workspace/` symlinks for git worktrees.

When you create a worktree with `git worktree add`, wtsync automatically creates and repairs symlinks pointing to the main repository's `workspace/` directory. It also supports persistent monitoring via macOS FSEvents.

## Installation

```bash
nimble build
cp bin/wtsync ~/.local/bin/
```

Or:

```bash
nimble install_local
```

**Requirements**: Nim >= 2.2.6, macOS (uses FSEvents API)

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

## Daemon (launchd)

```bash
wtsync daemon install      # Install and start
wtsync daemon uninstall    # Stop and remove
wtsync daemon restart      # Restart (after binary update)
wtsync daemon status       # Show running status
wtsync daemon log          # Show logs
```

## How It Works

1. Reads the `gitdir:` entry from the worktree's `.git` file to resolve the main repository path
2. If the main repo has a `workspace/` directory, creates a symlink in the worktree
3. In `watch` mode, monitors directory creation events via FSEvents and links in real-time

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
