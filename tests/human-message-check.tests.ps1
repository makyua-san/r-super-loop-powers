#Requires -Version 5.1
# Tests for hooks/human-message-check.ps1. The judge (claude -p) is replaced with
# small .cmd files through RSLP_JUDGE_CMD; each writes <name>.called when run.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hook = Join-Path $root 'hooks\human-message-check.ps1'
$script:failures = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $utf8
[Console]::OutputEncoding = $utf8
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}

$t = Join-Path ([IO.Path]::GetTempPath()) ('hmc-' + [guid]::NewGuid().ToString('N'))
$proj = Join-Path $t 'proj'
$goal = Join-Path $proj 'docs\r-super-loop-powers\g1'
New-Item -ItemType Directory -Path $goal -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $goal 'state.md'), "# state - g1`n- phase: milestone-implementation`n", $utf8)
$outside = Join-Path $t 'outside'
New-Item -ItemType Directory -Path $outside | Out-Null
$doneProj = Join-Path $t 'doneproj'
$doneGoal = Join-Path $doneProj 'docs\r-super-loop-powers\g0'
New-Item -ItemType Directory -Path $doneGoal -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $doneGoal 'state.md'), "# state - g0`n- phase: done`n", $utf8)
$log = Join-Path $goal 'hook-log.md'
# Real state.md files decorate the phase ("- phase: **done**(2026-09-25)").
$decoProj = Join-Path $t 'decoproj'
$decoDone = Join-Path $decoProj 'docs\r-super-loop-powers\g0'
New-Item -ItemType Directory -Path $decoDone -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $decoDone 'state.md'), "# state - g0`n- phase: **done**(2026-09-25) finished`n", $utf8)
$mixProj = Join-Path $t 'mixproj'
$mixActive = Join-Path $mixProj 'docs\r-super-loop-powers\g1'
$mixDone = Join-Path $mixProj 'docs\r-super-loop-powers\g2'
New-Item -ItemType Directory -Path $mixActive, $mixDone -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $mixActive 'state.md'), "- phase: milestone-implementation`n", $utf8)
Start-Sleep -Milliseconds 50
[IO.File]::WriteAllText((Join-Path $mixDone 'state.md'), "- phase: **done**`n", $utf8)

function New-Judge([string]$Name, [string]$Body) {
    $p = Join-Path $t "$Name.cmd"
    [IO.File]::WriteAllText($p, "@echo off`r`necho called> `"%~dp0$Name.called`"`r`n$Body`r`n", [Text.Encoding]::ASCII)
    return $p
}
$judgeOk = New-Judge 'ok' 'echo {"ok": true}'
$judgeNg = New-Judge 'ng' 'echo {"ok": false, "reason": "put the conclusion first"}'
$judgeNgDot = New-Judge 'ngdot' 'echo {"ok": false, "reason": "put the conclusion first."}'
$judgeFail = New-Judge 'fail' 'exit /b 3'
$judgeJunk = New-Judge 'junk' 'echo not json at all'
$judgeArgs = New-Judge 'args' ("echo %*> `"%~dp0args.txt`"`r`n" + 'echo {"ok": true}')
function Was-Called([string]$Name) { return (Test-Path (Join-Path $t "$Name.called")) }
function Reset-Called { Get-ChildItem $t -Filter '*.called' | Remove-Item -Force }
function Last-LogLine { if (Test-Path $log) { return @(Get-Content -Encoding UTF8 $log)[-1] } return '' }

function Invoke-Hook([string]$Stdin, [string]$Judge, [hashtable]$Env) {
    Reset-Called
    $env:RSLP_JUDGE_CMD = $Judge
    if ($Env) { foreach ($k in $Env.Keys) { Set-Item "env:$k" $Env[$k] } }
    $out = $Stdin | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hook 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($Env) { foreach ($k in $Env.Keys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } }
    Remove-Item env:RSLP_JUDGE_CMD -ErrorAction SilentlyContinue
    return @{ Out = $out.Trim(); Code = $code }
}
function New-Input([string]$Message, [string]$Cwd, [bool]$Active = $false) {
    return (@{ session_id = 's'; hook_event_name = 'Stop'; cwd = $Cwd; stop_hook_active = $Active; last_assistant_message = $Message } | ConvertTo-Json -Compress)
}

$ja = '承認をお願いします。マイルストーン1の実装が終わり、判定も通りました。次は受け入れテストです。手順は下のとおりです。問題なければ「OK」、気になる点があればその内容を返信してください。'
$en = 'The milestone is complete and the gate passed. Please run the acceptance test using the steps below and reply with OK or describe any problems you found during the test run.'
$mixed = 'impl-check の STATUS が OK になったので、次のマイルストーンの実装に進みます。Implementation Gate の判定は PASS でした。あなたの確認は不要です。'
$codeHeavy = @'
結果です。
```powershell
Get-ChildItem -Path C:\foo | Where-Object { $_.Length -gt 0 } | Select-Object Name, Length, LastWriteTime
```
以上です。
'@

$r = Invoke-Hook (New-Input $en $proj) $judgeOk
Check 'english-blocked' ($r.Code -eq 0 -and $r.Out -match '"decision"\s*:\s*"block"' -and $r.Out -match '\[r-super-loop-powers\]') $r.Out
Check 'english-reason-keeps-requested-english' ($r.Out -match 'コードブロック') $r.Out
Check 'english-no-judge' (-not (Was-Called 'ok')) 'judge must not run when the ratio already fails'
Check 'english-logged' ((Last-LogLine) -match '\| BLOCK \| ja-ratio=') (Last-LogLine)

$r = Invoke-Hook (New-Input $ja $proj) $judgeOk
Check 'japanese-clear-passes' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out
Check 'japanese-judge-called' (Was-Called 'ok') 'judge not called'
Check 'pass-logged' ((Last-LogLine) -match '\| PASS \|') (Last-LogLine)

$r = Invoke-Hook (New-Input $ja $proj) $judgeNg
Check 'judge-ng-blocks' ($r.Out -match '"decision"\s*:\s*"block"' -and $r.Out -match 'put the conclusion first') $r.Out

$r = Invoke-Hook (New-Input $ja $proj) $judgeNgDot
Check 'reason-no-double-stop' ($r.Out -match 'put the conclusion first' -and $r.Out -notmatch 'first\.') $r.Out

$r = Invoke-Hook (New-Input $en $proj $true) $judgeOk
Check 'stop-hook-active-skips' ($r.Code -eq 0 -and $r.Out -eq '' -and -not (Was-Called 'ok')) $r.Out

$r = Invoke-Hook (New-Input $en $outside) $judgeOk
Check 'outside-loop-skips' ($r.Out -eq '' -and -not (Was-Called 'ok')) $r.Out

$r = Invoke-Hook (New-Input $en $doneProj) $judgeOk
Check 'done-goal-skips' ($r.Out -eq '' -and -not (Test-Path (Join-Path $doneGoal 'hook-log.md'))) $r.Out

$r = Invoke-Hook (New-Input $en $proj) $judgeOk @{ RSLP_HOOK_CHILD = '1' }
Check 'child-session-skips' ($r.Out -eq '' -and -not (Was-Called 'ok')) $r.Out

$r = Invoke-Hook (New-Input $ja $proj) $judgeFail
Check 'judge-fail-open' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out
Check 'judge-fail-logged' ((Last-LogLine) -match '\| ERROR \|') (Last-LogLine)

$r = Invoke-Hook (New-Input $ja $proj) $judgeJunk
Check 'judge-junk-open' ($r.Code -eq 0 -and $r.Out -eq '' -and (Last-LogLine) -match '\| ERROR \|') "$($r.Out) / $(Last-LogLine)"

$r = Invoke-Hook (New-Input $codeHeavy $proj) $judgeOk
Check 'code-heavy-not-blocked' ($r.Out -eq '' -and (Was-Called 'ok')) $r.Out

$r = Invoke-Hook (New-Input $mixed $proj) $judgeOk
Check 'mixed-terms-not-blocked' ($r.Out -eq '' -and (Was-Called 'ok')) $r.Out

$longLog = (1..30 | ForEach-Object { "error line $_ failed to open the file because access was denied" }) -join "`n"
$tilde = "結果です。`n~~~`n$longLog`n~~~`n以上です。"
$r = Invoke-Hook (New-Input $tilde $proj) $judgeOk
Check 'tilde-fence-not-blocked' ($r.Out -eq '' -and (Was-Called 'ok')) $r.Out
$unclosed = "結果です。ログを貼ります。`n``````text`n$longLog"
$r = Invoke-Hook (New-Input $unclosed $proj) $judgeOk
Check 'unclosed-fence-not-blocked' ($r.Out -eq '' -and (Was-Called 'ok')) $r.Out

$r = Invoke-Hook (New-Input $en $decoProj) $judgeOk
Check 'decorated-done-skips' ($r.Out -eq '' -and -not (Was-Called 'ok') -and -not (Test-Path (Join-Path $decoDone 'hook-log.md'))) $r.Out
[IO.File]::WriteAllText((Join-Path $decoDone 'state.md'), "- phase: **完了(終了条件 (b))**`n", $utf8)
$r = Invoke-Hook (New-Input $en $decoProj) $judgeOk
Check 'japanese-done-skips' ($r.Out -eq '' -and -not (Was-Called 'ok')) $r.Out
[IO.File]::WriteAllText((Join-Path $decoDone 'state.md'), "- phase: 実装完了。**段 0(人間)待ち**`n", $utf8)
$r = Invoke-Hook (New-Input $en $decoProj) $judgeOk
Check 'waiting-is-active' ($r.Out -match '"decision"\s*:\s*"block"') $r.Out
Remove-Item (Join-Path $decoDone 'hook-log.md') -ErrorAction SilentlyContinue
[IO.File]::WriteAllText((Join-Path $decoDone 'state.md'), "# state - g0`n- phase: **done**(2026-09-25) finished`n", $utf8)
$r = Invoke-Hook (New-Input $ja $mixProj) $judgeOk
Check 'active-goal-chosen-over-decorated-done' ((Test-Path (Join-Path $mixActive 'hook-log.md')) -and -not (Test-Path (Join-Path $mixDone 'hook-log.md'))) 'log landed in the wrong goal'

$r = Invoke-Hook (New-Input $ja $proj) $judgeArgs
$argText = ''; if (Test-Path (Join-Path $t 'args.txt')) { $argText = Get-Content -Raw (Join-Path $t 'args.txt') }
Check 'judge-has-no-tools' ($argText -match '--tools' -and $argText -match '--strict-mcp-config' -and $argText -match 'haiku') $argText

$r = Invoke-Hook (New-Input '' $proj) $judgeOk
Check 'empty-message-skips' ($r.Out -eq '' -and -not (Was-Called 'ok')) $r.Out

$r = Invoke-Hook 'this is not json' $judgeOk
Check 'bad-stdin-open' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out

$bytes = [IO.File]::ReadAllBytes($hook)
Check 'hook-has-bom' ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'save hooks/human-message-check.ps1 as UTF-8 with BOM'
$hj = Get-Content -Raw (Join-Path $root 'hooks\hooks.json') | ConvertFrom-Json
$stop = @($hj.hooks.Stop)[0].hooks[0]
Check 'hooks-json-stop' ($stop.type -eq 'command' -and $stop.command -match 'human-message-check\.ps1' -and $stop.command -match 'CLAUDE_PLUGIN_ROOT' -and $stop.timeout -eq 90) ($stop | ConvertTo-Json)

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
