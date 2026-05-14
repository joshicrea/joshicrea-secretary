# フック設定.ps1
# git pre-commit hook をセットアップして、コミット前に パス検証.py を自動実行する
# 使い方: powershell -ExecutionPolicy Bypass -File ツール/フック設定.ps1

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$HookPath = "$RepoRoot\.git\hooks\pre-commit"

$hookContent = @'
#!/bin/sh
# joshicrea-secretary pre-commit hook: パス検証.py を自動実行
python3 "ツール/パス検証.py"
if [ $? -ne 0 ]; then
    echo ""
    echo "コミットがブロックされました。上記の問題を修正してから再度コミットしてください。"
    exit 1
fi
'@

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($HookPath, $hookContent, $utf8NoBom)

try { & git update-index --chmod=+x ".git/hooks/pre-commit" 2>$null } catch {}

Write-Host "pre-commit hook をセットアップしました: $HookPath"
Write-Host "次回 git commit 時から パス検証.py が自動実行されます。"
