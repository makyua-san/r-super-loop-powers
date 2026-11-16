#Requires -Version 5.1
# Tests for bin/parallel.ps1: -Prepare (checks, worktrees, ledger, state.md) and -Status.
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

$b = [IO.File]::ReadAllBytes($script)
Check 'script-has-bom' ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'save parallel.ps1 as UTF-8 with BOM'

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
