#Requires -Version 5.1
<#
  impl-check.ps1 -- judge one builder (Sonnet subagent) delegation by comparing its
  self-report with what git actually shows. A returned report is not a finished
  milestone: this script is the only thing that may call it OK.

  Emits "KEY: VALUE" lines; the last three are STATUS / REASON / NEXT.
  STATUS: OK | MALFORMED | CONTRACT_VIOLATION | BLOCKED | INCOMPLETE
  Exit code 0 only on OK.

  -Snapshot -WorkDir <repo> -OutFile <path>
    Run right before the delegation. Writes one line per dirty path:
    "<repo-relative path><TAB><git hash-object of the file | DELETED | DIR>".
    Pass the file to the check as -PreexistingFile so that uncommitted work that
    was already there (earlier tasks of the same milestone) is not credited to,
    or blamed on, this run.
#>
[CmdletBinding()]
param(
    [string]$ReportFile,
    [Parameter(Mandatory = $true)][string]$WorkDir,
    # git HEAD recorded right before the delegation (impl-runs/<label>.base.txt).
    [string]$BaseRef,
    # Orchestrator-owned paths (state.md, impl-runs/...) that live in the target
    # repo but are not implementation work. Repo-relative, forward slashes.
    [string[]]$IgnorePath = @('docs/r-super-loop-powers/'),
    # Snapshot written by -Snapshot before the delegation (impl-runs/<label>.pre.txt).
    [string]$PreexistingFile,
    [switch]$Snapshot,
    [string]$OutFile
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

# git with unquoted UTF-8 paths. Without both settings a non-ASCII file name comes
# back as "\343\203..." or mojibake and never matches the report.
function Invoke-Git([string[]]$GitArgs) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $prevEnc = $null
    try { $prevEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { $prevEnc = $null }
    try {
        $out = @(& git -c core.quotepath=false -C $WorkDir @GitArgs 2>$null)
    } finally {
        if ($prevEnc) { try { [Console]::OutputEncoding = $prevEnc } catch { } }
        $ErrorActionPreference = $prevEap
    }
    return $out
}

# Every dirty path (staged, unstaged, untracked), repo-relative.
function Get-DirtyPath {
    $paths = @()
    foreach ($line in @(Invoke-Git @('status', '--porcelain', '--untracked-files=all') | Where-Object { $_ })) {
        $p = ([string]$line).Substring(3)
        if ($p -match ' -> ') { $p = ($p -split ' -> ')[-1] }
        $paths += (ConvertTo-RepoPath $p $WorkDir)
    }
    return $paths
}

function Get-PathFingerprint([string]$RelPath) {
    $full = Join-Path $WorkDir $RelPath
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $h = (@(Invoke-Git @('hash-object', '--', $RelPath)) -join '').Trim()
        if ($h) { return $h }
        return 'UNREADABLE'
    }
    if (Test-Path -LiteralPath $full) { return 'DIR' }
    return 'DELETED'
}

function Test-Ignored([string]$RelPath) {
    foreach ($ig in $IgnorePath) { if ($ig -and $RelPath.StartsWith($ig, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}

if (-not (Test-Path -LiteralPath $WorkDir)) { throw "WorkDir does not exist: $WorkDir" }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path

# --- snapshot mode -------------------------------------------------------------
if ($Snapshot) {
    if (-not $OutFile) { throw '-Snapshot needs -OutFile <path> (impl-runs/<label>.pre.txt).' }
    $top = (@(Invoke-Git @('rev-parse', '--show-toplevel')) -join '').Trim()
    if (-not $top) { throw "WorkDir is not a git repository: $WorkDir" }
    $lines = @()
    foreach ($p in @(Get-DirtyPath)) { $lines += ($p + "`t" + (Get-PathFingerprint $p)) }
    $outDir = Split-Path -Parent $OutFile
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $body = ''
    if ($lines.Count -gt 0) { $body = ($lines -join "`n") + "`n" }
    Write-TextFile $OutFile $body
    Write-Kv 'SNAPSHOT' $OutFile
    Write-Kv 'DIRTY_PATHS' $lines.Count
    exit 0
}

if (-not $ReportFile) { throw '-ReportFile is required (or use -Snapshot -OutFile).' }
if (-not $BaseRef) { throw '-BaseRef is required (or use -Snapshot -OutFile).' }

$required = @('summary', 'changed_files', 'verification', 'acceptance_criteria',
    'new_assumptions', 'unresolved', 'blocked', 'blocked_reason', 'committed')
$redo = 'Re-delegate once with the same prompt. If it happens again, escalate (B-4).'

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
# Only PASS is a pass. A missing or unknown outcome is not evidence of anything.
$failed = @($ran | Where-Object { $_.outcome -ne 'PASS' })
$criteria = @(@($report.acceptance_criteria) | Where-Object { $_ })
$unmet = @($criteria | Where-Object { $_.status -ne 'MET' })
foreach ($a in @($report.new_assumptions)) { if ($a) { Write-Kv 'NEW_ASSUMPTION' $a } }
foreach ($u in @($report.unresolved)) { if ($u) { Write-Kv 'UNRESOLVED' $u } }

# --- 2. what git actually shows -----------------------------------------------
$head = (@(Invoke-Git @('rev-parse', 'HEAD')) -join '').Trim()
$baseFull = (@(Invoke-Git @('rev-parse', '--verify', "$($BaseRef.Trim())^{commit}")) -join '').Trim()
$dirty = @(Get-DirtyPath)
if (-not $baseFull) { Complete-Check 'MALFORMED' "BaseRef '$BaseRef' does not resolve to a commit" 'Fix impl-runs/<label>.base.txt (the git HEAD recorded before the delegation); do not re-delegate.' }

# Pre-existing uncommitted work: path -> fingerprint taken before the delegation.
$pre = @{}
if ($PreexistingFile) {
    if (-not (Test-Path -LiteralPath $PreexistingFile)) {
        Complete-Check 'MALFORMED' "PreexistingFile not found: $PreexistingFile" 'Fix impl-runs/<label>.pre.txt (impl-check.ps1 -Snapshot before the delegation); do not re-delegate.'
    }
    foreach ($line in ((Read-TextFile $PreexistingFile) -split "`r?`n")) {
        if (-not $line) { continue }
        $parts = $line -split "`t", 2
        $pre[$parts[0]] = $(if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' })
    }
}

# A dirty path is this run's change only if it was not dirty before, or its content
# differs from the snapshot. A pre-existing dirty path that is clean now was
# reverted by this run, which is also a change.
$actual = @()
$preUnchanged = @()
foreach ($p in $dirty) {
    if (Test-Ignored $p) { continue }
    if ($pre.ContainsKey($p)) {
        if ((Get-PathFingerprint $p) -eq $pre[$p]) { $preUnchanged += $p; continue }
    }
    $actual += $p
}
foreach ($p in $pre.Keys) {
    if ((Test-Ignored $p) -or ($dirty | Where-Object { $_ -ceq $p })) { continue }
    $actual += $p
}

Write-Kv 'HEAD' $head
Write-Kv 'CHANGED_FILES_REPORTED' ($reported -join ', ')
Write-Kv 'CHANGED_FILES_ACTUAL' ($actual -join ', ')
if ($PreexistingFile) { Write-Kv 'PREEXISTING_UNCHANGED' ($preUnchanged -join ', ') }
foreach ($p in $actual) {
    if (-not ($reported | Where-Object { $_ -ieq $p })) { Write-Kv 'WARN' "unreported change: $p" }
}
foreach ($p in $reported) {
    if (-not ($actual | Where-Object { $_ -ieq $p })) { Write-Kv 'WARN' "reported but unchanged: $p" }
}
Write-Kv 'REPORT' ("blocked=$($report.blocked) committed=$($report.committed) verifications_run=$($ran.Count) verifications_failed=$($failed.Count) criteria=$($criteria.Count) criteria_unmet=$($unmet.Count)")
foreach ($u in ($unmet | Select-Object -First 5)) { Write-Kv 'CRITERION_UNMET' ("[$($u.status)] $($u.criterion)") }

# --- 3. verdict (first match wins; order is the spec's section 4) --------------
if ($report.committed -eq $true -or ($head -and $head -ne $baseFull)) {
    Complete-Check 'CONTRACT_VIOLATION' "the builder committed (committed=$($report.committed), HEAD $BaseRef -> $head). Commits belong to the orchestrator." 'Inspect git log / git status first, undo the commit if unwanted, then decide whether to keep the work.'
}
if ($report.blocked -eq $true) {
    Complete-Check 'BLOCKED' "the builder stopped without finishing: $($report.blocked_reason)" 'Do NOT advance the milestone. Resolve the blocker or escalate (B-4), then re-delegate.'
}
if ($actual.Count -eq 0) {
    Complete-Check 'INCOMPLETE' 'git shows no implementation change by this run (outside the ignored orchestrator paths and the pre-existing snapshot).' 'Re-delegate with a concrete file list in SCOPE.'
}
if ($ran.Count -eq 0 -or $failed.Count -gt 0) {
    Complete-Check 'INCOMPLETE' "verification is missing, failing, or has an outcome other than PASS / SKIPPED (run=$($ran.Count), not_passed=$($failed.Count)); there is no evidence to submit (PL-004)." 'Re-delegate quoting the failing or missing verification.'
}
if ($criteria.Count -eq 0 -or $unmet.Count -gt 0) {
    Complete-Check 'INCOMPLETE' "$($unmet.Count) acceptance criteria unmet (of $($criteria.Count))." 'Re-delegate quoting the unmet criteria. Do NOT write submission.md from this run.'
}
Complete-Check 'OK' 'the report is consistent with git and every criterion is MET with executed verification.' 'Proceed to B-3 acceptance.'
