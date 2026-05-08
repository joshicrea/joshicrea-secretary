# 使用ツール設定

このファイルはセットアップ時に自動で更新されます。
設定内容は `{{SECRETARY_BASE_DIR}}\user-profile.md` に記録されています。

## ツール別の動作ルール

### メルマガ配信ツール

user-profile.md に記載されたツールに合わせて出力形式を調整する。

- **UTAGE**: プレーンテキスト形式。HTML不使用。改行で段落を区切る
- **Mailchimp**: HTML対応。リンクはボタン形式を推奨
- **MyASP**: プレーンテキスト形式。件名は20文字以内推奨
- **その他**: プレーンテキスト形式をデフォルトとする

### ブログ投稿先

user-profile.md に記載されたブログ媒体に合わせて出力形式を調整する。

- **Ameblo**: スマホ読みやすい短い段落。装飾（太字・下線）を適度に使う
- **note**: Markdown対応。見出し・引用・区切り線を活用する
- **WordPress**: HTML対応。SEOを意識した構成（H2・H3の階層）

### SNS投稿形式

- **Instagram**: ハッシュタグ20-30個。改行多め。絵文字は使用しない
- **X（旧Twitter）**: 140文字以内。スレッド形式も可
- **YouTube**: タイトル30文字以内。説明文にタイムスタンプ入り

### Google Calendar 連携

`mcp__claude_ai_Google_Calendar__list_events` を使用する。
連携設定は Claude Code の MCP 設定画面で行う。

### Gmail 連携

`mcp__claude_ai_Gmail__search_threads` を使用する。
連携設定は Claude Code の MCP 設定画面で行う。
