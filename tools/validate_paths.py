#!/usr/bin/env python3
"""
joshicrea-secretary 相対パス検出バリデーター
コミット前に実行して相対パス漏れを検出する

使い方:
  python3 tools/validate_paths.py
  git commit 前に自動実行するには .git/hooks/pre-commit に追加
"""
import os, sys, re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLACEHOLDER = "{{SECRETARY_BASE_DIR}}"

# 相対パスとして検出するパターン（backtick内のファイルパス）
RELATIVE_PATH_PATTERNS = [
    r"`\.setup-status`",
    r"`templates/[^`]+`",
    r"`memory/[^`]+`",
    r"`resources/[^`]+`",
]

# スキャン対象外（プレースホルダーが展開済みのファイルや、バリデーター自体）
SKIP_FILES = {"validate_paths.py", "README.md", "ARCHITECTURE.md"}
SKIP_DIRS = {".git", "node_modules"}

def scan_file(path):
    issues = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        return issues

    for i, line in enumerate(lines, 1):
        for pattern in RELATIVE_PATH_PATTERNS:
            for m in re.finditer(pattern, line):
                # プレースホルダーが含まれている行は除外
                if PLACEHOLDER in line:
                    continue
                # コメント行は除外
                if line.strip().startswith("#"):
                    continue
                issues.append({
                    "line": i,
                    "text": line.rstrip(),
                    "match": m.group(0),
                    "pattern": pattern,
                })
    return issues

def main():
    total_issues = 0
    for root, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fname in files:
            if fname in SKIP_FILES:
                continue
            if not fname.endswith(".md"):
                continue
            path = os.path.join(root, fname)
            issues = scan_file(path)
            if issues:
                rel = os.path.relpath(path, REPO)
                print(f"\n{rel}:")
                for issue in issues:
                    print(f"  L{issue['line']}: {issue['match']}  ← 相対パス")
                    print(f"    {issue['text'][:100]}")
                total_issues += len(issues)

    if total_issues > 0:
        print(f"\n❌ {total_issues} 件の相対パスが残っています。")
        print(f"  修正方法: 相対パスを {{{{SECRETARY_BASE_DIR}}}}\\xxx の形式に変更してください。")
        sys.exit(1)
    else:
        print("✅ 相対パスの漏れなし。")
        sys.exit(0)

if __name__ == "__main__":
    main()
