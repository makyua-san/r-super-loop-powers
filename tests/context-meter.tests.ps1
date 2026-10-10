#Requires -Version 5.1
# Tests for hooks/context-meter.ps1 (PostToolUse) with synthetic transcripts.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hook = Join-Path $root 'hooks\context-meter.ps1'
$script:failures = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $utf8
[Console]::OutputEncoding = $utf8
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}
function W([string]$Path, [string]$Text) {
    $d = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Get-Text([string]$Path) { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path, $utf8) } return '' }
function Get-AssistantLine([int64]$Ctx) {
    $cc = [int64]($Ctx / 2); $cr = $Ctx - $cc - 5
    return '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"x"}],"usage":{"input_tokens":5,"cache_creation_input_tokens":' + $cc + ',"cache_read_input_tokens":' + $cr + ',"output_tokens":10,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1}}},"timestamp":"t"}'
}
function New-Transcript([string]$Path, [int64[]]$Ctx, [string]$Tail = '') {
    $lines = @('{"type":"user","message":{"role":"user","content":"hi"}}')
    foreach ($c in $Ctx) { $lines += (Get-AssistantLine $c) }
    W $Path (($lines -join "`n") + "`n" + $Tail)
}
function Invoke-Meter([string]$Stdin, [hashtable]$Env) {
    if ($Env) { foreach ($k in $Env.Keys) { Set-Item "env:$k" $Env[$k] } }
    $out = $Stdin | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hook 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($Env) { foreach ($k in $Env.Keys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } }
    return @{ Out = $out.Trim(); Code = $code }
}
function New-Input([string]$Cwd, [string]$Transcript) {
    return (@{ session_id = 's'; hook_event_name = 'PostToolUse'; cwd = $Cwd; transcript_path = $Transcript; tool_name = 'Agent'; tool_input = @{ prompt = 'p' }; tool_use_id = 't1' } | ConvertTo-Json -Compress)
}
function Get-Context($Result) {
    try { $j = $Result.Out | ConvertFrom-Json } catch { return $null }
    if (-not $j -or -not $j.hookSpecificOutput) { return $null }
    return $j.hookSpecificOutput
}

$t = Join-Path ([IO.Path]::GetTempPath()) ('ctm-' + [guid]::NewGuid().ToString('N'))
$proj = Join-Path $t 'proj'
$g = Join-Path $proj 'docs\r-super-loop-powers\g1'
W (Join-Path $g 'state.md') "- phase: milestone-implementation`n"
$log = Join-Path $g 'hook-log.md'
$tr = Join-Path $t 'session.jsonl'
$low = @{ RSLP_CTX_THRESHOLD = '200000' }

New-Transcript $tr @(50000, 120000)
$r = Invoke-Meter (New-Input $proj $tr) $low
Check 'below-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out
Check 'below-logged' ((Get-Text $log) -match '\| CTX \| tokens=120000 \| tool=Agent') (Get-Text $log)

New-Transcript $tr @(50000, 250000)
$r = Invoke-Meter (New-Input $proj $tr) $low
$ctx = Get-Context $r
Check 'over-notifies' ($ctx -and $ctx.hookEventName -eq 'PostToolUse' -and $ctx.additionalContext -match '約 25 万トークン' -and $ctx.additionalContext -match '境界リセット' -and $ctx.additionalContext -match '20 万') $r.Out
Check 'over-logged' ((Get-Text $log) -match 'tokens=250000') (Get-Text $log)

# The last line is being written (no closing brace): use the previous complete one.
New-Transcript $tr @(50000, 150000) '{"type":"assistant","message":{"usage":{"input_tokens":999999,"cache_creation_input_tokens":'
$r = Invoke-Meter (New-Input $proj $tr) $low
Check 'partial-line-skipped' ($r.Out -eq '' -and (Get-Text $log) -match 'tokens=150000' -and (Get-Text $log) -notmatch '999999') (Get-Text $log)

$before = @((Get-Text $log) -split "`n").Count
W $tr ('{"type":"user","message":{"content":"x"}}' + "`n")
$r = Invoke-Meter (New-Input $proj $tr) $low
Check 'no-usage-silent' ($r.Code -eq 0 -and $r.Out -eq '' -and @((Get-Text $log) -split "`n").Count -eq $before) $r.Out

$r = Invoke-Meter (New-Input $proj (Join-Path $t 'nope.jsonl')) $low
Check 'missing-transcript-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out

$outside = Join-Path $t 'outside'
New-Item -ItemType Directory -Path $outside -Force | Out-Null
New-Transcript $tr @(300000)
$r = Invoke-Meter (New-Input $outside $tr) $low
Check 'outside-loop-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out

$r = Invoke-Meter (New-Input $proj $tr) @{ RSLP_HOOK_CHILD = '1'; RSLP_CTX_THRESHOLD = '200000' }
Check 'child-session-silent' ($r.Out -eq '') $r.Out

# Default threshold is 200,000.
New-Transcript $tr @(199999)
$r = Invoke-Meter (New-Input $proj $tr) $null
Check 'default-threshold-below' ($r.Out -eq '') $r.Out
New-Transcript $tr @(200000)
$r = Invoke-Meter (New-Input $proj $tr) $null
Check 'default-threshold-at' ($null -ne (Get-Context $r)) $r.Out

# Big transcript: only the tail is read, and the newest usage still wins.
$junk = (1..400 | ForEach-Object { '{"type":"user","message":{"content":"' + ('j' * 2000) + '"}}' }) -join "`n"
W $tr ($junk + "`n" + (Get-AssistantLine 210000) + "`n")
$r = Invoke-Meter (New-Input $proj $tr) $low
Check 'tail-read-finds-usage' ((Get-Context $r) -and (Get-Text $log) -match 'tokens=210000') $r.Out

$r = Invoke-Meter 'not json' $low
Check 'bad-stdin-open' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out

$b = [IO.File]::ReadAllBytes($hook)
Check 'hook-has-bom' ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'save context-meter.ps1 as UTF-8 with BOM'

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
