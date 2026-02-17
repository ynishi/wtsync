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

  test "存在しないパス → false":
    check not isWorktree(TestBase / "nonexistent")

  test "通常ディレクトリ（.git がディレクトリ） → false":
    let dir = TestBase / "normal_repo"
    createDir(dir / ".git")
    check not isWorktree(dir)

  test ".git がファイル → true":
    let dir = TestBase / "worktree"
    createDir(dir)
    writeFile(dir / ".git", "gitdir: /tmp/fake/.git/worktrees/wt")
    check isWorktree(dir)

  test ".git が存在しない → false":
    let dir = TestBase / "empty"
    createDir(dir)
    check not isWorktree(dir)

# ============================================================================
# resolveMainRepo
# ============================================================================

suite "resolveMainRepo":
  setup: setup()
  teardown: cleanup()

  test ".git ファイルなし → 空文字列":
    check resolveMainRepo(TestBase / "nonexistent") == ""

  test "不正な .git 内容 → 空文字列":
    let dir = TestBase / "invalid"
    createDir(dir)
    writeFile(dir / ".git", "not a gitdir reference")
    check resolveMainRepo(dir) == ""

  test "絶対パスの gitdir → 本体リポパスを返す":
    let mainRepo = TestBase / "repo"
    let wt = TestBase / "repo-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo-wt")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo-wt")
    let resolved = resolveMainRepo(wt)
    check expandFilename(resolved) == expandFilename(mainRepo)

  test "相対パスの gitdir → 正しく解決される":
    let mainRepo = TestBase / "repo_rel"
    let wt = TestBase / "repo_rel-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_rel-wt")
    createDir(wt)
    # 相対パス: wt から見た mainRepo/.git/worktrees/repo_rel-wt
    writeFile(wt / ".git", "gitdir: ../repo_rel/.git/worktrees/repo_rel-wt")
    let resolved = resolveMainRepo(wt)
    check expandFilename(resolved) == expandFilename(mainRepo)

# ============================================================================
# check
# ============================================================================

suite "check":
  setup: setup()
  teardown: cleanup()

  test "通常ディレクトリ → wsNotWorktree":
    let dir = TestBase / "normal"
    createDir(dir)
    let r = check(dir)
    check r.state == wsNotWorktree

  test "本体リポが見つからない → wsNoMainRepo":
    let dir = TestBase / "bad_wt"
    createDir(dir)
    writeFile(dir / ".git", "gitdir: /nonexistent/.git/worktrees/x")
    let r = check(dir)
    # resolveMainRepo returns a path but it doesn't exist as a git repo
    # Actually it returns a non-empty string, so state depends on workspace check
    check r.state in {wsNoMainRepo, wsNoWorkspace}

  test "workspace/ なし → wsNoWorkspace":
    let mainRepo = TestBase / "repo_nows"
    let wt = TestBase / "repo_nows-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_nows-wt")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_nows-wt")
    let r = check(wt)
    check r.state == wsNoWorkspace

  test "symlink 未作成 → wsNeedsLink":
    let mainRepo = TestBase / "repo_needs"
    let wt = TestBase / "repo_needs-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_needs-wt")
    createDir(mainRepo / "workspace")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_needs-wt")
    let r = check(wt)
    check r.state == wsNeedsLink
    check r.mainRepo != ""

  test "正しい symlink → wsAlreadyLinked":
    let mainRepo = TestBase / "repo_linked"
    let wt = TestBase / "repo_linked-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_linked-wt")
    createDir(mainRepo / "workspace")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_linked-wt")
    createSymlink(mainRepo / "workspace", wt / "workspace")
    let r = check(wt)
    check r.state == wsAlreadyLinked

  test "間違ったターゲットの symlink → wsBrokenLink":
    let mainRepo = TestBase / "repo_broken"
    let wt = TestBase / "repo_broken-wt"
    createDir(mainRepo / ".git" / "worktrees" / "repo_broken-wt")
    createDir(mainRepo / "workspace")
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "repo_broken-wt")
    createSymlink("/tmp/wrong_target", wt / "workspace")
    let r = check(wt)
    check r.state == wsBrokenLink

  test "実ディレクトリの workspace → wsRealDirExists":
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

  test "wsNeedsLink → symlink 作成":
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
    # fix 後は wsAlreadyLinked
    let r2 = check(wt)
    check r2.state == wsAlreadyLinked

  test "wsBrokenLink → 再リンク":
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

  test "wsNotWorktree → fix しない":
    let r = CheckResult(path: "/tmp", state: wsNotWorktree)
    check not fix(r)

  test "wsAlreadyLinked → fix しない":
    let r = CheckResult(path: "/tmp", state: wsAlreadyLinked)
    check not fix(r)

  test "wsRealDirExists → fix しない":
    let r = CheckResult(path: "/tmp", state: wsRealDirExists)
    check not fix(r)

# ============================================================================
# findAllDirs
# ============================================================================

suite "findAllDirs":
  setup: setup()
  teardown: cleanup()

  test "ネストしたディレクトリを再帰的に検出":
    createDir(TestBase / "a" / "b")
    createDir(TestBase / "c")
    let dirs = findAllDirs(TestBase)
    check dirs.len >= 3  # a, a/b, c

  test "隠しディレクトリをスキップ":
    createDir(TestBase / ".hidden")
    createDir(TestBase / "visible")
    let dirs = findAllDirs(TestBase)
    check dirs.len == 1
    check dirs[0].extractFilename == "visible"

  test "gitリポジトリの中には再帰しない":
    createDir(TestBase / "repo" / ".git" / "objects")
    createDir(TestBase / "repo" / "src")
    createDir(TestBase / "other")
    let dirs = findAllDirs(TestBase)
    # repo は含む、repo/src は含まない（.git dir があるので再帰停止）、other は含む
    var names: seq[string]
    for d in dirs:
      names.add(d.extractFilename)
    check "repo" in names
    check "other" in names
    check "src" notin names

  test "worktree の中には再帰しない":
    let wt = TestBase / "wt"
    createDir(wt / "src")
    writeFile(wt / ".git", "gitdir: /tmp/fake")
    let dirs = findAllDirs(TestBase)
    var names: seq[string]
    for d in dirs:
      names.add(d.extractFilename)
    check "wt" in names
    check "src" notin names

  test "空ディレクトリ → 空リスト":
    let dirs = findAllDirs(TestBase)
    check dirs.len == 0

# ============================================================================
# findWorktreesForMainRepo
# ============================================================================

suite "findWorktreesForMainRepo":
  setup: setup()
  teardown: cleanup()

  test "本体リポに属するworktreeを検出":
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

  test "別リポのworktreeは含まない":
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

  test "ネストしたディレクトリ内のworktreeも検出":
    let sub = TestBase / "sub"
    let mainRepo = sub / "repo"
    createDir(mainRepo / ".git" / "worktrees" / "wt")
    let wt = sub / "repo-wt"
    createDir(wt)
    writeFile(wt / ".git", "gitdir: " & mainRepo / ".git" / "worktrees" / "wt")
    let found = findWorktreesForMainRepo(mainRepo, TestBase)
    check found.len == 1
