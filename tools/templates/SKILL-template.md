---
name: skill-name
description: このスキルが何をするかの1行説明（Skillツールが一致判定に使う）
---

# スキル名

## ミッション

このスキルが解決する問題・提供する価値を1-2文で書く。

---

## トリガーワード

| ユーザーの発言 | このスキルが担当する理由 |
|---|---|
| 「〇〇して」 | 〇〇の処理を担当するから |

---

## 実行手順

### Step 1: データ読み込み

以下を並列で取得する:

- ユーザープロフィール: `{{SECRETARY_BASE_DIR}}\user-profile.md` を Read
- タスクデータ: `{{SECRETARY_BASE_DIR}}\memory\タスク\` を Glob → Read
- リソース: `{{SECRETARY_BASE_DIR}}\resources\` を Glob → Read（必要なら）

### Step 2: 処理

処理内容を書く。

### Step 3: 記録

結果を以下に書き込む:

- 処理ログ: `{{SECRETARY_BASE_DIR}}\memory\学習ログ\YYYY-MM-DD.md`
- タスク変更: `{{SECRETARY_BASE_DIR}}\memory\タスク\` フォルダ内

---

## パス参照ルール（必須・違反はバリデーターが検出）

- `{{SECRETARY_BASE_DIR}}` は install 時に絶対パスに展開される
- **相対パス禁止**: `memory/xxx` や `.setup-status` のように書かない
- **正しい書き方**: `{{SECRETARY_BASE_DIR}}\memory\xxx` / `{{SECRETARY_BASE_DIR}}\.setup-status`
- install.ps1 がキャッシュ内 SKILL.md のプレースホルダーを install 時に置換する

---

## チェックリスト（全項目OKになるまで実行しない）

- [ ] user-profile.md を読み込んだ
- [ ] ユーザーのプロフィール・設定を反映した出力になっている
- [ ] ファイルを編集する前に Read で現在の内容を確認した
- [ ] 送信・削除等の不可逆操作の前にユーザーに確認した
- [ ] 記録が必要な場合は学習ログに書き込んだ

---

## エラー対応

- ファイルが見つからない: 「〇〇の情報がまだ登録されていません」と日本語で案内する
- MCP連携エラー: 「連携が切れています。〇〇を試してください」と日本語で案内する
  （英語エラーメッセージをそのままユーザーに見せない）
