#Requires -Version 5.1
# roles.md (source of truth) vs the builder.md roles region, and the section format.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sync = Join-Path $root 'scripts\sync-roles.ps1'
$roles = Join-Path $root 'skills\r-super-loop-powers\references\roles.md'
$builder = Join-Path $root 'agents\builder.md'
$script:failures = 0
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}
function Invoke-Sync([string[]]$Extra) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $sync @Extra 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

$r = Invoke-Sync @('-Mode', 'Verify')
Check 'repo-in-sync' ($r.Code -eq 0) $r.Out

. (Join-Path $root 'skills\r-super-loop-powers\bin\roles-common.ps1')
$text = [IO.File]::ReadAllText($roles)
foreach ($id in @('overview', 'opus', 'proxy-fable', 'gate-fable', 'techpm', 'reviewer', 'builder', 'grareco')) {
    $s = Get-RoleSection $text $id
    Check "section-$id" ([bool]$s) "no section ($id) in roles.md"
    if ($id -ne 'overview') {
        $items = [regex]::Matches($s, '(?m)^- \*\*').Count
        Check "five-items-$id" ($items -eq 5) "expected 5 '- **' items, got $items"
    }
}
Check 'missing-id-empty' ((Get-RoleCharter -RolesFile $roles -Ids @('overview', 'nope')) -eq '') 'unknown id must yield empty'
$ErrorActionPreference = 'Stop'
$bad = 'x'
try { $bad = Get-RoleCharter -RolesFile ("C:\bad" + [char]13 + "path.md") -Ids @('overview') } catch { $bad = 'threw' }
$ErrorActionPreference = 'Continue'
Check 'invalid-path-empty' ($bad -eq '') "invalid path must yield empty, got: $bad"
Check 'missing-file-empty'((Get-RoleCharter -RolesFile (Join-Path $root 'nope.md') -Ids @('overview')) -eq '') 'missing file must yield empty'

# Drift is detected, and Copy repairs it (on temp copies).
$t = Join-Path ([IO.Path]::GetTempPath()) ('roles-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
$tRoles = Join-Path $t 'roles.md'; Copy-Item $roles $tRoles
$tBuilder = Join-Path $t 'builder.md'
$b = [IO.File]::ReadAllText($builder) -replace '<!-- roles:begin -->', "<!-- roles:begin -->`ndrift"
[IO.File]::WriteAllText($tBuilder, $b)
$r = Invoke-Sync @('-Mode', 'Verify', '-RolesFile', $tRoles, '-BuilderFile', $tBuilder)
Check 'drift-detected' ($r.Code -ne 0 -and $r.Out -match 'DIFF:') $r.Out
$r = Invoke-Sync @('-Mode', 'Copy', '-RolesFile', $tRoles, '-BuilderFile', $tBuilder)
Check 'copy-ok' ($r.Code -eq 0) $r.Out
$r = Invoke-Sync @('-Mode', 'Verify', '-RolesFile', $tRoles, '-BuilderFile', $tBuilder)
Check 'copy-repairs' ($r.Code -eq 0) $r.Out
$after = [IO.File]::ReadAllText($tBuilder)
Check 'copy-keeps-rest' ($after -match '(?m)^## ' -and $after -match 'name: builder' -and $after -notmatch '(?m)^drift$') 'content outside the region changed'

[IO.File]::WriteAllText($tBuilder, ([IO.File]::ReadAllText($builder) -replace '<!-- roles:(begin|end) -->', ''))
$r = Invoke-Sync @('-Mode', 'Verify', '-RolesFile', $tRoles, '-BuilderFile', $tBuilder)
Check 'no-markers-fails' ($r.Code -ne 0) $r.Out

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
