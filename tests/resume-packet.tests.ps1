#Requires -Version 5.1
# Tests for bin/resume-packet.ps1 on synthetic goal directories.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $root 'skills\r-super-loop-powers\bin\resume-packet.ps1'
$policy = Join-Path $root 'skills\r-super-loop-powers\policy.md'
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
function Get-Text([string]$Path) { return [IO.File]::ReadAllText($Path, $utf8) }
function Invoke-Packet([string]$Goal, [string[]]$Extra) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -GoalDir $Goal @Extra 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

$t = Join-Path ([IO.Path]::GetTempPath()) ('rpk-' + [guid]::NewGuid().ToString('N'))
$loop = Join-Path $t 'proj\docs\r-super-loop-powers'
$g = Join-Path $loop 'g1'
W (Join-Path $g 'state.md') "# state — g1`n- phase: milestone-implementation`n- 強度: MVP`n- milestone: 2-two`n- 次のCheckpoint: 2-two`n- 担当: opus-main`n- 次のゲート: impl-gate`n- 待ち: 人間の受け入れテスト結果`n- skill-dir: C:\skill`n- codex-env: C:\env.json`n- codex-run: m2-grareco`n- updated: 2026-10-10 10:00`n"
W (Join-Path $g 'goal-frame.md') "# Goal Frame — g1`n`n## ゴールの方向`n方向。`n`n## 制約`n- 制約A`n- 制約B`n`n## 承認基準`n1. 基準1`n2. 基準2`n`n## 終了条件(残存未知の許容基準)`n条件X`n`n## 参照した学習メモ`nなし`n"
W (Join-Path $g 'goal-plan.md') "# Goal Plan — g1`n`n- Spec: x`n`n## マイルストーン`n`n| # | 名前 | Checkpoint |`n|---|---|---|`n| 1 | 1-one | - |`n| 2 | 2-two | ✓ |`n`n## 主要設計判断`n判断。`n"
W (Join-Path $g 'assumptions.md') "# Assumptions`n`n| ID | 仮定内容 | 確信度 | 根拠 | ゴールへの寄与 | 検証方法 | 状態 |`n|---|---|---|---|---|---|---|`n| A1 | 仮定1 | 高 | 根拠 | 寄与 | 方法 | 検証済み |`n| A2 | 仮定2 | 中 | 根拠 | 寄与 | 方法 | 未検証 |`n| A3 | 仮定3 | 低 | 根拠 | 寄与 | 方法 | 未検証(条件付き) |`n| A4 | 仮定4 | 低 | 根拠 | 寄与 | 方法 | 棄却 |`n"
W (Join-Path $g 'goal-gate-decision.md') "# Goal Gate Decision`n`nPASS`n- 古い判定`n"
Start-Sleep -Milliseconds 60
W (Join-Path $g 'milestones\1-one\gate-decision.md') "# Gate Decision — 1-one`n`nPASS`n1. 根拠1`n"
Start-Sleep -Milliseconds 60
W (Join-Path $g 'milestones\2-two\gate-decision-2.md') "# Gate Decision — 2-two (2)`n`nREVISE`n1. 最新の根拠`n2. 根拠2`n"
W (Join-Path $g 'milestones\2-two\escalation-1.md') "# Escalation`n`n1. **何をしようとしたか**: x`n7. **Fableの判定**: DECIDE: 進める`n"
W (Join-Path $loop 'g0\milestones\9-old\retro.md') "# Retrospective — g0`n`n## うまく機能したこと(最大3点)`n- 良かった`n`n## 次回変えること(最大3点)`n- 古い教訓`n`n## 発見された未知`n- なし`n"
Start-Sleep -Milliseconds 60
W (Join-Path $g 'milestones\1-one\retro.md') "# Retrospective — g1`n`n## うまく機能したこと(最大3点)`n- 良かった`n`n## 次回変えること(最大3点)`n- 教訓1`n- 教訓2`n`n## 発見された未知`n- 未知1`n"
W (Join-Path $g 'impl-runs\m1-impl.prompt.md') 'p'
W (Join-Path $g 'impl-runs\m1-impl.report.md') 'r'
W (Join-Path $g 'impl-runs\m2-impl.prompt.md') 'p'
W (Join-Path $g 'codex-runs\techpm-assessment.prompt.md') 'p'
W (Join-Path $g 'codex-runs\techpm-assessment.exit') '0'
W (Join-Path $g 'codex-runs\m2-grareco.prompt.md') 'p'

$inject = Join-Path $t 'inject.md'
$r = Invoke-Packet $g @('-OutFile', $inject, '-PolicyFile', $policy)
Check 'runs' ($r.Code -eq 0 -and $r.Out -match '(?m)^PACKET: ') $r.Out
$full = Get-Text (Join-Path $g 'resume-packet.md')
$inj = Get-Text $inject
Check 'full-and-inject-same-when-small' ($full -eq $inj) 'full and inject differ'
Check 'title' ($full.StartsWith('# 再開パケット — g1')) $full.Substring(0, [Math]::Min(80, $full.Length))
# Pinned sections (1-5) come first so that a hard cut by the host can only reach the cuttable ones.
$heads = @('## 1. state.md', '## 2. 待ち', '## 3. 仮説自律の否定リスト', '## 4. 制約', '## 5. 未完了の委譲', '## 6. 対象マイルストーン', '## 7. 未検証の仮定', '## 8. 直近の判定', '## 9. 直近 retro')
$idx = @(); foreach ($h in $heads) { $idx += $full.IndexOf($h) }
$ordered = $true
for ($i = 0; $i -lt $idx.Count; $i++) { if ($idx[$i] -lt 0 -or ($i -gt 0 -and $idx[$i] -lt $idx[$i - 1])) { $ordered = $false } }
Check 'section-order' $ordered ($idx -join ',')
Check 'state-full' ($full.Contains("- phase: milestone-implementation`n- 強度: MVP") -and $full.Contains('- updated: 2026-10-10 10:00')) 'state.md body missing'
Check 'skill-dir-in-header' ($full.Contains('- skill-dir: C:\skill')) 'skill-dir'
Check 'wait' ($full -match '(?m)^## 2\. 待ち\s*\n\s*\n人間の受け入れテスト結果') 'wait missing'
$policyText = (Get-Text $policy) -replace "`r`n", "`n"
$negStart = $policyText.IndexOf('## 仮説自律の否定リスト')
$negEnd = $policyText.IndexOf("`n## ", $negStart + 1)
$neg = $policyText.Substring($negStart, $negEnd - $negStart).TrimEnd()
Check 'negative-list-verbatim' ($negStart -ge 0 -and $full.Contains($neg)) 'policy section not verbatim'
Check 'frame-verbatim' ($full.Contains("## 制約`n- 制約A`n- 制約B") -and $full.Contains("## 承認基準`n1. 基準1`n2. 基準2") -and $full.Contains("## 終了条件(残存未知の許容基準)`n条件X")) 'frame sections'
Check 'frame-excludes-others' (-not $full.Contains('## ゴールの方向') -and -not $full.Contains('参照した学習メモ')) 'extra goal-frame sections leaked'
Check 'milestone-section' ($full.Contains('| 2 | 2-two | ✓ |') -and -not $full.Contains('## 主要設計判断')) 'milestone section'
Check 'unverified-only' ($full.Contains('| A2 |') -and $full.Contains('| A3 |') -and -not $full.Contains('| A1 |') -and -not $full.Contains('| A4 |') -and $full.Contains('| ID | 仮定内容')) 'assumption rows'
Check 'latest-decision' ($full.Contains('[milestones\2-two\gate-decision-2.md]') -and $full.Contains('最新の根拠') -and -not $full.Contains('古い判定') -and -not $full.Contains('根拠1')) 'decision pick'
Check 'escalation-line-7' ($full.Contains('7. **Fableの判定**: DECIDE: 進める') -and -not $full.Contains('何をしようとしたか')) 'escalation'
Check 'latest-retro-section' ($full.Contains('- 教訓1') -and $full.Contains('- 教訓2') -and -not $full.Contains('古い教訓') -and -not $full.Contains('未知1') -and -not $full.Contains('良かった')) 'retro'
Check 'unfinished' ($full.Contains('impl-runs/m2-impl') -and -not $full.Contains('impl-runs/m1-impl') -and $full.Contains('codex-runs/m2-grareco') -and -not $full.Contains('codex-runs/techpm-assessment') -and $full.Contains('codex-run: m2-grareco')) 'unfinished labels'
$bytes = [IO.File]::ReadAllBytes((Join-Path $g 'resume-packet.md'))
Check 'full-no-bom-lf' ($bytes[0] -ne 0xEF -and -not $full.Contains("`r")) 'encoding'
Check 'no-truncation-when-small' ($r.Out -match '(?m)^TRUNCATED: 0') $r.Out

# Missing files are named, never fatal.
$g2 = Join-Path $loop 'g2'
W (Join-Path $g2 'state.md') "- phase: goal-definition`n- 待ち: -`n- updated: x`n"
W (Join-Path $g2 'goal-frame.md') "# Goal Frame`n`n## 承認基準`n1. b`n"
$r = Invoke-Packet $g2 @('-PolicyFile', $policy)
$full2 = Get-Text (Join-Path $g2 'resume-packet.md')
Check 'missing-ok' ($r.Code -eq 0) $r.Out
Check 'missing-constraints-marked' ($full2.Contains('(見つからない: goal-frame.md に「## 制約」が無い)') -and $full2.Contains("## 承認基準`n1. b") -and $full2.Contains('「## 終了条件」が無い')) 'markers'
Check 'missing-plan-marked' ($full2.Contains('「## マイルストーン」が無い')) 'plan marker'
Check 'missing-assumptions-marked' ($full2.Contains('(見つからない: assumptions.md')) 'assumptions marker'
Check 'wait-none' ($full2 -match '(?m)^## 2\. 待ち\s*\n\s*\nなし') 'wait none'
Check 'no-unfinished' ($full2 -match '(?m)^## 5\. 未完了の委譲\s*\n\s*\n\(なし\)') 'unfinished none'
Check 'no-decision' ($full2.Contains('(判定はまだない)')) 'decision none'
Check 'retro-from-sibling-goal' ($full2.Contains('- 教訓1')) 'newest retro of the project is used'

# Truncation keeps every pinned section and fits MaxChars.
$g3 = Join-Path $loop 'g3'
W (Join-Path $g3 'state.md') "- phase: milestone-implementation`n- 待ち: -`n- updated: x`n"
W (Join-Path $g3 'goal-frame.md') "## 制約`n- PINNED-CONSTRAINT`n`n## 承認基準`n1. PINNED-CRITERION`n`n## 終了条件`nPINNED-EXIT`n"
$rows = @(1..400 | ForEach-Object { '| A' + $_ + ' | ' + ('仮' * 30) + ' | 未検証 |' })
W (Join-Path $g3 'assumptions.md') ("| ID | 仮定 | 状態 |`n|---|---|---|`n" + ($rows -join "`n") + "`n")
W (Join-Path $g3 'goal-plan.md') ("## マイルストーン`n" + ('M' * 5000) + "`n")
$inj3 = Join-Path $t 'inject3.md'
$r = Invoke-Packet $g3 @('-OutFile', $inj3, '-PolicyFile', $policy, '-MaxChars', '6000')
$i3 = Get-Text $inj3
$f3 = Get-Text (Join-Path $g3 'resume-packet.md')
Check 'truncated-reported' ($r.Out -match '(?m)^TRUNCATED: [1-9]') $r.Out
Check 'inject-within-max' ($i3.Length -le 6000) "len=$($i3.Length)"
Check 'pinned-kept' ($i3.Contains('PINNED-CONSTRAINT') -and $i3.Contains('PINNED-CRITERION') -and $i3.Contains('PINNED-EXIT') -and $i3.Contains('仮説自律の否定リスト')) 'pinned lost'
Check 'cut-marker' ($i3.Contains('…(省略 ') -and $i3.Contains('全文: ')) 'marker'
Check 'full-not-cut' ($f3.Contains('| A400 |') -and -not $f3.Contains('…(省略 ')) 'full file was cut'
Check 'no-warn-when-fits' ($r.Out -notmatch '(?m)^WARN:') $r.Out

# Pinned alone over the limit: still complete, with a WARN.
$g4 = Join-Path $loop 'g4'
W (Join-Path $g4 'state.md') "- phase: milestone-implementation`n- 待ち: -`n- updated: x`n"
W (Join-Path $g4 'goal-frame.md') ("## 制約`n" + ('制' * 3000) + "`n`n## 承認基準`n1. x`n`n## 終了条件`ny`n")
$inj4 = Join-Path $t 'inject4.md'
$r = Invoke-Packet $g4 @('-OutFile', $inj4, '-PolicyFile', $policy, '-MaxChars', '2000')
Check 'pinned-overflow-warns' ($r.Code -eq 0 -and $r.Out -match '(?m)^WARN: packet exceeds') $r.Out
Check 'pinned-overflow-still-complete' ((Get-Text $inj4).Contains('制' * 3000)) 'pinned cut'

$g5 = Join-Path $loop 'g5'
New-Item -ItemType Directory -Path $g5 -Force | Out-Null
$r = Invoke-Packet $g5 @()
Check 'no-state-fails' ($r.Code -ne 0) $r.Out

$b = [IO.File]::ReadAllBytes($script)
Check 'script-has-bom' ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'save resume-packet.ps1 as UTF-8 with BOM'

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
