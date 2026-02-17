## wtsync core logic - worktree workspace/ symlink management

import std/[os, strutils]

type
  WorktreeState* = enum
    wsNotWorktree
    wsNoMainRepo
    wsNoWorkspace
    wsAlreadyLinked
    wsBrokenLink
    wsRealDirExists
    wsNeedsLink

  CheckResult* = object
    path*: string
    mainRepo*: string
    state*: WorktreeState

proc resolveMainRepo*(worktreePath: string): string =
  let gitFile = worktreePath / ".git"
  if not fileExists(gitFile):
    return ""
  let content = readFile(gitFile).strip()
  if not content.startsWith("gitdir:"):
    return ""
  var gitdir = content["gitdir:".len..^1].strip()
  # Resolve relative paths based on the worktree directory
  if not gitdir.isAbsolute:
    gitdir = worktreePath / gitdir
  # .git/worktrees/name → .git → repo root
  let raw = gitdir.parentDir.parentDir.parentDir
  try:
    result = expandFilename(raw)
  except OSError:
    result = normalizedPath(raw)

proc isWorktree*(path: string): bool =
  let gitPath = path / ".git"
  fileExists(gitPath) and not dirExists(gitPath)

proc check*(path: string): CheckResult =
  result.path = path
  if not isWorktree(path):
    result.state = wsNotWorktree
    return
  let mainRepo = resolveMainRepo(path)
  if mainRepo.len == 0:
    result.state = wsNoMainRepo
    return
  result.mainRepo = mainRepo
  let mainWorkspace = mainRepo / "workspace"
  if not dirExists(mainWorkspace):
    result.state = wsNoWorkspace
    return
  let wtWorkspace = path / "workspace"
  if symlinkExists(wtWorkspace):
    try:
      let target = expandSymlink(wtWorkspace)
      let absTarget = if target.isAbsolute: target
                      else: normalizedPath(wtWorkspace.parentDir / target)
      # Use expandFilename for comparison to resolve symlinks like /tmp -> /private/tmp
      let resolvedTarget = try: expandFilename(absTarget)
                           except OSError: normalizedPath(absTarget)
      let resolvedExpected = try: expandFilename(mainWorkspace)
                             except OSError: normalizedPath(mainWorkspace)
      if resolvedTarget == resolvedExpected:
        result.state = wsAlreadyLinked
      else:
        result.state = wsBrokenLink
    except OSError:
      result.state = wsBrokenLink
    return
  if dirExists(wtWorkspace):
    result.state = wsRealDirExists
    return
  result.state = wsNeedsLink

proc fix*(r: CheckResult): bool =
  case r.state
  of wsNeedsLink:
    createSymlink(r.mainRepo / "workspace", r.path / "workspace")
    return true
  of wsBrokenLink:
    removeFile(r.path / "workspace")
    createSymlink(r.mainRepo / "workspace", r.path / "workspace")
    return true
  else:
    return false

proc findAllDirs*(root: string): seq[string] =
  ## Recursively walks directories. Skips hidden directories.
  ## Does not recurse into git repositories or worktrees.
  for kind, path in walkDir(root):
    if kind != pcDir and kind != pcLinkToDir:
      continue
    if path.extractFilename.startsWith("."):
      continue
    result.add(path)
    # No need to recurse into git repositories/worktrees
    let gitPath = path / ".git"
    if not fileExists(gitPath) and not dirExists(gitPath):
      result.add(findAllDirs(path))

proc findWorktreesForMainRepo*(mainRepo: string, searchRoot: string): seq[string] =
  ## Recursively finds all worktrees belonging to the specified main repository
  let normalizedMain = try: expandFilename(mainRepo)
                       except OSError: normalizedPath(mainRepo)
  for dir in findAllDirs(searchRoot):
    if not isWorktree(dir):
      continue
    let resolved = resolveMainRepo(dir)
    if resolved == normalizedMain:
      result.add(dir)
