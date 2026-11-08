#Requires -Version 5.1
# Tests for bin/loop-log.ps1: call-log line, state.md fields, resume marker.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $root 'skills\r-super-loop-powers\bin\loop-log.ps1'
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
function Invoke-Log([string]$Goal, [string[]]$Extra) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -GoalDir $Goal @Extra 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
$stateLf = "# state — g1`n- phase: milestone-implementation`n- 強度: MVP`n- milestone: 1-one`n- 次のCheckpoint: 2-two`n- 担当: opus-main`n- 次のゲート: impl-gate`n- 待ち: -`n- skill-dir: C:\skill`n- codex-env: C:\env.json`n- codex-run: -`n- updated: 2026-10-10 10:00`n"

$t = Join-Path ([IO.Path]::GetTempPath()) ('llg-' + [guid]::NewGuid().ToString('N'))
$proj = Join-Path $t 'proj'
$g = Join-Path $proj 'docs\r-super-loop-powers\g1'
W (Join-Path $g 'state.md') $stateLf
W (Join-Path $g 'call-log.md') "# call-log — g1`n`n2026-10-10 09:00 | fable | goal-definition | 既存の行`n"
W (Join-Path $g 'goal-frame.md') "## 制約`n- c`n`n## 承認基準`n1. a`n`n## 終了条件`ne`n"

$r = Invoke-Log $g @('-Who', 'fable', '-Purpose', 'B-6 ゲート判定')
$log = Get-Text (Join-Path $g 'call-log.md')
Check 'log-ok' ($r.Code -eq 0 -and $r.Out -match '(?m)^STATUS: OK' -and $r.Out -match '(?m)^LOGGED: ') $r.Out
Check 'log-line-format' ($log -match '(?m)^\d{4}-\d{2}-\d{2} \d{2}:\d{2} \| fable \| milestone-implementation \| B-6 ゲート判定$') $log
Check 'log-keeps-existing' ($log.StartsWith('# call-log — g1') -and $log.Contains('既存の行')) $log
Check 'log-does-not-touch-state' ((Get-Text (Join-Path $g 'state.md')) -eq $stateLf) 'state.md changed by a log-only call'

$r = Invoke-Log $g @('-Who', 'codex-grareco', '-Purpose', 'x', '-Phase', 'learning')
Check 'log-explicit-phase' ((Get-Text (Join-Path $g 'call-log.md')) -match '(?m)\| codex-grareco \| learning \| x$') $r.Out
$r = Invoke-Log $g @('-Who', 'codex-scout', '-Purpose', 'scout-1: どこで決まるか')
Check 'log-codex-scout' ($r.Code -eq 0 -and (Get-Text (Join-Path $g 'call-log.md')) -match '(?m)\| codex-scout \| milestone-implementation \| scout-1: どこで決まるか$') $r.Out
$r = Invoke-Log $g @('-Who', 'haiku', '-Purpose', 'A-1a 事例調査')
Check 'who-haiku' ($r.Code -eq 0 -and (Get-Text (Join-Path $g 'call-log.md')) -match '(?m)\| haiku \| milestone-implementation \| A-1a 事例調査$') $r.Out
$r = Invoke-Log $g @('-Who', 'codex-surveyor', '-Purpose', 'A-0: create')
Check 'who-codex-surveyor' ($r.Code -eq 0 -and (Get-Text (Join-Path $g 'call-log.md')) -match '\| codex-surveyor \| milestone-implementation \| A-0: create$') $r.Out

# v0.12: the three gated transitions need a design.md history row.
$design = Join-Path $proj 'docs\r-super-loop-powers\design.md'
$row = "| 2026-11-08 10:00 | g1 | {0} | abc1234 | {1} |"
$r = Invoke-Log $g @('-SetOwner', 'hearing-fable')
Check 'owner-hearing-refused-without-design' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED\r?$' -and $r.Out -match "design\.md has no row for 'g1' / 'A-0'" -and $r.Out -match '(?m)^NEXT: .*design-doc\.ps1 .*-Milestone A-0') $r.Out
Check 'refused-writes-nothing' ((Get-Text (Join-Path $g 'state.md')) -notmatch 'hearing-fable') 'state.md changed on REFUSED'
W $design ("# 設計書`n## 更新履歴`n| 日時 | ゴール | 節目 | 見たコミット | 書き手 |`n|---|---|---|---|---|`n" + ($row -f 'CP:0-old', 'codex') + "`n")
$r = Invoke-Log $g @('-SetOwner', 'hearing-fable')
Check 'owner-hearing-refused-wrong-tag' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED\r?$') $r.Out
[IO.File]::WriteAllText($design, ((Get-Text $design) + ($row -f 'A-0', 'codex') + "`n").Replace("`n", "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
$r = Invoke-Log $g @('-SetOwner', 'hearing-fable')
Check 'owner-hearing-ok-crlf-bom' ($r.Code -eq 0 -and (Get-Text (Join-Path $g 'state.md')) -match '(?m)^- 担当: hearing-fable$') $r.Out
W $design ("# 設計書`n## 更新履歴`n" + ($row -f 'A-0', 'opus(代行: codex TIMEOUT x2)') + "`n")
$r = Invoke-Log $g @('-SetOwner', 'opus-main')
$r = Invoke-Log $g @('-SetOwner', 'hearing-fable')
Check 'owner-hearing-ok-fallback-row' ($r.Code -eq 0) $r.Out
# learning -> next / done
W (Join-Path $g 'state.md') ($stateLf -replace '- phase: milestone-implementation', '- phase: learning' -replace '- milestone: 1-one', '- milestone: 3-orders-and-degradation (CP1) — ACCEPT')
W $design ("# 設計書`n## 更新履歴`n" + ($row -f 'A-0', 'codex') + "`n")
$r = Invoke-Log $g @('-SetPhase', 'milestone-implementation', '-SetMilestone', '4-next')
Check 'learning-next-refused' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED\r?$' -and $r.Out -match "/ 'CP:3-orders-and-degradation \(CP1\) — ACCEPT'" -and (Get-Text (Join-Path $g 'state.md')) -match '(?m)^- phase: learning$') $r.Out
$r = Invoke-Log $g @('-SetPhase', 'done')
Check 'learning-done-refused' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED\r?$') $r.Out
W $design ((Get-Text $design) + ($row -f 'CP:3-orders-and-degradation (CP1) — ACCEPT', 'codex') + "`n")
$r = Invoke-Log $g @('-SetPhase', 'milestone-implementation', '-SetMilestone', '4-next')
Check 'learning-next-ok-decorated-milestone' ($r.Code -eq 0 -and (Get-Text (Join-Path $g 'state.md')) -match '(?m)^- milestone: 4-next$') $r.Out
# not gated: goal-definition -> done (closing without doing it), human-acceptance -> milestone-implementation (REJECT)
Remove-Item $design
W (Join-Path $g 'state.md') ($stateLf -replace '- phase: milestone-implementation', '- phase: goal-definition')
$r = Invoke-Log $g @('-SetPhase', 'done', '-SetOwner', 'opus-main')
Check 'goal-definition-done-not-gated' ($r.Code -eq 0) $r.Out
W (Join-Path $g 'state.md') ($stateLf -replace '- phase: milestone-implementation', '- phase: human-acceptance')
$r = Invoke-Log $g @('-SetPhase', 'milestone-implementation')
Check 'reject-return-not-gated' ($r.Code -eq 0) $r.Out
# slug with a regex metacharacter
$gd = Join-Path $proj 'docs\r-super-loop-powers\rb-84.85'
W (Join-Path $gd 'state.md') $stateLf
W $design ("# 設計書`n## 更新履歴`n| 2026-11-08 10:00 | rb-84x85 | A-0 | abc1234 | codex |`n")
$r = Invoke-Log $gd @('-SetOwner', 'hearing-fable')
Check 'slug-with-dot-escaped' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED\r?$') 'rb-84.85 must not match rb-84x85'
W (Join-Path $g 'state.md') $stateLf

W (Join-Path $g 'state.md') ($stateLf -replace '- codex-run: -', '- codex-run: m1-grareco')
$r = Invoke-Log $g @('-SetPhase', 'human-acceptance', '-SetMilestone', '2-two', '-SetWait', '受け入れテストの結果=OK/NG', '-Clear', 'codex-run')
$st = Get-Text (Join-Path $g 'state.md')
Check 'set-ok' ($r.Code -eq 0 -and $r.Out -match '(?m)^STATUS: OK') $r.Out
Check 'set-phase' ($st -match '(?m)^- phase: human-acceptance$') $st
Check 'set-milestone' ($st -match '(?m)^- milestone: 2-two$') $st
Check 'set-wait-with-equals' ($st -match '(?m)^- 待ち: 受け入れテストの結果=OK/NG$') $st
Check 'set-codex-run' ($st -match '(?m)^- codex-run: -$') $st
Check 'set-updated' ($st -match '(?m)^- updated: \d{4}-\d{2}-\d{2} \d{2}:\d{2}$' -and -not $st.Contains('2026-10-10 10:00')) $st
Check 'set-keeps-other-lines' ($st.StartsWith('# state — g1') -and $st.Contains('- skill-dir: C:\skill') -and $st.Contains('- 強度: MVP')) $st
Check 'set-output' ($r.Out -match '(?m)^SET: 4 field\(s\): SetPhase, SetMilestone, SetWait, Clear' -and $r.Out -match '(?m)^UPDATED: ') $r.Out
Check 'stdout-ascii' (($r.Out -replace '[\x00-\x7F]', '') -eq '') 'stdout must stay ASCII (console code pages differ between hosts)'

$r = Invoke-Log $g @('-SetIntensity', '高信頼', '-SetCheckpoint', '3-x', '-SetOwner', 'human', '-SetGate', 'none')
$st = Get-Text (Join-Path $g 'state.md')
Check 'set-japanese-keys' ($st -match '(?m)^- 強度: 高信頼$' -and $st -match '(?m)^- 次のCheckpoint: 3-x$' -and $st -match '(?m)^- 担当: human$' -and $st -match '(?m)^- 次のゲート: none$') $st

$r = Invoke-Log $g @('-Set', 'codex-env=D:\x=y.json')
Check 'generic-set' ((Get-Text (Join-Path $g 'state.md')) -match '(?m)^- codex-env: D:\\x=y\.json$') $r.Out

# -Clear resets several fields to "-" in one call (a lone "-" cannot be passed as a value).
$r = Invoke-Log $g @('-Clear', '待ち,milestone')
$st = Get-Text (Join-Path $g 'state.md')
Check 'clear-fields' ($r.Code -eq 0 -and $st -match '(?m)^- 待ち: -$' -and $st -match '(?m)^- milestone: -$' -and $st -match '(?m)^- 次のCheckpoint: 3-x$') $st
$r = Invoke-Log $g @('-Clear', 'nope')
Check 'clear-unknown-fails' ($r.Code -ne 0 -and $r.Out -match "no field 'nope'") $r.Out

# A decorated value is replaced as a whole.
W (Join-Path $g 'state.md') ($stateLf -replace '- phase: milestone-implementation', '- phase: **実装完了。段 0(人間)待ち**   ')
$r = Invoke-Log $g @('-SetPhase', 'learning')
Check 'set-replaces-decorated-value' ((Get-Text (Join-Path $g 'state.md')) -match '(?m)^- phase: learning$') (Get-Text (Join-Path $g 'state.md'))

# Unknown field: nothing is written.
W (Join-Path $g 'state.md') $stateLf
$r = Invoke-Log $g @('-SetPhase', 'learning', '-Set', 'nope=1')
Check 'unknown-key-fails' ($r.Code -ne 0 -and $r.Out -match "(?m)^STATUS: FAILED" -and $r.Out -match "no field 'nope'") $r.Out
Check 'unknown-key-writes-nothing' ((Get-Text (Join-Path $g 'state.md')) -eq $stateLf) 'state.md was modified'

# CRLF files stay CRLF.
$g2 = Join-Path $proj 'docs\r-super-loop-powers\g2'
W (Join-Path $g2 'state.md') ($stateLf -replace "`n", "`r`n")
W (Join-Path $g2 'call-log.md') "# call-log — g2`r`n`r`n"
$r = Invoke-Log $g2 @('-SetPhase', 'learning', '-Who', 'fable', '-Purpose', 'p')
$st2 = Get-Text (Join-Path $g2 'state.md'); $lg2 = Get-Text (Join-Path $g2 'call-log.md')
Check 'crlf-state-kept' ($st2.Contains("`r`n- phase: learning`r`n") -and (($st2 -replace "`r`n", '') -notmatch "`n")) 'state.md line endings changed'
Check 'crlf-log-kept' ($lg2 -match "\| fable \| milestone-implementation \| p`r`n$") 'call-log line ending'
Check 'log-phase-is-pre-update' ($lg2 -match '\| milestone-implementation \|') $lg2

# Missing call-log.md is created with a heading.
$g4 = Join-Path $proj 'docs\r-super-loop-powers\g4'
W (Join-Path $g4 'state.md') $stateLf
$r = Invoke-Log $g4 @('-Who', 'sonnet-builder', '-Purpose', 'B-2 m1-impl')
$lg4 = Get-Text (Join-Path $g4 'call-log.md')
Check 'log-created' ($lg4.StartsWith("# call-log — g4`n`n") -and $lg4 -match '\| sonnet-builder \| milestone-implementation \| B-2 m1-impl\n$') $lg4

# -Mark builds the packet first, then writes the marker.
$r = Invoke-Log $g @('-SetWait', '承認待ち', '-Mark')
$marker = Join-Path $g 'resume-pending'
Check 'mark-ok' ($r.Code -eq 0 -and $r.Out -match '(?m)^MARKED: ' -and $r.Out -match '(?m)^NEXT: .*clear') $r.Out
Check 'mark-file' ((Test-Path -LiteralPath $marker) -and (Get-Text $marker) -match '(?m)^created: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' -and (Get-Text $marker) -match ('(?m)^cwd: ' + [regex]::Escape($proj) + '\s*$')) (Get-Text $marker)
Check 'mark-packet-built' (Test-Path -LiteralPath (Join-Path $g 'resume-packet.md')) 'resume-packet.md missing'
Check 'mark-state-updated' ((Get-Text (Join-Path $g 'state.md')) -match '(?m)^- 待ち: 承認待ち$') 'state not updated with -Mark'
Check 'mark-reports-inject-chars' ($r.Out -match '(?m)^INJECT_CHARS: \d+' -and $r.Out -notmatch '(?m)^WARN:') $r.Out

# -Mark relays the packet builder's WARN when the pinned sections alone exceed the cap.
$g5 = Join-Path $proj 'docs\r-super-loop-powers\g5'
W (Join-Path $g5 'state.md') $stateLf
W (Join-Path $g5 'goal-frame.md') ("## 制約`n" + ('制' * 12000) + "`n`n## 承認基準`n1. a`n`n## 終了条件`ne`n")
$r = Invoke-Log $g5 @('-Mark')
Check 'mark-relays-warn' ($r.Code -eq 0 -and $r.Out -match '(?m)^WARN: packet exceeds' -and $r.Out -match '(?m)^MARKED: ') $r.Out

$g3 = Join-Path $proj 'docs\r-super-loop-powers\g3'
New-Item -ItemType Directory -Path $g3 -Force | Out-Null
$r = Invoke-Log $g3 @('-Mark')
Check 'mark-without-state-fails' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: FAILED' -and -not (Test-Path -LiteralPath (Join-Path $g3 'resume-pending'))) $r.Out

$r = Invoke-Log $g @()
Check 'nothing-to-do-fails' ($r.Code -ne 0 -and $r.Out -match 'nothing to do') $r.Out
$r = Invoke-Log $g @('-Who', 'fable')
Check 'who-needs-purpose' ($r.Code -ne 0 -and $r.Out -match 'needs -Purpose') $r.Out
$r = Invoke-Log $g @('-Who', 'opus', '-Purpose', 'p')
Check 'unknown-who-fails' ($r.Code -ne 0 -and $r.Out -match 'unknown -Who') $r.Out
$r = Invoke-Log (Join-Path $t 'nope') @('-Mark')
Check 'missing-goaldir-fails' ($r.Code -ne 0) $r.Out

$b = [IO.File]::ReadAllBytes($script)
Check 'script-has-bom' ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'save loop-log.ps1 as UTF-8 with BOM'

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
