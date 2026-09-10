# AI秘書プラグイン インストールスクリプト
# 対象ユーザー: IT初心者の女性起業家
#   Windows: PowerShell 5.1以上
#   Mac/Linux: PowerShell 7以上（pwsh）が必要
# 使い方: Claude Code のチャットに以下をそのままコピペしてください
#
#   以下のURLからAI秘書プラグインのインストールスクリプトを取得して、
#   内容を確認してから実行してください:
#   https://raw.githubusercontent.com/joshicrea/joshicrea-secretary/master/install.ps1
#

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# TLS 1.2 を明示的に有効化 for Windows PowerShell 5.1
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# winget 不在検知
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "winget が見つかりません。Microsoft Storeで「アプリ インストーラー」を更新してください:"
    Write-Host "https://www.microsoft.com/p/app-installer/9nblggh4nns1"
    exit 1
}

Write-Host ""
Write-Host "AI秘書プラグインをインストールしています..."
Write-Host ""

# UTF-8 BOMなしでファイルを書き込む（PS5.1/PS7両対応）
function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# --- OS判定・パス設定（Windows / Mac / Linux 共通対応）---
if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)) {
    $HomeDir = $env:USERPROFILE
} else {
    $HomeDir = $env:HOME
}
$TempDir    = [IO.Path]::GetTempPath()
$ClaudeDir  = [IO.Path]::Combine($HomeDir, ".claude")
$PluginsDir = [IO.Path]::Combine($ClaudeDir, "plugins")
$CacheDir   = [IO.Path]::Combine($PluginsDir, "cache", "joshicrea", "joshicrea-secretary")

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

$InstallPath = [IO.Path]::Combine($CacheDir, $shortSha)

# すでにインストール済みの場合はスキップ
if (Test-Path $InstallPath) {
    Write-Host "すでに最新版がインストールされています ($shortSha)"
} else {
    # --- ZIPをダウンロードして展開 ---
    $ZipUrl  = "https://github.com/joshicrea/joshicrea-secretary/archive/refs/heads/master.zip"
    $ZipPath = [IO.Path]::Combine($TempDir, "joshicrea-secretary.zip")
    $ExtTemp = [IO.Path]::Combine($TempDir, "joshicrea-extract-$shortSha")

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
$InstalledPath = [IO.Path]::Combine($PluginsDir, "installed_plugins.json")

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
$SettingsPath = [IO.Path]::Combine($ClaudeDir, "settings.json")

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
$RulesDir      = [IO.Path]::Combine($ClaudeDir, "rules")
$SecretaryBase = [IO.Path]::Combine($ClaudeDir, "secretary")
New-Item -ItemType Directory -Force -Path $RulesDir | Out-Null

# --- 既存ユーザー向けマイグレーション（旧英語名 → 新日本語名）---
# 旧バージョンからのアップグレード時のみ実行。新規ユーザーには無害。
$migrationsRules = @(
    @{ Old = "secretary.md"; New = "秘書.md" },
    @{ Old = "work-tools.md"; New = "使用ツール.md" }
)
foreach ($m in $migrationsRules) {
    $oldPath = [IO.Path]::Combine($RulesDir, $m.Old)
    $newPath = [IO.Path]::Combine($RulesDir, $m.New)
    if ((Test-Path $oldPath) -and (-not (Test-Path $newPath))) {
        Move-Item $oldPath $newPath -Force -ErrorAction SilentlyContinue
    } elseif ((Test-Path $oldPath) -and (Test-Path $newPath)) {
        # 両方ある場合は旧ファイルを削除（新ファイルが正）
        Remove-Item $oldPath -Force -ErrorAction SilentlyContinue
    }
}
$migrationsSecretary = @(
    @{ Old = "user-profile.md"; New = "ユーザープロフィール.md" },
    @{ Old = "work-tools.md"; New = "使用ツール.md" },
    @{ Old = "resources"; New = "素材" }
)
if (Test-Path $SecretaryBase) {
    foreach ($m in $migrationsSecretary) {
        $oldPath = [IO.Path]::Combine($SecretaryBase, $m.Old)
        $newPath = [IO.Path]::Combine($SecretaryBase, $m.New)
        if ((Test-Path $oldPath) -and (-not (Test-Path $newPath))) {
            Move-Item $oldPath $newPath -Force -ErrorAction SilentlyContinue
        }
    }
}
# 旧スキルディレクトリの削除（新スキルは新名でキャッシュから供給されるため、ユーザー側にあるなら旧キャッシュ）
# ~/.claude/skills/ 配下に古い英語名スキルが残っている場合は削除する
$UserSkillsDir = [IO.Path]::Combine($ClaudeDir, "skills")
$oldSkillNames = @("secretary","document","expense","goal","habit","memo","monthly-summary","payment","schedule","skill-creator","task")
if (Test-Path $UserSkillsDir) {
    foreach ($name in $oldSkillNames) {
        $oldSkillPath = [IO.Path]::Combine($UserSkillsDir, $name)
        if (Test-Path $oldSkillPath) {
            Remove-Item $oldSkillPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# rulesファイルをコピー（{{SECRETARY_BASE_DIR}}を実際のパスに置換）
# 2026-07-28 修正: 以前は元のファイル名のまま無条件に上書きしていた。
#  - お客様が自分で置いたルールと同名なら黙って破壊する
#  - どれがこのプラグインの置いたファイルか分からず、解約後も消せない
# 対策: 製品プレフィックスを付ける / 既存はバックアップ / 先頭に由来マーカーを入れる
$RulesPrefix = "AI秘書_"
$RulesMarker = "<!-- このファイルは joshicrea-secretary プラグインが配置しました。削除するとAI秘書の出力品質ルールが無効になります。アンインストール手順はプラグイン内の アンインストール.md を参照してください。 -->`n"
$RulesBackupDir = [IO.Path]::Combine($RulesDir, "_backup_secretary_" + (Get-Date -Format "yyyyMMddHHmmss"))
$BackedUp = 0
$RemovedOld = 0

$SourceRulesDir = [IO.Path]::Combine($InstallPath, ".claude", "rules")
foreach ($rulesFile in (Get-ChildItem $SourceRulesDir -Filter "*.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)) {
    $SourceFile = [IO.Path]::Combine($SourceRulesDir, $rulesFile)
    if (Test-Path $SourceFile) {
        $content = [System.IO.File]::ReadAllText($SourceFile, [System.Text.Encoding]::UTF8)
        $content = $content.Replace("{{SECRETARY_BASE_DIR}}", $SecretaryBase)

        $DestName = $RulesPrefix + $rulesFile
        $DestFile = [IO.Path]::Combine($RulesDir, $DestName)

        # 既存ファイルがこのプラグイン由来でなければ退避してから書く
        if (Test-Path $DestFile) {
            $existing = [System.IO.File]::ReadAllText($DestFile, [System.Text.Encoding]::UTF8)
            if (-not $existing.Contains("joshicrea-secretary")) {
                if (-not (Test-Path $RulesBackupDir)) { New-Item -ItemType Directory -Force -Path $RulesBackupDir | Out-Null }
                Write-Utf8NoBom -Path ([IO.Path]::Combine($RulesBackupDir, $DestName)) -Content $existing
                $BackedUp++
            }
        }

        Write-Utf8NoBom -Path $DestFile -Content ($RulesMarker + $content)

        # 旧バージョンがプレフィックスなしで置いたファイルを掃除する
        $LegacyFile = [IO.Path]::Combine($RulesDir, $rulesFile)
        if (Test-Path $LegacyFile) {
            $legacyContent = [System.IO.File]::ReadAllText($LegacyFile, [System.Text.Encoding]::UTF8)
            if ($legacyContent.Contains("joshicrea-secretary") -or $legacyContent.Contains("{{SECRETARY_BASE_DIR}}") -or $legacyContent.Contains($SecretaryBase)) {
                Remove-Item $LegacyFile -Force -ErrorAction SilentlyContinue
                $RemovedOld++
            }
        }
    }
}
if ($BackedUp -gt 0) { Write-Host "  既存の同名ファイル $BackedUp 件を $RulesBackupDir に退避しました" -ForegroundColor Yellow }
if ($RemovedOld -gt 0) { Write-Host "  旧バージョンが配置したファイル $RemovedOld 件を整理しました" -ForegroundColor Gray }

# --- SKILL.md の{{SECRETARY_BASE_DIR}}をプラグインキャッシュ内で置換 ---
# Skillツールはキャッシュ内のSKILL.mdを読む。絶対パスに置換しておかないとパスが壊れる。
$SourceSkillsDir = [IO.Path]::Combine($InstallPath, "skills")
Get-ChildItem $SourceSkillsDir -Recurse -Filter "SKILL.md" -ErrorAction SilentlyContinue | ForEach-Object {
    $skillContent = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    $skillReplaced = $skillContent.Replace("{{SECRETARY_BASE_DIR}}", $SecretaryBase)
    if ($skillReplaced -ne $skillContent) {
        Write-Utf8NoBom -Path $_.FullName -Content $skillReplaced
    }
}
Write-Host "ルールファイルとスキルを設定しました"

# --- email-mcp を展開して依存関係をインストール ---
$EmailMcpSrc = [IO.Path]::Combine($InstallPath, "ツール", "email-mcp")
$EmailMcpDst = [IO.Path]::Combine($SecretaryBase, "ツール", "email-mcp")
if (Test-Path $EmailMcpSrc) {
    if (-not (Test-Path $EmailMcpDst)) {
        New-Item -ItemType Directory -Force -Path $EmailMcpDst | Out-Null
    }
    Copy-Item ([IO.Path]::Combine($EmailMcpSrc, "index.js"))      $EmailMcpDst -Force
    Copy-Item ([IO.Path]::Combine($EmailMcpSrc, "package.json"))  $EmailMcpDst -Force
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Push-Location $EmailMcpDst
        npm install --silent 2>&1 | Out-Null
        Pop-Location
        Write-Host "email-mcp の依存パッケージをインストールしました"
    } else {
        Write-Host "警告: npm が見つかりません。独自ドメインメール連携を使う場合は Node.js をインストールしてください: https://nodejs.org/"
    }
}

# --- データディレクトリを作成 ---
$dirsToCreate = @(
    [IO.Path]::Combine($SecretaryBase, "memory", "学習ログ"),
    [IO.Path]::Combine($SecretaryBase, "memory", "タスク"),
    [IO.Path]::Combine($SecretaryBase, "素材")
)
foreach ($dir in $dirsToCreate) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# テンプレートをコピー（初回のみ・既存データを上書きしない）
# 旧パス（templates/）と新パス（テンプレート/）の両方を試行する
$TemplatesDir = [IO.Path]::Combine($InstallPath, "テンプレート")
if (-not (Test-Path $TemplatesDir)) {
    $TemplatesDir = [IO.Path]::Combine($InstallPath, "templates")
}
if (Test-Path $TemplatesDir) {
    Get-ChildItem $TemplatesDir -File | ForEach-Object {
        # 旧ファイル名 user-profile.md / work-tools.md は新ファイル名にマップする
        $destName = $_.Name
        if ($destName -eq "user-profile.md") { $destName = "ユーザープロフィール.md" }
        elseif ($destName -eq "work-tools.md") { $destName = "使用ツール.md" }
        $destFile = [IO.Path]::Combine($SecretaryBase, $destName)
        if (-not (Test-Path $destFile)) {
            Copy-Item $_.FullName $destFile -Force
        }
    }
}
# ナレッジをコピー（{{SECRETARY_BASE_DIR}}を実際のパスに置換）
# 2026-07-28 追加: rules/秘書.md と CLAUDE.md が {{SECRETARY_BASE_DIR}}/ナレッジ/_共通プロトコル.md を
# 参照しているのに、install がこのフォルダをコピーしておらず、参照が常に失敗していた。
$SourceKnowledgeDir = [IO.Path]::Combine($InstallPath, ".claude", "ナレッジ")
if (Test-Path $SourceKnowledgeDir) {
    $DestKnowledgeDir = [IO.Path]::Combine($SecretaryBase, "ナレッジ")
    New-Item -ItemType Directory -Force -Path $DestKnowledgeDir | Out-Null
    Get-ChildItem $SourceKnowledgeDir -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $c = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
        $c = $c.Replace("{{SECRETARY_BASE_DIR}}", $SecretaryBase)
        Write-Utf8NoBom -Path ([IO.Path]::Combine($DestKnowledgeDir, $_.Name)) -Content $c
    }
}

# 初回セットアップ手順を配置（毎回読ませないため rules/ ではなくデータ側に置く）
# 2026-09-10 追加: install.py 側にしか無く、Windows では配置されないまま
# rules/秘書.md の Phase 0-1 が読めと指示していた（購入者環境で手順書が不在になっていた）。
$OnboardingSrc = [IO.Path]::Combine($InstallPath, "初回セットアップ.md")
if (Test-Path $OnboardingSrc) {
    $c = [System.IO.File]::ReadAllText($OnboardingSrc, [System.Text.Encoding]::UTF8)
    $c = $c.Replace("{{SECRETARY_BASE_DIR}}", $SecretaryBase)
    Write-Utf8NoBom -Path ([IO.Path]::Combine($SecretaryBase, "初回セットアップ.md")) -Content $c
}

Write-Host "データフォルダを準備しました"

# --- インストール後の検証 ---
$verifyOk    = $true
$secMdPath   = [IO.Path]::Combine($RulesDir, ($RulesPrefix + "秘書.md"))
$profilePath = [IO.Path]::Combine($SecretaryBase, "ユーザープロフィール.md")
$onboardingPath = [IO.Path]::Combine($SecretaryBase, "初回セットアップ.md")
$requiredFiles = @($secMdPath, $profilePath, $onboardingPath)

foreach ($f in $requiredFiles) {
    if (-not (Test-Path $f)) {
        Write-Host "エラー: $f が作成されませんでした"
        $verifyOk = $false
    }
}
# 配置した rules 全ファイルにプレースホルダーが残っていないか確認
# 2026-07-28 修正: 以前は 秘書.md 1本しか検証しておらず、他10本の置換漏れを見逃していた
$placeholderLeft = @()
foreach ($f in (Get-ChildItem $RulesDir -Filter ($RulesPrefix + "*.md") -ErrorAction SilentlyContinue)) {
    $c = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    if ($c.Contains("{{SECRETARY_BASE_DIR}}")) { $placeholderLeft += $f.Name }
}
if ($placeholderLeft.Count -gt 0) {
    Write-Host ("エラー: パス置換が不完全なファイルがあります: " + ($placeholderLeft -join ", "))
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
