# AI秘書プラグイン インストールスクリプト
# 対象ユーザー: IT初心者の女性起業家（PowerShell 5.1以上で動作）
# 使い方: Claude Codeのチャットに以下を貼り付けてEnter
#   次のPowerShellコマンドを実行してAI秘書プラグインをインストールしてください：
#   powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/joshicrea/joshicrea-secretary/master/install.ps1 | iex"
#   完了したら教えてください。

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # iwr の進捗UIを無効化（PS5.1でのハング防止）

Write-Host ""
Write-Host "AI秘書プラグインをインストールしています..."
Write-Host ""

# UTF-8 BOMなしでファイルを書き込む（PS5.1/PS7両対応）
function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# --- パス設定 ---
$ClaudeDir = "$env:USERPROFILE\.claude"
$PluginsDir = "$ClaudeDir\plugins"
$CacheDir   = "$PluginsDir\cache\joshicrea\joshicrea-secretary"

New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

# --- GitHubから最新コミット情報を取得 ---
try {
    $commitInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/joshicrea/joshicrea-secretary/commits/master" -Headers @{"User-Agent"="joshicrea-install"} -UseBasicParsing
    $fullSha = $commitInfo.sha
    $shortSha = $fullSha.Substring(0, 12)
} catch {
    Write-Host "GitHubへの接続に失敗しました。インターネット接続を確認してください。"
    exit 1
}

$InstallPath = "$CacheDir\$shortSha"

# すでにインストール済みの場合はスキップ
if (Test-Path $InstallPath) {
    Write-Host "すでに最新版がインストールされています ($shortSha)"
} else {
    # --- ZIPをダウンロードして展開 ---
    $ZipUrl  = "https://github.com/joshicrea/joshicrea-secretary/archive/refs/heads/master.zip"
    $ZipPath = "$env:TEMP\joshicrea-secretary.zip"
    $ExtTemp = "$env:TEMP\joshicrea-extract-$shortSha"

    try {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
    } catch {
        Write-Host "ダウンロードに失敗しました: $_"
        exit 1
    }

    if (Test-Path $ExtTemp) { Remove-Item $ExtTemp -Recurse -Force }
    Expand-Archive -Path $ZipPath -DestinationPath $ExtTemp -Force

    # GitHubのZIPは "{repo}-master" フォルダに展開される
    $ExtractedFolder = Get-ChildItem $ExtTemp | Select-Object -First 1
    Move-Item $ExtractedFolder.FullName $InstallPath -Force
    Remove-Item $ExtTemp -Force -ErrorAction SilentlyContinue
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue

    Write-Host "ダウンロード完了 ($shortSha)"
}

# --- installed_plugins.json を更新 ---
$InstalledPath = "$PluginsDir\installed_plugins.json"

if (Test-Path $InstalledPath) {
    $Installed = Get-Content $InstalledPath -Raw | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force -Path $PluginsDir | Out-Null
    $Installed = [PSCustomObject]@{
        version = 2
        plugins = [PSCustomObject]@{}
    }
}

$PluginEntry = [PSCustomObject]@{
    scope        = "user"
    installPath  = $InstallPath
    version      = $shortSha
    installedAt  = (Get-Date -Format "o")
    lastUpdated  = (Get-Date -Format "o")
    gitCommitSha = $fullSha
}

$Key = "joshicrea-secretary@joshicrea"
if ($Installed.plugins.PSObject.Properties[$Key]) {
    $Installed.plugins.PSObject.Properties[$Key].Value = @($PluginEntry)
} else {
    $Installed.plugins | Add-Member -Name $Key -Value @($PluginEntry) -MemberType NoteProperty
}

Write-Utf8NoBom -Path $InstalledPath -Content ($Installed | ConvertTo-Json -Depth 10)

# --- settings.json に enabledPlugins を追加 ---
$SettingsPath = "$ClaudeDir\settings.json"

if (Test-Path $SettingsPath) {
    $Settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
} else {
    $Settings = [PSCustomObject]@{}
}

if (-not ($Settings.PSObject.Properties["enabledPlugins"])) {
    $Settings | Add-Member -Name "enabledPlugins" -Value ([PSCustomObject]@{}) -MemberType NoteProperty
}

if ($Settings.enabledPlugins.PSObject.Properties[$Key]) {
    $Settings.enabledPlugins.PSObject.Properties[$Key].Value = $true
} else {
    $Settings.enabledPlugins | Add-Member -Name $Key -Value $true -MemberType NoteProperty
}

Write-Utf8NoBom -Path $SettingsPath -Content ($Settings | ConvertTo-Json -Depth 10)

# --- 完了 ---
Write-Host ""
Write-Host "インストール完了！"
Write-Host ""
Write-Host "次の手順:"
Write-Host "  1. Claude Code を完全に閉じる"
Write-Host "  2. Claude Code を再度開く"
Write-Host "  3. チャットに「はじめまして」と送るとセットアップが始まります"
Write-Host ""
