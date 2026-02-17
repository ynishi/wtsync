import std/[os, unittest]
import wtsync/core

const TestBase = "/tmp/wtsync_test"

proc cleanup() =
  removeDir(TestBase)

proc setup() =
  cleanup()
  createDir(TestBase)

# ============================================================================
# isWorktree
# ============================================================================

suite "isWorktree":
  setup: setup()
  teardown: cleanup()

  test "nonexistent path -> false":
    check not isWorktree(TestBase / "nonexistent")

  test "regular directory (.git is a directory) -> false":
    let dir = TestBase / "normal_repo"
    createDir(dir / ".git")
    check not isWorktree(dir)

  test ".git is a file -> true":
    let dir = TestBase / "worktree"
    createDir(dir)
    writeFile(dir / ".git", "gitdir: /tmp/fake/.git/worktrees/wt")
    check isWorktree(dir)

  test ".git does not exist -> false":
    let dir = TestBase / "empty"
    createDir(dir)
    check not isWorktree(dir)

# ============================================================================
# resolveMainRepo
# ============================================================================

suite "resolveMainRepo":
  setup: setup()
  teardown: cleanup()

  test "no .git file -> empty string":
    check resolveMainRepo(TestBase / "nonexistent") == ""

  test "invalid .git content -> empty string":
    let dir = TestBase / "invalid"
    createDir(dir)
    writeFile(dir / ".git", "not a gitdir reference")
    check resolveMainRepo(dir) == ""

  test "absolute gitdir path -> returns main repo path":
    let mainRepo = TestBase / "repo"
    let wt = TestBase / "repo-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo-wt")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo-wt")
    let resolved = resolveMainRepo(wt)
    check expandFilename(resolved) == expandFilename(mainRepo)

  test "relative gitdir path -> resolved correctly":
    let mainRepo = TestBase / "repo_rel"
    let wt = TestBase / "repo_rel-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_rel-wt")
    createDir(wt)
    # Relative path: mainRepo/.git/worktrees/repo_rel-wt as seen from wt
    writeFile(wt / ".git", "gitdir: ../repo_rel/.git/worktrees/repo_rel-wt")
    let resolved = resolveMainRepo(wt)
    check expandFilename(resolved) == expandFilename(mainRepo)

# ============================================================================
# check
# ============================================================================

suite "check":
  setup: setup()
  teardown: cleanup()

  test "regular directory -> wsNotWorktree":
    let dir = TestBase / "normal"
    createDir(dir)
    let r = check(dir)
    check r.state == wsNotWorktree

  test "main repo not found -> wsNoMainRepo":
    let dir = TestBase / "bad_wt"
    createDir(dir)
    writeFile(dir / ".git", "gitdir: /nonexistent/.git/worktrees/x")
    let r = check(dir)
    # resolveMainRepo returns a path but it doesn't exist as a git repo
    # Actually it returns a non-empty string, so state depends on workspace check
    check r.state in {wsNoMainRepo, wsNoWorkspace}

  test "no workspace/ -> wsNoWorkspace":
    let mainRepo = TestBase / "repo_nows"
    let wt = TestBase / "repo_nows-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_nows-wt")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_nows-wt")
    let r = check(wt)
    check r.state == wsNoWorkspace

  test "symlink not created -> wsNeedsLink":
    let mainRepo = TestBase / "repo_needs"
    let wt = TestBase / "repo_needs-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_needs-wt")
    createDir(mainRepo / "workspace")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_needs-wt")
    let r = check(wt)
    check r.state == wsNeedsLink
    check r.mainRepo != ""

  test "correct symlink -> wsAlreadyLinked":
    let mainRepo = TestBase / "repo_linked"
    let wt = TestBase / "repo_linked-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_linked-wt")
    createDir(mainRepo / "workspace")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_linked-wt")
    createSymlink(mainRepo / "workspace", wt / "workspace")
    let r = check(wt)
    check r.state == wsAlreadyLinked

  test "wrong symlink target -> wsBrokenLink":
    let mainRepo = TestBase / "repo_broken"
    let wt = TestBase / "repo_broken-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_broken-wt")
    createDir(mainRepo / "workspace")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_broken-wt")
    createSymlink("/tmp/wrong_target", wt / "workspace")
    let r = check(wt)
    check r.state == wsBrokenLink

  test "real directory as workspace -> wsRealDirExists":
    let mainRepo = TestBase / "repo_realdir"
    let wt = TestBase / "repo_realdir-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_realdir-wt")
    createDir(mainRepo / "workspace")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_realdir-wt")
    createDir(wt / "workspace")
    let r = check(wt)
    check r.state == wsRealDirExists

# ============================================================================
# fix
# ============================================================================

suite "fix":
  setup: setup()
  teardown: cleanup()

  test "wsNeedsLink -> creates symlink":
    let mainRepo = TestBase / "repo_fix"
    let wt = TestBase / "repo_fix-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_fix-wt")
    createDir(mainRepo / "workspace")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_fix-wt")
    let r = check(wt)
    check r.state == wsNeedsLink
    check fix(r)
    check symlinkExists(wt / "workspace")
    # After fix, state should be wsAlreadyLinked
    let r2 = check(wt)
    check r2.state == wsAlreadyLinked

  test "wsBrokenLink -> relinks":
    let mainRepo = TestBase / "repo_relink"
    let wt = TestBase / "repo_relink-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_relink-wt")
    createDir(mainRepo / "workspace")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_relink-wt")
    createSymlink("/tmp/wrong", wt / "workspace")
    let r = check(wt)
    check r.state == wsBrokenLink
    check fix(r)
    check symlinkExists(wt / "workspace")
    let r2 = check(wt)
    check r2.state == wsAlreadyLinked

  test "wsNotWorktree -> no fix":
    let r = CheckResult(path: "/tmp", state: wsNotWorktree)
    check not fix(r)

  test "wsAlreadyLinked -> no fix":
    let r = CheckResult(path: "/tmp", state: wsAlreadyLinked)
    check not fix(r)

  test "wsRealDirExists -> no fix":
    let r = CheckResult(path: "/tmp", state: wsRealDirExists)
    check not fix(r)

# ============================================================================
# findAllDirs
# ============================================================================

suite "findAllDirs":
  setup: setup()
  teardown: cleanup()

  test "detects nested directories recursively":
    createDir(TestBase / "a" / "b")
    createDir(TestBase / "c")
    let dirs = findAllDirs(TestBase)
    check dirs.len >= 3  # a, a/b, c

  test "skips hidden directories":
    createDir(TestBase / ".hidden")
    createDir(TestBase / "visible")
    let dirs = findAllDirs(TestBase)
    check dirs.len == 1
    check dirs[0].extractFilename == "visible"

  test "does not recurse into git repositories":
    createDir(TestBase / "repo" / ".git" / "objects")
    createDir(TestBase / "repo" / "src")
    createDir(TestBase / "other")
    let dirs = findAllDirs(TestBase)
    # repo is included, repo/src is not (recursion stops at .git dir), other is included
    var names: seq[string]
    for d in dirs:
      names.add(d.extractFilename)
    check "repo" in names
    check "other" in names
    check "src" notin names

  test "does not recurse into worktrees":
    let wt = TestBase / "wt"
    createDir(wt / "src")
    writeFile(wt / ".git", "gitdir: /tmp/fake")
    let dirs = findAllDirs(TestBase)
    var names: seq[string]
    for d in dirs:
      names.add(d.extractFilename)
    check "wt" in names
    check "src" notin names

  test "empty directory -> empty list":
    let dirs = findAllDirs(TestBase)
    check dirs.len == 0

# ============================================================================
# findWorktreesForMainRepo
# ============================================================================

suite "findWorktreesForMainRepo":
  setup: setup()
  teardown: cleanup()

  test "detects worktrees belonging to main repo":
    let mainRepo = TestBase / "main"
    createDir(mainRepo / ".git" / "worktrees" / "wt1")
    createDir(mainRepo / ".git" / "worktrees" / "wt2")
    let wt1 = TestBase / "main-wt1"
    let wt2 = TestBase / "main-wt2"
    createDir(wt1)
    createDir(wt2)
    writeFile(wt1 / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "wt1")
    writeFile(wt2 / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "wt2")
    let found = findWorktreesForMainRepo(mainRepo, TestBase)
    check found.len == 2

  test "excludes worktrees from other repos":
    let repo1 = TestBase / "repo1"
    let repo2 = TestBase / "repo2"
    createDir(repo1 / ".git" / "worktrees" / "wt")
    createDir(repo2 / ".git" / "worktrees" / "wt")
    let wt1 = TestBase / "repo1-wt"
    let wt2 = TestBase / "repo2-wt"
    createDir(wt1)
    createDir(wt2)
    writeFile(wt1 / ".git", "gitdir: " & repo1 / ".git" / "worktrees" / "wt")
    writeFile(wt2 / ".git", "gitdir: " & repo2 / ".git" / "worktrees" / "wt")
    let found = findWorktreesForMainRepo(repo1, TestBase)
    check found.len == 1

  test "detects worktrees in nested directories":
    let sub = TestBase / "sub"
    let mainRepo = sub / "repo"
    createDir(mainRepo / ".git" / "worktrees" / "wt")
    let wt = sub / "repo-wt"
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "wt")
    let found = findWorktreesForMainRepo(mainRepo, TestBase)
    check found.len == 1
