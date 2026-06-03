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
        except Exception:
            pass


def extract_last_assistant(transcript):
    for msg in reversed(transcript):
        if msg.get("role") == "assistant":
            content = msg.get("content", [])
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                return "\n".join(
                    b.get("text", "")
                    for b in content
                    if isinstance(b, dict) and b.get("type") == "text"
                )
    return ""


def main():
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    except Exception:
        sys.exit(0)

    session_id = data.get("session_id", "")
    cwd = data.get("cwd", "")
    ts = datetime.now().strftime("%H:%M")

    if event == "UserPromptSubmit":
        prompt = data.get("prompt", "").strip()
        if prompt:
            append(f"\n### {ts} User\n\n{prompt}\n", session_id, cwd)
    elif event == "Stop":
        text = extract_last_assistant(data.get("transcript", [])).strip()
        if text:
            append(f"\n### {ts} Claude\n\n{text}\n", session_id, cwd)

    sys.exit(0)


if __name__ == "__main__":
    main()
