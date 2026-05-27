import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { ImapFlow } from "imapflow";

const IMAP_HOST = process.env.IMAP_HOST || "";
const IMAP_PORT = parseInt(process.env.IMAP_PORT || "993");
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
          query: {
            type: "string",
            description: "検索キーワード（空文字で全件）",
          },
          limit: {
            type: "number",
            description: "取得件数（デフォルト20）",
          },
          unread_only: {
            type: "boolean",
            description: "未読のみ取得するか",
          },
        },
      },
    },
    {
      name: "get_email",
      description: "メール本文を取得する",
      inputSchema: {
        type: "object",
        properties: {
          uid: { type: "string", description: "メールUID" },
        },
        required: ["uid"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "search_emails") {
    const client = new ImapFlow({
      host: IMAP_HOST,
      port: IMAP_PORT,
      secure: IMAP_PORT === 993,
      auth: { user: EMAIL_USER, pass: EMAIL_PASS },
      logger: false,
    });
    try {
      await client.connect();
      const lock = await client.getMailboxLock("INBOX");
      const limit = args.limit || 20;
      const searchCriteria = args.unread_only ? ["UNSEEN"] : ["ALL"];
      const messages = [];
      for await (const msg of client.fetch(searchCriteria, {
        uid: true,
        flags: true,
        envelope: true,
      })) {
        messages.push({
          uid: String(msg.uid),
          subject: msg.envelope.subject || "(件名なし)",
          from: msg.envelope.from?.[0]?.address || "",
          date: msg.envelope.date?.toISOString() || "",
          unread: !msg.flags.has("\\Seen"),
        });
        if (messages.length >= limit) break;
      }
      lock.release();
      await client.logout();
      return {
        content: [
          { type: "text", text: JSON.stringify(messages.reverse(), null, 2) },
        ],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `エラー: ${err.message}` }],
        isError: true,
      };
    }
  }

  if (name === "get_email") {
    const client = new ImapFlow({
      host: IMAP_HOST,
      port: IMAP_PORT,
      secure: IMAP_PORT === 993,
      auth: { user: EMAIL_USER, pass: EMAIL_PASS },
      logger: false,
    });
    try {
      await client.connect();
      const lock = await client.getMailboxLock("INBOX");
      let result = null;
      for await (const msg of client.fetch(args.uid, {
        uid: true,
        envelope: true,
        source: true,
      })) {
        result = {
          uid: String(msg.uid),
          subject: msg.envelope.subject || "(件名なし)",
          from: msg.envelope.from?.[0]?.address || "",
          date: msg.envelope.date?.toISOString() || "",
          body: msg.source.toString(),
        };
      }
      lock.release();
      await client.logout();
      return {
        content: [
          {
            type: "text",
            text: result
              ? JSON.stringify(result, null, 2)
              : "メールが見つかりません",
          },
        ],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `エラー: ${err.message}` }],
        isError: true,
      };
    }
  }

  return {
    content: [{ type: "text", text: `不明なツール: ${name}` }],
    isError: true,
  };
});

const transport = new StdioServerTransport();
await server.connect(transport);
