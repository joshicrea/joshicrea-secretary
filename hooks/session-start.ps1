# SessionStart hook for joshicrea-secretary plugin for Windows PowerShell
# CLAUDE.md 全文をセッションのコンテキストへ注入する。
#
# 2026-09-10 新設:
#  - これまで Windows では run-hook.cmd が Git for Windows の bash を探し、
#    見つからなければ何も実行せず exit /b 0 で「成功」として返していた。
#    対象ユーザーは Git を入れていない層なので、大半の Windows 環境で
#    この注入が丸ごと不発のまま「一見動いている」状態になっていた。
#  - AI経営者プラグインが既に採用している .ps1 優先方式に揃えて、
#    bash が無くても動くようにした。
#
#  このファイルは UTF-8 BOM 付きで保存すること。BOM が無いと Windows PowerShell 5.1 は
#  ANSI（日本語環境では CP932）として読み、スクリプト内の日本語リテラルが壊れる。

$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $ScriptDir
$ClaudeMd   = Join-Path $PluginRoot "CLAUDE.md"
$ErrorLog   = Join-Path $env:USERPROFILE ".claude\secretary\logs\hook_errors.log"

function Write-HookError {
    param([string]$Message)
    # fail-open でも無音にしない。失敗を後から観測できるようにする（bash 版と同じ方針）。
    try {
        $dir = Split-Path -Parent $ErrorLog
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $ErrorLog -Value "$stamp session-start.ps1: $Message" -Encoding UTF8
    } catch { }
}

if (-not (Test-Path $ClaudeMd)) {
    Write-HookError "CLAUDE.md が見つかりません: $ClaudeMd"
    exit 0
}

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $secretaryContent = [System.IO.File]::ReadAllText($ClaudeMd, $utf8NoBom)
} catch {
    Write-HookError "CLAUDE.md の読み込みに失敗しました: $_"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($secretaryContent)) {
    Write-HookError "CLAUDE.md が空です: $ClaudeMd"
    exit 0
}

$sessionContext = "<EXTREMELY_IMPORTANT>`nYou are an AI secretary (joshicrea-secretary plugin is active).`n`nThe following are your operating instructions. Follow them exactly:`n`n$secretaryContent`n</EXTREMELY_IMPORTANT>"

$payload = [PSCustomObject]@{
    hookSpecificOutput = [PSCustomObject]@{
        hookEventName     = "SessionStart"
        additionalContext = $sessionContext
    }
}

$json = $payload | ConvertTo-Json -Depth 10 -Compress

# stdout へ UTF-8 バイトを直接書く（[Console]::OutputEncoding の影響を受けない）
$bytes  = $utf8NoBom.GetBytes($json)
$stdout = [System.Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
