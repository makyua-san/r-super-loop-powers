#Requires -Version 5.1
# Tests for bin/parallel.ps1: -Prepare (checks, worktrees, ledger, state.md), -Status, -Pass, -Halt, -Merge and -Cleanup.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $root 'skills\r-super-loop-powers\bin\parallel.ps1'
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
function Invoke-Par([string]$Goal, [string[]]$Extra) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -GoalDir $Goal @Extra 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
# 一時ディレクトリに「ゴール g1 をコミット済みのリポジトリ」を作り、ベースのパスを返す。
function New-Repo([string]$Dir, [string]$StateText) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    git -C $Dir init -q -b main 2>$null
    git -C $Dir config user.email t@example.com; git -C $Dir config user.name t
    git -C $Dir config core.autocrlf false
    $g = Join-Path $Dir 'docs\r-super-loop-powers\g1'
    W (Join-Path $g 'state.md') $StateText
    W (Join-Path $g 'call-log.md') "# call-log — g1`n`n"
    W (Join-Path $g 'hook-log.md') "2026-11-16 09:00 | PASS | ja-ratio=0.9 |  | m=-`n"
    W (Join-Path $g 'assumptions.md') "| ID | 仮定 | 状態 |`n|---|---|---|`n"
    W (Join-Path $g 'goal-frame.md') "## 制約`n- c`n`n## 承認基準`n1. a`n`n## 終了条件`ne`n"
    W (Join-Path $Dir 'app.txt') "a`n"
    git -C $Dir add -A 2>$null; git -C $Dir commit -q -m init 2>$null
    return $Dir
}
# state.md and info/attributes as they are before a -Prepare call ($null = absent).
function Get-Snapshot([string]$Base) {
    $common = (git -C $Base rev-parse --path-format=absolute --git-common-dir).Trim()
    $snap = @{ State = $null; Attr = $null }
    $sf = Join-Path $Base 'docs\r-super-loop-powers\g1\state.md'
    $af = Join-Path $common 'info\attributes'
    if (Test-Path -LiteralPath $sf) { $snap.State = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sf)) }
    if (Test-Path -LiteralPath $af) { $snap.Attr = [Convert]::ToBase64String([IO.File]::ReadAllBytes($af)) }
    return $snap
}
# '' when a refused / failed -Prepare left nothing behind; otherwise what it left.
function Assert-Nothing([string]$Base, $Before) {
    $bad = @()
    $wt = @(git -C $Base worktree list 2>$null)
    if ($wt.Count -ne 1) { $bad += "worktrees: $($wt -join '; ')" }
    $br = @(git -C $Base branch --list 'rslp/*' 2>$null)
    if ($br.Count -ne 0) { $bad += "branches: $($br -join '; ')" }
    $common = (git -C $Base rev-parse --path-format=absolute --git-common-dir).Trim()
    if (Test-Path -LiteralPath (Join-Path $common 'rslp-parallel\g1')) { $bad += 'ledger dir exists' }
    $now = Get-Snapshot $Base
    if ($now.State -ne $Before.State) { $bad += 'state.md changed' }
    if ($now.Attr -ne $Before.Attr) { $bad += 'info/attributes changed' }
    $rslp = Join-Path (Split-Path -Parent $Base) ((Split-Path -Leaf $Base) + '.rslp')
    if (Test-Path -LiteralPath $rslp) { $bad += "worktree folder exists: $rslp" }
    return ($bad -join "`n")
}

$t = Join-Path ([IO.Path]::GetTempPath()) ('par-' + [guid]::NewGuid().ToString('N'))
$stateLf = "# state — g1`n- phase: goal-definition`n- 強度: MVP`n- milestone: -`n- 次のCheckpoint: 2-two`n- 担当: opus-main`n- 次のゲート: goal-gate`n- 待ち: -`n- skill-dir: C:\skill`n- codex-env: C:\env.json`n- codex-run: -`n- updated: 2026-11-16 10:00`n"

# --- happy path (base path with a space) ---
$base = New-Repo (Join-Path $t 'my app') $stateLf
$g = Join-Path $base 'docs\r-super-loop-powers\g1'
$r = Invoke-Par $g @('-Status')
Check 'status-none' ($r.Code -eq 0 -and (Get-Kv $r.Out 'GROUP') -eq 'none') $r.Out
$r = Invoke-Par $g @('-Prepare', '-Milestones', '1-one,2-two')
$w1 = Join-Path $t 'my app.rslp\g1-m1'; $w2 = Join-Path $t 'my app.rslp\g1-m2'
$c1 = Join-Path $w1 'docs\r-super-loop-powers\g1'
Check 'prepare-path-with-space' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'OK' -and (Test-Path -LiteralPath $c1) -and (Test-Path -LiteralPath (Join-Path $w2 'app.txt'))) $r.Out
$s1 = Get-Text (Join-Path $c1 'state.md')
Check 'prepare-child-state' ($s1 -match '(?m)^- phase: milestone-implementation$' -and $s1 -match '(?m)^- milestone: 1-one$' -and $s1 -match '(?m)^- 次のゲート: impl-gate$' -and $s1.Contains("- parallel-base: $base`n- updated:")) $s1
$sb = Get-Text (Join-Path $g 'state.md')
Check 'prepare-base-state' ($sb -match '(?m)^- phase: parallel$' -and $sb -match '(?m)^- milestone: 1-one \+ 2-two$' -and $sb -match '(?m)^- 待ち: 並行中: 1-one / 2-two') $sb
$mk = Get-Text (Join-Path $c1 'resume-pending')
Check 'prepare-child-marker-cwd' ($mk -match ('(?m)^cwd: ' + [regex]::Escape($w1) + '$')) $mk
$common = (git -C $base rev-parse --path-format=absolute --git-common-dir).Trim()
$led = Join-Path $common 'rslp-parallel\g1'
Check 'prepare-ledger' ((Test-Path (Join-Path $led 'group.json')) -and ((Get-Text (Join-Path $led 'm1.json')) | ConvertFrom-Json).status -eq 'running' -and -not (Test-Path (Join-Path $led 'merger'))) (Get-ChildItem $led -ErrorAction SilentlyContinue | Out-String)
$attr = Get-Text (Join-Path $common 'info\attributes')
Check 'prepare-attributes' ($attr.Contains('docs/r-super-loop-powers/*/call-log.md merge=union') -and $attr.Contains('docs/r-super-loop-powers/*/hook-log.md merge=union') -and $attr.Contains('docs/r-super-loop-powers/*/assumptions.md merge=union') -and $attr.Contains('docs/r-super-loop-powers/*/scout/index.md merge=union')) $attr
Check 'prepare-branches' ((git -C $base branch --list 'rslp/g1/*' | Measure-Object).Count -eq 2) (git -C $base branch | Out-String)
$r = Invoke-Par $c1 @('-Status')
Check 'status-child' ((Get-Kv $r.Out 'ROLE') -eq 'child' -and (Get-Kv $r.Out 'SELF') -eq 'm1' -and $r.Out -match '(?m)^CHILD: m2 \| running \| - \| ' -and (Get-Kv $r.Out 'HALTED') -eq 'no') $r.Out
$r = Invoke-Par $g @('-Status')
Check 'status-base' ((Get-Kv $r.Out 'ROLE') -eq 'base' -and (Get-Kv $r.Out 'GROUP') -eq '1-one + 2-two') $r.Out
$r = Invoke-Par $g @('-Prepare', '-Milestones', '1-one,2-two')
Check 'prepare-twice-refused' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out

# --- refusals: a fresh repo each, and nothing may be left behind ---
function Test-Refused([string]$Name, [string]$Dir, [string]$Milestones, [string]$ReasonPart) {
    $before = Get-Snapshot $Dir
    $r = Invoke-Par (Join-Path $Dir 'docs\r-super-loop-powers\g1') @('-Prepare', '-Milestones', $Milestones)
    $left = Assert-Nothing $Dir $before
    $ok = ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED' -and $left -eq '')
    if ($ReasonPart) { $ok = $ok -and (Get-Kv $r.Out 'REASON').Contains($ReasonPart) }
    Check $Name $ok ($r.Out + $left)
}
$d = New-Repo (Join-Path $t 'r-three') $stateLf
Test-Refused 'prepare-refused-three' $d '1-a,2-b,3-c' ''
$d = New-Repo (Join-Path $t 'r-same') $stateLf
Test-Refused 'prepare-refused-same-number' $d '1-a,1-b' ''
$d = New-Repo (Join-Path $t 'r-high') ($stateLf.Replace('- 強度: MVP', '- 強度: 高信頼'))
Test-Refused 'prepare-refused-high' $d '1-a,2-b' ''
$d = New-Repo (Join-Path $t 'r-detached') $stateLf
git -C $d checkout -q --detach 2>$null
Test-Refused 'prepare-refused-detached' $d '1-a,2-b' 'detached'
$d = New-Repo (Join-Path $t 'r-dirty') $stateLf
W (Join-Path $d 'app.txt') "changed`n"
Test-Refused 'prepare-refused-dirty' $d '1-a,2-b' 'app.txt'
$d = New-Repo (Join-Path $t 'r-untracked') $stateLf
W (Join-Path $d 'docs\r-super-loop-powers\g1\goal-plan.md') "# plan`n"
Test-Refused 'prepare-refused-untracked-goal-file' $d '1-a,2-b' 'goal-plan.md'
$d = New-Repo (Join-Path $t 'r-learning') ($stateLf.Replace('- phase: goal-definition', '- phase: learning').Replace('- milestone: -', '- milestone: 0-zero'))
Test-Refused 'prepare-learning-refused-without-design-row' $d '1-a,2-b' 'design.md'

$d = New-Repo (Join-Path $t 'ok-resume') $stateLf
W (Join-Path $d 'docs\r-super-loop-powers\g1\resume-packet.md') "# packet`n"
$r = Invoke-Par (Join-Path $d 'docs\r-super-loop-powers\g1') @('-Prepare', '-Milestones', '1-a,2-b')
Check 'prepare-allows-resume-files' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'OK') $r.Out

$d = New-Repo (Join-Path $t 'ok-crlf') $stateLf
[IO.File]::WriteAllText((Join-Path $d 'docs\r-super-loop-powers\g1\state.md'), $stateLf.Replace("`n", "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
git -C $d add -A 2>$null; git -C $d commit -q --amend --no-edit 2>$null
$r = Invoke-Par (Join-Path $d 'docs\r-super-loop-powers\g1') @('-Prepare', '-Milestones', '1-a,2-b')
$sc = Get-Text (Join-Path $t 'ok-crlf.rslp\g1-m1\docs\r-super-loop-powers\g1\state.md')
Check 'prepare-crlf-state' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'OK' -and $sc.Contains("`r`n- parallel-base: ") -and -not ($sc -match '(?<!\r)\n')) ($r.Out + $sc)

# Paths on stdout keep their non-ASCII characters (the orchestrator hands them to the human).
$d = New-Repo (Join-Path $t '作業 app') $stateLf
$r = Invoke-Par (Join-Path $d 'docs\r-super-loop-powers\g1') @('-Prepare', '-Milestones', '1-a,2-b')
$wj = Join-Path $t '作業 app.rslp\g1-m1'
$mkj = Get-Text (Join-Path $wj 'docs\r-super-loop-powers\g1\resume-pending')
Check 'prepare-nonascii-path' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'OK' -and $r.Out -match ('(?m)^WORKTREE: m1 \| ' + [regex]::Escape($wj) + '\r?$') -and $mkj -match ('(?m)^cwd: ' + [regex]::Escape($wj) + '$')) ($r.Out + $mkj)

# Late failure: the base has an uncommitted design.md row, so the base passes the gate and
# the children (committed copy, no design.md) are refused -> everything is rolled back.
$d = New-Repo (Join-Path $t 'rb-design') ($stateLf.Replace('- phase: goal-definition', '- phase: learning').Replace('- milestone: -', '- milestone: 0-zero'))
W (Join-Path $d 'docs\r-super-loop-powers\design.md') "| 2026-11-16 | g1 | CP:0-zero | x |`n"
$before = Get-Snapshot $d
$r = Invoke-Par (Join-Path $d 'docs\r-super-loop-powers\g1') @('-Prepare', '-Milestones', '1-a,2-b')
$left = Assert-Nothing $d $before
Check 'prepare-rollback-on-child-refusal' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED' -and (Get-Kv $r.Out 'ROLLED_BACK') -eq 'yes' -and $left -eq '') ($r.Out + $left)

# --- -Pass / -Halt ---
# 準備済みのリポジトリを新しく作る。@{ Base; G; W1; W2; C1; C2; Led } を返す。
function New-Prepared([string]$Name) {
    $pb = New-Repo (Join-Path $t $Name) $stateLf
    $pg = Join-Path $pb 'docs\r-super-loop-powers\g1'
    $null = Invoke-Par $pg @('-Prepare', '-Milestones', '1-one,2-two')
    $pw1 = Join-Path $t "$Name.rslp\g1-m1"; $pw2 = Join-Path $t "$Name.rslp\g1-m2"
    $pc = (git -C $pb rev-parse --path-format=absolute --git-common-dir).Trim()
    return @{ Base = $pb; G = $pg; W1 = $pw1; W2 = $pw2
        C1 = (Join-Path $pw1 'docs\r-super-loop-powers\g1'); C2 = (Join-Path $pw2 'docs\r-super-loop-powers\g1')
        Led = (Join-Path $pc 'rslp-parallel\g1') }
}
# 子の作業ツリーで「実装 1 ファイル + PASS の判定 + ログ 1 行ずつ」を作る。
function Add-Work($P, [int]$N, [string]$File, [string]$Body) {
    $w = @($P.W1, $P.W2)[$N - 1]; $c = @($P.C1, $P.C2)[$N - 1]; $name = @('1-one', '2-two')[$N - 1]
    W (Join-Path $w $File) $Body
    W (Join-Path $c "milestones\$name\gate-decision.md") "PASS`n根拠`n"
    [IO.File]::AppendAllText((Join-Path $c 'call-log.md'), "2026-11-16 11:00 | fable | milestone-implementation | B-6 gate [m$N]`n", $utf8)
    [IO.File]::AppendAllText((Join-Path $c 'hook-log.md'), "2026-11-16 11:00 | PASS | ja-ratio=0.9 |  | m=$N`n", $utf8)
}
$fast = @('-ElectTries', '2', '-ElectWaitMs', '50')

$p = New-Prepared 'pass'
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-refused-without-gate-decision' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED' -and ((Get-Text (Join-Path $p.Led 'm1.json')) | ConvertFrom-Json).status -eq 'running') $r.Out
Add-Work $p 1 'f1.txt' "one`n"
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
$row1 = (Get-Text (Join-Path $p.Led 'm1.json')) | ConvertFrom-Json
$head1 = (git -C $p.W1 rev-parse HEAD).Trim()
Check 'pass-first-waits' ($r.Code -eq 0 -and (Get-Kv $r.Out 'ROLE') -eq 'wait' -and $row1.status -eq 'passed' -and $row1.sha -eq $head1 -and (Get-Kv $r.Out 'SHA') -eq $head1 -and -not (Test-Path (Join-Path $p.Led 'merger'))) $r.Out
$names = (git -C $p.W1 show --name-only --format= HEAD | Out-String)
Check 'pass-commit-contents' ($names -match 'f1\.txt' -and $names -match 'gate-decision\.md' -and $names -match 'call-log\.md' -and $names -notmatch 'state\.md' -and $names -notmatch 'resume-') $names
Check 'pass-leaves-state-uncommitted' ((git -C $p.W1 status --porcelain | Out-String) -match 'state\.md') (git -C $p.W1 status --porcelain | Out-String)
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-rerun-idempotent' ((Get-Kv $r.Out 'ROLE') -eq 'wait' -and (git -C $p.W1 rev-parse HEAD).Trim() -eq $head1 -and ((Get-Text (Join-Path $p.Led 'm1.json')) | ConvertFrom-Json).passed -eq $row1.passed) $r.Out
Add-Work $p 2 'f2.txt' "two`n"
$r = Invoke-Par $p.C2 (@('-Pass') + $fast)
Check 'pass-last-is-merger' ((Get-Kv $r.Out 'ROLE') -eq 'merger' -and (Get-Text (Join-Path $p.Led 'merger')).Trim() -eq '2' -and $r.Out -match '(?m)^NEXT: .*-Merge') $r.Out
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-sibling-holds-merger' ((Get-Kv $r.Out 'ROLE') -eq 'wait' -and (Get-Text (Join-Path $p.Led 'merger')).Trim() -eq '2') $r.Out
$r = Invoke-Par $p.C2 (@('-Pass') + $fast)
Check 'pass-own-stale-merger' ((Get-Kv $r.Out 'ROLE') -eq 'merger') $r.Out
$r = Invoke-Par $p.G (@('-Pass') + $fast)
Check 'pass-refused-from-base' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out

# A failing pre-commit hook: FAILED with git's words, the row stays running.
$p = New-Prepared 'hook'
$common = (git -C $p.Base rev-parse --path-format=absolute --git-common-dir).Trim()
W (Join-Path $common 'hooks\pre-commit') "#!/bin/sh`necho blocked-by-hook >&2`nexit 1`n"
Add-Work $p 1 'f1.txt' "one`n"
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-commit-hook-fails' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED' -and $r.Out -match 'blocked-by-hook' -and ((Get-Text (Join-Path $p.Led 'm1.json')) | ConvertFrom-Json).status -eq 'running') $r.Out

$p = New-Prepared 'halt'
$r = Invoke-Par $p.C1 @('-Halt')
Check 'halt-needs-reason' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED') $r.Out
$r = Invoke-Par $p.C1 @('-Halt', '-Reason', 'sibling definition changes')
$h = (Get-Text (Join-Path $p.Led 'halt.json')) | ConvertFrom-Json
Check 'halt-written' ($r.Code -eq 0 -and $h.by -eq '1' -and $h.keep -eq '1' -and $h.reason -eq 'sibling definition changes' -and (Get-Kv $r.Out 'KEEP') -eq 'm1') $r.Out
$r = Invoke-Par $p.C2 @('-Halt', '-Reason', 'late')
Check 'halt-first-wins' (((Get-Text (Join-Path $p.Led 'halt.json')) | ConvertFrom-Json).by -eq '1') $r.Out
$r = Invoke-Par $p.C2 @('-Status')
Check 'status-shows-halt' ($r.Out -match '(?m)^HALTED: yes \| keep=m1 \| sibling definition changes') $r.Out
Add-Work $p 2 'f2.txt' "two`n"
$before = (git -C $p.W2 rev-parse HEAD).Trim()
$r = Invoke-Par $p.C2 (@('-Pass') + $fast)
Check 'pass-halted-sibling-stops' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'HALTED' -and (git -C $p.W2 rev-parse HEAD).Trim() -eq $before) $r.Out
Add-Work $p 1 'f1.txt' "one`n"
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-halter-is-merger' ((Get-Kv $r.Out 'ROLE') -eq 'merger' -and (Get-Text (Join-Path $p.Led 'merger')).Trim() -eq '1') $r.Out

# --- -Merge / -Cleanup ---
# 両方 PASS・m2 が合流担当、まで進めた状態を返す。
function New-Passed([string]$Name, [string]$File1 = 'f1.txt', [string]$File2 = 'f2.txt') {
    $np = New-Prepared $Name
    Add-Work $np 1 $File1 "one`n"
    Add-Work $np 2 $File2 "two`n"
    $null = Invoke-Par $np.C1 (@('-Pass') + $fast)
    $null = Invoke-Par $np.C2 (@('-Pass') + $fast)
    return $np
}

$p = New-Passed 'merge'
$r = Invoke-Par $p.C1 @('-Merge')
Check 'merge-refused-non-merger' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out
[IO.File]::AppendAllText((Join-Path $p.G 'hook-log.md'), "2026-11-16 10:06 | PASS | ja-ratio=0.9 |  | m=1`n", $utf8)   # 準備したセッションの Stop フックの行
W (Join-Path $p.Base 'app.txt') "dirty`n"
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-refused-dirty-base' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED' -and $r.Out -match 'app\.txt') $r.Out
git -C $p.Base checkout -q -- app.txt
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-ok' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'OK' -and (Test-Path (Join-Path $p.Base 'f1.txt')) -and (Test-Path (Join-Path $p.Base 'f2.txt')) -and $r.Out -match '(?m)^MERGED: m1 \| [0-9a-f]{7}' -and $r.Out -match '(?m)^MERGED: m2 \| ' -and $r.Out -match '(?m)^WALL_MINUTES: \d+' -and $r.Out -match '(?m)^SERIAL_MINUTES: \d+') $r.Out
$cl = Get-Text (Join-Path $p.G 'call-log.md'); $hl = Get-Text (Join-Path $p.G 'hook-log.md')
Check 'merge-union-keeps-both' ($cl -match 'B-6 gate \[m1\]' -and $cl -match 'B-6 gate \[m2\]' -and $hl -match '(?m)\| m=1$' -and $hl -match '(?m)\| m=2$' -and $hl -match '10:06' -and $cl -notmatch '<<<<<<<') ($cl + $hl)
Check 'merge-base-state-untouched' ((Get-Text (Join-Path $p.G 'state.md')) -match '(?m)^- phase: parallel$') (Get-Text (Join-Path $p.G 'state.md'))
$pl = Get-Text (Join-Path $p.G 'parallel-log.md')
Check 'merge-writes-parallel-log' ($pl.StartsWith('# parallel-log — g1') -and $pl -match '(?m)^## \d{4}-\d{2}-\d{2} \d{2}:\d{2} 1-one \+ 2-two$' -and $pl -match '壁時計 \d+ 分 / 直列換算 \d+ 分' -and $pl -match '(?m)^- 中止: なし$' -and $pl -match '(?m)^\| 1-one \| merged \| ' -and $pl -match '(?m)^\| 2-two \| merged \| ') $pl
$headB = (git -C $p.Base rev-parse HEAD).Trim()
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-rerun-noop' ($r.Code -eq 0 -and (git -C $p.Base rev-parse HEAD).Trim() -eq $headB -and ([regex]::Matches((Get-Text (Join-Path $p.G 'parallel-log.md')), '(?m)^## ')).Count -eq 1) $r.Out
$r = Invoke-Par $p.C2 @('-Cleanup')
Check 'cleanup-refused-from-child' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out
$r = Invoke-Par $p.G @('-Cleanup')
Check 'cleanup-ok' ($r.Code -eq 0 -and -not (Test-Path $p.W1) -and -not (Test-Path $p.W2) -and -not (Test-Path $p.Led) -and -not (git -C $p.Base branch --list 'rslp/g1/*') -and (Test-Path (Join-Path $p.G 'parallel-log.md'))) $r.Out
$r = Invoke-Par $p.G @('-Status')
Check 'status-none-after-cleanup' ((Get-Kv $r.Out 'GROUP') -eq 'none') $r.Out

# 衝突(同じ実装ファイルを両方が書く)と、その後の中止。
$p = New-Passed 'conflict' 'same.txt' 'same.txt'      # Add-Work の本文は m1 と m2 で違う
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-conflict' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'CONFLICT' -and $r.Out -match '(?m)^CONFLICT_FILE: same\.txt' -and $r.Out -match '(?m)^UNMERGED: m2' -and $r.Out -match '(?m)^MERGED: m1 \| ') $r.Out
$gj = (Get-Text (Join-Path $p.Led 'group.json')) | ConvertFrom-Json
Check 'merge-conflict-recorded' (-not $gj.merged -and @($gj.redo).Count -eq 0 -and @($gj.conflicts).Count -eq 1 -and [string]@($gj.conflicts)[0].n -eq '2' -and @(@($gj.conflicts)[0].files) -contains 'same.txt') (Get-Text (Join-Path $p.Led 'group.json'))
Check 'merge-conflict-next-names-keep' ((Get-Kv $r.Out 'NEXT') -match '-Halt .*-Keep 1\b' -and (Get-Kv $r.Out 'NEXT') -match 'same\.txt') $r.Out
$r = Invoke-Par $p.C2 @('-Merge')
$gj = (Get-Text (Join-Path $p.Led 'group.json')) | ConvertFrom-Json
Check 'merge-conflict-rerun-no-duplicate' ((Get-Kv $r.Out 'STATUS') -eq 'CONFLICT' -and @($gj.conflicts).Count -eq 1) (Get-Text (Join-Path $p.Led 'group.json'))
Check 'merge-conflict-aborted' (-not (git -C $p.Base rev-parse -q --verify MERGE_HEAD 2>$null) -and (Get-Text (Join-Path $p.Base 'same.txt')) -notmatch '<<<<<<<') (git -C $p.Base status | Out-String)
$r = Invoke-Par $p.G @('-Cleanup')
Check 'cleanup-refused-before-merge' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out
$r = Invoke-Par $p.C2 @('-Halt', '-Keep', '2', '-Reason', 'x')
Check 'halt-refused-keep-unmerged-after-partial-merge' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED' -and (Get-Kv $r.Out 'NEXT') -match '-Keep 1\b' -and -not (Test-Path (Join-Path $p.Led 'halt.json'))) $r.Out
$r = Invoke-Par $p.C2 @('-Halt', '-Keep', '1', '-Reason', 'merge conflict: same.txt')
$r = Invoke-Par $p.C2 @('-Merge')
$pl = Get-Text (Join-Path $p.G 'parallel-log.md')
Check 'merge-after-halt-keep' ($r.Code -eq 0 -and $r.Out -match '(?m)^REDO: m2' -and $pl -match '(?m)^- 中止: m1 を残して中止\(merge conflict: same\.txt\)$' -and $pl -match '(?m)^- 合流の衝突: m2: same\.txt$' -and $pl -match '(?m)^\| 2-two \| redo \| ') ($r.Out + $pl)
$r = Invoke-Par $p.G @('-Cleanup')
Check 'cleanup-keeps-redo' ($r.Code -eq 0 -and -not (Test-Path $p.W1) -and (Test-Path $p.W2) -and $r.Out -match '(?m)^KEPT_BRANCH: rslp/g1/m2' -and $r.Out -match '(?m)^KEPT_WORKTREE: ' -and -not (Test-Path $p.Led)) $r.Out

# 最初のマージが衝突する(分割の後にベースが同じファイルを足した): -Halt は勧めない。
$p = New-Passed 'first' 'same.txt' 'f2.txt'
W (Join-Path $p.Base 'same.txt') "base`n"
git -C $p.Base add -- same.txt 2>$null; git -C $p.Base commit -q -m 'base adds same.txt' 2>$null
$headF = (git -C $p.Base rev-parse HEAD).Trim()
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-first-conflict-next-reports' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'CONFLICT' -and $r.Out -match '(?m)^UNMERGED: m1' -and (Get-Kv $r.Out 'NEXT') -notmatch '-Halt' -and $r.Out -notmatch '(?m)^MERGED: ' -and -not (git -C $p.Base rev-parse -q --verify MERGE_HEAD 2>$null) -and (git -C $p.Base log --merges --oneline "$headF..HEAD" | Measure-Object).Count -eq 0) $r.Out

# 中止した側だけの合流。
$p = New-Prepared 'solo'
Invoke-Par $p.C1 @('-Halt', '-Reason', 'coupled') | Out-Null
Add-Work $p 1 'f1.txt' "one`n"
Invoke-Par $p.C1 (@('-Pass') + $fast) | Out-Null
$r = Invoke-Par $p.C1 @('-Merge')
Check 'merge-solo-after-halt' ($r.Code -eq 0 -and (Test-Path (Join-Path $p.Base 'f1.txt')) -and $r.Out -match '(?m)^REDO: m2' -and $r.Out -notmatch '(?m)^MERGED: m2') $r.Out

# ベースが別のブランチに居る。
$p = New-Passed 'branch'
git -C $p.Base checkout -q -b other
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-refused-wrong-branch' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED' -and $r.Out -match 'main') $r.Out

$b = [IO.File]::ReadAllBytes($script)
Check 'script-has-bom' ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'save parallel.ps1 as UTF-8 with BOM'

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
