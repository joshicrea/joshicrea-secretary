#!/usr/bin/env python3
"""
joshicrea-secretary 開発時バリデーター
コミット前に実行して問題を検出する

使い方:
  python3 tools/validate_paths.py
  git commit 前に自動実行: tools/setup-hooks.ps1 を実行してください
"""
import os, sys, re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLACEHOLDER = "{{SECRETARY_BASE_DIR}}"

# ----------------------------------------------------------------
# Check 1: .md ファイルの相対パス検出
# ----------------------------------------------------------------
RELATIVE_PATH_PATTERNS = [
    r"`\.setup-status`",
    r"`templates/[^`]+`",
    r"`memory/[^`]+`",
    r"`resources/[^`]+`",
]

SKIP_FILES_MD = {"validate_paths.py", "README.md", "ARCHITECTURE.md", "CONTRIBUTING.md", "SKILL-template.md"}
SKIP_DIRS = {".git", "node_modules"}

def check_md_relative_paths():
    issues = []
    for root, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fname in files:
            if fname in SKIP_FILES_MD or not fname.endswith(".md"):
                continue
            path = os.path.join(root, fname)
            try:
                lines = open(path, encoding="utf-8").readlines()
            except Exception:
                continue
            for i, line in enumerate(lines, 1):
                for pat in RELATIVE_PATH_PATTERNS:
                    for m in re.finditer(pat, line):
                        if PLACEHOLDER in line or line.strip().startswith("#"):
                            continue
                        issues.append({"file": os.path.relpath(path, REPO), "line": i,
                                       "text": line.rstrip(), "match": m.group(0)})
    return issues

# ----------------------------------------------------------------
# Check 2: .ps1 ファイルの禁止パターン検出
#   - Get-Content で設定JSONを読む（PS5.1でUTF-8を壊す）
#   - iwr ... | iex （WebResponseObjectをiexに渡して失敗する）
#   - Write-Host "...日本語..." で -Encoding なし（任意）
# ----------------------------------------------------------------
PS1_FORBIDDEN = [
    # (pattern, 説明, 正しい書き方)
    (r'Get-Content\s+\$\w+\s+(-Raw\s+)?\|\s*ConvertFrom-Json',
     "Get-Content | ConvertFrom-Json は PS5.1 で UTF-8 JSON を壊す",
     "[System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json"),
    (r'iwr\s+https?://[^\s|]+\s*\|\s*iex',
     "iwr | iex は WebResponseObject をそのまま渡して失敗する",
     "(iwr https://... -UseBasicParsing).Content | iex"),
    (r'Get-Content\s+-Path\s+\S+\s+-Encoding\s+(?!UTF8)',
     "Get-Content の -Encoding が UTF8 以外",
     "Get-Content -Path $path -Encoding UTF8 または [System.IO.File]::ReadAllText を使う"),
]

SKIP_FILES_PS1 = {"setup-hooks.ps1"}

def check_ps1_patterns():
    issues = []
    for root, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fname in files:
            if fname in SKIP_FILES_PS1 or not fname.endswith(".ps1"):
                continue
            path = os.path.join(root, fname)
            try:
                lines = open(path, encoding="utf-8").readlines()
            except Exception:
                continue
            for i, line in enumerate(lines, 1):
                if line.strip().startswith("#"):
                    continue
                for pat, desc, fix in PS1_FORBIDDEN:
                    if re.search(pat, line):
                        issues.append({"file": os.path.relpath(path, REPO), "line": i,
                                       "text": line.rstrip(), "desc": desc, "fix": fix})
    return issues

# ----------------------------------------------------------------
# Check 3: .claude/rules/ と install.ps1 の整合性
#   - .claude/rules/ に .md があるのに install.ps1 が動的コピーしていない
# ----------------------------------------------------------------
def check_rules_coverage():
    issues = []
    rules_dir = os.path.join(REPO, ".claude", "rules")
    install_ps1 = os.path.join(REPO, "install.ps1")
    if not os.path.exists(rules_dir) or not os.path.exists(install_ps1):
        return issues
    rules_files = [f for f in os.listdir(rules_dir) if f.endswith(".md")]
    install_content = open(install_ps1, encoding="utf-8").read()
    # 動的コピー（Get-ChildItem ... -Filter "*.md"）が使われているか確認
    if 'Get-ChildItem' in install_content and '.claude\\rules' in install_content and '*.md' in install_content:
        return issues  # 動的コピーOK
    # 静的リストの場合: 各ファイルが含まれているか確認
    for fname in rules_files:
        if fname not in install_content:
            issues.append({"file": "install.ps1", "line": 0,
                           "text": f".claude/rules/{fname}",
                           "desc": f"{fname} が install.ps1 の rules コピーリストにない",
                           "fix": "install.ps1 の foreach ($rulesFile in ...) に追加するか、動的コピーに変更する"})
    return issues

# ----------------------------------------------------------------
# main
# ----------------------------------------------------------------
def main():
    total = 0

    md_issues = check_md_relative_paths()
    if md_issues:
        print(f"\n[Check 1] .md ファイルの相対パス ({len(md_issues)} 件)")
        for iss in md_issues:
            print(f"  {iss['file']}:L{iss['line']}: {iss['match']}")
            print(f"    {iss['text'][:100]}")
        total += len(md_issues)
    else:
        print("[Check 1] .md 相対パス: OK")

    ps1_issues = check_ps1_patterns()
    if ps1_issues:
        print(f"\n[Check 2] .ps1 禁止パターン ({len(ps1_issues)} 件)")
        for iss in ps1_issues:
            print(f"  {iss['file']}:L{iss['line']}: {iss['desc']}")
            print(f"    正しい書き方: {iss['fix']}")
        total += len(ps1_issues)
    else:
        print("[Check 2] .ps1 禁止パターン: OK")

    rules_issues = check_rules_coverage()
    if rules_issues:
        print(f"\n[Check 3] rules/install.ps1 整合性 ({len(rules_issues)} 件)")
        for iss in rules_issues:
            print(f"  {iss['desc']}")
            print(f"    対応: {iss['fix']}")
        total += len(rules_issues)
    else:
        print("[Check 3] rules/install.ps1 整合性: OK")

    if total > 0:
        print(f"\nNG: {total} 件の問題が見つかりました。コミット前に修正してください。")
        sys.exit(1)
    else:
        print("\nOK: 全チェック通過。コミットできます。")
        sys.exit(0)

if __name__ == "__main__":
    main()
