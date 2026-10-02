#Requires -Version 5.1
<#
  impl-check.ps1 -- judge one builder (Sonnet subagent) delegation by comparing its
  self-report with what git actually shows. A returned report is not a finished
  milestone: this script is the only thing that may call it OK.

  Emits "KEY: VALUE" lines; the last three are STATUS / REASON / NEXT.
  STATUS: OK | MALFORMED | CONTRACT_VIOLATION | BLOCKED | INCOMPLETE
  Exit code 0 only on OK.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReportFile,
    [Parameter(Mandatory = $true)][string]$WorkDir,
    # git HEAD recorded right before the delegation (impl-runs/<label>.base.txt).
    [Parameter(Mandatory = $true)][string]$BaseRef,
    # Orchestrator-owned paths (state.md, impl-runs/...) that live in the target
    # repo but are not implementation work. Repo-relative, forward slashes.
    [string[]]$IgnorePath = @('docs/r-super-loop-powers/')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'codex-common.ps1')

function Complete-Check([string]$Status, [string]$Reason, [string]$Next) {
    Write-Kv 'STATUS' $Status
    Write-Kv 'REASON' $Reason
    Write-Kv 'NEXT' $Next
    if ($Status -eq 'OK') { exit 0 }
    exit 1
}

function ConvertTo-RepoPath([string]$Path, [string]$Root) {
    $p = ([string]$Path).Trim().Trim('"')
    $p = $p.Replace([char]92, [char]47)
    $r = $Root.Replace([char]92, [char]47).TrimEnd('/') + '/'
    if ($p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { $p = $p.Substring($r.Length) }
    if ($p.StartsWith('./')) { $p = $p.Substring(2) }
    return $p
}

$required = @('summary', 'changed_files', 'verification', 'acceptance_criteria',
    'new_assumptions', 'unresolved', 'blocked', 'blocked_reason', 'committed')
$redo = 'Re-delegate once with the same prompt. If it happens again, escalate (B-4).'

if (-not (Test-Path -LiteralPath $WorkDir)) { throw "WorkDir does not exist: $WorkDir" }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
Write-Kv 'REPORT_FILE' $ReportFile
Write-Kv 'BASE_REF' $BaseRef

# --- 1. parse the report ------------------------------------------------------
$text = Read-TextFile $ReportFile
if (-not $text.Trim()) { Complete-Check 'MALFORMED' "the report is empty or missing: $ReportFile" $redo }
$fences = [regex]::Matches($text, '(?s)```(?:json)?\s*(\{.*?\})\s*```')
if ($fences.Count -gt 0) { $jsonText = $fences[$fences.Count - 1].Groups[1].Value } else { $jsonText = $text.Trim() }
$report = $null
try { $report = $jsonText | ConvertFrom-Json } catch { $report = $null }
if (-not $report) { Complete-Check 'MALFORMED' 'the report does not contain a readable JSON object.' $redo }
$missing = @($required | Where-Object { $report.PSObject.Properties.Name -notcontains $_ })
if ($missing.Count -gt 0) { Complete-Check 'MALFORMED' ("the report is missing: " + ($missing -join ', ')) $redo }

$reported = @(@($report.changed_files) | Where-Object { $_ } | ForEach-Object { ConvertTo-RepoPath $_ $WorkDir })
$ran = @(@($report.verification) | Where-Object { $_ -and $_.outcome -ne 'SKIPPED' })
$failed = @(@($report.verification) | Where-Object { $_ -and $_.outcome -eq 'FAIL' })
$criteria = @(@($report.acceptance_criteria) | Where-Object { $_ })
$unmet = @($criteria | Where-Object { $_.status -ne 'MET' })
foreach ($a in @($report.new_assumptions)) { if ($a) { Write-Kv 'NEW_ASSUMPTION' $a } }
foreach ($u in @($report.unresolved)) { if ($u) { Write-Kv 'UNRESOLVED' $u } }

# --- 2. what git actually shows -----------------------------------------------
$ErrorActionPreference = 'Continue'
$head = (& git -C $WorkDir rev-parse HEAD 2>$null | Out-String).Trim()
$porcelain = @(& git -C $WorkDir status --porcelain --untracked-files=all 2>$null | Where-Object { $_ })
$ErrorActionPreference = 'Stop'

$actual = @()
foreach ($line in $porcelain) {
    $p = $line.Substring(3)
    if ($p -match ' -> ') { $p = ($p -split ' -> ')[-1] }
    $p = ConvertTo-RepoPath $p $WorkDir
    $ignored = $false
    foreach ($ig in $IgnorePath) { if ($ig -and $p.StartsWith($ig, [StringComparison]::OrdinalIgnoreCase)) { $ignored = $true } }
    if (-not $ignored) { $actual += $p }
}
Write-Kv 'HEAD' $head
Write-Kv 'CHANGED_FILES_REPORTED' ($reported -join ', ')
Write-Kv 'CHANGED_FILES_ACTUAL' ($actual -join ', ')
foreach ($p in $actual) {
    if (-not ($reported | Where-Object { $_ -ieq $p })) { Write-Kv 'WARN' "unreported change: $p" }
}
Write-Kv 'REPORT' ("blocked=$($report.blocked) committed=$($report.committed) verifications_run=$($ran.Count) verifications_failed=$($failed.Count) criteria=$($criteria.Count) criteria_unmet=$($unmet.Count)")
foreach ($u in ($unmet | Select-Object -First 5)) { Write-Kv 'CRITERION_UNMET' ("[$($u.status)] $($u.criterion)") }

# --- 3. verdict (first match wins; order is the spec's section 4) --------------
if ($report.committed -eq $true -or ($head -and $head -ne $BaseRef.Trim())) {
    Complete-Check 'CONTRACT_VIOLATION' "the builder committed (committed=$($report.committed), HEAD $BaseRef -> $head). Commits belong to the orchestrator." 'Inspect git log / git status first, undo the commit if unwanted, then decide whether to keep the work.'
}
if ($report.blocked -eq $true) {
    Complete-Check 'BLOCKED' "the builder stopped without finishing: $($report.blocked_reason)" 'Do NOT advance the milestone. Resolve the blocker or escalate (B-4), then re-delegate.'
}
if ($actual.Count -eq 0) {
    Complete-Check 'INCOMPLETE' 'git shows no implementation change (outside the ignored orchestrator paths).' 'Re-delegate with a concrete file list in SCOPE.'
}
if ($ran.Count -eq 0 -or $failed.Count -gt 0) {
    Complete-Check 'INCOMPLETE' "verification is missing or failing (run=$($ran.Count), failed=$($failed.Count)); there is no evidence to submit (PL-004)." 'Re-delegate quoting the failing or missing verification.'
}
if ($criteria.Count -eq 0 -or $unmet.Count -gt 0) {
    Complete-Check 'INCOMPLETE' "$($unmet.Count) acceptance criteria unmet (of $($criteria.Count))." 'Re-delegate quoting the unmet criteria. Do NOT write submission.md from this run.'
}
Complete-Check 'OK' 'the report is consistent with git and every criterion is MET with executed verification.' 'Proceed to B-3 acceptance.'
