echo --% >/dev/null;: ' | out-null
<#'
# ---------------------------------------------------------------------------
# run-hook.ps1 : hook dispatcher that is BOTH a PowerShell script and a POSIX
# shell script. hooks.json calls it with a leading dot:
#
#     . "${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.ps1" <name> [args...]
#
# The dot means "run this file here" in both shells, so the same command line
# works whichever shell Claude Code uses for hooks:
#   - macOS / Linux, and Windows with Git Bash : bash or zsh reads this part.
#   - Windows without Git Bash                 : PowerShell reads the part
#                                                after the end of this block.
#   (Never type the two characters "#" ">" next to each other in this block:
#    PowerShell would end its comment there.)
#
# Why (2026-10-28):
#   The old command was  "<root>/hooks/run-hook.cmd" <name> . On Windows
#   machines without Git Bash, Claude Code runs hooks with PowerShell, and
#   PowerShell cannot parse a quoted path followed by an argument, so every
#   hook failed with a parse error and the SessionStart injection never ran.
#   The old route also went claude -> shell -> cmd.exe -> powershell.exe.
#   Every extra console program in that chain is one more chance for a
#   console window to appear. Here the PowerShell route runs the hook inside
#   the PowerShell that Claude Code already started (no cmd.exe, no second
#   powershell.exe), and the Git Bash route skips cmd.exe.
#
# Rules for editing this file:
#   - Keep it ASCII only (Windows PowerShell 5.1 reads BOM-less files as ANSI).
#   - Keep LF line endings (.gitattributes pins this file to eol=lf; a CR
#     breaks the shell part on macOS).
#   - Do not change the first two lines. They make each shell skip the other
#     shell's part. Line 1 prints nothing in either shell.
#   - Never write to stdout here. SessionStart stdout must be exactly the
#     JSON that the hook script prints.
# ---------------------------------------------------------------------------
_rh_self="${BASH_SOURCE:-$0}"
_rh_dir="$(cd "$(dirname "$_rh_self")" && pwd)"
_rh_name="${1:-}"
if [ -z "$_rh_name" ]; then
    echo "run-hook.ps1: missing script name" >&2
    exit 1
fi
shift
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
        # Windows with Git Bash: run the PowerShell version directly (no cmd.exe).
        if [ -f "${_rh_dir}/${_rh_name}.ps1" ]; then
            exec powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${_rh_dir}/${_rh_name}.ps1" "$@"
        fi
        ;;
esac
if [ -f "${_rh_dir}/${_rh_name}" ]; then
    exec bash "${_rh_dir}/${_rh_name}" "$@"
fi
echo "run-hook.ps1: ${_rh_name} not found in ${_rh_dir}" >&2
exit 1
#>
# ---------------------------- PowerShell part ------------------------------
# Runs inside the PowerShell process Claude Code started for this hook. The
# hook script is called with & (its own scope), so its "exit N" ends only that
# script; the code is then passed on as this hook's exit code.
if ($args.Count -lt 1) {
    [Console]::Error.WriteLine("run-hook.ps1: missing script name")
    exit 1
}
$__rhName = [string]$args[0]
$__rhRest = @($args | Select-Object -Skip 1)
$__rhDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$__rhPs1  = Join-Path $__rhDir ($__rhName + ".ps1")
if (-not (Test-Path -LiteralPath $__rhPs1)) {
    [Console]::Error.WriteLine("run-hook.ps1: ERROR - $__rhName.ps1 was not found. Please report this to info@joshicrea.com.")
    exit 1
}
$global:LASTEXITCODE = 0
& $__rhPs1 @__rhRest
if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
