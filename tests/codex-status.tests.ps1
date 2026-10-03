#Requires -Version 5.1
# Verdict tests for codex-status.ps1 on hand-made, already-finished runs.
$ErrorActionPreference = 'Continue'
$status = Join-Path $PSScriptRoot '..\skills\r-super-loop-powers\bin\codex-status.ps1'
$script:failures = 0
$t = Join-Path ([IO.Path]::GetTempPath()) ('codexstatus-' + [guid]::NewGuid().ToString('N'))
$runDir = Join-Path $t 'runs'
New-Item -ItemType Directory -Path $runDir | Out-Null

function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}

# A finished run: exit 0, turn.completed, a final message.
function New-Run([string]$Label, [string]$Role, [string]$CodexHome, [string]$ThreadId, [string[]]$ExtraEvents) {
    $meta = [ordered]@{ label = $Label; role = $Role; model = 'gpt-6.1-sol'; effort = 'medium'; timeoutMinutes = 60; startedAt = (Get-Date).ToString('s') }
    if ($CodexHome) { $meta.codexHome = $CodexHome }
    [IO.File]::WriteAllText((Join-Path $runDir "$Label.meta.json"), ($meta | ConvertTo-Json))
    $events = @(('{"type":"thread.started","thread_id":"' + $ThreadId + '"}'), '{"type":"turn.started"}') + $ExtraEvents + @(
        '{"type":"item.completed","item":{"id":"i9","type":"agent_message","text":"done"}}',
        '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}')
    [IO.File]::WriteAllText((Join-Path $runDir "$Label.out.jsonl"), ($events -join "`n"))
    [IO.File]::WriteAllText((Join-Path $runDir "$Label.last.txt"), 'generated one image')
    [IO.File]::WriteAllText((Join-Path $runDir "$Label.exit"), '0')
}
function Invoke-Status([string]$Label) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $status -RunDir $runDir -Label $Label 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
function New-Image([string]$CodexHome, [string]$ThreadId) {
    $d = Join-Path $CodexHome "generated_images\$ThreadId"
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    $f = Join-Path $d 'exec-1.png'
    [IO.File]::WriteAllBytes($f, [byte[]](1, 2, 3))
    return $f
}

$home1 = Join-Path $t 'home1'
New-Item -ItemType Directory -Path $home1 | Out-Null

# Issue #4: codex said "generated" but no image exists -> must not read as OK.
New-Run 'g-none' 'grareco' $home1 'thread-none' @()
$r = Invoke-Status 'g-none'
Check 'grareco-no-image-not-ok' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: NO_IMAGE\s*$') $r.Out

$img = New-Image $home1 'thread-yes'
New-Run 'g-yes' 'grareco' $home1 'thread-yes' @()
$r = Invoke-Status 'g-yes'
Check 'grareco-image-ok' ($r.Code -eq 0 -and $r.Out -match '(?m)^STATUS: OK\s*$') $r.Out
Check 'grareco-image-path' ($r.Out -match ('(?m)^IMAGE: ' + [regex]::Escape($img) + '\s*$')) $r.Out

# Runs launched before the fix wrote images to the default ~/.codex, not to
# codexHome. The search must still find them there (here: a fake USERPROFILE).
$fakeProfile = Join-Path $t 'profile'
$img2 = New-Image (Join-Path $fakeProfile '.codex') 'thread-legacy'
New-Run 'g-legacy' 'grareco' '' 'thread-legacy' @()
$savedProfile = $env:USERPROFILE
$env:USERPROFILE = $fakeProfile
try { $r = Invoke-Status 'g-legacy' } finally { $env:USERPROFILE = $savedProfile }
Check 'grareco-legacy-home' ($r.Code -eq 0 -and $r.Out -match ('(?m)^IMAGE: ' + [regex]::Escape($img2) + '\s*$')) $r.Out

# Non-grareco roles never need an image.
New-Run 't-ok' 'techpm' $home1 'thread-tp' @()
$r = Invoke-Status 't-ok'
Check 'techpm-ok-without-image' ($r.Code -eq 0 -and $r.Out -match '(?m)^STATUS: OK\s*$' -and $r.Out -notmatch '(?m)^IMAGE:') $r.Out

# The broken elevated sandbox: every shell command fails before it starts.
$broken = '{"type":"item.completed","item":{"id":"i1","type":"command_execution","command":"powershell -Command Get-Content x","aggregated_output":"Failed to create unified exec process: helper_unknown_error: setup refresh had errors","exit_code":-1,"status":"failed"}}'
New-Run 't-shell' 'techpm' $home1 'thread-sh' @($broken)
$r = Invoke-Status 't-shell'
Check 'shell-broken-warns' ($r.Out -match '(?m)^WARN: .*shell could not start') $r.Out

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
