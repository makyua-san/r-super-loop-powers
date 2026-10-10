#Requires -Version 5.1
<#
  context-meter.ps1 -- PostToolUse hook (matcher: Agent) for r-super-loop-powers.

  The orchestrator cannot see its own context size, but the transcript can: the
  last assistant line's usage (input + cache_creation + cache_read) is the context
  of the latest request. While a goal loop is active, record it in hook-log.md and,
  at or above the threshold, tell Claude (as a fact) that the boundary-reset guideline
  is exceeded. Only the tail of the transcript is read.

  Env:
    RSLP_CTX_THRESHOLD   tokens (default 200000); test seam
    RSLP_HOOK_CHILD=1    skip (judge sessions)
  Fail-open: every failure exits 0 with no output.
  Saved as UTF-8 with BOM (the notice is Japanese).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hook-common.ps1')

$Threshold = 200000
if ($env:RSLP_CTX_THRESHOLD) { [void][int]::TryParse($env:RSLP_CTX_THRESHOLD, [ref]$Threshold) }
$TailBytes = 512 * 1024

function Get-ContextTokens([string]$Path) {
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try {
        $len = $fs.Length
        $start = [Math]::Max(0, $len - $TailBytes)
        [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] ([int]($len - $start))
        $got = 0
        while ($got -lt $buf.Length) {
            $n = $fs.Read($buf, $got, $buf.Length - $got)
            if ($n -le 0) { break }
            $got += $n
        }
        $text = $Utf8.GetString($buf, 0, $got)
    } finally { $fs.Dispose() }
    $lines = $text -split "`n"
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i].TrimEnd()
        if (-not $line.EndsWith('}')) { continue }          # a line still being written
        if ($line.IndexOf('"assistant"') -lt 0) { continue }
        $u = $line.IndexOf('"usage"')
        if ($u -lt 0) { continue }
        $chunk = $line.Substring($u, [Math]::Min(1000, $line.Length - $u))
        $sum = [int64]0
        foreach ($k in @('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens')) {
            $m = [regex]::Match($chunk, '"' + $k + '"\s*:\s*(\d+)')
            if ($m.Success) { $sum += [int64]$m.Groups[1].Value }
        }
        if ($sum -gt 0) { return $sum }
    }
    return [int64]0
}

if ($env:RSLP_HOOK_CHILD -eq '1') { exit 0 }
try { $hookInput = Read-StdinUtf8 | ConvertFrom-Json } catch { exit 0 }
if (-not $hookInput) { exit 0 }
$cwd = [string]$hookInput.cwd
if (-not $cwd) { $cwd = (Get-Location).Path }
$goalDir = $null
try { $goalDir = Find-GoalDir $cwd } catch { exit 0 }
if (-not $goalDir) { exit 0 }
$transcript = [string]$hookInput.transcript_path
if (-not $transcript -or -not (Test-Path -LiteralPath $transcript)) { exit 0 }

$tokens = [int64]0
try { $tokens = Get-ContextTokens $transcript } catch { exit 0 }
if ($tokens -le 0) { exit 0 }
$tool = [string]$hookInput.tool_name
Write-HookLogLine $goalDir 'CTX' "tokens=$tokens" "tool=$tool"
if ($tokens -ge $Threshold) {
    $man = [Math]::Round($tokens / 10000.0)
    $guide = [Math]::Round($Threshold / 10000.0)
    $msg = "[r-super-loop-powers] 現在の文脈は約 $man 万トークンで、境界リセットの目安($guide 万)を超えている。次の境界(B-6 PASS の中間クローズ後 / Checkpoint ACCEPT の確定処理後 / A-8 承認後 / 人間待ち)で SKILL.md「境界リセット」の手順を行う。"
    Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } }
}
exit 0
