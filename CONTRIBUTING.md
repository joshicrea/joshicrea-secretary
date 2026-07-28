# 開発ルール (CONTRIBUTING.md)

このリポジトリに新しいスキル・ルール・機能を追加するときのルール。
**全ルールは `ツール/パス検証.py` で自動チェックされる。コミット前に必ず通過させること。**

---

## セットアップ（初回のみ）

```powershell
powershell -ExecutionPolicy Bypass -File ツール/フック設定.ps1
```

これで `git commit` のたびに `パス検証.py` が自動実行される。

---

## Rule 1: ファイルパスは必ず {{SECRETARY_BASE_DIR}} を使う

### 背景

Claude Code のプラグインシステムでは、キャッシュ内の `.claude/rules/*.md` は **自動読み込みされない**。
`install.ps1` が `~/.claude/rules/` に直接コピーして初めて読み込まれる。
コピー時に `{{SECRETARY_BASE_DIR}}` を実際の絶対パスに置換する。

### ルール

| 禁止 | 正しい書き方 |
|---|---|
| `` `.setup-status` `` | `` `{{SECRETARY_BASE_DIR}}/.setup-status` `` |
| `` `memory/タスク/` `` | `` `{{SECRETARY_BASE_DIR}}/memory/タスク/` `` |
| `` `テンプレート/ユーザープロフィール.md` `` | `` `{{SECRETARY_BASE_DIR}}/ユーザープロフィール.md` `` |
| `` `素材/backup/` `` | `` `{{SECRETARY_BASE_DIR}}/素材/backup/` `` |

### SKILL.md での注意

SKILL.md はキャッシュ内から Skill ツールが読む。
`install.ps1` がキャッシュ内の SKILL.md に対しても `{{SECRETARY_BASE_DIR}}` 置換を実行する。
**相対パス禁止・プレースホルダー使用のルールは同じ。**

新しいスキルを作るときは `ツール/テンプレート/スキルテンプレート.md` をコピーして使う。

---

## Rule 2: .ps1 ファイルの禁止パターン

### PS5.1 エンコーディング問題

PowerShell 5.1 は BOM なし UTF-8 ファイルをシステム ANSI（日本語環境では CP932）として読む。
設定 JSON を `Get-Content | ConvertFrom-Json` で読むと日本語が壊れる。

| 禁止 | 正しい書き方 |
|---|---|
| `Get-Content $path -Raw \| ConvertFrom-Json` | `[System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) \| ConvertFrom-Json` |
| `Get-Content $path \| Set-Content $dest` | `Write-Utf8NoBom -Path $dest -Content (...)` |

### iex の正しい呼び方

```powershell
# 禁止: iwr がオブジェクトを返すため iex に渡せない
iwr https://example.com/script.ps1 | iex

# 正しい: .Content で文字列を取り出してから iex に渡す
(iwr https://example.com/script.ps1 -UseBasicParsing).Content | iex
```

`パス検証.py` がこのパターンを自動検出する。

---

## Rule 3: 新しいルールファイル (.claude/rules/) を追加するとき

`install.ps1` の rules コピーループは動的に `.claude/rules/*.md` を全件コピーする。
新しいファイルを `.claude/rules/` に追加するだけで自動的にコピー対象になる。
**静的リストに追加する必要はない。**

---

## Rule 4: インストール後の検証

`install.ps1` は末尾で以下を自動検証する:

- `~/.claude/rules/秘書.md` が存在するか
- `~/.claude/secretary/ユーザープロフィール.md` が存在するか
- `~/.claude/rules/秘書.md` に `{{SECRETARY_BASE_DIR}}` が残っていないか

検証失敗時は `exit 1` でインストールを中断する。

---

## コミット前チェック

```bash
python3 ツール/パス検証.py
```

全チェック通過（exit 0）を確認してからコミットする。
`ツール/フック設定.ps1` を実行済みであれば自動実行される。

---

## アーキテクチャ図

```
GitHub (joshicrea/joshicrea-secretary)
  └─ install.ps1 を (iwr ...).Content | iex で実行
       ├─ ZIP ダウンロード → キャッシュ: ~/.claude/plugins/cache/{org}/{name}/{sha}/
       ├─ .claude/rules/*.md を ~/.claude/rules/ にコピー（全件・動的）
       │   └─ {{SECRETARY_BASE_DIR}} → 実際の絶対パスに置換
       ├─ キャッシュ内 .claude/skills/*/SKILL.md の {{SECRETARY_BASE_DIR}} を置換
       ├─ installed_plugins.json / settings.json を更新
       ├─ ~/.claude/secretary/ データディレクトリを作成
       └─ インストール後検証（失敗したら exit 1）

Claude Code 起動時:
  ~/.claude/rules/AI秘書_*.md が自動読み込み → AI秘書_秘書.md が秘書ルールを定義
  Skill ツール呼び出し時:
    キャッシュ内の SKILL.md が読み込まれる（{{SECRETARY_BASE_DIR}} 置換済み）
```

---

## 開発時の注意（2026-07-28 CLAUDE.md から移設）

CLAUDE.md は SessionStart hook でお客様のセッションに「あなたの動作指示」として丸ごと注入される。開発者向けの内容を CLAUDE.md に書くと、お客様に開発手順が指示として渡る。開発者向けの記述はこのファイルに書く。

- パス参照は必ず `{{SECRETARY_BASE_DIR}}/xxx` の形式で書く（相対パス禁止）
- コミット前に `python3 ツール/パス検証.py` を実行してパス漏れを確認する
- install.ps1 / install.py を変更したら、クリーンな環境でインストールを通して検証する

### rules の配置規約（2026-07-28変更）

`~/.claude/rules/` はお客様の領域であり、他のプラグインやお客様自身のルールと共有する。次を守る。

- 配置するファイル名には `AI秘書_` プレフィックスを付ける（名前の衝突を避ける）
- ファイル先頭に由来マーカー（`<!-- このファイルは joshicrea-secretary プラグインが配置しました... -->`）を入れる
- 同名の既存ファイルがプラグイン由来でなければ `_backup_secretary_<日時>/` へ退避してから書く
- 旧バージョンがプレフィックスなしで置いたファイルは、由来が確認できるものだけ削除する

### hook を書くときの必須事項（2026-07-28確定・実測ベース）

- **stdin は必ず bytes で読んで UTF-8 デコードする。** `sys.stdin.read()` は Windows で cp932 として解釈され、日本語を含む入力で JSON パースが壊れる
- **PowerShell スクリプトは UTF-8 BOM 付きで保存する。** BOM が無いと PowerShell 5.1 が ANSI（日本語環境では CP932）として読み、スクリプト内の日本語リテラルが壊れる
- **PowerShell から JSON を出すときは `[Console]::Out.Write` を使わない。** stdout リダイレクト時に `[Console]::OutputEncoding`（日本語環境では shift_jis）で書き出され、UTF-8 の日本語が破損する。標準出力ストリームへ UTF-8 バイトを直接書く
- **JSON エスケープは1回だけ。** プレフィックス文字列に `\n` リテラルを書かず実改行を使う。2回エスケープすると改行が文字列 `\n` になり、注入内容の Markdown 構造が全部失われる
- **printf のフォーマット文字列にデータを渡さない。** 注入内容に `%` が1文字入ると出力が壊れる
- **fail-open は維持しつつ、無音にしない。** 例外は `{{SECRETARY_BASE_DIR}}/logs/hook_errors.log` に記録する。無音だと「ルールが届かなくなった」ことが正常時と見分けられない
- **Stop hook の payload は `transcript_path`（ファイルパス）。** `transcript`（配列）は存在しない
