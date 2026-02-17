# wtsync

Git worktree の `workspace/` シンボリックリンクを自動管理するツール。

`git worktree add` で作成した worktree に、本体リポジトリの `workspace/` ディレクトリへの symlink を自動的に作成・修復します。macOS FSEvents による常駐監視にも対応。

## インストール

```bash
nimble build
cp bin/wtsync ~/.local/bin/
```

または：

```bash
nimble install_local
```

**要件**: Nim >= 2.2.6, macOS（FSEvents API を使用）

## 使い方

```bash
# 単一ディレクトリの確認・修復
wtsync check [path]

# ~/projects 配下の全 worktree を一括修復
wtsync fix [root]

# 全 worktree の状態表示（変更なし）
wtsync status [root]

# FSEvents で監視し、新規 worktree を自動リンク
wtsync watch [root]
```

デフォルトの `root` は `~/projects` です。

## デーモン（launchd）

```bash
wtsync daemon install      # インストール＆起動
wtsync daemon uninstall    # 停止＆削除
wtsync daemon restart      # 再起動（バイナリ更新後に）
wtsync daemon status       # 稼働状態を確認
wtsync daemon log          # ログ表示
```

## 動作の仕組み

1. worktree の `.git` ファイルから `gitdir:` を読み、本体リポジトリのパスを逆算
2. 本体リポに `workspace/` があれば、worktree 側に symlink を作成
3. `watch` モードでは FSEvents でディレクトリ作成イベントを監視し、リアルタイムでリンク

### 状態判定

| 状態 | 意味 |
|------|------|
| `wsAlreadyLinked` | 正しい symlink が存在 |
| `wsNeedsLink` | symlink 未作成 → `fix` で作成 |
| `wsBrokenLink` | symlink 先が不正 → `fix` で再作成 |
| `wsRealDirExists` | 実ディレクトリが存在（警告のみ） |
| `wsNoWorkspace` | 本体リポに workspace/ なし（スキップ） |

## ライセンス

MIT
