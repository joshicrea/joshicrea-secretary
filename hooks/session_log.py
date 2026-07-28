#!/usr/bin/env python3
"""
セッションログ自動保存フック (joshicrea-secretary)

UserPromptSubmit / Stop フックから run-hook.cmd 経由で呼ばれる。
会話を memory/会話ログ/ に1セッション1ファイルで追記する。
Obsidian連携が設定されている場合はVaultにも二重保存する。

設計方針:
- 標準インストール先 ~/.claude/secretary をデータ基盤とする（環境変数で上書き可）
- 本文は切り捨てず全文を記録する
- 例外は全て握りつぶし、ツール本体・会話の進行を絶対に止めない
"""
import sys
import json
import os
from datetime import datetime
from pathlib import Path

# データ基盤（標準インストール先。install時に環境変数で上書きされる場合に対応）
BASE_DIR = Path(os.environ.get(
    "SECRETARY_BASE_DIR",
    str(Path.home() / ".claude" / "secretary"),
))
NOTES_DIR = BASE_DIR / "memory" / "会話ログ"
PROFILE_PATH = BASE_DIR / "ユーザープロフィール.md"
ERROR_LOG = BASE_DIR / "logs" / "hook_errors.log"


def log_error(message):
    """fail-open は維持しつつ、失敗を後から観測できるように残す。

    2026-07-28 追加: 以前は全ての例外を無言で握りつぶしており、
    「ログが増えない」以外に異常を知る手段が無かった。
    """
    try:
        ERROR_LOG.parent.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(str(ERROR_LOG), "a", encoding="utf-8", errors="replace") as f:
            f.write(f"{stamp} session_log.py: {message}\n")
    except Exception:
        pass  # ログにも書けないなら諦める。会話は止めない


def get_obsidian_dir():
    """ユーザープロフィールからObsidian Vaultパスを読む。連携OFF/未設定ならNone。"""
    try:
        if not PROFILE_PATH.exists():
            return None
        content = PROFILE_PATH.read_text(encoding="utf-8")
        if "Obsidian連携: true" not in content:
            return None
        for line in content.splitlines():
            if line.startswith("Obsidian Vaultパス:"):
                p = line.split(":", 1)[1].strip()
                if p and p != "{{obsidian_path}}":
                    return Path(p) / "AI秘書" / "会話ログ"
    except Exception:
        return None
    return None


def note_path(base_dir, session_id):
    base_dir.mkdir(parents=True, exist_ok=True)
    today = datetime.now().strftime("%Y-%m-%d")
    short_id = session_id[:8] if session_id else "unknown"
    return base_dir / f"{today}_{short_id}.md"


def ensure_header(path, session_id, cwd):
    if not path.exists():
        header = (
            f"# 会話ログ {datetime.now().strftime('%Y-%m-%d')}\n\n"
            f"- session: `{session_id}`\n"
            f"- cwd: `{cwd}`\n\n---\n"
        )
        path.write_text(header, encoding="utf-8", errors="replace")


def append(text, session_id, cwd):
    targets = [NOTES_DIR]
    obsidian = get_obsidian_dir()
    if obsidian:
        targets.append(obsidian)
    for base in targets:
        try:
            p = note_path(base, session_id)
            ensure_header(p, session_id, cwd)
            with open(str(p), "a", encoding="utf-8") as f:
                f.write(text)
        except Exception as e:
            log_error(f"会話ログの書き込みに失敗しました ({base}): {e}")


def extract_text(content):
    """メッセージの content からテキストだけを取り出す。"""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            b.get("text", "")
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return ""


def last_assistant_from_transcript_file(transcript_path):
    """Stop hook が渡す transcript_path（JSONL）から最後のassistant発言を取り出す。

    2026-07-28 修正: 以前は data.get("transcript", []) を読んでいたが、
    Claude Code が渡すのは transcript（配列）ではなく transcript_path（ファイルパス）。
    そのため常に空になり、Claude側の発言が一度もログに保存されていなかった。
    しかも例外を握りつぶす設計のため、誰も気づけない状態だった。
    """
    if not transcript_path:
        return ""
    p = Path(transcript_path)
    if not p.exists():
        log_error(f"transcript_path が存在しません: {transcript_path}")
        return ""
    text = ""
    try:
        with open(str(p), "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except Exception:
                    continue
                msg = entry.get("message") if isinstance(entry.get("message"), dict) else entry
                if msg.get("role") != "assistant":
                    continue
                t = extract_text(msg.get("content", [])).strip()
                if t:
                    text = t  # 最後に見つかったものを採用
    except Exception as e:
        log_error(f"transcript の読み込みに失敗しました: {e}")
        return ""
    return text


def main():
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        # stdin は必ず bytes で読んで UTF-8 デコードする。
        # sys.stdin.read() は Windows で cp932 解釈され、日本語入力でパースが壊れる。
        data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    except Exception as e:
        log_error(f"stdin の JSON パースに失敗しました: {e}")
        sys.exit(0)
    if not isinstance(data, dict):
        log_error(f"stdin の JSON が dict ではありません: {type(data).__name__}")
        sys.exit(0)

    session_id = data.get("session_id", "")
    cwd = data.get("cwd", "")
    ts = datetime.now().strftime("%H:%M")

    if event == "UserPromptSubmit":
        prompt = data.get("prompt", "").strip()
        if prompt:
            append(f"\n### {ts} User\n\n{prompt}\n", session_id, cwd)
    elif event == "Stop":
        text = last_assistant_from_transcript_file(data.get("transcript_path", "")).strip()
        if text:
            append(f"\n### {ts} Claude\n\n{text}\n", session_id, cwd)

    sys.exit(0)


if __name__ == "__main__":
    main()
