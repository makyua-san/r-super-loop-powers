#Requires -Version 5.1
# Plain-PowerShell tests for impl-check.ps1. Run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\impl-check.tests.ps1
$ErrorActionPreference = 'Continue'
$script = Join-Path $PSScriptRoot '..\skills\r-super-loop-powers\bin\impl-check.ps1'
$script:failures = 0
$fence = '`' * 3

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

function Invoke-Check($Repo, [string]$ReportText, [string]$Base) {
    $rf = Join-Path ([IO.Path]::GetTempPath()) ('implcheck-report-' + [guid]::NewGuid().ToString('N') + '.md')
    [IO.File]::WriteAllText($rf, $ReportText, (New-Object Text.UTF8Encoding($false)))
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReportFile $rf -WorkDir $Repo -BaseRef $Base 2>&1 | Out-String
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

if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
