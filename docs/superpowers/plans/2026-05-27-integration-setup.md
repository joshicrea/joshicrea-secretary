# AI秘書 連携設定メニュー Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** セットアップ時に5つの統合（Google Calendar・Gmail・独自ドメインメール・Chatwork・天気）を選択・設定・接続テストまで一括で完了させる。

**Architecture:** Phase 1 ④を複数選択メニューに置き換え、選択した統合ごとに案内→認証情報入力→接続テスト→`ユーザープロフィール.md`への verified フラグ記録を順次実行する。独自ドメインメールのみ Node.js MCPサーバーを同梱し、`~/.claude/mcp.json` に書き込む。朝ブリーフィングはプロフィールの verified フラグを読んで取得対象を動的に切り替える。

**Tech Stack:** Claude Code MCP (mcp__claude_ai_Gmail / Google_Calendar), Chatwork REST API, Open-Meteo API (無料・認証不要), Node.js + imapflow + nodemailer (独自メールMCP), PowerShell (install.ps1)

---

## ファイル構成

| ファイル | 操作 | 役割 |
|---|---|---|
| `.claude/rules/秘書.md` | 変更 | Phase 1 ④ を連携設定メニューに置き換え |
| `.claude/skills/秘書/SKILL.md` | 変更 | 朝ブリーフィングを verified フラグ対応に |
| `テンプレート/ユーザープロフィール.md` | 変更 | 連携設定セクションを拡張 |
| `ツール/email-mcp/package.json` | 新規 | メールMCPサーバーの依存定義 |
| `ツール/email-mcp/index.js` | 新規 | IMAP/SMTP MCPサーバー本体 |
| `install.ps1` | 変更 | email-mcp を secretary/ツール/ にコピー + npm install |

---

## Task 1: ユーザープロフィールテンプレートに連携設定セクションを追加

**Files:**
- Modify: `テンプレート/ユーザープロフィール.md`

- [ ] **Step 1: 連携設定セクションを拡張する**

`テンプレート/ユーザープロフィール.md` の `## 連携設定` セクションを以下に全置換する:

```markdown
## 連携設定

gcal_verified: false
gmail_verified: false
custom_email_verified: false
custom_email_address:
custom_email_imap:
custom_email_smtp:
chatwork_verified: false
chatwork_token:
weather_verified: false
weather_location:
weather_lat:
weather_lon:
memory_location: memory/
obsidian_vault:
```

- [ ] **Step 2: 既存の `gmail_connected` `gcal_connected` を削除する**

同ファイルの旧フィールド `gmail_connected: false` と `gcal_connected: false` の行を削除する（上記で置換済みのため不要）。

- [ ] **Step 3: コミット**

```bash
cd "{{WORKSPACE_ROOT}}/販売ツール/AI秘書"
git add "テンプレート/ユーザープロフィール.md"
git commit -m "feat(secretary): 連携設定フィールドを5統合対応に拡張"
```

---

## Task 2: email-mcp サーバーを新規作成

**Files:**
- Create: `ツール/email-mcp/package.json`
- Create: `ツール/email-mcp/index.js`

- [ ] **Step 1: package.json を作成する**

```json
{
  "name": "secretary-email-mcp",
  "version": "1.0.0",
  "description": "AI秘書用 IMAP/SMTPメールMCPサーバー",
  "type": "module",
  "main": "index.js",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.12.0",
    "imapflow": "^1.0.169",
    "nodemailer": "^6.9.15"
  }
}
```

- [ ] **Step 2: index.js を作成する**

```javascript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { ImapFlow } from "imapflow";

const IMAP_HOST = process.env.IMAP_HOST || "";
const IMAP_PORT = parseInt(process.env.IMAP_PORT || "993");
const SMTP_HOST = process.env.SMTP_HOST || "";
const SMTP_PORT = parseInt(process.env.SMTP_PORT || "587");
const EMAIL_USER = process.env.EMAIL_USER || "";
const EMAIL_PASS = process.env.EMAIL_PASS || "";

const server = new Server(
  { name: "secretary-email-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "search_emails",
      description: "メールを検索・一覧取得する",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "検索キーワード（空文字で全件）" },
          limit: { type: "number", description: "取得件数（デフォルト20）" },
          unread_only: { type: "boolean", description: "未読のみ取得するか" }
        }
      }
    },
    {
      name: "get_email",
      description: "メール本文を取得する",
      inputSchema: {
        type: "object",
        properties: {
          uid: { type: "string", description: "メールUID" }
        },
        required: ["uid"]
      }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "search_emails") {
    const client = new ImapFlow({
      host: IMAP_HOST,
      port: IMAP_PORT,
      secure: IMAP_PORT === 993,
      auth: { user: EMAIL_USER, pass: EMAIL_PASS },
      logger: false
    });
    try {
      await client.connect();
      const lock = await client.getMailboxLock("INBOX");
      const limit = args.limit || 20;
      const searchCriteria = args.unread_only ? ["UNSEEN"] : ["ALL"];
      const messages = [];
      for await (const msg of client.fetch(searchCriteria, {
        uid: true, flags: true, envelope: true, bodyStructure: false
      })) {
        messages.push({
          uid: String(msg.uid),
          subject: msg.envelope.subject || "(件名なし)",
          from: msg.envelope.from?.[0]?.address || "",
          date: msg.envelope.date?.toISOString() || "",
          unread: !msg.flags.has("\\Seen")
        });
        if (messages.length >= limit) break;
      }
      lock.release();
      await client.logout();
      return {
        content: [{ type: "text", text: JSON.stringify(messages.reverse(), null, 2) }]
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `エラー: ${err.message}` }],
        isError: true
      };
    }
  }

  if (name === "get_email") {
    const client = new ImapFlow({
      host: IMAP_HOST,
      port: IMAP_PORT,
      secure: IMAP_PORT === 993,
      auth: { user: EMAIL_USER, pass: EMAIL_PASS },
      logger: false
    });
    try {
      await client.connect();
      const lock = await client.getMailboxLock("INBOX");
      let result = null;
      for await (const msg of client.fetch(args.uid, { uid: true, envelope: true, source: true })) {
        result = {
          uid: String(msg.uid),
          subject: msg.envelope.subject || "(件名なし)",
          from: msg.envelope.from?.[0]?.address || "",
          date: msg.envelope.date?.toISOString() || "",
          body: msg.source.toString()
        };
      }
      lock.release();
      await client.logout();
      return {
        content: [{ type: "text", text: result ? JSON.stringify(result, null, 2) : "メールが見つかりません" }]
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `エラー: ${err.message}` }],
        isError: true
      };
    }
  }

  return { content: [{ type: "text", text: `不明なツール: ${name}` }], isError: true };
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

- [ ] **Step 3: コミット**

```bash
cd "{{WORKSPACE_ROOT}}/販売ツール/AI秘書"
git add "ツール/email-mcp/package.json" "ツール/email-mcp/index.js"
git commit -m "feat(secretary): IMAP/SMTP email-mcp サーバーを追加"
```

---

## Task 3: install.ps1 に email-mcp セットアップ処理を追加

**Files:**
- Modify: `install.ps1`

- [ ] **Step 1: email-mcp コピー処理を追加する**

`install.ps1` の `# --- データディレクトリを作成 ---` ブロックの直前（215行目付近）に以下を挿入する:

```powershell
# --- email-mcp をユーザー領域にコピー ---
$EmailMcpSrc = [IO.Path]::Combine($InstallPath, "ツール", "email-mcp")
$EmailMcpDst = [IO.Path]::Combine($SecretaryBase, "ツール", "email-mcp")
if (Test-Path $EmailMcpSrc) {
    New-Item -ItemType Directory -Force -Path $EmailMcpDst | Out-Null
    Copy-Item ([IO.Path]::Combine($EmailMcpSrc, "package.json")) $EmailMcpDst -Force
    Copy-Item ([IO.Path]::Combine($EmailMcpSrc, "index.js"))     $EmailMcpDst -Force
    # node_modules がなければ npm install を実行
    $NodeModules = [IO.Path]::Combine($EmailMcpDst, "node_modules")
    if (-not (Test-Path $NodeModules)) {
        if (Get-Command node -ErrorAction SilentlyContinue) {
            Push-Location $EmailMcpDst
            & npm install --silent 2>&1 | Out-Null
            Pop-Location
            Write-Host "email-mcp の依存パッケージをインストールしました"
        } else {
            Write-Host "注意: Node.js が見つかりません。独自ドメインメール機能を使う場合は Node.js をインストールしてください。"
        }
    }
}
```

- [ ] **Step 2: コミット**

```bash
cd "{{WORKSPACE_ROOT}}/販売ツール/AI秘書"
git add install.ps1
git commit -m "feat(secretary): install.ps1 に email-mcp コピー処理を追加"
```

---

## Task 4: 秘書.md の Phase 1 ④ を連携設定メニューに置き換え

**Files:**
- Modify: `.claude/rules/秘書.md`

- [ ] **Step 1: ④ 連携設定の確認セクションを全置換する**

`.claude/rules/秘書.md` の `### ④ 連携設定の確認` から `### ⑤ ユーザープロフィール.md の自動生成` の直前まで（現在の ④ ブロック全体）を以下に置換する:

````markdown
### ④ 連携設定の確認

**まず使いたい機能を一括選択してもらう（複数選択可）:**

AskUserQuestion（multiSelect: true）で以下を確認する:

「朝の確認で使いたい機能を選んでください（複数選択可）」
- Googleカレンダー（今日の予定を毎朝確認）
- Gmail（Googleメールの確認・返信下書き）
- 独自ドメインメール（会社・事業用メールの確認）
- Chatwork（メッセージの確認）
- 天気（毎朝の天気・服装アドバイス）
- 学習内容の保存先をObsidianにする

選択後、選んだ項目を以下の順で1つずつセットアップする。

---

#### Googleカレンダー（選択された場合）

「GoogleカレンダーをAI秘書に接続します。

Claude Codeの設定でGoogleアカウントを接続してください:
1. Claude Codeの左下の歯車アイコン → 「Settings」を開く
2. 「Connections」または「Integrations」を選択
3. 「Google Calendar」の「Connect」をクリック
4. Googleアカウントでログインして許可する
5. 完了したら「つないだ」と教えてください」

→ ユーザーが「つないだ」と言ったら:
`mcp__claude_ai_Google_Calendar__list_events` を呼んで今日の予定を取得する。

成功した場合:
「接続を確認しました。カレンダーが使えます。」
`{{SECRETARY_BASE_DIR}}/ユーザープロフィール.md` の `gcal_verified: false` を `gcal_verified: true` に更新する。

失敗した場合:
「まだ接続されていないようです。上記の手順を再度確認してから「つないだ」と教えてください。」

---

#### Gmail（選択された場合）

「GmailをAI秘書に接続します。

Claude Codeの設定でGmailを接続してください:
1. Claude Codeの左下の歯車アイコン → 「Settings」を開く
2. 「Connections」または「Integrations」を選択
3. 「Gmail」の「Connect」をクリック
4. Googleアカウントでログインして許可する
5. 完了したら「つないだ」と教えてください」

→ ユーザーが「つないだ」と言ったら:
`mcp__claude_ai_Gmail__search_threads` を `{ "query": "is:unread", "maxResults": 3 }` で呼ぶ。

成功した場合（エラーなく返ってきた場合）:
「接続を確認しました。Gmailが使えます。」
`{{SECRETARY_BASE_DIR}}/ユーザープロフィール.md` の `gmail_verified: false` を `gmail_verified: true` に更新する。

失敗した場合:
「まだ接続されていないようです。上記の手順を再度確認してから「つないだ」と教えてください。」

---

#### 独自ドメインメール（選択された場合）

「会社・事業用メールの接続情報を入力してください。」

AskUserQuestion で順番に聞く（1問ずつ）:
1. 「IMAPサーバーを教えてください（例: imap.example.com）」
2. 「SMTPサーバーを教えてください（例: smtp.example.com）」
3. 「メールアドレスを教えてください（例: info@example.com）」
4. 「パスワードを教えてください」

4項目が揃ったら:

**Bash で `~/.claude/mcp.json` に追記する:**

```bash
python3 - <<'PYEOF'
import json, os, pathlib

mcp_path = pathlib.Path.home() / ".claude" / "mcp.json"
secretary_base = "{{SECRETARY_BASE_DIR}}"
email_mcp_js = os.path.join(secretary_base, "ツール", "email-mcp", "index.js")

if mcp_path.exists():
    data = json.loads(mcp_path.read_text(encoding="utf-8"))
else:
    data = {"mcpServers": {}}

if "mcpServers" not in data:
    data["mcpServers"] = {}

data["mcpServers"]["email-custom"] = {
    "command": "node",
    "args": [email_mcp_js],
    "env": {
        "IMAP_HOST": "IMAP_HOST_VALUE",
        "SMTP_HOST": "SMTP_HOST_VALUE",
        "EMAIL_USER": "EMAIL_USER_VALUE",
        "EMAIL_PASS": "EMAIL_PASS_VALUE"
    }
}

mcp_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print("mcp.json を更新しました")
PYEOF
```

（上記スクリプトの IMAP_HOST_VALUE・SMTP_HOST_VALUE・EMAIL_USER_VALUE・EMAIL_PASS_VALUE を実際に入力された値で置換してから実行する）

書き込み後:
「設定を保存しました。Claude Codeを完全に閉じて再起動してください。再起動後に「メール接続テストして」と言っていただくと接続を確認します。」

`{{SECRETARY_BASE_DIR}}/ユーザープロフィール.md` に以下を記録する:
```
custom_email_address: （入力されたメールアドレス）
custom_email_imap: （入力されたIMAPサーバー）
custom_email_smtp: （入力されたSMTPサーバー）
```

**「メール接続テストして」と言われたら（Claude Code再起動後）:**

`mcp__email-custom__search_emails` を `{ "limit": 3, "unread_only": true }` で呼ぶ。

成功した場合:
「接続を確認しました。メールが使えます。」
`custom_email_verified: false` を `custom_email_verified: true` に更新する。

失敗した場合:
「接続できませんでした。サーバー情報・パスワードを確認してください。もう一度最初から設定し直す場合は「メール設定やり直し」と言ってください。」

---

#### Chatwork（選択された場合）

「ChatworkのAPIトークンを入力してください。

取得方法:
1. Chatworkにログインする
2. 右上のアイコン → 「サービス連携」を選択
3. 「APIトークン」をコピーする」

→ AskUserQuestion: 「APIトークンを貼り付けてください」

入力されたら WebFetch で接続テストする:
```
URL: https://api.chatwork.com/v2/me
Headers: { "X-ChatWorkToken": "（入力されたトークン）" }
```

成功した場合（accountName が返ってきた場合）:
「〇〇さんのアカウントを確認しました。Chatworkが使えます。」
`{{SECRETARY_BASE_DIR}}/ユーザープロフィール.md` の以下を更新する:
```
chatwork_token: （入力されたトークン）
chatwork_verified: true
```

失敗した場合:
「接続できませんでした。APIトークンを確認して再度貼り付けてください。」

---

#### 天気（選択された場合）

「天気を確認する場所を教えてください（例: 東京都渋谷区・大阪市北区・名古屋市中区）」

→ AskUserQuestion: 「場所を教えてください」

入力されたら Open-Meteo Geocoding API で座標を取得する:
```
WebFetch: https://geocoding-api.open-meteo.com/v1/search?name=（入力された場所）&count=1&language=ja&format=json
```

座標が取得できたら天気を取得してテスト表示する:
```
WebFetch: https://api.open-meteo.com/v1/forecast?latitude=（lat）&longitude=（lon）&current=temperature_2m,weathercode,windspeed_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=Asia/Tokyo&forecast_days=1
```

成功した場合:
「〇〇の今日の天気: ○℃、（天気概況）。設定完了です。」
`{{SECRETARY_BASE_DIR}}/ユーザープロフィール.md` を更新する:
```
weather_location: （入力された場所）
weather_lat: （取得した緯度）
weather_lon: （取得した経度）
weather_verified: true
```

---

#### Obsidian（選択された場合）

まずObsidianのインストール有無を確認する。AskUserQuestionで聞く:
「Obsidianはすでにインストール済みですか？」
→ [インストール済み] [まだインストールしていない]

**「まだインストールしていない」の場合:**
「Obsidianは無料のノートアプリです。以下の手順でインストールしてください。

1. https://obsidian.md/ をブラウザで開く
2. 「Download」ボタンをクリックしてダウンロード
3. ダウンロードしたファイルを開いてインストール
4. インストールが終わったら「インストールできた」と教えてください」
→ 「インストールできた」が来たら次へ進む

**「インストール済み」または完了後:**
「Obsidian Vaultのフォルダパスをコピペしてください。
例: C:/Users/〇〇/Documents/MyVault」
→ 入力されたパスを `{{SECRETARY_BASE_DIR}}/ユーザープロフィール.md` の `obsidian_vault:` に記録する
````

- [ ] **Step 2: コミット**

```bash
cd "{{WORKSPACE_ROOT}}/販売ツール/AI秘書"
git add ".claude/rules/秘書.md"
git commit -m "feat(secretary): セットアップ ④ を5統合の連携設定メニューに置き換え"
```

---

## Task 5: 朝ブリーフィング SKILL.md を verified フラグ対応に更新

**Files:**
- Modify: `.claude/skills/秘書/SKILL.md`

- [ ] **Step 1: Step 1（並列取得）ブロックを verified フラグ確認対応に置き換える**

SKILL.md の `#### Step 1: 並列取得（同時に実行する）` ブロック全体を以下に置き換える:

````markdown
#### Step 0: 連携設定を確認する（必須・最初に実行）

`{{SECRETARY_BASE_DIR}}/ユーザープロフィール.md` を Read で読み、各統合の verified フラグを確認する。

#### Step 1: 並列取得（verified=true の統合のみ・同時に実行する）

プロフィールで `verified: true` になっている統合のみ取得する。`false` の統合はスキップする（エラーにしない）。

- **Gmail**（`gmail_verified: true` の場合のみ）:
  `mcp__claude_ai_Gmail__search_threads` で未読メールを取得
  ```
  query: "is:unread"
  maxResults: 30
  ```

- **Google Calendar**（`gcal_verified: true` の場合のみ）:
  `mcp__claude_ai_Google_Calendar__list_events` で今日・明日の予定を取得

- **独自ドメインメール**（`custom_email_verified: true` の場合のみ）:
  `mcp__email-custom__search_emails` で未読メールを取得
  ```
  { "limit": 20, "unread_only": true }
  ```

- **Chatwork**（`chatwork_verified: true` の場合のみ）:
  プロフィールから `chatwork_token` を読んで WebFetch でメッセージを取得
  ```
  URL: https://api.chatwork.com/v2/my/status
  Headers: { "X-ChatWorkToken": "（chatwork_token の値）" }
  ```

- **天気**（`weather_verified: true` の場合のみ）:
  プロフィールから `weather_lat` `weather_lon` を読んで Open-Meteo API で取得
  ```
  WebFetch: https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,weathercode,windspeed_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=Asia/Tokyo&forecast_days=2
  ```

- **タスク**: `{{SECRETARY_BASE_DIR}}/memory/タスク/` フォルダに pending ファイルがあれば Read で取得
````

- [ ] **Step 2: Step 3（報告フォーマット）に天気・独自メール・Chatwork のセクションを追加する**

既存の報告フォーマットの `【今日の予定】` の前に以下を追加する:

````markdown
【天気】（weather_verified: true の場合のみ表示）
〇〇（場所） 最高XX℃ / 最低XX℃ 降水確率XX%
服装アドバイス: 〇〇

````

`【メール】` セクションの後に以下を追加する:

````markdown
【独自ドメインメール】（custom_email_verified: true の場合のみ）
要対応 N件
1. [送信者] [件名の要約]
   → 推奨: 〇〇

【Chatwork】（chatwork_verified: true の場合のみ）
未読 N件
1. [ルーム名] [メッセージ要約]
   → 推奨: 〇〇

````

- [ ] **Step 3: コミット**

```bash
cd "{{WORKSPACE_ROOT}}/販売ツール/AI秘書"
git add ".claude/skills/秘書/SKILL.md"
git commit -m "feat(secretary): 朝ブリーフィングを verified フラグ対応・5統合に拡張"
```

---

## Task 6: 動作確認

- [ ] **Step 1: install.ps1 を実行してインストールが完了するか確認する**

Claude Code のチャットに以下を貼り付けて実行する:
```
以下のURLからAI秘書プラグインのインストールスクリプトを取得して、内容を確認してから実行してください:
https://raw.githubusercontent.com/joshicrea/joshicrea-secretary/master/install.ps1
```

期待結果: エラーなく「インストール完了！」が表示される。`~/.claude/secretary/ツール/email-mcp/` が作成されている。

- [ ] **Step 2: 初回セットアップで連携設定メニューが表示されるか確認する**

`~/.claude/secretary/.setup-status` を削除してから Claude Code を再起動し「はじめまして」と送る。

期待結果: ④ で複数選択メニューが表示される。

- [ ] **Step 3: 各統合を1つずつ選択してセットアップが完了するか確認する**

- Google Calendar を選択 → 接続 → `gcal_verified: true` が記録されるか確認
- Chatwork を選択 → APIトークン入力 → `chatwork_verified: true` が記録されるか確認
- 天気を選択 → 場所入力 → `weather_verified: true` と座標が記録されるか確認
- 独自ドメインメール を選択 → 認証情報入力 → mcp.json に `email-custom` が追記されるか確認

- [ ] **Step 4: 「おはよう」で有効な統合のみ表示されるか確認する**

期待結果: `verified: false` の統合はセクションが表示されず、エラーも出ない。

- [ ] **Step 5: git push して GitHub に反映する**

```bash
cd "{{WORKSPACE_ROOT}}/販売ツール/AI秘書"
git push origin master
```
