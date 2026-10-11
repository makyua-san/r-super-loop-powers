#Requires -Version 5.1
# Tests for bin/scout.ps1: prompt/label (launcher via where.exe), collect (hand-made runs), index, log.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillDir = Join-Path $root 'skills\r-super-loop-powers'
$scout = Join-Path $skillDir 'bin\scout.ps1'
$script:failures = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $utf8
[Console]::OutputEncoding = $utf8
. (Join-Path $skillDir 'bin\codex-common.ps1')
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}
function W([string]$Path, [string]$Text) {
    $d = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Get-Text([string]$Path) { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path, $utf8) } return '' }
function Invoke-Scout([string]$Goal, [string[]]$Extra) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scout -GoalDir $Goal @Extra 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
function Get-Kv([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Key) + ': ?(.*)$')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}
$t = Join-Path ([IO.Path]::GetTempPath()) ('scout-' + [guid]::NewGuid().ToString('N'))
$where = Join-Path $env:SystemRoot 'System32\where.exe'
$stateLf = "# state — g1`n- phase: milestone-implementation`n- 強度: MVP`n- milestone: 1-one`n- 次のCheckpoint: 2-two`n- 担当: opus-main`n- 次のゲート: impl-gate`n- 待ち: -`n- skill-dir: C:\skill`n- codex-env: C:\env.json`n- codex-run: -`n- updated: 2026-10-10 10:00`n"

# A goal dir with state.md, call-log.md and a where.exe-backed codex-env.json.
function New-Goal([string]$Name) {
    $g = Join-Path $t "proj\docs\r-super-loop-powers\$Name"
    W (Join-Path $g 'state.md') $stateLf
    W (Join-Path $g 'call-log.md') "# call-log — $Name`n`n"
    $e = [ordered]@{ kind = 'exe'; exe = $where; version = '0.160.0'; model = 'gpt-6.1-sol'; envSchema = 2; skillDir = $skillDir; codexHome = $t }
    W (Join-Path $g 'codex-env.json') ($e | ConvertTo-Json)
    return $g
}
# A finished scout run made by hand (same shape as codex-status.tests.ps1).
function New-FinishedRun([string]$Goal, [string]$Label, [string]$Last, [bool]$Web, [string]$Question, [int]$ExitCode = 0) {
    $runDir = Join-Path $Goal 'codex-runs'
    $meta = [ordered]@{ label = $Label; role = 'scout'; model = 'gpt-6.1-sol'; effort = 'medium'; web = $Web; timeoutMinutes = 60; startedAt = (Get-Date).AddMinutes(-3).ToString('s') }
    W (Join-Path $runDir "$Label.meta.json") ($meta | ConvertTo-Json)
    $events = @('{"type":"thread.started","thread_id":"th-1"}', '{"type":"turn.started"}',
        '{"type":"item.completed","item":{"id":"i9","type":"agent_message","text":"done"}}',
        '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}')
    W (Join-Path $runDir "$Label.out.jsonl") ($events -join "`n")
    W (Join-Path $runDir "$Label.last.txt") $Last
    W (Join-Path $runDir "$Label.done.json") ('{"label":"' + $Label + '","exitCode":' + $ExitCode + ',"timedOut":false,"durationSec":150}')
    W (Join-Path $runDir "$Label.exit") ([string]$ExitCode)
    if ($null -ne $Question) { W (Join-Path $runDir "$Label.prompt.md") "== TASK: SCOUT ==`n## 問い`n$Question`n`n## 調べる範囲`n- x`n" }
}
$good = "## 問い`nどこで決まるか`n`n## 結論`n- loop-log.ps1 の 40 行目で決まる`n- 閉じた語彙である`n`n## 根拠`n- skills/r-super-loop-powers/bin/loop-log.ps1:40 `$Roles = @(...)`n`n## 未確認`n- テストの網羅性`n"

# --- collect: OK ---
$g1 = New-Goal 'g1'
New-FinishedRun $g1 'scout-1' $good $false 'どこで決まるか'
$r = Invoke-Scout $g1 @('-Collect', 'scout-1', '-WaitMinutes', '0')
$rep = Join-Path $g1 'scout\scout-1.md'
Check 'collect-ok' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'OK' -and (Get-Kv $r.Out 'LABEL') -eq 'scout-1') $r.Out
Check 'collect-report-path' ((Get-Kv $r.Out 'REPORT') -eq $rep -and (Test-Path -LiteralPath $rep)) $r.Out
$repText = Get-Text $rep
Check 'collect-report-header' ($repText -match '(?m)^- 日時: \d{4}-\d{2}-\d{2} \d{2}:\d{2}$' -and $repText -match '(?m)^- label: scout-1$' -and $repText -match '(?m)^- web: not-requested$' -and $repText -match '(?m)^- effort: medium$' -and $repText -match '(?m)^- 問い: どこで決まるか$') $repText
Check 'collect-report-body-verbatim' ($repText.EndsWith("`n`n" + $good)) $repText
# Out-String yields CRLF, so trim the captured line.
$conc = @([regex]::Matches($r.Out, '(?m)^CONCLUSION: (.*)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
Check 'collect-conclusion-lines' ($conc.Count -eq 2 -and $conc[0] -eq '- loop-log.ps1 の 40 行目で決まる') ($conc -join '|')
Check 'collect-unverified-count' ((Get-Kv $r.Out 'UNVERIFIED') -eq '1') $r.Out
Check 'collect-web-not-requested' ((Get-Kv $r.Out 'WEB') -eq 'not-requested') $r.Out
Check 'collect-elapsed' ((Get-Kv $r.Out 'ELAPSED_MIN') -match '^\d+(\.\d)?$') $r.Out
$idx = Get-Text (Join-Path $g1 'scout\index.md')
Check 'collect-index-line' ($idx -match '(?m)^\d{4}-\d{2}-\d{2} \d{2}:\d{2} \| scout-1 \| web:n \| どこで決まるか$') $idx
Check 'collect-index-heading' ($idx.StartsWith('# scout index — g1')) $idx
Check 'collect-call-log' ((Get-Text (Join-Path $g1 'call-log.md')) -match '(?m)\| codex-scout \| milestone-implementation \| scout-1: どこで決まるか$') (Get-Text (Join-Path $g1 'call-log.md'))
Check 'collect-no-bom-lf' ((-not ([IO.File]::ReadAllBytes($rep)[0] -eq 0xEF)) -and (-not $repText.Contains("`r"))) 'report must be UTF-8 without BOM, LF'
Check 'collect-state-untouched' ((Get-Text (Join-Path $g1 'state.md')) -eq $stateLf) 'state.md changed by a sync collect'
# collecting the same label again must not duplicate the index line
$r = Invoke-Scout $g1 @('-Collect', 'scout-1', '-WaitMinutes', '0')
$idx2 = Get-Text (Join-Path $g1 'scout\index.md')
Check 'collect-twice-no-duplicate' (([regex]::Matches($idx2, '\| scout-1 \|')).Count -eq 1) $idx2

# --- collect: INCOMPLETE (no 根拠) ---
New-FinishedRun $g1 'scout-2' "## 問い`nq`n`n## 結論`n- 何か`n" $false 'q'
$r = Invoke-Scout $g1 @('-Collect', 'scout-2', '-WaitMinutes', '0')
Check 'incomplete-status' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'INCOMPLETE' -and (Get-Kv $r.Out 'REASON') -match '根拠') $r.Out
Check 'incomplete-raw-saved' ((Get-Kv $r.Out 'RAW') -eq (Join-Path $g1 'scout\scout-2.raw.md') -and (Test-Path -LiteralPath (Join-Path $g1 'scout\scout-2.raw.md'))) $r.Out
Check 'incomplete-not-indexed' (-not (Get-Text (Join-Path $g1 'scout\index.md')).Contains('scout-2')) 'index has scout-2'
Check 'incomplete-not-logged' (-not (Get-Text (Join-Path $g1 'call-log.md')).Contains('scout-2')) 'call-log has scout-2'
Check 'incomplete-no-report' (-not (Test-Path -LiteralPath (Join-Path $g1 'scout\scout-2.md'))) 'scout-2.md exists'

# --- collect: WEB_UNAVAILABLE ---
New-FinishedRun $g1 'scout-3' ($good + "WEB_UNAVAILABLE`n") $true 'q3'
$r = Invoke-Scout $g1 @('-Collect', 'scout-3', '-WaitMinutes', '0')
Check 'web-unavailable' ((Get-Kv $r.Out 'STATUS') -eq 'OK' -and (Get-Kv $r.Out 'WEB') -eq 'unavailable') $r.Out
New-FinishedRun $g1 'scout-4' $good $true 'q4'
$r = Invoke-Scout $g1 @('-Collect', 'scout-4', '-WaitMinutes', '0')
Check 'web-used' ((Get-Kv $r.Out 'WEB') -eq 'used' -and (Get-Text (Join-Path $g1 'scout\index.md')) -match '\| scout-4 \| web:y \|') $r.Out

# --- collect: FAILED / RUNNING / unknown label ---
New-FinishedRun $g1 'scout-5' 'x' $false 'q5' 1
$r = Invoke-Scout $g1 @('-Collect', 'scout-5', '-WaitMinutes', '0')
Check 'failed-relayed' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED' -and -not (Test-Path -LiteralPath (Join-Path $g1 'scout\scout-5.md'))) $r.Out
Check 'failed-not-logged' (-not (Get-Text (Join-Path $g1 'call-log.md')).Contains('scout-5')) 'call-log has scout-5'
New-FinishedRun $g1 'scout-6' $good $false 'q6'
Remove-Item -LiteralPath (Join-Path $g1 'codex-runs\scout-6.exit') -Force
W (Join-Path $g1 'codex-runs\scout-6.pid') ([string]$PID)
$r = Invoke-Scout $g1 @('-Collect', 'scout-6', '-WaitMinutes', '0')
Check 'running-relayed' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'RUNNING' -and (Get-Kv $r.Out 'NEXT') -match '-Collect scout-6') $r.Out
$r = Invoke-Scout $g1 @('-Collect', 'nope', '-WaitMinutes', '0')
Check 'unknown-label-fails' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED') $r.Out

# --- review focus 1: CRLF, numbered headings, trailing spaces ---
$crlf = "## 1. 問い  `r`nq`r`n`r`n## 2. 結論 `r`n- a`r`n- b`r`n- c`r`n- d`r`n- e`r`n- f`r`n`r`n## 3. 根拠`r`n- f:1`r`n`r`n## 4. 未確認`r`n"
New-FinishedRun $g1 'scout-7' $crlf $false 'q7'
$r = Invoke-Scout $g1 @('-Collect', 'scout-7', '-WaitMinutes', '0')
$conc7 = @([regex]::Matches($r.Out, '(?m)^CONCLUSION: (.*)$'))
Check 'collect-crlf-numbered-headings' ((Get-Kv $r.Out 'STATUS') -eq 'OK' -and $conc7.Count -eq 5 -and (Get-Kv $r.Out 'UNVERIFIED') -eq '0') $r.Out

# --- review focus 3: no prompt.md ---
New-FinishedRun $g1 'scout-8' $good $false $null
Remove-Item -LiteralPath (Join-Path $g1 'codex-runs\scout-8.prompt.md') -Force -ErrorAction SilentlyContinue
$r = Invoke-Scout $g1 @('-Collect', 'scout-8', '-WaitMinutes', '0')
Check 'collect-without-prompt-md' ((Get-Kv $r.Out 'STATUS') -eq 'OK' -and (Get-Text (Join-Path $g1 'scout\scout-8.md')) -match '(?m)^- 問い: \(不明\)$') $r.Out

# --- review focus 4: no state.md ---
$g2 = New-Goal 'g2'
Remove-Item -LiteralPath (Join-Path $g2 'state.md') -Force
New-FinishedRun $g2 'scout-1' $good $false 'q'
$r = Invoke-Scout $g2 @('-Collect', 'scout-1', '-WaitMinutes', '0')
Check 'collect-without-state-warns' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'OK' -and $r.Out -match '(?m)^WARN: .*call-log' -and (Test-Path -LiteralPath (Join-Path $g2 'scout\scout-1.md'))) $r.Out

# --- -Collect clears codex-run when it holds this label ---
$g3 = New-Goal 'g3'
W (Join-Path $g3 'state.md') ($stateLf -replace '- codex-run: -', '- codex-run: scout-1')
New-FinishedRun $g3 'scout-1' $good $false 'q'
$r = Invoke-Scout $g3 @('-Collect', 'scout-1', '-WaitMinutes', '0')
Check 'collect-clears-codex-run' ((Get-Kv $r.Out 'STATUS') -eq 'OK' -and (Get-Text (Join-Path $g3 'state.md')) -match '(?m)^- codex-run: -$') (Get-Text (Join-Path $g3 'state.md'))

# --- -List ---
$r = Invoke-Scout $g2 @('-List')
Check 'list-shows-index' ($r.Code -eq 0 -and $r.Out -match '\| scout-1 \|') $r.Out
$g4 = New-Goal 'g4'
$r = Invoke-Scout $g4 @('-List')
Check 'list-none' ($r.Code -eq 0 -and $r.Out -match '(?m)^INDEX: none') $r.Out

# --- launch (codex replaced by where.exe) ---
$r = Invoke-Scout $g4 @('-WorkDir', $t, '-Question', 'どこで決まるか', '-Async')
Check 'async-started' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'STARTED' -and (Get-Kv $r.Out 'LABEL') -eq 'scout-1' -and (Get-Kv $r.Out 'NEXT') -match '-Collect scout-1') $r.Out
Check 'async-sets-codex-run' ((Get-Text (Join-Path $g4 'state.md')) -match '(?m)^- codex-run: scout-1$') (Get-Text (Join-Path $g4 'state.md'))
$p1 = Get-Text (Join-Path $g4 'codex-runs\scout-1.prompt.md')
Check 'prompt-question' ($p1 -match '(?m)^== TASK: SCOUT ==' -and $p1 -match "(?m)^## 問い`nどこで決まるか$") $p1
Check 'prompt-no-web' ($p1 -match '(?m)^- Web: 使わない') $p1
Check 'prompt-scope' ($p1 -match ([regex]::Escape($t)) -and $p1 -match ([regex]::Escape($g4))) $p1
Check 'prompt-format' ($p1 -match '`## 結論`' -and $p1 -match '`## 根拠`' -and $p1 -match '`## 未確認`') $p1
$m1 = Get-Content -Raw (Join-Path $g4 'codex-runs\scout-1.meta.json') | ConvertFrom-Json
Check 'launch-role-scout' ($m1.role -eq 'scout' -and $m1.effort -eq 'medium') ($m1 | ConvertTo-Json)
$qf = Join-Path $t 'q.md'; W $qf "複数行の`n問い"
$r = Invoke-Scout $g4 @('-WorkDir', $t, '-QuestionFile', $qf, '-Web', '-Effort', 'high', '-Async')
Check 'second-label' ((Get-Kv $r.Out 'LABEL') -eq 'scout-2') $r.Out
$p2 = Get-Text (Join-Path $g4 'codex-runs\scout-2.prompt.md')
Check 'prompt-web-and-file' ($p2 -match '(?m)^- Web: 使ってよい' -and $p2 -match "複数行の`n問い") $p2
Check 'launch-effort-high' ((Get-Content -Raw (Join-Path $g4 'codex-runs\scout-2.meta.json') | ConvertFrom-Json).effort -eq 'high') 'effort'
$r = Invoke-Scout $g4 @('-WorkDir', $t, '-Question', 'x', '-Label', 'scout-1', '-Async')
Check 'same-label-refused' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out
$r = Invoke-Scout $g4 @('-WorkDir', $t, '-Question', 'x', '-QuestionFile', $qf, '-Async')
Check 'both-question-forms-fail' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED') $r.Out
$r = Invoke-Scout $g4 @('-WorkDir', $t, '-Async')
Check 'no-question-fails' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED') $r.Out
$r = Invoke-Scout $g4 @('-Question', 'x', '-Async')
Check 'no-workdir-fails' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED') $r.Out
# Smoke 2026-10-12: a goal dir outside the working directory is unreadable under contract
# item 1 unless it is added with --add-dir; inside the working directory nothing is added.
Check 'launch-no-add-dir-inside' ($m1.command -notmatch '--add-dir') $m1.command
$outside = Join-Path $t 'proj2'; New-Item -ItemType Directory -Path $outside -Force | Out-Null
$r = Invoke-Scout $g4 @('-WorkDir', $outside, '-Question', 'x', '-Label', 'scout-out', '-Async')
$mOut = Get-Content -Raw (Join-Path $g4 'codex-runs\scout-out.meta.json') | ConvertFrom-Json
Check 'launch-add-dir-outside' ((Get-Kv $r.Out 'STATUS') -eq 'STARTED' -and $mOut.command -match ('--add-dir ' + [regex]::Escape((ConvertTo-Arg $g4)))) $mOut.command
# Review 2026-10-12 (Important 1): a stale codex-env.json (codex upgraded, preflight not
# re-run) makes codex-run.ps1 throw; the launch failure must still come back as KV lines,
# and the prompt written before the launch must not be left behind as an orphan.
$g5 = New-Goal 'g5'
$stale = [ordered]@{ kind = 'exe'; exe = (Join-Path $t 'missing-codex.exe'); version = '0.160.0'; model = 'gpt-6.1-sol'; envSchema = 2; skillDir = $skillDir; codexHome = $t }
W (Join-Path $g5 'codex-env.json') ($stale | ConvertTo-Json)
$r = Invoke-Scout $g5 @('-WorkDir', $t, '-Question', 'x', '-Async')
Check 'launch-stale-env-fails-cleanly' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED' -and (Get-Kv $r.Out 'REASON') -match 'codex-preflight') $r.Out
Check 'launch-failure-no-orphan-prompt' (-not (Test-Path -LiteralPath (Join-Path $g5 'codex-runs\scout-1.prompt.md')) -and -not (Test-Path -LiteralPath (Join-Path $g5 'codex-runs\scout-1.meta.json'))) 'orphan prompt/meta left after a failed launch'
# Review 2026-10-12 (Important 2): a terminal non-OK collect must release codex-run: too.
$g6 = New-Goal 'g6'
New-FinishedRun $g6 'scout-2' "## 問い`nq`n`n## 結論`n- 何か`n" $false 'q'
W (Join-Path $g6 'state.md') ($stateLf -replace '- codex-run: -', '- codex-run: scout-2')
$r = Invoke-Scout $g6 @('-Collect', 'scout-2', '-WaitMinutes', '0')
Check 'incomplete-clears-codex-run' ((Get-Kv $r.Out 'STATUS') -eq 'INCOMPLETE' -and (Get-Text (Join-Path $g6 'state.md')) -match '(?m)^- codex-run: -$') (Get-Text (Join-Path $g6 'state.md'))
New-FinishedRun $g6 'scout-5' 'x' $false 'q5' 1
W (Join-Path $g6 'state.md') ($stateLf -replace '- codex-run: -', '- codex-run: scout-5')
$r = Invoke-Scout $g6 @('-Collect', 'scout-5', '-WaitMinutes', '0')
Check 'failed-clears-codex-run' ((Get-Kv $r.Out 'STATUS') -eq 'FAILED' -and (Get-Text (Join-Path $g6 'state.md')) -match '(?m)^- codex-run: -$') (Get-Text (Join-Path $g6 'state.md'))
Check 'failed-still-not-logged' (-not (Get-Text (Join-Path $g6 'call-log.md')).Contains('scout-5')) 'call-log has scout-5'
# sync launch: where.exe exits non-zero quickly -> FAILED is relayed, nothing saved.
$r = Invoke-Scout $g4 @('-WorkDir', $t, '-Question', 'sync', '-WaitMinutes', '1')
Check 'sync-failed-relayed' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -match '^(FAILED|SUSPECT)$' -and -not (Test-Path -LiteralPath (Join-Path $g4 'scout\scout-3.md'))) $r.Out

# --- review focus 2: a long question with | and newlines stays one index line ---
$long = ('あ' * 130) + "|`nb"
New-FinishedRun $g4 'scout-9' $good $false $long
$r = Invoke-Scout $g4 @('-Collect', 'scout-9', '-WaitMinutes', '0')
$idx4 = Get-Text (Join-Path $g4 'scout\index.md')
$line9 = @(($idx4 -split "`n") | Where-Object { $_ -match '\| scout-9 \|' })
Check 'index-one-line-long-question' ($line9.Count -eq 1 -and $line9[0].Length -le (40 + 120) -and $line9[0] -notmatch '\|\s*$') ($line9 -join '/')

Check 'script-has-bom' ([IO.File]::ReadAllBytes($scout)[0] -eq 0xEF) 'scout.ps1 must be UTF-8 with BOM (Japanese literals)'

# Smoke 2026-10-12: the orchestrator calls scout.ps1 from the Bash tool, whose console code
# page is not UTF-8, and the Japanese CONCLUSION lines arrived garbled. The script must emit
# UTF-8 bytes whatever code page the console has.
$rawOut = Join-Path $t 'list-raw.txt'
& cmd.exe /c "chcp 932 >nul & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""$scout"" -GoalDir ""$g1"" -List > ""$rawOut"" & chcp 65001 >nul"
$rawText = [IO.File]::ReadAllText($rawOut, $utf8)
Check 'stdout-utf8-under-cp932' ($rawText -match '\| scout-1 \| web:n \| どこで決まるか' -and $rawText -match '# scout index — g1') $rawText

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
