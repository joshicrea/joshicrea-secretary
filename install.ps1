# AI秘書プラグイン インストールスクリプト
# 対象ユーザー: IT初心者の女性起業家（PowerShell 5.1以上で動作）
# 使い方: Claude Code のチャットに以下をそのままコピペしてください
#
#   以下のURLからAI秘書プラグインのインストールスクリプトを取得して、
#   内容を確認してから実行してください:
#   https://raw.githubusercontent.com/joshicrea/joshicrea-secretary/master/install.ps1
#

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
    $Installed = [System.IO.File]::ReadAllText($InstalledPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
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
    $Settings = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
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

# --- rules/*.md をユーザーグローバルルールとして配置 ---
# プラグインキャッシュ内の.claude/rules/はClaude Codeに読み込まれない。
# ~/.claude/rules/ に直接コピーすることで確実にシステムコンテキストに読み込まれる。
$RulesDir = "$ClaudeDir\rules"
New-Item -ItemType Directory -Force -Path $RulesDir | Out-Null

$SecretaryBase = "$env:USERPROFILE\.claude\secretary"

# rulesファイルをコピー（{{SECRETARY_BASE_DIR}}を実際のパスに置換）
foreach ($rulesFile in (Get-ChildItem "$InstallPath\.claude\rules" -Filter "*.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)) {
    $SourceFile = "$InstallPath\.claude\rules\$rulesFile"
    if (Test-Path $SourceFile) {
        $content = [System.IO.File]::ReadAllText($SourceFile, [System.Text.Encoding]::UTF8)
        $content = $content.Replace("{{SECRETARY_BASE_DIR}}", $SecretaryBase)
        Write-Utf8NoBom -Path "$RulesDir\$rulesFile" -Content $content
    }
}

# --- SKILL.md の{{SECRETARY_BASE_DIR}}をプラグインキャッシュ内で置換 ---
# Skillツールはキャッシュ内のSKILL.mdを読む。絶対パスに置換しておかないとパスが壊れる。
Get-ChildItem "$InstallPath\.claude\skills" -Recurse -Filter "SKILL.md" -ErrorAction SilentlyContinue | ForEach-Object {
    $skillContent = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    $skillReplaced = $skillContent.Replace("{{SECRETARY_BASE_DIR}}", $SecretaryBase)
    if ($skillReplaced -ne $skillContent) {
        Write-Utf8NoBom -Path $_.FullName -Content $skillReplaced
    }
}
Write-Host "ルールファイルとスキルを設定しました"

# --- データディレクトリを作成 ---
$dirsToCreate = @(
    "$SecretaryBase\memory\学習ログ",
    "$SecretaryBase\memory\タスク",
    "$SecretaryBase\resources"
)
foreach ($dir in $dirsToCreate) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# テンプレートをコピー（初回のみ・既存データを上書きしない）
$TemplatesDir = "$InstallPath\templates"
if (Test-Path $TemplatesDir) {
    Get-ChildItem $TemplatesDir -File | ForEach-Object {
        $destFile = "$SecretaryBase\$($_.Name)"
        if (-not (Test-Path $destFile)) {
            Copy-Item $_.FullName $destFile -Force
        }
    }
}
Write-Host "データフォルダを準備しました"

# --- インストール後の検証 ---
$verifyOk = $true
$requiredFiles = @(
    "$RulesDir\secretary.md",
    "$SecretaryBase\user-profile.md"
)
foreach ($f in $requiredFiles) {
    if (-not (Test-Path $f)) {
        Write-Host "エラー: $f が作成されませんでした"
        $verifyOk = $false
    }
}
# secretary.mdにプレースホルダーが残っていないか確認
$secContent = [System.IO.File]::ReadAllText("$RulesDir\secretary.md", [System.Text.Encoding]::UTF8)
if ($secContent.Contains("{{SECRETARY_BASE_DIR}}")) {
    Write-Host "エラー: secretary.mdのパス置換が不完全です"
    $verifyOk = $false
}
if (-not $verifyOk) {
    Write-Host ""
    Write-Host "インストールに問題が発生しました。もう一度試してください。"
    exit 1
}

# --- 完了 ---
Write-Host ""
Write-Host "インストール完了！"
Write-Host ""
Write-Host "次の手順:"
Write-Host "  1. Claude Code を完全に閉じる"
Write-Host "  2. Claude Code を再度開く"
Write-Host "  3. チャットに「はじめまして」と送るとセットアップが始まります"
Write-Host ""
