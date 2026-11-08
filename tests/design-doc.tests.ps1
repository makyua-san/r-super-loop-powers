#Requires -Version 5.1
# Tests for bin/design-doc.ps1: modes (create / update / unchanged / fallback), prompt, label,
# collect (hand-made runs), history rows, shape check, NEXT, size warning, -AddDir.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillDir = Join-Path $root 'skills\r-super-loop-powers'
$designDoc = Join-Path $skillDir 'bin\design-doc.ps1'
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
function Get-Kv([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Key) + ': ?(.*)$')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}
# -WaitMinutes 0: a launch (codex replaced by where.exe) comes back at once as RUNNING or FAILED;
# the tests look at the prompt, the meta json and the LABEL line, not at the verdict.
function Invoke-DesignDoc([string]$Goal, [string[]]$Extra) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $designDoc -GoalDir $Goal @Extra -WaitMinutes 0 2>&1 | Out-String
    return @{ Out = ($out -replace "`r`n", "`n"); Code = $LASTEXITCODE }
}
function Get-Meta([string]$Goal, [string]$Label) {
    $f = Join-Path $Goal "codex-runs\$Label.meta.json"
    if (-not (Test-Path -LiteralPath $f)) { return [pscustomobject]@{ effort = ''; command = '' } }
    return (Get-Text $f | ConvertFrom-Json)
}
$t = Join-Path ([IO.Path]::GetTempPath()) ('designdoc-' + [guid]::NewGuid().ToString('N'))
$where = Join-Path $env:SystemRoot 'System32\where.exe'
$stateLf = "# state — g`n- phase: milestone-implementation`n- 強度: MVP`n- milestone: 1-one`n- 次のCheckpoint: 2-two`n- 担当: opus-main`n- 次のゲート: impl-gate`n- 待ち: -`n- skill-dir: C:\skill`n- codex-env: C:\env.json`n- codex-run: -`n- updated: 2026-10-10 10:00`n"

# A git repository with one empty commit (the WorkDir).
function New-Proj([string]$Name) {
    $p = Join-Path $t $Name
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    git -C $p init -q 2>&1 | Out-Null
    git -C $p -c user.name=t -c user.email=t@t commit -q --allow-empty -m init 2>&1 | Out-Null
    return $p
}
# A goal dir <base>\docs\r-super-loop-powers\<name> with state.md, call-log.md, codex-env.json.
function New-Goal([string]$Base, [string]$Name) {
    $g = Join-Path $Base "docs\r-super-loop-powers\$Name"
    W (Join-Path $g 'state.md') $stateLf
    W (Join-Path $g 'call-log.md') "# call-log — $Name`n`n"
    $e = [ordered]@{ kind = 'exe'; exe = $where; version = '0.160.0'; model = 'gpt-6.1-sol'; envSchema = 2; skillDir = $skillDir; codexHome = $t }
    W (Join-Path $g 'codex-env.json') ($e | ConvertTo-Json)
    return $g
}
# A finished surveyor run made by hand (same shape as codex-status.tests.ps1). The work dir is
# the project three levels above the goal dir; the prompt carries the milestone tag.
function New-FinishedRun([string]$Goal, [string]$Label, [string]$Last, [string]$Tag, [int]$ExitCode = 0, [bool]$TimedOut = $false, [string]$Effort = 'medium') {
    $runDir = Join-Path $Goal 'codex-runs'
    $work = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Goal))
    $meta = [ordered]@{ label = $Label; workDir = $work; runDir = $runDir; role = 'surveyor'; model = 'gpt-6.1-sol'; effort = $Effort; web = $false; timeoutMinutes = 30; startedAt = (Get-Date).AddMinutes(-3).ToString('s') }
    W (Join-Path $runDir "$Label.meta.json") ($meta | ConvertTo-Json)
    $events = @('{"type":"thread.started","thread_id":"th-1"}', '{"type":"turn.started"}',
        '{"type":"item.completed","item":{"id":"i9","type":"agent_message","text":"done"}}',
        '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}')
    W (Join-Path $runDir "$Label.out.jsonl") ($events -join "`n")
    W (Join-Path $runDir "$Label.last.txt") $Last
    W (Join-Path $runDir "$Label.done.json") ('{"label":"' + $Label + '","exitCode":' + $ExitCode + ',"timedOut":' + $(if ($TimedOut) { 'true' } else { 'false' }) + ',"durationSec":150}')
    W (Join-Path $runDir "$Label.exit") ([string]$ExitCode)
    W (Join-Path $runDir "$Label.prompt.md") "== TASK: DESIGN DOC ==`n## 節目: $Tag`n"
}

$good = @'
# 設計書 — demo

## 更新履歴

| 日時 | ゴール | 節目 | 見たコミット | 書き手 |
|---|---|---|---|---|
| BOGUS-ROW |

## このプロジェクトは何か

デモ。

## 0. 構成

### 0.1 全体概要(どこで何が動いているか)

一台で動く。

## 1. 機能の地図(到達度)

| 機能 | 何をする | どこにある(拡張の入口) | つながり | 到達度 |
|---|---|---|---|---|
| a | x | src/a.js | b | できている |
| b | y | src/b.js | a | 一部 → 2 章 |
| c | z | src/c.js | - | 未着手 |

## 2. 取り組んだが足りない(頼み直しでは解決しない件)

### b

- **試したこと**: t

### d

- **試したこと**: t

## 3. 要望はあるが未着手

- r1(出典: g1 + acceptance.md)

## 4. 運用で見る懸念(使いながら確かめる)

- c1(出典: g1 + goal-frame.md)
'@ -replace "`r`n", "`n"
$goodWithRow = $good.Replace('| BOGUS-ROW |', '| 2026-11-01 10:00 | g | A-0 | {0} | codex |')
$previous = $good.Replace('| BOGUS-ROW |', '| 2026-11-01 10:00 | g3 | CP:1-one | 0000000 | codex |').Replace("デモ。`n", "デモ。`nBODY-MARKER`n")

$proj = New-Proj 'p1'; $g1 = New-Goal $proj 'g1'; $design1 = Join-Path $proj 'docs\r-super-loop-powers\design.md'
$proj2 = New-Proj 'p2'; $g2 = New-Goal $proj2 'g2'; $design2 = Join-Path $proj2 'docs\r-super-loop-powers\design.md'
$proj3 = New-Proj 'p3'; $g3 = New-Goal $proj3 'g3'; $design3 = Join-Path $proj3 'docs\r-super-loop-powers\design.md'
$proj4 = New-Proj 'p4'; $g4 = New-Goal $proj4 'g4'
$proj5 = New-Proj 'p5'; $g5 = New-Goal $proj5 'g5'; $design5 = Join-Path $proj5 'docs\r-super-loop-powers\design.md'
$proj6 = New-Proj 'p6'; $g6 = New-Goal $proj6 'g6'; $design6 = Join-Path $proj6 'docs\r-super-loop-powers\design.md'
$projOut = New-Proj 'pout'; $gOut = New-Goal (Join-Path $t 'elsewhere') 'gout'

# --- create ---
$r = Invoke-DesignDoc $g1 @('-WorkDir', $proj, '-Milestone', 'A-0')
$p = Get-Text (Join-Path $g1 'codex-runs\design-A-0-1.prompt.md')
Check 'create-prompt' ($p -match '== TASK: DESIGN DOC ==' -and $p -match 'モード: 作成' -and $p -match '## 更新履歴' -and $p -match '更新履歴の行は書かない' -and $p -match [regex]::Escape($proj)) $p
Check 'create-effort-high' ((Get-Meta $g1 'design-A-0-1').effort -eq 'high') 'create must pass -Effort high'
Check 'create-label' ($r.Out -match '(?m)^LABEL: design-A-0-1$') $r.Out
# --- update: an existing design.md whose last row points at an older SHA ---
W $design1 ($goodWithRow -f 'deadbee')
$r = Invoke-DesignDoc $g1 @('-WorkDir', $proj, '-Milestone', 'A-0')
$p = Get-Text (Join-Path $g1 'codex-runs\design-A-0-2.prompt.md')
Check 'update-prompt' ($p -match 'モード: 更新' -and $p -match 'git log --oneline deadbee\.\.HEAD' -and $p -match 'git diff --stat deadbee\.\.HEAD' -and $p -match [regex]::Escape($design1)) $p
Check 'update-effort-medium' ((Get-Meta $g1 'design-A-0-2').effort -eq 'medium') 'update uses the role default'
# The update prompt measures from the last codex row, not from a later opus fallback row.
$proj12 = New-Proj 'p12'; $g12 = New-Goal $proj12 'g12'
W (Join-Path $proj12 'docs\r-super-loop-powers\design.md') ($good.Replace('| BOGUS-ROW |', "| 2026-11-01 10:00 | g | A-0 | deadbee | codex |`n| 2026-11-02 10:00 | g | CP:1-one | cafe123 | opus(代行: x) |"))
$r = Invoke-DesignDoc $g12 @('-WorkDir', $proj12, '-Milestone', 'A-0')
$p = Get-Text (Join-Path $g12 'codex-runs\design-A-0-1.prompt.md')
Check 'update-prompt-base-is-last-codex-row' ($p -match 'モード: 更新' -and $p -match 'git log --oneline deadbee\.\.HEAD' -and $p -notmatch 'cafe123') $p
# Only a fallback row (as -Fallback creates): no git range, read everything.
$proj13 = New-Proj 'p13'; $g13 = New-Goal $proj13 'g13'
W (Join-Path $proj13 'docs\r-super-loop-powers\design.md') ($good.Replace('| BOGUS-ROW |', '| 2026-11-02 10:00 | g | A-0 | cafe123 | opus(代行: x) |'))
$r = Invoke-DesignDoc $g13 @('-WorkDir', $proj13, '-Milestone', 'A-0')
$p = Get-Text (Join-Path $g13 'codex-runs\design-A-0-1.prompt.md')
Check 'update-prompt-no-codex-row-reads-all' ($p -match 'モード: 更新' -and $p -match '全体に読み直し' -and $p -notmatch 'git log --oneline' -and $p -notmatch 'git diff --stat') $p

# --- unchanged: last row SHA == HEAD, writer codex, nothing dirty outside the goal dir ---
$head2 = (git -C $proj2 rev-parse --short HEAD)
W $design2 ($goodWithRow -f $head2)
$r = Invoke-DesignDoc $g2 @('-WorkDir', $proj2, '-Milestone', 'A-0')
Check 'unchanged-skips-codex' ($r.Code -eq 0 -and $r.Out -match '(?m)^MODE: unchanged$' -and -not (Test-Path (Join-Path $g2 'codex-runs\design-A-0-1.meta.json'))) $r.Out
Check 'unchanged-appends-row' ((Get-Text $design2) -match '(?m)^\| \d{4}-\d{2}-\d{2} \d{2}:\d{2} \| g2 \| A-0 \| [0-9a-f]{7,} \| unchanged \|$') (Get-Text $design2)
Check 'unchanged-logged' ((Get-Text (Join-Path $g2 'call-log.md')) -match '\| codex-surveyor \| [^|]+ \| A-0: unchanged$') 'call-log'
# Reset to a codex row at HEAD so only the dirty file can force an update.
W $design2 ($goodWithRow -f $head2)
W (Join-Path $proj2 'src\x.js') 'dirty'
$r = Invoke-DesignDoc $g2 @('-WorkDir', $proj2, '-Milestone', 'A-0')
Check 'dirty-tree-is-update' ($r.Out -match '(?m)^LABEL: design-A-0-1$') $r.Out

# --- unchanged is measured from the last codex row; the row goal's records and design.md do not count ---
# A project whose design.md has a codex row (slug rowgoal, SHA = the first commit); then design.md is
# committed, modified and committed again together with $CommitPath; then a new goal dir is made.
function New-RowFixture([string]$Name, [string]$CommitPath) {
    $p = New-Proj $Name
    $head = (git -C $p rev-parse --short HEAD)
    $d = Join-Path $p 'docs\r-super-loop-powers\design.md'
    W $d (($goodWithRow -f $head).Replace('| g | A-0 |', '| rowgoal | A-0 |'))
    git -C $p add -A 2>&1 | Out-Null
    git -C $p -c user.name=t -c user.email=t@t commit -q -m design 2>&1 | Out-Null
    W $d ((Get-Text $d) + "`n追記`n")
    W (Join-Path $p $CommitPath) 'x'
    git -C $p add -A 2>&1 | Out-Null
    git -C $p -c user.name=t -c user.email=t@t commit -q -m later 2>&1 | Out-Null
    return @{ P = $p; G = (New-Goal $p 'newgoal') }
}
$f = New-RowFixture 'p7' 'docs\r-super-loop-powers\rowgoal\milestones\1-x\retro.md'
$r = Invoke-DesignDoc $f.G @('-WorkDir', $f.P, '-Milestone', 'A-0')
Check 'unchanged-ignores-row-goal-records' ($r.Code -eq 0 -and $r.Out -match '(?m)^MODE: unchanged$') $r.Out
$f = New-RowFixture 'p8' 'docs\r-super-loop-powers\other\milestones\1-x\retro.md'
$r = Invoke-DesignDoc $f.G @('-WorkDir', $f.P, '-Milestone', 'A-0')
Check 'changed-other-goal-records' ($r.Out -match '(?m)^LABEL: design-A-0-1$' -and $r.Out -notmatch 'MODE: unchanged') $r.Out
$f = New-RowFixture 'p9' 'src\x.js'
$r = Invoke-DesignDoc $f.G @('-WorkDir', $f.P, '-Milestone', 'A-0')
Check 'changed-code-since-row' ($r.Out -match '(?m)^LABEL: design-A-0-1$' -and $r.Out -notmatch 'MODE: unchanged') $r.Out
# CP never skips codex, even with the fixture that gives unchanged at A-0.
$proj10 = New-Proj 'p10'; $g10 = New-Goal $proj10 'g10'
W (Join-Path $proj10 'docs\r-super-loop-powers\design.md') ($goodWithRow -f (git -C $proj10 rev-parse --short HEAD))
$r = Invoke-DesignDoc $g10 @('-WorkDir', $proj10, '-Milestone', 'CP')
Check 'cp-never-unchanged' ($r.Out -match '(?m)^LABEL: design-CP\.1-one-1$' -and $r.Out -notmatch 'MODE: unchanged') $r.Out
# A later unchanged row does not hide the codex row before it.
$proj11 = New-Proj 'p11'; $g11 = New-Goal $proj11 'g11'
$head11 = (git -C $proj11 rev-parse --short HEAD)
$codexRow = "| 2026-11-01 10:00 | g | A-0 | $head11 | codex |"
W (Join-Path $proj11 'docs\r-super-loop-powers\design.md') ($good.Replace('| BOGUS-ROW |', "$codexRow`n| 2026-11-02 10:00 | g | A-0 | $head11 | unchanged |"))
$r = Invoke-DesignDoc $g11 @('-WorkDir', $proj11, '-Milestone', 'A-0')
Check 'unchanged-after-unchanged-row' ($r.Code -eq 0 -and $r.Out -match '(?m)^MODE: unchanged$') $r.Out

# --- collect: a hand-made finished run ---
New-FinishedRun $g3 'design-A-0-1' $good 'A-0'
W $design3 $previous
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-1')
$d3 = Get-Text $design3
Check 'collect-ok' ($r.Code -eq 0 -and $r.Out -match '(?m)^STATUS: OK$' -and $r.Out -match '(?m)^MODE: update$' -and $r.Out -match '(?m)^FEATURES: 3$' -and $r.Out -match '(?m)^INSUFFICIENT: 2$') $r.Out
Check 'collect-saves-prev' ((Get-Text (Join-Path $g3 'codex-runs\design-A-0-1.design-prev.md')) -eq $previous) 'previous design.md not kept'
Check 'collect-history-row' ($d3 -match '(?m)^\| \d{4}-\d{2}-\d{2} \d{2}:\d{2} \| g3 \| A-0 \| [0-9a-f]{7,} \| codex \|$' -and $d3 -match '\| g3 \| CP:1-one \| 0000000 \| codex \|') "new row missing or previous rows lost`n$d3"
Check 'collect-strips-codex-rows' ($d3 -notmatch 'BOGUS-ROW') 'rows written by codex must be dropped'
Check 'collect-logged' ((Get-Text (Join-Path $g3 'call-log.md')) -match '\| codex-surveyor \| [^|]+ \| A-0: update$') 'call-log'
Check 'collect-history-kv' ((Get-Kv $r.Out 'HISTORY') -match '^\| \d{4}-\d{2}-\d{2} \d{2}:\d{2} \| g3 \| A-0 \| [0-9a-f]{7,} \| codex \|$' -and (Get-Kv $r.Out 'DESIGN_DOC') -eq $design3) $r.Out
Check 'collect-no-bom-lf' ((-not ([IO.File]::ReadAllBytes($design3)[0] -eq 0xEF)) -and (-not $d3.Contains("`r"))) 'design.md must be UTF-8 without BOM, LF'
New-FinishedRun $g3 'design-A-0-2' ("``````markdown`n" + $good + "`n``````") 'A-0'
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-2')
Check 'collect-unwraps-fence' ($r.Out -match '(?m)^STATUS: OK$' -and -not (Get-Text $design3).StartsWith('```')) $r.Out
New-FinishedRun $g3 'design-A-0-3' ($good -replace '## 1\. 機能の地図\(到達度\)', '## 1. 機能') 'A-0'
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-3')
Check 'collect-incomplete' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: INCOMPLETE$' -and $r.Out -match '機能の地図' -and (Test-Path (Join-Path $g3 'codex-runs\design-A-0-3.raw.md'))) $r.Out
Check 'incomplete-next-same-command' ((Get-Kv $r.Out 'NEXT') -match ('-WorkDir ''' + [regex]::Escape($proj3) + ''' -Milestone A-0$')) $r.Out
Check 'incomplete-keeps-design' ((Get-Text $design3) -notmatch '(?m)^## 1\. 機能$') 'design.md must not be overwritten on INCOMPLETE'
New-FinishedRun $g3 'design-A-0-4' $good 'A-0' -ExitCode 124 -TimedOut $true -Effort 'high'
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-4')
Check 'timeout-next-lower-effort' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: TIMEOUT$' -and $r.Out -match '(?m)^NEXT: .*-Effort medium') $r.Out
New-FinishedRun $g3 'design-A-0-6' $good 'A-0'
Remove-Item -LiteralPath (Join-Path $g3 'codex-runs\design-A-0-6.exit') -Force
W (Join-Path $g3 'codex-runs\design-A-0-6.pid') ([string]$PID)
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-6')
Check 'running-next-collect' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'RUNNING' -and (Get-Kv $r.Out 'NEXT') -match '-Collect design-A-0-6$') $r.Out
$r = Invoke-DesignDoc $g3 @('-Collect', 'nope')
Check 'unknown-label-fails' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED') $r.Out

# --- CP tag comes from state.md ---
W (Join-Path $g4 'state.md') ($stateLf -replace '- milestone: 1-one', '- milestone: 3-orders-and-degradation (CP1) — ACCEPT')
$r = Invoke-DesignDoc $g4 @('-WorkDir', $proj4, '-Milestone', 'CP')
$pf = Get-ChildItem (Join-Path $g4 'codex-runs') -Filter 'design-CP.*-1.prompt.md' -ErrorAction SilentlyContinue | Select-Object -First 1
$p = if ($pf) { Get-Text $pf.FullName } else { '' }
Check 'cp-tag-from-state' ($pf -and $pf.Name -match '^design-CP\.3-orders-and-degradation[.A-Za-z0-9_-]*-1\.prompt\.md$' -and $p -match '節目: CP:3-orders-and-degradation \(CP1\) — ACCEPT') "$($pf.Name) / $p"
$r = Invoke-DesignDoc $g4 @('-WorkDir', $proj4, '-Milestone', 'M3')
Check 'bad-milestone-fails' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: FAILED$' -and $r.Out -match '-Milestone') $r.Out

# --- fallback ---
$r = Invoke-DesignDoc $g5 @('-WorkDir', $proj5, '-Milestone', 'A-0', '-Fallback', '-Reason', 'codex TIMEOUT x2')
$d5 = Get-Text $design5
Check 'fallback-create' ($r.Code -eq 0 -and $r.Out -match '(?m)^MODE: fallback$' -and $d5 -match '(?m)^## 1\. 機能の地図' -and $d5 -match '\(未作成: Codex 失敗のため — codex TIMEOUT x2\)' -and $d5 -match '\| g5 \| A-0 \| [0-9a-f]{7,} \| opus\(代行: codex TIMEOUT x2\) \|') $d5
Check 'fallback-logged' ((Get-Text (Join-Path $g5 'call-log.md')) -match 'A-0: FAILED→Opus が代行') 'call-log'
$r = Invoke-DesignDoc $g5 @('-WorkDir', $proj5, '-Milestone', 'A-0')
Check 'fallback-then-not-unchanged' ($r.Out -match '(?m)^LABEL: design-A-0-1$' -and $r.Out -notmatch 'unchanged') 'a fallback row must not count as an up-to-date codex run'
W $design6 $previous
$r = Invoke-DesignDoc $g6 @('-WorkDir', $proj6, '-Milestone', 'CP', '-Fallback', '-Reason', 'x')
Check 'fallback-append-keeps-body' ((Get-Text $design6) -match 'BODY-MARKER' -and (Get-Text $design6) -match '\| g6 \| CP:1-one \| [0-9a-f]{7,} \| opus\(代行: x\) \|') (Get-Text $design6)

# --- size warning ---
New-FinishedRun $g3 'design-A-0-5' ($good + "`n" + ('x' * 41000)) 'A-0'
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-5')
Check 'size-warn' ($r.Out -match '(?m)^WARN: design\.md is \d+ KB' -and $r.Out -match '(?m)^STATUS: OK$') $r.Out

# --- goal dir outside the work dir gets -AddDir (same as scout) ---
$r = Invoke-DesignDoc $gOut @('-WorkDir', $projOut, '-Milestone', 'A-0')
Check 'goal-outside-workdir-adddir' ((Get-Meta $gOut 'design-A-0-1').command -match [regex]::Escape($gOut)) 'AddDir missing'
$b = [IO.File]::ReadAllBytes($designDoc)
Check 'script-has-bom' ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'save design-doc.ps1 as UTF-8 with BOM'

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
