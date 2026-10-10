#Requires -Version 5.1
<#
  loop-log.ps1 -- the orchestrator's bookkeeping in ONE call:
    call-log.md line   -Who <role> -Purpose <text> [-Phase <phase>]
    state.md fields    -SetPhase / -SetIntensity / -SetMilestone / -SetCheckpoint /
                       -SetOwner / -SetGate / -SetWait / -SetCodexRun / -Set 'key=value' /
                       -Clear 'key,key' (back to "-")
                       ("updated:" is refreshed whenever a field changes)
    resume marker      -Mark  (writes <goal-dir>/resume-pending after a dry build of
                       the resume packet; see resume-packet.ps1)
  Nothing is written when a requested field does not exist in state.md.
  Line endings follow the file (CRLF if it has any, else LF). UTF-8 without BOM.
  One named parameter per field because `powershell -File` cannot pass several
  values to one array parameter.
  Saved as UTF-8 with BOM: the state.md keys are Japanese.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GoalDir,
    [string]$Who = '',
    [string]$Purpose = '',
    [string]$Phase = '',
    [string]$SetPhase,
    [string]$SetIntensity,
    [string]$SetMilestone,
    [string]$SetCheckpoint,
    [string]$SetOwner,
    [string]$SetGate,
    [string]$SetWait,
    [string]$SetCodexRun,
    [string]$Set = '',
    # Comma-separated state.md keys to reset to "-" (none). A lone "-" cannot be passed
    # as a value through `powershell -File` (it is swallowed as "read from stdin").
    [string]$Clear = '',
    [switch]$Mark
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'codex-common.ps1')
$Roles = @('fable', 'codex-techpm', 'codex-review', 'codex-grareco', 'sonnet-builder')

function Stop-Failed([string]$Reason, [string]$Next) {
    Write-Kv 'STATUS' 'FAILED'
    Write-Kv 'REASON' $Reason
    if ($Next) { Write-Kv 'NEXT' $Next }
    exit 1
}

function Get-Field([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^\s*-\s*' + [regex]::Escape($Key) + ':[ \t]*([^\r\n]*)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

# Replace the value of "- <key>: ..." (the whole rest of the line). $null when absent.
function Set-Field([string]$Text, [string]$Key, [string]$Value) {
    $m = [regex]::Match($Text, '(?m)^(\s*-\s*' + [regex]::Escape($Key) + ':)[ \t]*[^\r\n]*')
    if (-not $m.Success) { return $null }
    return $Text.Substring(0, $m.Index) + $m.Groups[1].Value + ' ' + $Value + $Text.Substring($m.Index + $m.Length)
}

if (-not (Test-Path -LiteralPath $GoalDir -PathType Container)) { Stop-Failed "GoalDir does not exist: $GoalDir" '' }
$GoalDir = (Resolve-Path -LiteralPath $GoalDir).Path

# Named -Set* parameters -> state.md keys.
$map = [ordered]@{
    SetPhase = 'phase'; SetIntensity = '強度'; SetMilestone = 'milestone'; SetCheckpoint = '次のCheckpoint'
    SetOwner = '担当'; SetGate = '次のゲート'; SetWait = '待ち'; SetCodexRun = 'codex-run'
}
$updates = [ordered]@{}
foreach ($p in $map.Keys) {
    if ($PSBoundParameters.ContainsKey($p)) { $updates[$map[$p]] = [string]$PSBoundParameters[$p] }
}
if ($Set) {
    $i = $Set.IndexOf('=')
    if ($i -lt 1) { Stop-Failed "bad -Set '$Set' (expected key=value)" '' }
    $updates[$Set.Substring(0, $i).Trim()] = $Set.Substring($i + 1)
}
if ($Clear) {
    foreach ($k in ($Clear -split ',')) { if ($k.Trim()) { $updates[$k.Trim()] = '-' } }
}
# An empty value also means "none": state.md writes "-" for that.
foreach ($k in @($updates.Keys)) { if (-not ([string]$updates[$k]).Trim()) { $updates[$k] = '-' } }
if (-not $Who -and $updates.Count -eq 0 -and -not $Mark) { Stop-Failed 'nothing to do' 'pass -Who/-Purpose, one or more -Set* fields, and/or -Mark' }
if ($Who -and ($Roles -notcontains $Who)) { Stop-Failed "unknown -Who '$Who'" ('use one of: ' + ($Roles -join ', ')) }
if ($Who -and -not $Purpose) { Stop-Failed '-Who needs -Purpose' '' }

$stateFile = Join-Path $GoalDir 'state.md'
$stateText = Read-TextFile $stateFile
if (-not $stateText.Trim()) { Stop-Failed "state.md not found or empty: $stateFile" '' }
$now = Get-Date -Format 'yyyy-MM-dd HH:mm'

# 1. state.md -- validate every key before writing anything.
$newState = $stateText
foreach ($key in $updates.Keys) {
    $r = Set-Field $newState $key $updates[$key]
    if ($null -eq $r) { Stop-Failed "state.md has no field '$key'" 'nothing was written; valid fields: phase / 強度 / milestone / 次のCheckpoint / 担当 / 次のゲート / 待ち / codex-run (or any "- key:" line via -Set)' }
    $newState = $r
}
if ($updates.Count -gt 0) {
    $r = Set-Field $newState 'updated' $now
    if ($null -eq $r) { Stop-Failed "state.md has no field 'updated'" '' }
    $newState = $r
    Write-TextFile $stateFile $newState
    # stdout stays ASCII: the console code page differs between Bash and PowerShell
    # hosts, and the values are in the file anyway.
    $setNames = @()
    foreach ($p in $map.Keys) { if ($PSBoundParameters.ContainsKey($p)) { $setNames += $p } }
    if ($Set) { $setNames += 'Set' }
    if ($Clear) { $setNames += 'Clear' }
    Write-Kv 'SET' (('{0} field(s): ' -f $updates.Count) + ($setNames -join ', '))
    Write-Kv 'UPDATED' $now
}

# 2. call-log.md -- the phase is the one the call happened in (state.md before this update).
if ($Who) {
    if (-not $Phase) { $Phase = Get-Field $stateText 'phase' }
    $logFile = Join-Path $GoalDir 'call-log.md'
    $logText = Read-TextFile $logFile
    $nl = "`n"
    if ($logText.Contains("`r`n") -or ((-not $logText) -and $stateText.Contains("`r`n"))) { $nl = "`r`n" }
    $line = "$now | $Who | $Phase | $Purpose"
    if (-not $logText) { $logText = "# call-log — $(Split-Path -Leaf $GoalDir)$nl$nl" }
    elseif (-not $logText.EndsWith("`n")) { $logText += $nl }
    Write-TextFile $logFile ($logText + $line + $nl)
    Write-Kv 'LOGGED' ("$now | $Who | $Phase")
}

# 3. marker -- only after a dry build proves the packet can be made from these files.
if ($Mark) {
    $packet = Join-Path $PSScriptRoot 'resume-packet.ps1'
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = 'powershell' }
    # Build the injectable form too, so the hook's size warning shows up here, at mark time.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('rslp-mark-' + [guid]::NewGuid().ToString('N') + '.md')
    $out = & $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $packet -GoalDir $GoalDir -OutFile $tmp -MaxChars 9500 2>&1 | Out-String
    $code = $LASTEXITCODE
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    if ($code -ne 0) { Stop-Failed ('resume packet could not be built: ' + $out.Trim()) 'fix the goal files (state.md must exist); no marker was written' }
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -match '^CHARS: (\d+)') { Write-Kv 'INJECT_CHARS' $Matches[1] }
        elseif ($line -match '^WARN: ') { Write-Output $line }
    }
    $projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $GoalDir))
    $marker = Join-Path $GoalDir 'resume-pending'
    Write-TextFile $marker ('created: ' + (Get-Date).ToString('o') + "`ncwd: $projectRoot`n")
    Write-Kv 'MARKED' $marker
    Write-Kv 'NEXT' 'End the turn now and ask the human to run /clear, then send a short "continue" message. The SessionStart hook injects the packet.'
}
Write-Kv 'STATUS' 'OK'
exit 0
