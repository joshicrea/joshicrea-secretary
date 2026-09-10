# セッションログ hook ラッパー for Windows PowerShell (joshicrea-secretary)
# run-hook.cmd 経由で UserPromptSubmit / Stop から呼ばれる。
# python(または python3) で session_log.py を実行する。
# Python が無い環境では静かに終了し、ツール本体には一切影響させない（bash 版と同じ方針）。
#
# 2026-09-10 新設: Git for Windows の bash が無い環境でも動くようにするため。

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Event     = if ($args.Count -ge 1) { $args[0] } else { "" }
$Target    = Join-Path $ScriptDir "session_log.py"

foreach ($exe in @("python3", "python", "py")) {
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue
    if ($cmd) {
        try { & $cmd.Source $Target $Event 2>$null | Out-Null } catch { }
        break
    }
}

exit 0
