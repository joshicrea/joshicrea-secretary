# 起業家オンラインコワーキング（会員サイト /coworking）在席心拍。
# {{SECRETARY_BASE_DIR}}\cw-token.txt にトークンがあるときだけ、会員サイトの
# /api/cw/heartbeat を叩いて「AI秘書起動中=在席」を伝える。
#
# fail-open: トークン未設定・通信失敗のいずれも、このスクリプトの主目的（AI秘書の
# 通常動作）を妨げない。何もせず exit 0 で終える。async 実行なのでユーザー体感への
# 影響もない。
#
# トークンの取得方法: 会員サイト /coworking/settings で発行し、このファイルに1行貼る。
#
# SECRETARY_BASE_DIR は常に ~/.claude/secretary（install.py の SECRETARY_BASE と同じ定義）。
# 他の秘書ファイルは {{SECRETARY_BASE_DIR}} プレースホルダーをインストール時に静的展開するが、
# hooks/*.ps1 はその置換対象（install.py が rules/ナレッジ/skills のみを対象にしている）に
# 含まれないため、ここでは実行時に $env:USERPROFILE から組み立てる。

$ErrorActionPreference = "Continue"

$SecretaryBase = Join-Path $env:USERPROFILE ".claude\secretary"
$TokenFile = Join-Path $SecretaryBase "cw-token.txt"
if (-not (Test-Path $TokenFile)) {
    exit 0
}

$Token = (Get-Content -Path $TokenFile -Raw -ErrorAction SilentlyContinue)
if ([string]::IsNullOrWhiteSpace($Token)) {
    exit 0
}
$Token = $Token.Trim()

try {
    Invoke-WebRequest -Uri "https://eventsnews.info/api/cw/heartbeat" `
        -Method POST `
        -Headers @{ "Authorization" = "Bearer $Token" } `
        -TimeoutSec 5 `
        -UseBasicParsing | Out-Null
} catch {
    # 通信失敗は無視する（コワーキング未契約・オフライン等）。ログにも残さない
    # （毎回のプロンプトで呼ばれるため、失敗をログすると secretary のログが埋まる）
}

exit 0
