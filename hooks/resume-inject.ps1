#Requires -Version 5.1
<#
  resume-inject.ps1 -- SessionStart hook for r-super-loop-powers (matcher: startup|clear).

  When the orchestrator left a marker <goal-dir>/resume-pending (loop-log.ps1 -Mark) and
  the session (re)starts in that project, build the resume packet NOW from the goal's
  files (resume-packet.ps1) and hand it to Claude as additionalContext. The marker is
  used once and removed. Markers older than 24 h are discarded (STALE). If the packet
  cannot be built, the marker is renamed to resume-pending.failed and ERROR is logged;
  the orchestrator then resumes the old way (startup check 3 reads state.md).

  Fail-open: every failure exits 0 with no output. Log lines go to <goal-dir>/hook-log.md.
  Saved as UTF-8 with BOM (shared helpers match Japanese).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hook-common.ps1')

$MaxAgeHours = 24
$MaxChars = 9500

function Get-MarkerCreated($File) {
    $text = ''
    try { $text = [System.IO.File]::ReadAllText($File.FullName, $Utf8) } catch { }
    $m = [regex]::Match($text, '(?m)^created:\s*(\S+)')
    if ($m.Success) {
        try { return [datetime]::Parse($m.Groups[1].Value, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch { }
    }
    return $File.LastWriteTime
}

try { $hookInput = Read-StdinUtf8 | ConvertFrom-Json } catch { exit 0 }
if (-not $hookInput) { exit 0 }
$source = [string]$hookInput.source
if (@('startup', 'clear') -notcontains $source) { exit 0 }
$cwd = [string]$hookInput.cwd
if (-not $cwd) { $cwd = (Get-Location).Path }
$root = Join-Path $cwd 'docs\r-super-loop-powers'
if (-not (Test-Path -LiteralPath $root)) { exit 0 }

$markers = @(Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
        Get-Item -LiteralPath (Join-Path $_.FullName 'resume-pending') -ErrorAction SilentlyContinue } | Where-Object { $_ })
if ($markers.Count -eq 0) { exit 0 }

$now = Get-Date
$valid = @()
foreach ($mk in $markers) {
    $created = Get-MarkerCreated $mk
    if (($now - $created).TotalHours -gt $MaxAgeHours) {
        Remove-Item -LiteralPath $mk.FullName -Force -ErrorAction SilentlyContinue
        Write-HookLogLine $mk.DirectoryName 'STALE' "source=$source" ('marker created ' + $created.ToString('s') + ' discarded')
        continue
    }
    $valid += [pscustomobject]@{ File = $mk; Created = $created }
}
if ($valid.Count -eq 0) { exit 0 }
$pick = $valid | Sort-Object Created | Select-Object -Last 1
$goalDir = $pick.File.DirectoryName

$packetScript = Join-Path $PSScriptRoot '..\skills\r-super-loop-powers\bin\resume-packet.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('rslp-resume-' + [guid]::NewGuid().ToString('N') + '.md')
try {
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = 'powershell' }
    $out = & $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $packetScript -GoalDir $goalDir -OutFile $tmp -MaxChars $MaxChars 2>&1 | Out-String
    $code = $LASTEXITCODE
    $packet = ''
    if ($code -eq 0 -and (Test-Path -LiteralPath $tmp)) { $packet = [System.IO.File]::ReadAllText($tmp, $Utf8) }
    if (-not $packet.Trim()) { throw "resume-packet.ps1 exited $code : $($out.Trim())" }
    if ($packet.Length -gt $MaxChars) { $packet = $packet.Substring(0, $MaxChars) }
    Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $packet } }
    Remove-Item -LiteralPath $pick.File.FullName -Force -ErrorAction SilentlyContinue
    Write-HookLogLine $goalDir 'RESUME' "source=$source" "chars=$($packet.Length)"
} catch {
    try { Move-Item -LiteralPath $pick.File.FullName -Destination ($pick.File.FullName + '.failed') -Force } catch { }
    Write-HookLogLine $goalDir 'ERROR' "source=$source" $_.Exception.Message
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
exit 0
