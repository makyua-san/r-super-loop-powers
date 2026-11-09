#Requires -Version 5.1
# Layout and wording checks for the split SKILL.md (common / workflow-a / workflow-b).
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillDir = Join-Path $root 'skills\r-super-loop-powers'
$script:failures = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}
function Get-Text([string]$Path) { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path, $utf8) } return '' }
$skillFile = Join-Path $skillDir 'SKILL.md'
$s = Get-Text $skillFile
$a = Get-Text (Join-Path $skillDir 'references\workflow-a.md')
$b = Get-Text (Join-Path $skillDir 'references\workflow-b.md')

Check 'workflow-files-exist' ($a -ne '' -and $b -ne '') 'references/workflow-a.md / workflow-b.md missing'
# Measured on LF-normalized text: core.autocrlf checks files out with CRLF, which must not change the verdict.
$skillBytes = [Text.Encoding]::UTF8.GetByteCount(($s -replace "`r`n", "`n"))
Check 'skill-size' ($skillBytes -le 24KB) ("SKILL.md is $skillBytes bytes (LF-normalized)")
Check 'skill-points-to-workflows' ($s -match 'references/workflow-a\.md' -and $s -match 'references/workflow-b\.md') 'workflow references'
Check 'skill-common-sections' ($s -match '(?m)^## 起動時チェック' -and $s -match '(?m)^## 記録ルール' -and $s -match '(?m)^## 境界リセット' -and $s -match '(?m)^## Fableサブエージェント共通契約' -and $s -match '(?m)^## 読むものと読まないもの') 'common sections'
Check 'skill-mentions-tools' ($s -match 'loop-log\.ps1' -and $s -match 'resume-packet\.ps1' -and $s -match 'resume-pending' -and $s -match 'context-meter\.ps1' -and $s -match '再開パケット') 'tool names'
Check 'skill-recitation' ($s -match '復唱') 'recitation rule'
# v0.10: scout (codex investigation) rules live in SKILL.md, both workflows, policy and the invocation guide.
Check 'skill-scout' ($s -match 'scout\.ps1' -and $s -match 'まずスカウト' -and $s -match '-Role techpm \| reviewer \| grareco \| scout') 'scout rules in SKILL.md'
Check 'a-scout' ($a -match 'scout\.ps1') 'scout in workflow-a'
Check 'b-scout' ($b -match 'scout\.ps1') 'scout in workflow-b'
$policyText = Get-Text (Join-Path $skillDir 'policy.md')
Check 'policy-scout' ($policyText -match '\| スカウト \| Codex `gpt-6\.1-sol` / `medium` / read-only\(`-Role scout`\)' -and $policyText -match 'codex-scout') 'policy.md scout row / vocabulary'
$invText = Get-Text (Join-Path $skillDir 'references\codex-invocation.md')
Check 'invocation-scout' ($invText -match 'scout\.ps1' -and $invText -match '-Web') 'codex-invocation.md scout'
Check 'skill-roles-jit' ($s -match 'roles\.md' -and $s -notmatch 'policy\.md` と `references/roles\.md`\(ロール憲章\)を読む') 'roles.md must be read just in time'
Check 'skill-failures-only' ($s -match 'FAIL\\?\|ALL PASS') 'shell results: failures only'
Check 'skill-no-image-read' ($s -match 'SendUserFile') 'image rule'
# Step headings look like "**A-0 …**" or "**B-2〜B-3 …**": the number is followed by a space or 〜.
foreach ($step in @('A-0', 'A-1a', 'A-1b', 'A-5', 'A-6', 'A-7', 'A-8')) {
    Check "a-$step-in-workflow-a" ($a -match ('(?m)^\*\*' + [regex]::Escape($step) + '[ 〜]')) "$step missing in workflow-a"
    Check "a-$step-not-in-skill" ($s -notmatch ('(?m)^\*\*' + [regex]::Escape($step) + '[ 〜]')) "$step still in SKILL.md"
}
Check 'a-2-4-in-workflow-a' ($a -match '(?m)^\*\*A-2') 'A-2〜A-4 missing'
Check 'techpm-contract-in-a' ($a -match '(?m)^## 技術PM\(Codex\)共通契約' -and $s -notmatch '(?m)^## 技術PM\(Codex\)共通契約') 'techpm contract placement'
Check 'a-techpm-paths' ($a -match '40 KB' -and $a -match 'パスで渡') 'techpm prompt by path'
foreach ($step in @('B-1', 'B-2', 'B-3', 'B-4', 'B-5', 'B-6', 'B-7', 'B-8', 'B-9', 'B-10')) {
    Check "b-$step-in-workflow-b" ($b -match ('(?m)^\*\*' + [regex]::Escape($step) + '[ 〜]')) "$step missing in workflow-b"
    Check "b-$step-not-in-skill" ($s -notmatch ('(?m)^\*\*' + [regex]::Escape($step) + '[ 〜]')) "$step still in SKILL.md"
}
Check 'learning-in-b' ($b -match '(?m)^## Learning' -and $s -notmatch '(?m)^## Learning') 'Learning placement'
Check 'b2-prepare-save' ($b -match '-Prepare' -and $b -match '-SaveReport' -and $b -match '## 再委譲の差分' -and $b -match '\.prompt\.md にある') 'B-2 delegation wording'
Check 'b-grareco-low' ($b -match 'effort `low`') 'grareco effort'
Check 'b-retro-ctx' ($b -match 'CTX' -and $b -match 'RESUME') 'retro observation'
Check 'boundary-list' ($s -match '人間待ち' -and $s -match 'B-6 PASS' -and $s -match 'ACCEPT' -and $s -match 'A-8' -and $s -match '/clear') 'boundary rule'
Check 'policy-grareco-low' ((Get-Text (Join-Path $skillDir 'policy.md')) -match '`low` / read-only\(`-Role grareco`\)') 'policy.md grareco effort'
Check 'builder-read-exception' ((Get-Text (Join-Path $root 'agents\builder.md')) -match 'impl-runs/\*\.prompt\.md' -and (Get-Text (Join-Path $root 'agents\builder.md')) -match 'tech-assessment\.md') 'builder exception'
$ver = ((Get-Text (Join-Path $root '.claude-plugin\plugin.json')) | ConvertFrom-Json).version
Check 'version-0.12.0' ($ver -eq '0.12.0') "version=$ver"
Check 'skill-model-check-hearing' ($s -match 'hearing-fable' -and $s -match '/model fable') 'model check knows the hearing'
Check 'skill-hearing-ref' ($s -match 'references/hearing\.md') 'SKILL points to hearing.md'
Check 'skill-proxy-a2' ($s -notmatch 'A-1a〜A-4') 'proxy alive range is A-2..A-4'
Check 'skill-design-doc' ($s -match 'docs/r-super-loop-powers/design\.md' -and $s -match 'codex-surveyor' -and $s -match '-Role techpm \| reviewer \| grareco \| scout \| surveyor' -and $s -match '設計書役の失敗' -and $s -match '5ロール') 'SKILL.md design-doc rules'
Check 'policy-fable-direct' ($policyText -match 'メインセッション' -and $policyText -match '10 分') 'policy rows updated'
$readme = Get-Text (Join-Path $root 'README.md')
Check 'readme-direct-hearing' ($readme -match '/model fable' -and $readme -notmatch 'A-1aでFable駆動のヒアリング往復が行われ') 'README flow and E2E list'
# v0.11: the Fable runs the hearing in the main session (references/hearing.md).
$h = Get-Text (Join-Path $skillDir 'references\hearing.md')
Check 'hearing-file' ($h -ne '') 'references/hearing.md missing'
Check 'hearing-purposes' ($h -match '認識' -and $h -match '方針' -and $h -match 'スコープ' -and $h -match 'メタ' -and $h -match '利用場面') 'five purposes'
Check 'hearing-no-fixed-list' ($h -notmatch '3〜7問' -and $h -notmatch '感情・体験 → 嗜好・制約 → 検証' -and $a -notmatch '3〜7問') 'fixed list removed'
Check 'hearing-one-question' ($h -match '1 つだけ' -and $h -match 'AskUserQuestion') 'one question / selection UI'
Check 'hearing-haiku' ($h -match 'model: "haiku"' -and $h -match '-Who haiku') 'haiku delegation'
Check 'hearing-scout' ($h -match 'scout\.ps1') 'fable may ask the scout'
Check 'hearing-no-boundary-reset' ($h -match '印を置かない' -and $a -match 'A-0 の終わりから A-1b の確定まで' -and $s -match '切らない区間\*\*: ヒアリング中') 'no /clear during the hearing'
Check 'state-format-hearing-fable' ($s -match '担当: opus-main \| hearing-fable \|') 'hearing-fable in the state.md format'
Check 'hearing-not-fable-stops' ($h -match 'Fable でなければ' -and $h -match 'Fable が使えない' -and $s -match 'Fable が使えない') 'Opus does not run the hearing unless the user says Fable is unavailable'
Check 'hearing-scout-async' ($h -match '-Async' -and $h -match '-Collect' -and $h -match 'scout/index\.md') 'non-blocking scout during the hearing'
Check 'hearing-ten-min'($h -match '10 分' -and $h -match '運用で見る懸念') 'acceptance default'
Check 'a-model-switch' ($a -match '/model fable' -and $a -match '/model opus' -and $a -match 'hearing-fable' -and $a -match 'references/hearing\.md') 'workflow-a hand-offs'
Check 'a-close-route' ($a -match 'phase: done' -and $a -match '## 結論') 'close route when not doing it'
Check 'a-proxy-starts-at-a2' ($a -match 'A-2〜A-4 は代理Fable\(SendMessage 継続\)が生きている' -and $a -notmatch 'この区間は代理Fable') 'boundary wording updated'
Check 'a-gate-ten-min' ($a -match '10 分') 'A-6 / assessment / proxy use the 10-minute default'
Check 'b-verification-ten-min' ($b -match '10 分') 'B-2 verification uses the 10-minute default'
Check 'b6-concerns-accepted' ($b -match '運用で見る懸念') 'B-6 treats operational concerns as accepted unknowns'
$roles = Get-Text (Join-Path $skillDir 'references\roles.md')
Check 'roles-hearing-fable' ($roles -match '(?m)^## ヒアリング Fable \(hearing-fable\)') 'hearing-fable section'
Check 'roles-opus-not-only-talker' ($roles -notmatch '人間と直接話すのはあなただけ') 'Opus is no longer the only one talking to the human'
Check 'roles-proxy-a2' ($roles -match 'A-2〜A-4' -and $roles -notmatch '(?m)^- \*\*あなたの立場\*\*: MVP強度のヒアリングから') 'proxy range'
Check 'roles-scout-from-fable' ($roles -match 'ヒアリング中の Fable') 'scout accepts questions from the hearing Fable'
# v0.11: operational concerns, direct-hearing log, report lists the concerns.
$tpl = Join-Path $skillDir 'templates'
$gf = Get-Text (Join-Path $tpl 'goal-frame.md')
$hl = Get-Text (Join-Path $tpl 'hearing-log.md')
$hr = Get-Text (Join-Path $tpl 'human-review-report.md')
Check 'tpl-goal-frame-concerns' ($gf -match '(?m)^## 運用で見る懸念' -and $gf -match '10 分') 'goal-frame concerns section'
Check 'tpl-hearing-log-direct' ($hl -match '(?m)^## 結論' -and $hl -match '整理して返した内容' -and $hl -notmatch '過去の不満・避けたい体験') 'hearing-log template'
Check 'tpl-report-concerns' ($hr -match '運用で見る懸念') 'human report lists concerns'
# v0.12: project design document template (written by the surveyor, saved by design-doc.ps1).
$dd = Get-Text (Join-Path $tpl 'design-doc.md')
Check 'tpl-design-doc-sections' ($dd -match '(?m)^## 更新履歴' -and $dd -match '(?m)^## 0\. 構成' -and $dd -match '(?m)^### 0\.1 全体概要' -and $dd -match '(?m)^### 0\.2 主要な機能の流れ' -and $dd -match '(?m)^## 1\. 機能の地図' -and $dd -match '(?m)^## 2\. 取り組んだが足りない' -and $dd -match '(?m)^## 3\. 要望はあるが未着手' -and $dd -match '(?m)^## 4\. 運用で見る懸念') 'design-doc template sections'
Check 'tpl-design-doc-vocab' ($dd -match 'できている / 一部 / 取り組んだが足りない / 進行中 / 未着手' -and $dd -match '\| 日時 \| ゴール \| 節目 \| 見たコミット \| 書き手 \|' -and $dd -match '\(推測\)') 'design-doc vocabulary'
$cver = ((Get-Text (Join-Path $root '.codex-plugin\plugin.json')) | ConvertFrom-Json).version
Check 'codex-version-0.1.3' ($cver -eq '0.1.3') "codex version=$cver"
& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\sync-templates.ps1') -Mode Verify | Out-Null
Check 'templates-in-sync' ($LASTEXITCODE -eq 0) 'sync-templates Verify failed'
& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\sync-roles.ps1') -Mode Verify | Out-Null
Check 'roles-in-sync' ($LASTEXITCODE -eq 0) 'sync-roles Verify failed'

# v0.12: the project design document (design-doc.ps1 / surveyor) runs through the process docs.
Check 'a-design-doc' ($a -match 'design-doc\.ps1' -and $a -match '-Milestone A-0' -and $a -match '直列' -and $a -match '-Fallback' -and $a -match '衝突' -and $a -match '初回は十数分') 'workflow-a A-0 design-doc steps'
Check 'a-close-commits-docs' ($a -match 'phase: done' -and $a -match 'docs/r-super-loop-powers/` の未コミット分') 'closing route commits the goal records'
Check 'b-design-doc' ($b -match '1\.5' -and $b -match 'design-doc\.ps1' -and $b -match '-Milestone CP' -and $b -match '未コミット分') 'workflow-b Learning 1.5 and the commit before 3'
Check 'hearing-design-doc' ($h -match 'design\.md' -and $h -match '頼み直し' -and $h -match '設計書は文書なので') 'hearing.md reads the design doc rows and asks the re-ask question'
Check 'invocation-five-scripts' ($invText -match '5本のスクリプト' -and $invText -notmatch '4本のスクリプト' -and $invText -match '5ロール' -and $invText -match 'design-doc\.ps1' -and $invText -match '### 2-7') 'codex-invocation.md design-doc'
Check 'policy-surveyor' ($policyText -match '\| 設計書役 \| Codex `gpt-6\.1-sol` / 作成 `high`・更新 `medium` / read-only\(`-Role surveyor`\)' -and $policyText -match '(?m)^## 設計書役を呼ぶ場面' -and $policyText -match 'codex-surveyor') 'policy.md surveyor row / call sites'
Check 'policy-pl009-design' ($policyText -match 'PL-009.*設計書.*読んでよい') 'PL-009 allows the design doc'
Check 'tpl-goal-frame-relation' ($gf -match '既存機能との関係') 'goal-frame knows the relation to existing features'
Check 'readme-surveyor' ($readme -match '設計書役' -and $readme -match 'design-doc') 'README role table / repo layout'

if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
