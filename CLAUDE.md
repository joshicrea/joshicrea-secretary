# AI秘書 プラグイン

## 開発者向けメモ

このリポジトリは `joshicrea-secretary` Claude Code プラグインです。

## AI秘書のロジック

AI秘書のメインロジックは `.claude/rules/secretary.md` に定義されています。
install.ps1 がこのファイルをユーザーの `~/.claude/rules/secretary.md` にコピー（パス置換済み）します。

## 開発時の注意

- パス参照は必ず `{{SECRETARY_BASE_DIR}}\xxx` の形式で記述する（相対パス禁止）
- コミット前に `python3 tools/validate_paths.py` を実行してパス漏れがないか確認する
- install.ps1 を変更したら `powershell -ExecutionPolicy Bypass -File test_install.ps1` でテストする
