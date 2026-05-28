import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { ImapFlow } from "imapflow";
import nodemailer from "nodemailer";

const SMTP_HOST = process.env.SMTP_HOST || "";
const SMTP_PORT = parseInt(process.env.SMTP_PORT || "465");

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
    {
      name: "send_email",
      description: "メールを送信する（返信・新規送信）",
      inputSchema: {
        type: "object",
        properties: {
          to: { type: "string", description: "送信先メールアドレス" },
          subject: { type: "string", description: "件名" },
          body: { type: "string", description: "本文（プレーンテキスト）" },
          reply_to_uid: {
            type: "string",
            description: "返信対象メールのUID（返信の場合）",
          },
          from_address: {
            type: "string",
            description: "送信元アドレス（省略時は EMAIL_USER を使用）",
          },
        },
        required: ["to", "subject", "body"],
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

  if (name === "send_email") {
    try {
      const transporter = nodemailer.createTransport({
        host: SMTP_HOST,
        port: SMTP_PORT,
        secure: SMTP_PORT === 465,
        auth: { user: EMAIL_USER, pass: EMAIL_PASS },
      });

      const from = args.from_address || EMAIL_USER;

      // 返信の場合は元メールの件名に Re: を付与（すでに付いていれば付けない）
      let subject = args.subject;
      if (
        args.reply_to_uid &&
        !subject.startsWith("Re:") &&
        !subject.startsWith("RE:")
      ) {
        subject = `Re: ${subject}`;
      }

      await transporter.sendMail({
        from,
        to: args.to,
        subject,
        text: args.body,
      });

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              success: true,
              to: args.to,
              subject,
              from,
            }),
          },
        ],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `送信エラー: ${err.message}` }],
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
