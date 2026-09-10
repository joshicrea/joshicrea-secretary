#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""隔離HOMEへインストールした結果を検証する（CI用・クロスプラットフォーム）。

使い方: python verify_install.py <サンドボックスのHOME>
終了コード: 0=全項目OK / 1=NGあり

この検査が見ていない層:
  - 配置されたファイルの中身が正しいか（存在とプレースホルダ残存だけを見る）
  - Claude Code が実際にスキルを読めるか（起動を伴う検証は別）
  - MCPサーバーが接続できるか
"""
import pathlib
import sys

REQUIRED = [
    ("初回セットアップ.md", ("secretary", "初回セットアップ.md")),
    ("ユーザープロフィール.md", ("secretary", "ユーザープロフィール.md")),
    ("動作ルール.md", ("secretary", "動作ルール.md")),
    ("ナレッジ/_共通プロトコル.md", ("secretary", "ナレッジ", "_共通プロトコル.md")),
    ("AI秘書_秘書.md", ("rules", "AI秘書_秘書.md")),
]
MIN_RULES = 12
PLACEHOLDER = "{{SECRETARY_BASE_DIR}}"


def main() -> int:
    if len(sys.argv) < 2:
        print("使い方: verify_install.py <サンドボックスのHOME>")
        return 1
    claude = pathlib.Path(sys.argv[1]) / ".claude"
    rules = claude / "rules"
    ng = []

    for label, parts in REQUIRED:
        if not claude.joinpath(*parts).exists():
            ng.append("作成されていない: " + label)

    placed = sorted(rules.glob("AI秘書_*.md")) if rules.is_dir() else []
    print("配置された rules: {} 本".format(len(placed)))
    if len(placed) < MIN_RULES:
        ng.append("rules の配置数が足りない: {} 本（{} 本以上を期待）".format(len(placed), MIN_RULES))

    left = [f.name for f in placed if PLACEHOLDER in f.read_text(encoding="utf-8")]
    if left:
        ng.append("プレースホルダが残っている: " + ", ".join(left))

    if ng:
        for x in ng:
            print("NG: " + x)
        return 1
    print("全項目 OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
