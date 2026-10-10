#Requires -Version 5.1
# Plain-PowerShell tests for impl-check.ps1. Run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\impl-check.tests.ps1
$ErrorActionPreference = 'Continue'
$script = Join-Path $PSScriptRoot '..\skills\r-super-loop-powers\bin\impl-check.ps1'
$script:failures = 0
$fence = '`' * 3
$utf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $utf8
[Console]::OutputEncoding = $utf8

function New-Repo {
    $d = Join-Path ([IO.Path]::GetTempPath()) ('implcheck-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $d | Out-Null
    git -C $d init -q 2>$null
    git -C $d config user.email t@example.com
    git -C $d config user.name t
    [IO.File]::WriteAllText((Join-Path $d 'a.txt'), "a`n")
    git -C $d add -A 2>$null
    git -C $d commit -q -m init 2>$null
    return $d
}
function Get-Head($Repo) { return (git -C $Repo rev-parse HEAD).Trim() }

function New-Report([hashtable]$Over, [string]$Prefix = 'Done.', [switch]$Raw) {
    $r = [ordered]@{
        summary = 's'; changed_files = @('a.txt')
        verification = @(@{ command = 'echo ok'; outcome = 'PASS'; evidence = 'ok' })
        acceptance_criteria = @(@{ criterion = 'c1'; status = 'MET'; note = 'n' })
        new_assumptions = @('assume x'); unresolved = @(); blocked = $false; blocked_reason = ''; committed = $false
    }
    if ($Over) { foreach ($k in $Over.Keys) { $r[$k] = $Over[$k] } }
    $json = $r | ConvertTo-Json -Depth 6
    if ($Raw) { return $json }
    return "$Prefix`n$fence" + "json`n$json`n$fence`nThanks."
}

function Invoke-Check($Repo, [string]$ReportText, [string]$Base, [string[]]$Extra = @()) {
    $rf = Join-Path ([IO.Path]::GetTempPath()) ('implcheck-report-' + [guid]::NewGuid().ToString('N') + '.md')
    [IO.File]::WriteAllText($rf, $ReportText, (New-Object Text.UTF8Encoding($false)))
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReportFile $rf -WorkDir $Repo -BaseRef $Base @Extra 2>&1 | Out-String
    $code = $LASTEXITCODE
    Remove-Item -LiteralPath $rf -Force -ErrorAction SilentlyContinue
    return @{ Out = $out; Code = $code }
}

function Assert-Status([string]$Name, $Result, [string]$Expected) {
    $okCode = ($Expected -eq 'OK') -eq ($Result.Code -eq 0)
    if (($Result.Out -match "(?m)^STATUS: $Expected\s*$") -and $okCode) { Write-Output "PASS $Name" }
    else { Write-Output "FAIL $Name (expected $Expected, exit $($Result.Code))`n$($Result.Out)"; $script:failures++ }
}
function Assert-Match([string]$Name, $Result, [string]$Pattern) {
    if ($Result.Out -match $Pattern) { Write-Output "PASS $Name" }
    else { Write-Output "FAIL $Name (no match: $Pattern)`n$($Result.Out)"; $script:failures++ }
}
function Set-Change($Repo, [string]$Rel = 'a.txt') {
    $p = Join-Path $Repo $Rel
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($p, "changed`n")
}

# --- cases ---------------------------------------------------------------------
$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'ok' (Invoke-Check $r (New-Report @{}) $b) 'OK'
Assert-Match 'ok-emits-assumption' (Invoke-Check $r (New-Report @{}) $b) '(?m)^NEW_ASSUMPTION: assume x'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'fenced-with-prose' (Invoke-Check $r (New-Report @{} 'Here is my report:') $b) 'OK'
Assert-Status 'raw-json' (Invoke-Check $r (New-Report @{} -Raw) $b) 'OK'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'not-json' (Invoke-Check $r 'I finished everything.' $b) 'MALFORMED'
$partial = "$fence" + "json`n{ `"summary`": `"s`" }`n$fence"
Assert-Status 'missing-keys' (Invoke-Check $r $partial $b) 'MALFORMED'
Assert-Status 'empty-report' (Invoke-Check $r '' $b) 'MALFORMED'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'committed-flag' (Invoke-Check $r (New-Report @{ committed = $true }) $b) 'CONTRACT_VIOLATION'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
git -C $r commit -q -am sneaky 2>$null
Assert-Status 'head-moved' (Invoke-Check $r (New-Report @{}) $b) 'CONTRACT_VIOLATION'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'blocked' (Invoke-Check $r (New-Report @{ blocked = $true; blocked_reason = 'missing api' }) $b) 'BLOCKED'

$r = New-Repo; $b = Get-Head $r
Assert-Status 'no-actual-change' (Invoke-Check $r (New-Report @{}) $b) 'INCOMPLETE'

$r = New-Repo; $b = Get-Head $r; Set-Change $r 'docs/r-super-loop-powers/g/state.md'
Assert-Status 'docs-only-change' (Invoke-Check $r (New-Report @{ changed_files = @() }) $b) 'INCOMPLETE'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'verification-fail' (Invoke-Check $r (New-Report @{ verification = @(@{ command = 'npm test'; outcome = 'FAIL'; evidence = '1 failed' }) }) $b) 'INCOMPLETE'
Assert-Status 'verification-empty' (Invoke-Check $r (New-Report @{ verification = @() }) $b) 'INCOMPLETE'
Assert-Status 'verification-all-skipped' (Invoke-Check $r (New-Report @{ verification = @(@{ command = 'x'; outcome = 'SKIPPED'; evidence = '-' }) }) $b) 'INCOMPLETE'
Assert-Status 'criterion-partial' (Invoke-Check $r (New-Report @{ acceptance_criteria = @(@{ criterion = 'c1'; status = 'PARTIAL'; note = 'half' }) }) $b) 'INCOMPLETE'
Assert-Status 'criteria-empty' (Invoke-Check $r (New-Report @{ acceptance_criteria = @() }) $b) 'INCOMPLETE'

$r = New-Repo; $b = Get-Head $r; Set-Change $r; Set-Change $r 'src/extra.txt'
Assert-Match 'unreported-change' (Invoke-Check $r (New-Report @{}) $b) '(?m)^WARN: unreported change: src/extra.txt'

$r = New-Repo; $b = Get-Head $r; Set-Change $r 'src/x.txt'
$abs = (Join-Path $r 'src\x.txt')
$res = Invoke-Check $r (New-Report @{ changed_files = @($abs) }) $b
Assert-Status 'backslash-absolute-paths' $res 'OK'
if ($res.Out -match 'unreported change') { Write-Output 'FAIL backslash-absolute-paths-no-warn'; $script:failures++ } else { Write-Output 'PASS backslash-absolute-paths-no-warn' }

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'short-baseref-ok' (Invoke-Check $r (New-Report @{}) $b.Substring(0, 7)) 'OK'
Assert-Status 'bad-baseref' (Invoke-Check $r (New-Report @{}) 'deadbeef') 'MALFORMED'

function Assert-NoMatch([string]$Name, $Result, [string]$Pattern) {
    if ($Result.Out -notmatch $Pattern) { Write-Output "PASS $Name" }
    else { Write-Output "FAIL $Name (unexpected match: $Pattern)`n$($Result.Out)"; $script:failures++ }
}
function Invoke-Snapshot($Repo, [string]$OutFile) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Snapshot -WorkDir $Repo -OutFile $OutFile 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
function New-PreFile { return (Join-Path ([IO.Path]::GetTempPath()) ('implcheck-pre-' + [guid]::NewGuid().ToString('N') + '.txt')) }

# F1: changes that were already uncommitted before the delegation are not this run's work.
$r = New-Repo; $b = Get-Head $r; Set-Change $r; $pre = New-PreFile
$s = Invoke-Snapshot $r $pre
$snapText = ''; if (Test-Path $pre) { $snapText = [IO.File]::ReadAllText($pre) }
if ($s.Code -eq 0 -and $snapText -match "(?m)^a\.txt\t[0-9a-f]{40}\r?$") { Write-Output 'PASS snapshot-writes-path-and-hash' }
else { Write-Output "FAIL snapshot-writes-path-and-hash (exit $($s.Code))`n$($s.Out)`n$snapText"; $script:failures++ }
$res = Invoke-Check $r (New-Report @{}) $b @('-PreexistingFile', $pre)
Assert-Status 'preexisting-no-new-change' $res 'INCOMPLETE'
Assert-Match 'preexisting-listed' $res '(?m)^PREEXISTING_UNCHANGED: a\.txt'

$r = New-Repo; $b = Get-Head $r; Set-Change $r; $pre = New-PreFile
$null = Invoke-Snapshot $r $pre
[IO.File]::WriteAllText((Join-Path $r 'a.txt'), "changed again`n")
Assert-Status 'preexisting-modified-again' (Invoke-Check $r (New-Report @{}) $b @('-PreexistingFile', $pre)) 'OK'

$r = New-Repo; $b = Get-Head $r; Set-Change $r 'old-work.txt'; $pre = New-PreFile
$null = Invoke-Snapshot $r $pre
Set-Change $r 'new.txt'
$res = Invoke-Check $r (New-Report @{ changed_files = @('new.txt') }) $b @('-PreexistingFile', $pre)
Assert-Status 'preexisting-plus-new-file' $res 'OK'
Assert-NoMatch 'preexisting-plus-new-file-no-warn' $res 'unreported change: old-work\.txt'
Assert-Match 'preexisting-plus-new-file-actual' $res '(?m)^CHANGED_FILES_ACTUAL: new\.txt\s*$'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'preexisting-file-missing' (Invoke-Check $r (New-Report @{}) $b @('-PreexistingFile', (New-PreFile))) 'MALFORMED'
$out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Snapshot -WorkDir $r 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Write-Output 'PASS snapshot-needs-outfile' } else { Write-Output "FAIL snapshot-needs-outfile`n$out"; $script:failures++ }
$out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -WorkDir $r -BaseRef $b 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Write-Output 'PASS check-needs-reportfile' } else { Write-Output "FAIL check-needs-reportfile`n$out"; $script:failures++ }

# F5: non-ASCII file names must match between the report and git.
$r = New-Repo; $b = Get-Head $r
$jp = (-join ([char]0x30C6, [char]0x30B9, [char]0x30C8)) + '.txt'
Set-Change $r $jp
$res = Invoke-Check $r (New-Report @{ changed_files = @($jp) }) $b
Assert-Status 'non-ascii-path' $res 'OK'
Assert-NoMatch 'non-ascii-path-no-warn' $res '(?m)^WARN:'

# F6: a reported path that this run did not change is flagged.
$r = New-Repo; $b = Get-Head $r; Set-Change $r
$res = Invoke-Check $r (New-Report @{ changed_files = @('a.txt', 'ghost.txt') }) $b
Assert-Status 'reported-but-unchanged-still-ok' $res 'OK'
Assert-Match 'reported-but-unchanged-warn' $res '(?m)^WARN: reported but unchanged: ghost\.txt'
Assert-NoMatch 'reported-and-changed-no-warn' $res 'reported but unchanged: a\.txt'

# F10: an outcome that is neither PASS nor SKIPPED is not a pass.
$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'verification-unknown-outcome' (Invoke-Check $r (New-Report @{ verification = @(@{ command = 'x'; outcome = 'DONE'; evidence = '-' }) }) $b) 'INCOMPLETE'
Assert-Status 'verification-missing-outcome' (Invoke-Check $r (New-Report @{ verification = @(@{ command = 'x'; evidence = '-' }) }) $b) 'INCOMPLETE'
Assert-Status 'verification-pass-lowercase-ok' (Invoke-Check $r (New-Report @{ verification = @(@{ command = 'x'; outcome = 'pass'; evidence = '-' }) }) $b) 'OK'

# v0.9: -Prepare writes base + pre in one call; -SaveReport takes the report on stdin.
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}
function Invoke-Prepare($Repo, [string]$Goal, [string]$Label) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Prepare -Label $Label -GoalDir $Goal -WorkDir $Repo 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
function Invoke-Save($Repo, [string]$Goal, [string]$Label, [string]$ReportText) {
    $out = $ReportText | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -SaveReport -Label $Label -GoalDir $Goal -WorkDir $Repo 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
$r = New-Repo; $b = Get-Head $r
$goal = Join-Path $r 'docs\r-super-loop-powers\g'
New-Item -ItemType Directory -Path $goal -Force | Out-Null
Set-Change $r 'old.txt'
$p = Invoke-Prepare $r $goal 'm1-impl'
Check 'prepare-ok' ($p.Code -eq 0 -and $p.Out -match '(?m)^STATUS: OK' -and $p.Out -match '(?m)^BASE_REF: [0-9a-f]{40}' -and $p.Out -match '(?m)^DIRTY_PATHS: 1') $p.Out
Check 'prepare-base-file' (((Get-Content -Raw (Join-Path $goal 'impl-runs\m1-impl.base.txt')).Trim()) -eq $b) 'base.txt'
Check 'prepare-pre-file' ((Get-Content -Raw (Join-Path $goal 'impl-runs\m1-impl.pre.txt')) -match "(?m)^old\.txt\t[0-9a-f]{40}") 'pre.txt'
Set-Change $r 'new.txt'
$report = New-Report @{ changed_files = @('new.txt'); summary = "日本語の要約 | with pipe`r`nsecond line" }
$s = Invoke-Save $r $goal 'm1-impl' $report
Check 'save-ok' ($s.Code -eq 0 -and $s.Out -match '(?m)^STATUS: OK' -and $s.Out -match '(?m)^SAVED: .*m1-impl\.report\.md') $s.Out
$saved = [IO.File]::ReadAllText((Join-Path $goal 'impl-runs\m1-impl.report.md'), $utf8)
Check 'save-verbatim' ($saved.TrimEnd() -eq $report.TrimEnd()) "saved:`n$saved"
Check 'save-uses-prepare-files' ($s.Out -match '(?m)^PREEXISTING_UNCHANGED: old\.txt' -and $s.Out -match '(?m)^CHANGED_FILES_ACTUAL: new\.txt\s*$') $s.Out
$p2 = Invoke-Prepare $r $goal 'm1-impl'
Check 'prepare-refuses-label-reuse' ($p2.Code -ne 0 -and $p2.Out -match '(?m)^STATUS: REFUSED') $p2.Out
$null = Invoke-Prepare $r $goal 'm1-impl-2'
$s2 = Invoke-Save $r $goal 'm1-impl-2' 'not json at all'
Check 'save-malformed-still-saved' ($s2.Code -ne 0 -and $s2.Out -match '(?m)^STATUS: MALFORMED' -and (Get-Content -Raw (Join-Path $goal 'impl-runs\m1-impl-2.report.md')) -match 'not json at all') $s2.Out
$s3 = Invoke-Save $r $goal 'm9-impl' $report
Check 'save-without-prepare' ($s3.Code -ne 0 -and $s3.Out -match '(?m)^STATUS: MALFORMED' -and $s3.Out -match 'no base ref' -and $s3.Out -match '(?m)^NEXT: .*-Prepare') $s3.Out
$null = Invoke-Prepare $r $goal 'm1-impl-3'
$s4 = Invoke-Save $r $goal 'm1-impl-3' ''
Check 'save-empty-stdin' ($s4.Code -ne 0 -and $s4.Out -match '(?m)^STATUS: MALFORMED') $s4.Out
$out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Prepare -WorkDir $r 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Write-Output 'PASS prepare-needs-label' } else { Write-Output "FAIL prepare-needs-label`n$out"; $script:failures++ }
$empty = Join-Path ([IO.Path]::GetTempPath()) ('implcheck-empty-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $empty | Out-Null
git -C $empty init -q 2>$null
$p5 = Invoke-Prepare $empty (Join-Path $empty 'docs\r-super-loop-powers\g') 'm1-impl'
Check 'prepare-needs-commit' ($p5.Code -ne 0) $p5.Out

if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
