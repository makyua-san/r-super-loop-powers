#Requires -Version 5.1
# Launcher-only tests for codex-run.ps1: codex itself is replaced by where.exe.
$ErrorActionPreference = 'Continue'
$run = Join-Path $PSScriptRoot '..\skills\r-super-loop-powers\bin\codex-run.ps1'
$script:failures = 0
$t = Join-Path ([IO.Path]::GetTempPath()) ('codexrun-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
$where = Join-Path $env:SystemRoot 'System32\where.exe'
$skillDir = (Resolve-Path (Join-Path $PSScriptRoot '..\skills\r-super-loop-powers')).Path

function New-Env([hashtable]$Extra) {
    $e = [ordered]@{ kind = 'exe'; exe = $where; version = '0.153.4'; model = 'gpt-6.1-sol'; envSchema = 2; skillDir = $skillDir; codexHome = $t }
    if ($Extra) { foreach ($k in $Extra.Keys) { if ($null -eq $Extra[$k]) { $e.Remove($k) } else { $e[$k] = $Extra[$k] } } }
    $f = Join-Path $t ('env-' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($f, ($e | ConvertTo-Json))
    return $f
}
$prompt = Join-Path $t 'p.md'; [IO.File]::WriteAllText($prompt, 'hello')

function Invoke-Run([string]$EnvFile, [string]$Label, [string[]]$Extra) {
    # -NonInteractive: a missing Mandatory -Role must fail, not prompt and hang.
    $args2 = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $run, '-EnvFile', $EnvFile, '-Label', $Label,
        '-PromptFile', $prompt, '-WorkDir', $t, '-RunDir', (Join-Path $t 'runs')) + $Extra
    $out = & powershell @args2 2>&1 | Out-String
    $code = $LASTEXITCODE
    $exit = Join-Path $t "runs\$Label.exit"
    for ($i = 0; $i -lt 60 -and -not (Test-Path $exit) -and $code -eq 0; $i++) { Start-Sleep -Milliseconds 500 }
    return @{ Out = $out; Code = $code }
}
function Get-Meta([string]$Label) { return (Get-Content -Raw (Join-Path $t "runs\$Label.meta.json") | ConvertFrom-Json) }
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}

$env1 = New-Env @{}
$r = Invoke-Run $env1 'tp' @('-Role', 'techpm')
$m = Get-Meta 'tp'
Check 'techpm-starts' ($r.Code -eq 0) $r.Out
Check 'techpm-read-only' ($m.sandbox -eq 'read-only' -and $m.command -match '-s read-only') $r.Out
Check 'techpm-effort-max' ($m.effort -eq 'max') $r.Out
Check 'plugins-disabled' ($m.command -match '--disable plugins') $m.command
Check 'model-from-env' ($m.model -eq 'gpt-6.1-sol') $m.model

$r = Invoke-Run $env1 'rv' @('-Role', 'reviewer')
$m = Get-Meta 'rv'
Check 'reviewer-read-only-max' ($r.Code -eq 0 -and $m.sandbox -eq 'read-only' -and $m.effort -eq 'max') $r.Out
Check 'reviewer-brief' ((Get-Content -Raw (Join-Path $t 'runs\rv.prompt.txt')) -match 'ROLE: TECH REVIEWER') 'brief missing'

$r = Invoke-Run $env1 'gr' @('-Role', 'grareco')
$m = Get-Meta 'gr'
Check 'grareco-read-only-medium' ($r.Code -eq 0 -and $m.sandbox -eq 'read-only' -and $m.effort -eq 'medium') $r.Out

$r = Invoke-Run $env1 'bd' @('-Role', 'builder')
Check 'builder-rejected' ($r.Code -ne 0) $r.Out
$r = Invoke-Run $env1 'nr' @()
Check 'role-required' ($r.Code -ne 0) $r.Out
$r = Invoke-Run $env1 'sb' @('-Role', 'techpm', '-Sandbox', 'workspace-write')
Check 'sandbox-param-gone' ($r.Code -ne 0) $r.Out

$r = Invoke-Run (New-Env @{ techpmModel = 'gpt-6-astra'; sandbox = 'danger-full-access' }) 'lg' @('-Role', 'techpm')
$m = Get-Meta 'lg'
Check 'legacy-env-warns' ($r.Out -match '(?m)^WARN: codex-env.json .*pre-v0.7') $r.Out
Check 'legacy-env-still-read-only' ($m.sandbox -eq 'read-only') $r.Out

# F4: the pre-v0.7 warning keys off the env schema marker, never the model name.
$r = Invoke-Run (New-Env @{ model = 'gpt-x' }) 'cm' @('-Role', 'techpm')
Check 'custom-model-no-warn' ($r.Code -eq 0 -and $r.Out -notmatch '(?m)^WARN:') $r.Out
Check 'custom-model-used' ((Get-Meta 'cm').model -eq 'gpt-x') $r.Out
$r = Invoke-Run (New-Env @{ envSchema = $null }) 'ns' @('-Role', 'techpm')
Check 'no-schema-warns' ($r.Out -match '(?m)^WARN: codex-env.json .*pre-v0.7') $r.Out
$r = Invoke-Run $env1 'cur' @('-Role', 'techpm')
Check 'current-env-no-warn' ($r.Out -notmatch '(?m)^WARN:') $r.Out
$pre = Get-Content -Raw (Join-Path $skillDir 'bin\codex-preflight.ps1')
Check 'preflight-writes-envschema-2' ($pre -match '(?m)^\s*envSchema\s*=\s*2\b') 'codex-preflight.ps1 does not write envSchema = 2'

# F2 / F12: brief wording.
$rvPrompt = Get-Content -Raw (Join-Path $t 'runs\rv.prompt.txt')
Check 'reviewer-sees-untracked' ($rvPrompt -match 'git status --porcelain --untracked-files=all' -and $rvPrompt -match 'untracked files directly') 'reviewer brief does not cover untracked files'
Check 'contract-complete-answer' ($rvPrompt -match 'complete answer' -and $rvPrompt -notmatch 'self-verification report') 'contract item 5 wording'

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
