#!/usr/bin/env python3
"""
自動学習フック
会話終了時に学習内容をmemory/またはObsidianに記録する。
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path


def get_config():
    """user-profile.mdからObsidian設定を読む"""
    profile_path = Path(__file__).parent.parent / "templates" / "user-profile.md"
    if not profile_path.exists():
        return {"obsidian": False, "obsidian_path": None}

    content = profile_path.read_text(encoding="utf-8")
    obsidian_connected = "true" in content.lower() if "Obsidian連携: true" in content else False
    obsidian_path = None

    for line in content.splitlines():
        if line.startswith("Obsidian Vaultパス:"):
            path_str = line.split(":", 1)[1].strip()
            if path_str and path_str != "{{obsidian_path}}":
                obsidian_path = path_str

    return {"obsidian": obsidian_connected, "obsidian_path": obsidian_path}


def get_memory_dir():
    """memory/ディレクトリのパスを返す"""
    return Path(__file__).parent.parent / "memory"


def save_to_memory(content: str, category: str):
    """memory/フォルダに保存する"""
    today = datetime.now().strftime("%Y-%m-%d")
    memory_dir = get_memory_dir() / category
    memory_dir.mkdir(parents=True, exist_ok=True)

    filepath = memory_dir / f"{today}.md"
    header = f"### {datetime.now().strftime('%H:%M')}\n"

    existing = filepath.read_text(encoding="utf-8") if filepath.exists() else ""
    filepath.write_text(existing + header + content + "\n\n", encoding="utf-8")
    return str(filepath)


def save_to_obsidian(content: str, category: str, vault_path: str):
    """Obsidian Vaultに保存する"""
    today = datetime.now().strftime("%Y-%m-%d")
    vault = Path(vault_path)
    target_dir = vault / "AI秘書" / category
    target_dir.mkdir(parents=True, exist_ok=True)

    filepath = target_dir / f"{today}.md"
    header = f"### {datetime.now().strftime('%H:%M')}\n"

    existing = filepath.read_text(encoding="utf-8") if filepath.exists() else ""
    filepath.write_text(existing + header + content + "\n\n", encoding="utf-8")
    return str(filepath)


def main():
    """メイン処理"""
    try:
        input_data = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    # Stopイベント以外は無視
    event = input_data.get("event", "")
    if event != "Stop":
        sys.exit(0)

    # 会話から学習内容を抽出（Claudeが出力したテキストから）
    transcript = input_data.get("transcript", [])
    if not transcript:
        sys.exit(0)

    # 最後のAssistantメッセージを取得
    last_assistant = ""
    for msg in reversed(transcript):
        if msg.get("role") == "assistant":
            for block in msg.get("content", []):
                if block.get("type") == "text":
                    last_assistant = block.get("text", "")
                    break
            break

    if not last_assistant:
        sys.exit(0)

    # 設定を読む
    config = get_config()
    today = datetime.now().strftime("%Y-%m-%d")

    # 保存内容を構築
    content = f"**会話日**: {today}\n\n{last_assistant[:500]}...\n"

    try:
        if config["obsidian"] and config["obsidian_path"]:
            save_to_obsidian(content, "会話ログ", config["obsidian_path"])
        else:
            save_to_memory(content, "会話ログ")
    except Exception:
        pass

    sys.exit(0)


if __name__ == "__main__":
    main()
