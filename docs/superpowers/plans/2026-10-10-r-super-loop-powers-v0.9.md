# r-super-loop-powers v0.9 Implementation Plan — 境界リセット(/clear + 再開パケット)と記帳の省力化

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opus メインセッションの文脈を、要約(コンパクション)を使わずにフェーズ境界で捨てられるようにし(スクリプトが組む再開パケット + `/clear` 後の自動注入 + 復唱)、記帳・委譲・読込の重複を減らして、精度を落とさずに文脈と費用を下げる。

**Architecture:** 正本はファイル、セッションは使い捨て。`bin/resume-packet.ps1` が state.md と正本ファイルから固定順・決定論的にパケットを組み、`hooks/resume-inject.ps1`(SessionStart、`startup|clear`)が印 `resume-pending` を見て一回限り注入する。`hooks/context-meter.ps1`(PostToolUse、`Agent`)がトランスクリプトから文脈サイズを測って境界の判断材料を出す。記帳は `bin/loop-log.ps1` と `impl-check.ps1 -Prepare / -SaveReport` で 1 ターンに畳み、SKILL.md は共通 + workflow-a + workflow-b に分けて phase に応じて読む。

**Tech Stack:** Windows PowerShell 5.1、Claude Code のプラグイン hooks(SessionStart / PostToolUse / Stop)、git。

**Spec:** `docs/superpowers/specs/2026-10-10-r-super-loop-powers-v0.9-design.md`

## Global Constraints

- 変更対象は Claude 版のみ。`skills-codex/` と `skills/r-super-loop-powers/templates/` は変更しない(`scripts/sync-templates.ps1 -Mode Verify` が通り続ける)
- PowerShell 5.1 で動くこと(`?:` `??` `&&` を使わない)。`-File` 起動では配列パラメータに複数値を渡せないので、複数の欄は名前付きパラメータにする
- 日本語の文字列リテラルを含む `.ps1` は **UTF-8 BOM 付き**で保存する(PS 5.1 は BOM 無しを ANSI として読む)。BOM 付与: `powershell -NoProfile -Command "$p='<path>'; [IO.File]::WriteAllText($p, [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding $false)), (New-Object Text.UTF8Encoding $true))"`
- 書き出すファイルは UTF-8 **BOM なし**、改行は元ファイルに合わせる(新規は LF)
- テストは既存の形式(`Check` 関数、最後に `ALL PASS` / `FAILURES: n`、実行は `powershell -NoProfile -ExecutionPolicy Bypass -File tests\<名>.tests.ps1`)
- 再開パケットの上限 `9,500` 文字(Claude Code の additionalContext 上限 10,000)。切ってよい節の上限: 5 = 2,000 / 6 = 2,500 / 7 = 1,200 / 8 = 1,000、縮小時の下限 200。印の有効期限 24 時間。文脈メーターのしきい値 200,000 トークン、末尾 512 KB を読む。codex プロンプトの WARN しきい値 40 KB(40,960 バイト)。グラレコ effort `low`
- hook-log の行書式: `YYYY-MM-DD HH:MM | <RESULT> | <第3欄> | <補足>`(v0.8 と同じ 4 欄。第 3 欄は `ja-ratio=` / `source=` / `tokens=`)
- `additionalContext` の文面は事実の記述で書く(命令口調にしない)
- version: `0.9.0`
- コミットメッセージ末尾に次の 2 行を付ける:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_012NXQ7BHv2451uHUAhCNPuW
  ```

## Review Focus

1. **state.md の値が装飾されている / 末尾に空白がある**(`- phase: **done**(…)`)— loop-log の `-Set*` は行の値全体を置き換え、他の行は触らないこと → Task 3 の `set-replaces-decorated-value`
2. **ピン留め節だけで 9,500 文字を超えるゴール** — 切らずに出し `WARN:` を出すこと(Claude Code 側で退避されても state.md が先頭に来る)→ Task 2 の `pinned-overflow-warns`
3. **別プロジェクトの印** — セッションの cwd 配下の印だけを見て、他のプロジェクトの印を注入しないこと → Task 4 の `other-cwd-silent`
4. **書きかけのトランスクリプト行**(最後の行が JSON として途中)— その行を捨てて直前の完全な assistant 行を使うこと → Task 5 の `partial-line-skipped`
5. **報告に `|`・日本語・CRLF が混ざる** — `-SaveReport` がバイトを変えずに保存すること → Task 6 の `save-verbatim`

---

### Task 1: フック共通部 `hooks/hook-common.ps1` と Stop フックの整理

**Files:**
- Create: `hooks/hook-common.ps1`(UTF-8 BOM 付き)
- Modify: `hooks/human-message-check.ps1`(共通関数を hook-common に移す。振る舞いは変えない)
- Test: `tests/human-message-check.tests.ps1`(変更なし。回帰として実行)

**Interfaces:**
- Produces: `$Utf8`(UTF8Encoding、BOM なし)/ `Read-StdinUtf8()` / `Write-StdoutUtf8([string])` / `Write-HookJson($obj)`(`ConvertTo-Json -Compress -Depth 4` を UTF-8 で stdout へ)/ `Find-GoalDir([string]$Cwd) -> string|$null` / `Write-HookLogLine([string]$GoalDir, [string]$Result, [string]$Field3, [string]$Note)`

- [ ] **Step 1: `hooks/hook-common.ps1` を書く**

```powershell
#Requires -Version 5.1
<#
  hook-common.ps1 -- helpers shared by the r-super-loop-powers hooks
  (Stop: human-message-check, SessionStart: resume-inject, PostToolUse: context-meter).
  Dot-source it:  . (Join-Path $PSScriptRoot 'hook-common.ps1')
  Saved as UTF-8 with BOM because Find-GoalDir matches a Japanese word.
#>

$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-StdinUtf8 {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $Utf8)
    return $reader.ReadToEnd()
}

function Write-StdoutUtf8([string]$Text) {
    $bytes = $Utf8.GetBytes($Text)
    $out = [Console]::OpenStandardOutput()
    $out.Write($bytes, 0, $bytes.Length)
    $out.Flush()
}

function Write-HookJson($Object) {
    Write-StdoutUtf8 ($Object | ConvertTo-Json -Compress -Depth 4)
}

# Newest state.md whose phase is not done; $null when the loop is not active here.
# Real state files decorate the value ("- phase: **done**(2026-09-25)", "**完了(...)**"),
# so only the leading word counts ("実装完了。…待ち" is still active).
function Find-GoalDir([string]$Cwd) {
    $root = Join-Path $Cwd 'docs\r-super-loop-powers'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $states = @(Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
            Get-Item -LiteralPath (Join-Path $_.FullName 'state.md') -ErrorAction SilentlyContinue })
    $active = @($states | Where-Object {
            $_ -and ([System.IO.File]::ReadAllText($_.FullName, $Utf8) -notmatch '(?m)^\s*-\s*phase:\s*\**\s*(done\b|完了)') })
    if ($active.Count -eq 0) { return $null }
    return ($active | Sort-Object LastWriteTime | Select-Object -Last 1).DirectoryName
}

# One line per event in <goal-dir>/hook-log.md:
#   "YYYY-MM-DD HH:MM | <Result> | <Field3> | <Note>"   (the same 4 columns as v0.8)
function Write-HookLogLine([string]$GoalDir, [string]$Result, [string]$Field3, [string]$Note) {
    try {
        $one = ($Note -replace '[\r\n|]+', ' ').Trim()
        if ($one.Length -gt 200) { $one = $one.Substring(0, 200) }
        $line = '{0} | {1} | {2} | {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $Result, $Field3, $one
        [System.IO.File]::AppendAllText((Join-Path $GoalDir 'hook-log.md'), $line + "`n", $Utf8)
    } catch { }
}
```

BOM を付ける(Global Constraints のコマンド)。

- [ ] **Step 2: `hooks/human-message-check.ps1` を共通部に乗せ換える**

(a) `$ErrorActionPreference = 'Stop'` の直後に `. (Join-Path $PSScriptRoot 'hook-common.ps1')` を足す。
(b) `$Utf8 = New-Object System.Text.UTF8Encoding($false)` の行と、関数 `Read-StdinUtf8` / `Write-StdoutUtf8` / `Find-GoalDir` / `Write-HookLog` の定義(コメント含む)を削除する。
(c) `Write-HookLog $goalDir 'BLOCK' $ratioText 'not japanese'` → `Write-HookLogLine $goalDir 'BLOCK' "ja-ratio=$ratioText" 'not japanese'`。同様に `'BLOCK' $ratioText $why` / `'PASS' $ratioText ''` / `'ERROR' $ratioText $_.Exception.Message` を `"ja-ratio=$ratioText"` 形に直す(4 箇所)。
(d) ファイル先頭の BOM はそのまま(日本語リテラルが残る)。

- [ ] **Step 3: 回帰テスト**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\human-message-check.tests.ps1`
Expected: `ALL PASS`(`english-logged` が `| BLOCK | ja-ratio=` を見るので、書式が変わっていないことの確認になる)

- [ ] **Step 4: コミット**

```bash
git add hooks/hook-common.ps1 hooks/human-message-check.ps1
git commit -m "refactor: フック共通部 hook-common.ps1 を切り出す"
```

---

### Task 2: 再開パケット `bin/resume-packet.ps1`

**Files:**
- Create: `skills/r-super-loop-powers/bin/resume-packet.ps1`(UTF-8 BOM 付き)
- Modify: `skills/r-super-loop-powers/bin/codex-common.ps1:3-5`(コメント: 日本語を含むスクリプトは BOM 付きで置く旨)
- Test: `tests/resume-packet.tests.ps1`(UTF-8 BOM 付き)

**Interfaces:**
- Consumes: `codex-common.ps1` の `Write-Kv` / `Read-TextFile` / `Write-TextFile`
- Produces: `resume-packet.ps1 -GoalDir <dir> [-OutFile <path>] [-PolicyFile <path>] [-MaxChars 9500]`。常に `<goal-dir>\resume-packet.md`(全文)を書き、`-OutFile` があれば収めた本文をそこに書く。stdout: `PACKET:` / `FULL_CHARS:` / `INJECT:` / `CHARS:` / `TRUNCATED:` / `WARN:`。state.md が無ければ非 0 終了。節の見出しは `## 1. state.md(全文)` 〜 `## 9. 未完了の委譲`(Task 4・9 がこの見出しと `# 再開パケット — <slug>` を前提にする)

- [ ] **Step 1: 失敗するテストを書く**

`tests/resume-packet.tests.ps1`(保存後に BOM を付ける):

```powershell
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
function R([string]$Path) { return [IO.File]::ReadAllText($Path, $utf8) }
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
$full = R (Join-Path $g 'resume-packet.md')
$inj = R $inject
Check 'full-and-inject-same-when-small' ($full -eq $inj) 'full and inject differ'
Check 'title' ($full.StartsWith('# 再開パケット — g1')) $full.Substring(0, [Math]::Min(80, $full.Length))
$heads = @('## 1. state.md', '## 2. 待ち', '## 3. 仮説自律の否定リスト', '## 4. 制約', '## 5. 対象マイルストーン', '## 6. 未検証の仮定', '## 7. 直近の判定', '## 8. 直近 retro', '## 9. 未完了の委譲')
$idx = @(); foreach ($h in $heads) { $idx += $full.IndexOf($h) }
$ordered = $true
for ($i = 0; $i -lt $idx.Count; $i++) { if ($idx[$i] -lt 0 -or ($i -gt 0 -and $idx[$i] -lt $idx[$i - 1])) { $ordered = $false } }
Check 'section-order' $ordered ($idx -join ',')
Check 'state-full' ($full.Contains("- phase: milestone-implementation`n- 強度: MVP") -and $full.Contains('- updated: 2026-10-10 10:00')) 'state.md body missing'
Check 'skill-dir-in-header' ($full.Contains('- skill-dir: C:\skill')) 'skill-dir'
Check 'wait' ($full -match '(?m)^## 2\. 待ち\s*\n\s*\n人間の受け入れテスト結果') 'wait missing'
$policyText = (R $policy) -replace "`r`n", "`n"
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
$full2 = R (Join-Path $g2 'resume-packet.md')
Check 'missing-ok' ($r.Code -eq 0) $r.Out
Check 'missing-constraints-marked' ($full2.Contains('(見つからない: goal-frame.md に「## 制約」が無い)') -and $full2.Contains("## 承認基準`n1. b") -and $full2.Contains('「## 終了条件」が無い')) 'markers'
Check 'missing-plan-marked' ($full2.Contains('「## マイルストーン」が無い')) 'plan marker'
Check 'missing-assumptions-marked' ($full2.Contains('(見つからない: assumptions.md')) 'assumptions marker'
Check 'wait-none' ($full2 -match '(?m)^## 2\. 待ち\s*\n\s*\nなし') 'wait none'
Check 'no-unfinished' ($full2 -match '(?m)^## 9\. 未完了の委譲\s*\n\s*\n\(なし\)') 'unfinished none'
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
$i3 = R $inj3
$f3 = R (Join-Path $g3 'resume-packet.md')
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
Check 'pinned-overflow-still-complete' ((R $inj4).Contains('制' * 3000)) 'pinned cut'

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
```

- [ ] **Step 2: 失敗を確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\resume-packet.tests.ps1`
Expected: `runs` ほかが FAIL(スクリプトが無い)、最後に `FAILURES:`。

- [ ] **Step 3: `bin/resume-packet.ps1` を書く**(保存後に BOM)

```powershell
#Requires -Version 5.1
<#
  resume-packet.ps1 -- build the resume packet for one goal, deterministically.

  The packet is what the orchestrator (Opus) reads right after /clear: state.md, the
  pinned constraints (negative list, goal-frame constraints / acceptance criteria /
  exit conditions, what it is waiting for), the current milestones, the unverified
  assumptions, the latest verdict, the latest retro lessons, and delegations that
  were started but never finished. No model summarises anything here, so nothing
  can be "lost in compaction".

  Outputs:
    <goal-dir>/resume-packet.md   always: the full text, nothing cut
    -OutFile <path>               optional: the same text with the non-pinned
                                  sections cut to fit -MaxChars (Claude Code caps a
                                  hook's additionalContext at 10,000 characters)
  stdout is KV only: PACKET / FULL_CHARS / INJECT / CHARS / TRUNCATED / WARN.
  Exit 1 (throw) when state.md is missing or empty.

  Saved as UTF-8 with BOM: it matches Japanese headings.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GoalDir,
    [string]$OutFile,
    # policy.md that holds "## 仮説自律の否定リスト". Empty = this skill's policy.md.
    [string]$PolicyFile,
    [int]$MaxChars = 9500
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'codex-common.ps1')

if (-not (Test-Path -LiteralPath $GoalDir -PathType Container)) { throw "GoalDir does not exist: $GoalDir" }
$GoalDir = (Resolve-Path -LiteralPath $GoalDir).Path
if (-not $PolicyFile) { $PolicyFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'policy.md' }
$slug = Split-Path -Leaf $GoalDir
$loopRoot = Split-Path -Parent $GoalDir
$fullFile = Join-Path $GoalDir 'resume-packet.md'

# Caps (characters) for the sections that may be cut. Pinned sections have none.
$Caps = @{ 5 = 2000; 6 = 2500; 7 = 1200; 8 = 1000 }
$MinCap = 200

function Get-Lines([string]$Text) { return ((($Text -replace "`r`n", "`n") -replace "`r", "`n") -split "`n") }

# "## <prefix>..." up to the next "## " heading. '' when the heading is missing.
function Get-Section([string]$Text, [string]$HeadingPrefix) {
    if (-not $Text) { return '' }
    $lines = Get-Lines $Text
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('## ' + $HeadingPrefix)) { $start = $i; break }
    }
    if ($start -lt 0) { return '' }
    $end = $lines.Count
    for ($k = $start + 1; $k -lt $lines.Count; $k++) { if ($lines[$k] -match '^## ') { $end = $k; break } }
    return (($lines[$start..($end - 1)]) -join "`n").TrimEnd()
}

function Get-StateField([string]$StateText, [string]$Key) {
    $m = [regex]::Match($StateText, '(?m)^\s*-\s*' + [regex]::Escape($Key) + ':[ \t]*([^\r\n]*)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Get-Missing([string]$File, [string]$What) { return "(見つからない: $File に「$What」が無い)" }

function Get-Newest($Files) {
    $list = @($Files | Where-Object { $_ })
    if ($list.Count -eq 0) { return $null }
    return ($list | Sort-Object LastWriteTime, FullName | Select-Object -Last 1)
}

function Get-FilesUnder([string]$Dir, [string]$Filter) {
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue)
}

function Get-RelativePath([string]$Full, [string]$Base) { return $Full.Substring($Base.Length + 1) }

# --- 1. state.md ----------------------------------------------------------------
$stateText = Read-TextFile (Join-Path $GoalDir 'state.md')
if (-not $stateText.Trim()) { throw "state.md not found or empty: $GoalDir" }
$stateBody = (($stateText -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd()
$skillDir = Get-StateField $stateText 'skill-dir'
if (-not $skillDir) { $skillDir = '(state.md に skill-dir: が無い)' }

# --- 2. waiting -----------------------------------------------------------------
$wait = Get-StateField $stateText '待ち'
if (-not $wait -or $wait -eq '-') { $wait = 'なし' }

# --- 3. negative list (policy.md, verbatim) -------------------------------------
$neg = Get-Section (Read-TextFile $PolicyFile) '仮説自律の否定リスト'
if (-not $neg) { $neg = Get-Missing $PolicyFile '## 仮説自律の否定リスト' }

# --- 4. goal-frame: constraints / acceptance criteria / exit conditions ----------
$gfText = Read-TextFile (Join-Path $GoalDir 'goal-frame.md')
$frameParts = @()
foreach ($h in @('制約', '承認基準', '終了条件')) {
    $s = Get-Section $gfText $h
    if (-not $s) { $s = Get-Missing 'goal-frame.md' "## $h" }
    $frameParts += $s
}
$frame = $frameParts -join "`n`n"

# --- 5. milestones (goal-plan.md) -----------------------------------------------
$ms = Get-Section (Read-TextFile (Join-Path $GoalDir 'goal-plan.md')) 'マイルストーン'
if (-not $ms) { $ms = Get-Missing 'goal-plan.md' '## マイルストーン' }

# --- 6. unverified assumptions --------------------------------------------------
$asText = Read-TextFile (Join-Path $GoalDir 'assumptions.md')
if ($asText) {
    $rows = @(Get-Lines $asText | Where-Object { $_.TrimStart().StartsWith('|') })
    $header = @($rows | Select-Object -First 2)
    $unverified = @($rows | Select-Object -Skip 2 | Where-Object {
            $cells = @(($_.Trim().TrimStart('|').TrimEnd('|')) -split '\|')
            $last = ''
            for ($c = $cells.Count - 1; $c -ge 0; $c--) { if ($cells[$c].Trim()) { $last = $cells[$c].Trim(); break } }
            $last.StartsWith('未検証')
        })
    if ($unverified.Count -gt 0) { $asm = (($header + $unverified) -join "`n") } else { $asm = '(未検証の仮定はない)' }
} else {
    $asm = Get-Missing 'assumptions.md' '仮定台帳'
}

# --- 7. latest verdict ----------------------------------------------------------
$decFiles = @()
$ggd = Join-Path $GoalDir 'goal-gate-decision.md'
if (Test-Path -LiteralPath $ggd) { $decFiles += Get-Item -LiteralPath $ggd }
$decFiles += Get-FilesUnder (Join-Path $GoalDir 'milestones') 'gate-decision*.md'
$dec = ''
$latestDec = Get-Newest $decFiles
if ($latestDec) {
    $head = @(Get-Lines (Read-TextFile $latestDec.FullName) | Select-Object -First 8)
    $dec = ('[' + (Get-RelativePath $latestDec.FullName $GoalDir) + ']' + "`n" + ($head -join "`n")).TrimEnd()
}
$latestEsc = Get-Newest (Get-FilesUnder (Join-Path $GoalDir 'milestones') 'escalation-*.md')
if ($latestEsc) {
    $line7 = @(Get-Lines (Read-TextFile $latestEsc.FullName) | Where-Object { $_ -match '^7\.' }) | Select-Object -First 1
    if ($line7) { $dec = ($dec + "`n`n[" + (Get-RelativePath $latestEsc.FullName $GoalDir) + ']' + "`n" + $line7).Trim() }
}
if (-not $dec) { $dec = '(判定はまだない)' }

# --- 8. latest retro of this project: what to change next time -------------------
$retro = ''
$latestRetro = Get-Newest (Get-FilesUnder $loopRoot 'retro.md')
if ($latestRetro) {
    $sec = Get-Section (Read-TextFile $latestRetro.FullName) '次回変えること'
    if ($sec) { $retro = '[' + (Get-RelativePath $latestRetro.FullName $loopRoot) + ']' + "`n" + $sec }
}
if (-not $retro) { $retro = '(retro はまだない)' }

# --- 9. unfinished delegations --------------------------------------------------
$unfinished = @()
$implDir = Join-Path $GoalDir 'impl-runs'
if (Test-Path -LiteralPath $implDir) {
    foreach ($p in @(Get-ChildItem -LiteralPath $implDir -File -Filter '*.prompt.md')) {
        $label = $p.Name.Substring(0, $p.Name.Length - 10)
        if (-not (Test-Path -LiteralPath (Join-Path $implDir "$label.report.md"))) {
            $unfinished += "impl-runs/$label (prompt あり・report なし。実装役の委譲はセッションを跨がない: git status を見てから新しいラベルで再委譲)"
        }
    }
}
$codexDir = Join-Path $GoalDir 'codex-runs'
if (Test-Path -LiteralPath $codexDir) {
    foreach ($p in @(Get-ChildItem -LiteralPath $codexDir -File -Filter '*.prompt.md')) {
        $label = $p.Name.Substring(0, $p.Name.Length - 10)
        if (-not (Test-Path -LiteralPath (Join-Path $codexDir "$label.exit"))) {
            $unfinished += "codex-runs/$label (prompt あり・exit なし。codex-status.ps1 で判定してから次を決める)"
        }
    }
}
$codexRun = Get-StateField $stateText 'codex-run'
if ($codexRun -and $codexRun -ne '-') { $unfinished += "state.md の codex-run: $codexRun" }
if ($unfinished.Count -gt 0) { $unf = (($unfinished | ForEach-Object { '- ' + $_ }) -join "`n") } else { $unf = '(なし)' }

# --- assemble -------------------------------------------------------------------
$sections = @(
    @{ N = 1; Title = 'state.md(全文)'; Body = $stateBody; Pin = $true },
    @{ N = 2; Title = '待ち'; Body = $wait; Pin = $true },
    @{ N = 3; Title = '仮説自律の否定リスト(policy.md 原文)'; Body = $neg; Pin = $true },
    @{ N = 4; Title = '制約・承認基準・終了条件(goal-frame.md 原文)'; Body = $frame; Pin = $true },
    @{ N = 5; Title = '対象マイルストーン(goal-plan.md)'; Body = $ms; Pin = $false },
    @{ N = 6; Title = '未検証の仮定(assumptions.md)'; Body = $asm; Pin = $false },
    @{ N = 7; Title = '直近の判定'; Body = $dec; Pin = $false },
    @{ N = 8; Title = '直近 retro の「次回変えること」'; Body = $retro; Pin = $false },
    @{ N = 9; Title = '未完了の委譲'; Body = $unf; Pin = $true }
)

$header = @(
    "# 再開パケット — $slug",
    '',
    "- 生成: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "- goal-dir: $GoalDir",
    "- skill-dir: $skillDir",
    "- 全文: $fullFile",
    '- このパケットは resume-packet.ps1 が state.md と正本のファイルから機械的に組んだもので、要約は含まない。再開の手順は SKILL.md の「起動時チェック」3 と「境界リセット」にある。'
) -join "`n"

function Join-Packet([hashtable]$Limits) {
    $cut = 0
    $parts = @($header)
    foreach ($s in $sections) {
        $body = [string]$s.Body
        if (-not $s.Pin -and $Limits.ContainsKey($s.N) -and $body.Length -gt $Limits[$s.N]) {
            $n = $body.Length - $Limits[$s.N]
            $body = $body.Substring(0, $Limits[$s.N]).TrimEnd() + "`n…(省略 $n 文字。全文: $fullFile)"
            $cut++
        }
        $parts += ("## $($s.N). $($s.Title)`n`n" + $body)
    }
    return @{ Text = (($parts -join "`n`n") + "`n"); Cut = $cut }
}

$full = Join-Packet @{}
Write-TextFile $fullFile $full.Text
Write-Kv 'PACKET' $fullFile
Write-Kv 'FULL_CHARS' $full.Text.Length

if ($OutFile) {
    $limits = @{}
    foreach ($k in $Caps.Keys) { $limits[$k] = $Caps[$k] }
    $packet = Join-Packet $limits
    # Still too long: shrink the cuttable sections from the back, down to MinCap each.
    foreach ($k in @(8, 7, 6, 5)) {
        if ($packet.Text.Length -le $MaxChars) { break }
        $limits[$k] = $MinCap
        $packet = Join-Packet $limits
    }
    Write-TextFile $OutFile $packet.Text
    Write-Kv 'INJECT' $OutFile
    Write-Kv 'CHARS' $packet.Text.Length
    Write-Kv 'TRUNCATED' $packet.Cut
    if ($packet.Text.Length -gt $MaxChars) {
        Write-Kv 'WARN' "packet exceeds $MaxChars chars even with every cuttable section at $MinCap; Claude Code will file it and show a 2000-char preview (state.md comes first)."
    }
}
exit 0
```

`codex-common.ps1` 冒頭コメント(3〜5 行目)を次に置き換える:

```powershell
# ASCII only in this file: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI,
# so a non-ASCII literal would silently mojibake. Scripts that must match Japanese
# (resume-packet.ps1, loop-log.ps1) are saved as UTF-8 WITH BOM instead.
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\resume-packet.tests.ps1`
Expected: `ALL PASS`

- [ ] **Step 5: コミット**

```bash
git add skills/r-super-loop-powers/bin/resume-packet.ps1 skills/r-super-loop-powers/bin/codex-common.ps1 tests/resume-packet.tests.ps1
git commit -m "feat: 再開パケットを固定順で組む resume-packet.ps1"
```

---

### Task 3: 記帳スクリプト `bin/loop-log.ps1`

**Files:**
- Create: `skills/r-super-loop-powers/bin/loop-log.ps1`(UTF-8 BOM 付き)
- Test: `tests/loop-log.tests.ps1`(UTF-8 BOM 付き)

**Interfaces:**
- Consumes: Task 2 の `resume-packet.ps1 -GoalDir <dir>`(exit 0 で `<goal-dir>\resume-packet.md`)
- Produces: `loop-log.ps1 -GoalDir <dir> [-Who <役> -Purpose <text> [-Phase <phase>]] [-SetPhase|-SetIntensity|-SetMilestone|-SetCheckpoint|-SetOwner|-SetGate|-SetWait|-SetCodexRun <v>] [-Set 'key=value'] [-Mark]`。stdout `LOGGED:` / `SET:` / `UPDATED:` / `MARKED:` / `NEXT:` / `STATUS: OK|FAILED` / `REASON:`。印 `<goal-dir>\resume-pending` の中身は `created: <ISO 8601 (o)>` と `cwd: <project root>` の 2 行(Task 4 が `created:` を読む)

- [ ] **Step 1: 失敗するテストを書く**

`tests/loop-log.tests.ps1`(保存後に BOM):

```powershell
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
function R([string]$Path) { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path, $utf8) } return '' }
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
$log = R (Join-Path $g 'call-log.md')
Check 'log-ok' ($r.Code -eq 0 -and $r.Out -match '(?m)^STATUS: OK' -and $r.Out -match '(?m)^LOGGED: ') $r.Out
Check 'log-line-format' ($log -match '(?m)^\d{4}-\d{2}-\d{2} \d{2}:\d{2} \| fable \| milestone-implementation \| B-6 ゲート判定$') $log
Check 'log-keeps-existing' ($log.StartsWith('# call-log — g1') -and $log.Contains('既存の行')) $log
Check 'log-does-not-touch-state' ((R (Join-Path $g 'state.md')) -eq $stateLf) 'state.md changed by a log-only call'

$r = Invoke-Log $g @('-Who', 'codex-grareco', '-Purpose', 'x', '-Phase', 'learning')
Check 'log-explicit-phase' ((R (Join-Path $g 'call-log.md')) -match '(?m)\| codex-grareco \| learning \| x$') $r.Out

$r = Invoke-Log $g @('-SetPhase', 'human-acceptance', '-SetMilestone', '2-two', '-SetWait', '受け入れテストの結果=OK/NG', '-SetCodexRun', '-')
$st = R (Join-Path $g 'state.md')
Check 'set-ok' ($r.Code -eq 0 -and $r.Out -match '(?m)^STATUS: OK') $r.Out
Check 'set-phase' ($st -match '(?m)^- phase: human-acceptance$') $st
Check 'set-milestone' ($st -match '(?m)^- milestone: 2-two$') $st
Check 'set-wait-with-equals' ($st -match '(?m)^- 待ち: 受け入れテストの結果=OK/NG$') $st
Check 'set-codex-run' ($st -match '(?m)^- codex-run: -$') $st
Check 'set-updated' ($st -match '(?m)^- updated: \d{4}-\d{2}-\d{2} \d{2}:\d{2}$' -and -not $st.Contains('2026-10-10 10:00')) $st
Check 'set-keeps-other-lines' ($st.StartsWith('# state — g1') -and $st.Contains('- skill-dir: C:\skill') -and $st.Contains('- 強度: MVP')) $st
Check 'set-output' ($r.Out -match '(?m)^SET: 待ち = 受け入れ' -and $r.Out -match '(?m)^UPDATED: ') $r.Out

$r = Invoke-Log $g @('-SetIntensity', '高信頼', '-SetCheckpoint', '3-x', '-SetOwner', 'human', '-SetGate', 'none')
$st = R (Join-Path $g 'state.md')
Check 'set-japanese-keys' ($st -match '(?m)^- 強度: 高信頼$' -and $st -match '(?m)^- 次のCheckpoint: 3-x$' -and $st -match '(?m)^- 担当: human$' -and $st -match '(?m)^- 次のゲート: none$') $st

$r = Invoke-Log $g @('-Set', 'codex-env=D:\x=y.json')
Check 'generic-set' ((R (Join-Path $g 'state.md')) -match '(?m)^- codex-env: D:\\x=y\.json$') $r.Out

# A decorated value is replaced as a whole.
W (Join-Path $g 'state.md') ($stateLf -replace '- phase: milestone-implementation', '- phase: **実装完了。段 0(人間)待ち**   ')
$r = Invoke-Log $g @('-SetPhase', 'learning')
Check 'set-replaces-decorated-value' ((R (Join-Path $g 'state.md')) -match '(?m)^- phase: learning$') (R (Join-Path $g 'state.md'))

# Unknown field: nothing is written.
W (Join-Path $g 'state.md') $stateLf
$r = Invoke-Log $g @('-SetPhase', 'learning', '-Set', 'nope=1')
Check 'unknown-key-fails' ($r.Code -ne 0 -and $r.Out -match "(?m)^STATUS: FAILED" -and $r.Out -match "no field 'nope'") $r.Out
Check 'unknown-key-writes-nothing' ((R (Join-Path $g 'state.md')) -eq $stateLf) 'state.md was modified'

# CRLF files stay CRLF.
$g2 = Join-Path $proj 'docs\r-super-loop-powers\g2'
W (Join-Path $g2 'state.md') ($stateLf -replace "`n", "`r`n")
W (Join-Path $g2 'call-log.md') "# call-log — g2`r`n`r`n"
$r = Invoke-Log $g2 @('-SetPhase', 'learning', '-Who', 'fable', '-Purpose', 'p')
$st2 = R (Join-Path $g2 'state.md'); $lg2 = R (Join-Path $g2 'call-log.md')
Check 'crlf-state-kept' ($st2.Contains("`r`n- phase: learning`r`n") -and (($st2 -replace "`r`n", '') -notmatch "`n")) 'state.md line endings changed'
Check 'crlf-log-kept' ($lg2 -match "\| fable \| milestone-implementation \| p`r`n$") 'call-log line ending'
Check 'log-phase-is-pre-update' ($lg2 -match '\| milestone-implementation \|') $lg2

# Missing call-log.md is created with a heading.
$g4 = Join-Path $proj 'docs\r-super-loop-powers\g4'
W (Join-Path $g4 'state.md') $stateLf
$r = Invoke-Log $g4 @('-Who', 'sonnet-builder', '-Purpose', 'B-2 m1-impl')
$lg4 = R (Join-Path $g4 'call-log.md')
Check 'log-created' ($lg4.StartsWith("# call-log — g4`n`n") -and $lg4 -match '\| sonnet-builder \| milestone-implementation \| B-2 m1-impl\n$') $lg4

# -Mark builds the packet first, then writes the marker.
$r = Invoke-Log $g @('-SetWait', '承認待ち', '-Mark')
$marker = Join-Path $g 'resume-pending'
Check 'mark-ok' ($r.Code -eq 0 -and $r.Out -match '(?m)^MARKED: ' -and $r.Out -match '(?m)^NEXT: .*clear') $r.Out
Check 'mark-file' ((Test-Path -LiteralPath $marker) -and (R $marker) -match '(?m)^created: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' -and (R $marker) -match ('(?m)^cwd: ' + [regex]::Escape($proj) + '\s*$')) (R $marker)
Check 'mark-packet-built' (Test-Path -LiteralPath (Join-Path $g 'resume-packet.md')) 'resume-packet.md missing'
Check 'mark-state-updated' ((R (Join-Path $g 'state.md')) -match '(?m)^- 待ち: 承認待ち$') 'state not updated with -Mark'

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
```

- [ ] **Step 2: 失敗を確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\loop-log.tests.ps1`
Expected: FAIL が並び、最後に `FAILURES:`。

- [ ] **Step 3: `bin/loop-log.ps1` を書く**(保存後に BOM)

```powershell
#Requires -Version 5.1
<#
  loop-log.ps1 -- the orchestrator's bookkeeping in ONE call:
    call-log.md line   -Who <role> -Purpose <text> [-Phase <phase>]
    state.md fields    -SetPhase / -SetIntensity / -SetMilestone / -SetCheckpoint /
                       -SetOwner / -SetGate / -SetWait / -SetCodexRun / -Set 'key=value'
                       ("updated:" is refreshed whenever a field changes)
    resume marker      -Mark  (writes <goal-dir>/resume-pending after a dry build of
                       the resume packet; see resume-packet.ps1)
  Nothing is written when a requested field does not exist in state.md.
  Line endings follow the file (CRLF if it has any, else LF). UTF-8 without BOM.
  One named parameter per field because `powershell -File` cannot pass several
  values to one array parameter.
  Saved as UTF-8 with BOM: the state.md keys are Japanese.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GoalDir,
    [string]$Who = '',
    [string]$Purpose = '',
    [string]$Phase = '',
    [string]$SetPhase,
    [string]$SetIntensity,
    [string]$SetMilestone,
    [string]$SetCheckpoint,
    [string]$SetOwner,
    [string]$SetGate,
    [string]$SetWait,
    [string]$SetCodexRun,
    [string]$Set = '',
    [switch]$Mark
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'codex-common.ps1')
$Roles = @('fable', 'codex-techpm', 'codex-review', 'codex-grareco', 'sonnet-builder')

function Stop-Failed([string]$Reason, [string]$Next) {
    Write-Kv 'STATUS' 'FAILED'
    Write-Kv 'REASON' $Reason
    if ($Next) { Write-Kv 'NEXT' $Next }
    exit 1
}

function Get-Field([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^\s*-\s*' + [regex]::Escape($Key) + ':[ \t]*([^\r\n]*)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

# Replace the value of "- <key>: ..." (the whole rest of the line). $null when absent.
function Set-Field([string]$Text, [string]$Key, [string]$Value) {
    $m = [regex]::Match($Text, '(?m)^(\s*-\s*' + [regex]::Escape($Key) + ':)[ \t]*[^\r\n]*')
    if (-not $m.Success) { return $null }
    return $Text.Substring(0, $m.Index) + $m.Groups[1].Value + ' ' + $Value + $Text.Substring($m.Index + $m.Length)
}

if (-not (Test-Path -LiteralPath $GoalDir -PathType Container)) { Stop-Failed "GoalDir does not exist: $GoalDir" '' }
$GoalDir = (Resolve-Path -LiteralPath $GoalDir).Path

# Named -Set* parameters -> state.md keys.
$map = [ordered]@{
    SetPhase = 'phase'; SetIntensity = '強度'; SetMilestone = 'milestone'; SetCheckpoint = '次のCheckpoint'
    SetOwner = '担当'; SetGate = '次のゲート'; SetWait = '待ち'; SetCodexRun = 'codex-run'
}
$updates = [ordered]@{}
foreach ($p in $map.Keys) {
    if ($PSBoundParameters.ContainsKey($p)) { $updates[$map[$p]] = [string]$PSBoundParameters[$p] }
}
if ($Set) {
    $i = $Set.IndexOf('=')
    if ($i -lt 1) { Stop-Failed "bad -Set '$Set' (expected key=value)" '' }
    $updates[$Set.Substring(0, $i).Trim()] = $Set.Substring($i + 1)
}
if (-not $Who -and $updates.Count -eq 0 -and -not $Mark) { Stop-Failed 'nothing to do' 'pass -Who/-Purpose, one or more -Set* fields, and/or -Mark' }
if ($Who -and ($Roles -notcontains $Who)) { Stop-Failed "unknown -Who '$Who'" ('use one of: ' + ($Roles -join ', ')) }
if ($Who -and -not $Purpose) { Stop-Failed '-Who needs -Purpose' '' }

$stateFile = Join-Path $GoalDir 'state.md'
$stateText = Read-TextFile $stateFile
if (-not $stateText.Trim()) { Stop-Failed "state.md not found or empty: $stateFile" '' }
$now = Get-Date -Format 'yyyy-MM-dd HH:mm'

# 1. state.md -- validate every key before writing anything.
$newState = $stateText
foreach ($key in $updates.Keys) {
    $r = Set-Field $newState $key $updates[$key]
    if ($null -eq $r) { Stop-Failed "state.md has no field '$key'" 'nothing was written; valid fields: phase / 強度 / milestone / 次のCheckpoint / 担当 / 次のゲート / 待ち / codex-run (or any "- key:" line via -Set)' }
    $newState = $r
}
if ($updates.Count -gt 0) {
    $r = Set-Field $newState 'updated' $now
    if ($null -eq $r) { Stop-Failed "state.md has no field 'updated'" '' }
    $newState = $r
    Write-TextFile $stateFile $newState
    foreach ($key in $updates.Keys) { Write-Kv 'SET' ($key + ' = ' + $updates[$key]) }
    Write-Kv 'UPDATED' $now
}

# 2. call-log.md -- the phase is the one the call happened in (state.md before this update).
if ($Who) {
    if (-not $Phase) { $Phase = Get-Field $stateText 'phase' }
    $logFile = Join-Path $GoalDir 'call-log.md'
    $logText = Read-TextFile $logFile
    $nl = "`n"
    if ($logText.Contains("`r`n") -or ((-not $logText) -and $stateText.Contains("`r`n"))) { $nl = "`r`n" }
    $line = "$now | $Who | $Phase | $Purpose"
    if (-not $logText) { $logText = "# call-log — $(Split-Path -Leaf $GoalDir)$nl$nl" }
    elseif (-not $logText.EndsWith("`n")) { $logText += $nl }
    Write-TextFile $logFile ($logText + $line + $nl)
    Write-Kv 'LOGGED' $line
}

# 3. marker -- only after a dry build proves the packet can be made from these files.
if ($Mark) {
    $packet = Join-Path $PSScriptRoot 'resume-packet.ps1'
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = 'powershell' }
    $out = & $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $packet -GoalDir $GoalDir 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Stop-Failed ('resume packet could not be built: ' + $out.Trim()) 'fix the goal files (state.md must exist); no marker was written' }
    $projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $GoalDir))
    $marker = Join-Path $GoalDir 'resume-pending'
    Write-TextFile $marker ('created: ' + (Get-Date).ToString('o') + "`ncwd: $projectRoot`n")
    Write-Kv 'MARKED' $marker
    Write-Kv 'NEXT' 'End the turn now and ask the human to run /clear, then send a short "continue" message. The SessionStart hook injects the packet.'
}
Write-Kv 'STATUS' 'OK'
exit 0
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\loop-log.tests.ps1`
Expected: `ALL PASS`

- [ ] **Step 5: コミット**

```bash
git add skills/r-super-loop-powers/bin/loop-log.ps1 tests/loop-log.tests.ps1
git commit -m "feat: call-log・state.md・再開の印を1回で書く loop-log.ps1"
```

---

### Task 4: SessionStart フック `hooks/resume-inject.ps1`

**Files:**
- Create: `hooks/resume-inject.ps1`(UTF-8 BOM 付き)
- Modify: `hooks/hooks.json`(SessionStart と PostToolUse を追加。PostToolUse の実体は Task 5)
- Test: `tests/resume-inject.tests.ps1`(UTF-8 BOM 付き)

**Interfaces:**
- Consumes: Task 1 の hook-common、Task 2 の `resume-packet.ps1 -GoalDir -OutFile -MaxChars`、Task 3 の印の書式
- Produces: stdin = SessionStart JSON(`source` / `cwd`)。stdout = 注入時のみ `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}`。常に exit 0。hook-log に `RESUME` / `STALE` / `ERROR`

- [ ] **Step 1: 失敗するテストを書く**

`tests/resume-inject.tests.ps1`(保存後に BOM):

```powershell
#Requires -Version 5.1
# Tests for hooks/resume-inject.ps1 (SessionStart) and the hooks.json registration.
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hook = Join-Path $root 'hooks\resume-inject.ps1'
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
function R([string]$Path) { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path, $utf8) } return '' }
function Invoke-Hook([string]$Stdin) {
    $out = $Stdin | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hook 2>&1 | Out-String
    return @{ Out = $out.Trim(); Code = $LASTEXITCODE }
}
function New-Input([string]$Source, [string]$Cwd) {
    return (@{ session_id = 's'; hook_event_name = 'SessionStart'; source = $Source; cwd = $Cwd } | ConvertTo-Json -Compress)
}
function Set-Marker([string]$Goal, [datetime]$Created) {
    W (Join-Path $Goal 'resume-pending') ("created: " + $Created.ToString('o') + "`ncwd: x`n")
}
function Get-Context($Result) {
    try { $j = $Result.Out | ConvertFrom-Json } catch { return $null }
    if (-not $j -or -not $j.hookSpecificOutput) { return $null }
    return $j.hookSpecificOutput
}

$t = Join-Path ([IO.Path]::GetTempPath()) ('rsi-' + [guid]::NewGuid().ToString('N'))
$proj = Join-Path $t 'proj'
$g1 = Join-Path $proj 'docs\r-super-loop-powers\g1'
$g2 = Join-Path $proj 'docs\r-super-loop-powers\g2'
$state = "# state — {0}`n- phase: milestone-implementation`n- 強度: MVP`n- milestone: 1-one`n- 次のCheckpoint: 1-one`n- 担当: opus-main`n- 次のゲート: impl-gate`n- 待ち: 承認待ち`n- skill-dir: C:\skill`n- codex-env: -`n- codex-run: -`n- updated: 2026-10-10 10:00`n"
W (Join-Path $g1 'state.md') ($state -f 'g1')
W (Join-Path $g1 'goal-frame.md') "## 制約`n- c`n`n## 承認基準`n1. a`n`n## 終了条件`ne`n"
W (Join-Path $g2 'state.md') ($state -f 'g2')
$m1 = Join-Path $g1 'resume-pending'
$m2 = Join-Path $g2 'resume-pending'

Set-Marker $g1 (Get-Date)
$r = Invoke-Hook (New-Input 'clear' $proj)
$ctx = Get-Context $r
Check 'clear-injects' ($r.Code -eq 0 -and $ctx -and $ctx.hookEventName -eq 'SessionStart' -and $ctx.additionalContext -match 'phase: milestone-implementation') $r.Out
Check 'clear-packet-pinned' ($ctx -and $ctx.additionalContext -match '仮説自律の否定リスト' -and $ctx.additionalContext -match '再開パケット — g1' -and $ctx.additionalContext -match '承認待ち') $r.Out
Check 'clear-marker-consumed' (-not (Test-Path -LiteralPath $m1)) 'marker still there'
Check 'clear-logged' ((R (Join-Path $g1 'hook-log.md')) -match '\| RESUME \| source=clear \| chars=\d+') (R (Join-Path $g1 'hook-log.md'))
Check 'clear-full-packet-written' (Test-Path -LiteralPath (Join-Path $g1 'resume-packet.md')) 'resume-packet.md missing'

Set-Marker $g1 (Get-Date)
$r = Invoke-Hook (New-Input 'startup' $proj)
$ctx = Get-Context $r
Check 'startup-injects' ($ctx -and $ctx.additionalContext -match '再開パケット — g1' -and -not (Test-Path -LiteralPath $m1)) $r.Out

foreach ($src in @('compact', 'resume', 'fork')) {
    Set-Marker $g1 (Get-Date)
    $r = Invoke-Hook (New-Input $src $proj)
    Check "$src-silent" ($r.Code -eq 0 -and $r.Out -eq '' -and (Test-Path -LiteralPath $m1)) $r.Out
}
Remove-Item -LiteralPath $m1 -Force

$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'no-marker-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out

Set-Marker $g1 ((Get-Date).AddHours(-25))
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'stale-silent' ($r.Out -eq '') $r.Out
Check 'stale-removed' (-not (Test-Path -LiteralPath $m1)) 'stale marker kept'
Check 'stale-logged' ((R (Join-Path $g1 'hook-log.md')) -match '\| STALE \| source=clear \|') (R (Join-Path $g1 'hook-log.md'))

# A marker without "created:" falls back to its write time.
W $m1 'x'
(Get-Item -LiteralPath $m1).LastWriteTime = (Get-Date).AddHours(-30)
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'mtime-fallback-stale' ($r.Out -eq '' -and -not (Test-Path -LiteralPath $m1)) $r.Out
W $m1 'x'
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'mtime-fallback-fresh' ((Get-Context $r) -and -not (Test-Path -LiteralPath $m1)) $r.Out

# Two goals: the newest marker wins, the other stays.
Set-Marker $g2 ((Get-Date).AddHours(-2))
Set-Marker $g1 (Get-Date)
$r = Invoke-Hook (New-Input 'clear' $proj)
$ctx = Get-Context $r
Check 'newest-marker-wins' ($ctx -and $ctx.additionalContext -match '再開パケット — g1' -and $ctx.additionalContext -notmatch '再開パケット — g2') $r.Out
Check 'older-marker-kept' ((Test-Path -LiteralPath $m2) -and -not (Test-Path -LiteralPath $m1)) 'markers'
Remove-Item -LiteralPath $m2 -Force

# Only the session's cwd is scanned.
$other = Join-Path $t 'other'
New-Item -ItemType Directory -Path $other -Force | Out-Null
Set-Marker $g1 (Get-Date)
$r = Invoke-Hook (New-Input 'clear' $other)
Check 'other-cwd-silent' ($r.Out -eq '' -and (Test-Path -LiteralPath $m1)) $r.Out
Remove-Item -LiteralPath $m1 -Force

# Packet cannot be built: marker renamed, ERROR logged, nothing injected.
$g3 = Join-Path $proj 'docs\r-super-loop-powers\g3'
New-Item -ItemType Directory -Path $g3 -Force | Out-Null
Set-Marker $g3 (Get-Date)
$r = Invoke-Hook (New-Input 'clear' $proj)
Check 'error-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out
Check 'error-marker-renamed' ((Test-Path -LiteralPath (Join-Path $g3 'resume-pending.failed')) -and -not (Test-Path -LiteralPath (Join-Path $g3 'resume-pending'))) 'marker'
Check 'error-logged' ((R (Join-Path $g3 'hook-log.md')) -match '\| ERROR \| source=clear \|') (R (Join-Path $g3 'hook-log.md'))

$r = Invoke-Hook 'this is not json'
Check 'bad-stdin-open' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out
$r = Invoke-Hook (New-Input 'clear' (Join-Path $t 'nowhere'))
Check 'missing-cwd-silent' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out

$hj = Get-Content -Raw (Join-Path $root 'hooks\hooks.json') | ConvertFrom-Json
$ss = @($hj.hooks.SessionStart)[0]
Check 'hooks-json-sessionstart' ($ss.matcher -eq 'startup|clear' -and $ss.hooks[0].type -eq 'command' -and $ss.hooks[0].command -match 'resume-inject\.ps1' -and $ss.hooks[0].command -match 'CLAUDE_PLUGIN_ROOT' -and $ss.hooks[0].timeout -eq 30) ($ss | ConvertTo-Json -Depth 4)
$pt = @($hj.hooks.PostToolUse)[0]
Check 'hooks-json-posttooluse' ($pt.matcher -eq 'Agent' -and $pt.hooks[0].command -match 'context-meter\.ps1' -and $pt.hooks[0].command -match 'CLAUDE_PLUGIN_ROOT' -and $pt.hooks[0].timeout -eq 10) ($pt | ConvertTo-Json -Depth 4)
$stop = @($hj.hooks.Stop)[0].hooks[0]
Check 'hooks-json-stop-kept' ($stop.command -match 'human-message-check\.ps1' -and $stop.timeout -eq 90) ($stop | ConvertTo-Json)
foreach ($f in @('hooks\resume-inject.ps1', 'hooks\hook-common.ps1')) {
    $b = [IO.File]::ReadAllBytes((Join-Path $root $f))
    Check "bom-$f" ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) "save $f as UTF-8 with BOM"
}

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
```

- [ ] **Step 2: 失敗を確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\resume-inject.tests.ps1`
Expected: FAIL が並ぶ(フックが無い・hooks.json に SessionStart が無い)。

- [ ] **Step 3: `hooks/resume-inject.ps1` を書く**(保存後に BOM)

```powershell
#Requires -Version 5.1
<#
  resume-inject.ps1 -- SessionStart hook for r-super-loop-powers (matcher: startup|clear).

  When the orchestrator left a marker <goal-dir>/resume-pending (loop-log.ps1 -Mark) and
  the session (re)starts in that project, build the resume packet NOW from the goal's
  files (resume-packet.ps1) and hand it to Claude as additionalContext. The marker is
  used once and removed. Markers older than 24 h are discarded (STALE). If the packet
  cannot be built, the marker is renamed to resume-pending.failed and ERROR is logged;
  the orchestrator then resumes the old way (startup check 3 reads state.md).

  Fail-open: every failure exits 0 with no output. Log lines go to <goal-dir>/hook-log.md.
  Saved as UTF-8 with BOM (shared helpers match Japanese).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hook-common.ps1')

$MaxAgeHours = 24
$MaxChars = 9500

function Get-MarkerCreated($File) {
    $text = ''
    try { $text = [System.IO.File]::ReadAllText($File.FullName, $Utf8) } catch { }
    $m = [regex]::Match($text, '(?m)^created:\s*(\S+)')
    if ($m.Success) {
        try { return [datetime]::Parse($m.Groups[1].Value, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch { }
    }
    return $File.LastWriteTime
}

try { $hookInput = Read-StdinUtf8 | ConvertFrom-Json } catch { exit 0 }
if (-not $hookInput) { exit 0 }
$source = [string]$hookInput.source
if (@('startup', 'clear') -notcontains $source) { exit 0 }
$cwd = [string]$hookInput.cwd
if (-not $cwd) { $cwd = (Get-Location).Path }
$root = Join-Path $cwd 'docs\r-super-loop-powers'
if (-not (Test-Path -LiteralPath $root)) { exit 0 }

$markers = @(Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
        Get-Item -LiteralPath (Join-Path $_.FullName 'resume-pending') -ErrorAction SilentlyContinue } | Where-Object { $_ })
if ($markers.Count -eq 0) { exit 0 }

$now = Get-Date
$valid = @()
foreach ($mk in $markers) {
    $created = Get-MarkerCreated $mk
    if (($now - $created).TotalHours -gt $MaxAgeHours) {
        Remove-Item -LiteralPath $mk.FullName -Force -ErrorAction SilentlyContinue
        Write-HookLogLine $mk.DirectoryName 'STALE' "source=$source" ('marker created ' + $created.ToString('s') + ' discarded')
        continue
    }
    $valid += [pscustomobject]@{ File = $mk; Created = $created }
}
if ($valid.Count -eq 0) { exit 0 }
$pick = $valid | Sort-Object Created | Select-Object -Last 1
$goalDir = $pick.File.DirectoryName

$packetScript = Join-Path $PSScriptRoot '..\skills\r-super-loop-powers\bin\resume-packet.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('rslp-resume-' + [guid]::NewGuid().ToString('N') + '.md')
try {
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = 'powershell' }
    $out = & $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $packetScript -GoalDir $goalDir -OutFile $tmp -MaxChars $MaxChars 2>&1 | Out-String
    $code = $LASTEXITCODE
    $packet = ''
    if ($code -eq 0 -and (Test-Path -LiteralPath $tmp)) { $packet = [System.IO.File]::ReadAllText($tmp, $Utf8) }
    if (-not $packet.Trim()) { throw "resume-packet.ps1 exited $code : $($out.Trim())" }
    if ($packet.Length -gt $MaxChars) { $packet = $packet.Substring(0, $MaxChars) }
    Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $packet } }
    Remove-Item -LiteralPath $pick.File.FullName -Force -ErrorAction SilentlyContinue
    Write-HookLogLine $goalDir 'RESUME' "source=$source" "chars=$($packet.Length)"
} catch {
    try { Move-Item -LiteralPath $pick.File.FullName -Destination ($pick.File.FullName + '.failed') -Force } catch { }
    Write-HookLogLine $goalDir 'ERROR' "source=$source" $_.Exception.Message
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
exit 0
```

- [ ] **Step 4: `hooks/hooks.json` を書き換える**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/resume-inject.ps1\"",
            "timeout": 30
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/context-meter.ps1\"",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/hooks/human-message-check.ps1\"",
            "timeout": 90
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: テストが通ることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\resume-inject.tests.ps1`
Expected: `ALL PASS`。続けて `tests\human-message-check.tests.ps1` も `ALL PASS`(hooks.json の Stop 判定 `hooks-json-stop` が `@($hj.hooks.Stop)[0]` を見るので、順序が変わっても通る)。

- [ ] **Step 6: コミット**

```bash
git add hooks/resume-inject.ps1 hooks/hooks.json tests/resume-inject.tests.ps1
git commit -m "feat: /clear 後に再開パケットを一回限り注入する SessionStart フック"
```

---

### Task 5: 文脈メーター `hooks/context-meter.ps1`

**Files:**
- Create: `hooks/context-meter.ps1`(UTF-8 BOM 付き)
- Test: `tests/context-meter.tests.ps1`(UTF-8 BOM 付き)

**Interfaces:**
- Consumes: Task 1 の hook-common(`Find-GoalDir` / `Write-HookLogLine` / `Write-HookJson`)。Task 4 で hooks.json に登録済み
- Produces: stdin = PostToolUse JSON(`cwd` / `transcript_path` / `tool_name`)。stdout = しきい値以上のときだけ `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[r-super-loop-powers] 現在の文脈は約 N 万トークンで、境界リセットの目安(20 万)を超えている。…"}}`。hook-log に `CTX | tokens=<n> | tool=<name>`。環境変数 `RSLP_CTX_THRESHOLD`(既定 200000)、`RSLP_HOOK_CHILD=1` で素通り

- [ ] **Step 1: 失敗するテストを書く**

`tests/context-meter.tests.ps1`(保存後に BOM):

```powershell
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
function R([string]$Path) { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path, $utf8) } return '' }
function Assistant-Line([int64]$Ctx) {
    $cc = [int64]($Ctx / 2); $cr = $Ctx - $cc - 5
    return '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"x"}],"usage":{"input_tokens":5,"cache_creation_input_tokens":' + $cc + ',"cache_read_input_tokens":' + $cr + ',"output_tokens":10,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1}}},"timestamp":"t"}'
}
function New-Transcript([string]$Path, [int64[]]$Ctx, [string]$Tail = '') {
    $lines = @('{"type":"user","message":{"role":"user","content":"hi"}}')
    foreach ($c in $Ctx) { $lines += (Assistant-Line $c) }
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
Check 'below-logged' ((R $log) -match '\| CTX \| tokens=120000 \| tool=Agent') (R $log)

New-Transcript $tr @(50000, 250000)
$r = Invoke-Meter (New-Input $proj $tr) $low
$ctx = Get-Context $r
Check 'over-notifies' ($ctx -and $ctx.hookEventName -eq 'PostToolUse' -and $ctx.additionalContext -match '約 25 万トークン' -and $ctx.additionalContext -match '境界リセット' -and $ctx.additionalContext -match '20 万') $r.Out
Check 'over-logged' ((R $log) -match 'tokens=250000') (R $log)

# The last line is being written (no closing brace): use the previous complete one.
New-Transcript $tr @(50000, 150000) '{"type":"assistant","message":{"usage":{"input_tokens":999999,"cache_creation_input_tokens":'
$r = Invoke-Meter (New-Input $proj $tr) $low
Check 'partial-line-skipped' ($r.Out -eq '' -and (R $log) -match 'tokens=150000' -and (R $log) -notmatch '999999') (R $log)

$before = @((R $log) -split "`n").Count
W $tr ('{"type":"user","message":{"content":"x"}}' + "`n")
$r = Invoke-Meter (New-Input $proj $tr) $low
Check 'no-usage-silent' ($r.Code -eq 0 -and $r.Out -eq '' -and @((R $log) -split "`n").Count -eq $before) $r.Out

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
Check 'default-threshold-at' ((Get-Context $r) -ne $null) $r.Out

# Big transcript: only the tail is read, and the newest usage still wins.
$junk = (1..400 | ForEach-Object { '{"type":"user","message":{"content":"' + ('j' * 2000) + '"}}' }) -join "`n"
W $tr ($junk + "`n" + (Assistant-Line 210000) + "`n")
$r = Invoke-Meter (New-Input $proj $tr) $low
Check 'tail-read-finds-usage' ((Get-Context $r) -and (R $log) -match 'tokens=210000') $r.Out

$r = Invoke-Meter 'not json' $low
Check 'bad-stdin-open' ($r.Code -eq 0 -and $r.Out -eq '') $r.Out

$b = [IO.File]::ReadAllBytes($hook)
Check 'hook-has-bom' ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'save context-meter.ps1 as UTF-8 with BOM'

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
```

- [ ] **Step 2: 失敗を確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\context-meter.tests.ps1`
Expected: FAIL が並ぶ(フックが無い)。

- [ ] **Step 3: `hooks/context-meter.ps1` を書く**(保存後に BOM)

```powershell
#Requires -Version 5.1
<#
  context-meter.ps1 -- PostToolUse hook (matcher: Agent) for r-super-loop-powers.

  The orchestrator cannot see its own context size, but the transcript can: the
  last assistant line's usage (input + cache_creation + cache_read) is the context
  of the latest request. While a goal loop is active, record it in hook-log.md and,
  at or above the threshold, tell Claude (as a fact) that the boundary-reset guideline
  is exceeded. Only the tail of the transcript is read.

  Env:
    RSLP_CTX_THRESHOLD   tokens (default 200000); test seam
    RSLP_HOOK_CHILD=1    skip (judge sessions)
  Fail-open: every failure exits 0 with no output.
  Saved as UTF-8 with BOM (the notice is Japanese).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hook-common.ps1')

$Threshold = 200000
if ($env:RSLP_CTX_THRESHOLD) { [void][int]::TryParse($env:RSLP_CTX_THRESHOLD, [ref]$Threshold) }
$TailBytes = 512 * 1024

function Get-ContextTokens([string]$Path) {
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try {
        $len = $fs.Length
        $start = [Math]::Max(0, $len - $TailBytes)
        [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] ([int]($len - $start))
        $got = 0
        while ($got -lt $buf.Length) {
            $n = $fs.Read($buf, $got, $buf.Length - $got)
            if ($n -le 0) { break }
            $got += $n
        }
        $text = $Utf8.GetString($buf, 0, $got)
    } finally { $fs.Dispose() }
    $lines = $text -split "`n"
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i].TrimEnd()
        if (-not $line.EndsWith('}')) { continue }          # a line still being written
        if ($line.IndexOf('"assistant"') -lt 0) { continue }
        $u = $line.IndexOf('"usage"')
        if ($u -lt 0) { continue }
        $chunk = $line.Substring($u, [Math]::Min(1000, $line.Length - $u))
        $sum = [int64]0
        foreach ($k in @('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens')) {
            $m = [regex]::Match($chunk, '"' + $k + '"\s*:\s*(\d+)')
            if ($m.Success) { $sum += [int64]$m.Groups[1].Value }
        }
        if ($sum -gt 0) { return $sum }
    }
    return [int64]0
}

if ($env:RSLP_HOOK_CHILD -eq '1') { exit 0 }
try { $hookInput = Read-StdinUtf8 | ConvertFrom-Json } catch { exit 0 }
if (-not $hookInput) { exit 0 }
$cwd = [string]$hookInput.cwd
if (-not $cwd) { $cwd = (Get-Location).Path }
$goalDir = $null
try { $goalDir = Find-GoalDir $cwd } catch { exit 0 }
if (-not $goalDir) { exit 0 }
$transcript = [string]$hookInput.transcript_path
if (-not $transcript -or -not (Test-Path -LiteralPath $transcript)) { exit 0 }

$tokens = [int64]0
try { $tokens = Get-ContextTokens $transcript } catch { exit 0 }
if ($tokens -le 0) { exit 0 }
$tool = [string]$hookInput.tool_name
Write-HookLogLine $goalDir 'CTX' "tokens=$tokens" "tool=$tool"
if ($tokens -ge $Threshold) {
    $man = [Math]::Round($tokens / 10000.0)
    $guide = [Math]::Round($Threshold / 10000.0)
    $msg = "[r-super-loop-powers] 現在の文脈は約 $man 万トークンで、境界リセットの目安($guide 万)を超えている。次の境界(B-6 PASS の中間クローズ後 / Checkpoint ACCEPT の確定処理後 / A-8 承認後 / 人間待ち)で SKILL.md「境界リセット」の手順を行う。"
    Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } }
}
exit 0
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\context-meter.tests.ps1`
Expected: `ALL PASS`

- [ ] **Step 5: コミット**

```bash
git add hooks/context-meter.ps1 tests/context-meter.tests.ps1
git commit -m "feat: Agent 呼び出し後に文脈サイズを記録し、目安超えを知らせる PostToolUse フック"
```

---

### Task 6: `impl-check.ps1 -Prepare / -SaveReport`

**Files:**
- Modify: `skills/r-super-loop-powers/bin/impl-check.ps1`(param 追加、スナップショット行の関数化、2 モード追加)
- Test: `tests/impl-check.tests.ps1`(末尾の `if ($script:failures …` の直前に追加。先頭に `$OutputEncoding` の設定を追加)

**Interfaces:**
- Produces: `impl-check.ps1 -Prepare -Label <l> -GoalDir <dir> -WorkDir <repo>` → `BASE_REF:` / `SNAPSHOT:` / `DIRTY_PATHS:` / `STATUS: OK`(同ラベルの `.report.md` があれば `STATUS: REFUSED` で exit 1)。`impl-check.ps1 -SaveReport -Label <l> -GoalDir <dir> -WorkDir <repo>`(報告は stdin)→ `SAVED:` + 従来の判定出力。`.base.txt` が無ければ `MALFORMED`

- [ ] **Step 1: 失敗するテストを足す**

`tests/impl-check.tests.ps1` の先頭 `$fence = '`' * 3` の直後に:

```powershell
$utf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $utf8
[Console]::OutputEncoding = $utf8
```

末尾の `if ($script:failures -gt 0)` の直前に:

```powershell
# v0.9: -Prepare writes base + pre in one call; -SaveReport takes the report on stdin.
function Invoke-Prepare($Repo, [string]$Goal, [string]$Label) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Prepare -Label $Label -GoalDir $Goal -WorkDir $Repo 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
function Invoke-Save($Repo, [string]$Goal, [string]$Label, [string]$ReportText) {
    $out = $ReportText | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -SaveReport -Label $Label -GoalDir $Goal -WorkDir $Repo 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
$r = New-Repo; $b = Get-Head $r
$goal = Join-Path $r 'docs\r-super-loop-powers\g'
New-Item -ItemType Directory -Path $goal -Force | Out-Null
Set-Change $r 'old.txt'
$p = Invoke-Prepare $r $goal 'm1-impl'
Check 'prepare-ok' ($p.Code -eq 0 -and $p.Out -match '(?m)^STATUS: OK' -and $p.Out -match '(?m)^BASE_REF: [0-9a-f]{40}' -and $p.Out -match '(?m)^DIRTY_PATHS: 1') $p.Out
Check 'prepare-base-file' (((Get-Content -Raw (Join-Path $goal 'impl-runs\m1-impl.base.txt')).Trim()) -eq $b) 'base.txt'
Check 'prepare-pre-file' ((Get-Content -Raw (Join-Path $goal 'impl-runs\m1-impl.pre.txt')) -match "(?m)^old\.txt\t[0-9a-f]{40}") 'pre.txt'
Set-Change $r 'new.txt'
$report = New-Report @{ changed_files = @('new.txt'); summary = "日本語の要約 | with pipe`r`nsecond line" }
$s = Invoke-Save $r $goal 'm1-impl' $report
Check 'save-ok' ($s.Code -eq 0 -and $s.Out -match '(?m)^STATUS: OK' -and $s.Out -match '(?m)^SAVED: .*m1-impl\.report\.md') $s.Out
$saved = [IO.File]::ReadAllText((Join-Path $goal 'impl-runs\m1-impl.report.md'), $utf8)
Check 'save-verbatim' ($saved.TrimEnd() -eq $report.TrimEnd()) "saved:`n$saved"
Check 'save-uses-prepare-files' ($s.Out -match '(?m)^PREEXISTING_UNCHANGED: old\.txt' -and $s.Out -match '(?m)^CHANGED_FILES_ACTUAL: new\.txt\s*$') $s.Out
$p2 = Invoke-Prepare $r $goal 'm1-impl'
Check 'prepare-refuses-label-reuse' ($p2.Code -ne 0 -and $p2.Out -match '(?m)^STATUS: REFUSED') $p2.Out
$null = Invoke-Prepare $r $goal 'm1-impl-2'
$s2 = Invoke-Save $r $goal 'm1-impl-2' 'not json at all'
Check 'save-malformed-still-saved' ($s2.Code -ne 0 -and $s2.Out -match '(?m)^STATUS: MALFORMED' -and (Get-Content -Raw (Join-Path $goal 'impl-runs\m1-impl-2.report.md')) -match 'not json at all') $s2.Out
$s3 = Invoke-Save $r $goal 'm9-impl' $report
Check 'save-without-prepare' ($s3.Code -ne 0 -and $s3.Out -match '(?m)^STATUS: MALFORMED' -and $s3.Out -match 'no base ref' -and $s3.Out -match '(?m)^NEXT: .*-Prepare') $s3.Out
$null = Invoke-Prepare $r $goal 'm1-impl-3'
$s4 = Invoke-Save $r $goal 'm1-impl-3' ''
Check 'save-empty-stdin' ($s4.Code -ne 0 -and $s4.Out -match '(?m)^STATUS: MALFORMED') $s4.Out
$out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Prepare -WorkDir $r 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Write-Output 'PASS prepare-needs-label' } else { Write-Output "FAIL prepare-needs-label`n$out"; $script:failures++ }
$empty = Join-Path ([IO.Path]::GetTempPath()) ('implcheck-empty-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $empty | Out-Null
git -C $empty init -q 2>$null
$p5 = Invoke-Prepare $empty (Join-Path $empty 'docs\r-super-loop-powers\g') 'm1-impl'
Check 'prepare-needs-commit' ($p5.Code -ne 0) $p5.Out
```

- [ ] **Step 2: 失敗を確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\impl-check.tests.ps1`
Expected: 既存ケースは PASS のまま、`prepare-ok` 以降が FAIL。

- [ ] **Step 3: `impl-check.ps1` を変更する**

(a) ヘッダコメントの `-Snapshot` 説明の後に追加:

```
  -Prepare -Label <l> -GoalDir <dir> -WorkDir <repo>
    Before the delegation: writes impl-runs/<l>.base.txt (HEAD) and <l>.pre.txt
    (the -Snapshot lines) in one call. Refuses a label that already has a report.
  -SaveReport -Label <l> -GoalDir <dir> -WorkDir <repo>   (report text on stdin)
    After the delegation: saves stdin verbatim as impl-runs/<l>.report.md, then
    judges it with the base/pre files of that label.
```

(b) param に追加(`[string]$OutFile` の後):

```powershell
    [switch]$Prepare,
    [switch]$SaveReport,
    [string]$Label,
    [string]$GoalDir
```

(c) `function Test-Ignored` の後に関数を足す:

```powershell
function Get-SnapshotLines {
    $lines = @()
    foreach ($p in @(Get-DirtyPath)) { $lines += ($p + "`t" + (Get-PathFingerprint $p)) }
    return $lines
}
function Write-SnapshotFile([string]$Path, [string[]]$Lines) {
    $outDir = Split-Path -Parent $Path
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $body = ''
    if ($Lines.Count -gt 0) { $body = ($Lines -join "`n") + "`n" }
    Write-TextFile $Path $body
}
```

(d) snapshot モードの本体を関数で書き直す(`$lines = @()` から `Write-TextFile $OutFile $body` までを置き換え):

```powershell
    $lines = @(Get-SnapshotLines)
    Write-SnapshotFile $OutFile $lines
```

(e) snapshot モードのブロックの直後、`if (-not $ReportFile) { throw ... }` の**前**に追加:

```powershell
# --- prepare / save-report modes (label-based paths under <goal-dir>/impl-runs) -----
if ($Prepare -or $SaveReport) {
    if (-not $Label) { throw '-Prepare / -SaveReport need -Label <label>.' }
    if (-not $GoalDir) { throw '-Prepare / -SaveReport need -GoalDir <goal-dir>.' }
    if ($Label -notmatch '^[A-Za-z0-9._-]+$') { throw "Label must be [A-Za-z0-9._-]+ (got: $Label)" }
    $implDir = Join-Path $GoalDir 'impl-runs'
    $baseFile = Join-Path $implDir "$Label.base.txt"
    $preFile = Join-Path $implDir "$Label.pre.txt"
    $reportPath = Join-Path $implDir "$Label.report.md"
}
if ($Prepare) {
    if (Test-Path -LiteralPath $reportPath) {
        Write-Kv 'STATUS' 'REFUSED'
        Write-Kv 'REASON' "label '$Label' already has a report: $reportPath"
        Write-Kv 'NEXT' 'Use a new label (m<n>-impl-2, -3, ...); never reuse one.'
        exit 1
    }
    $top = (@(Invoke-Git @('rev-parse', '--show-toplevel')) -join '').Trim()
    if (-not $top) { throw "WorkDir is not a git repository: $WorkDir" }
    $head = (@(Invoke-Git @('rev-parse', 'HEAD')) -join '').Trim()
    if (-not $head) { throw "WorkDir has no commit yet: $WorkDir (git init + first commit first; SKILL.md startup check 8)" }
    if (-not (Test-Path -LiteralPath $implDir)) { New-Item -ItemType Directory -Path $implDir -Force | Out-Null }
    Write-TextFile $baseFile ($head + "`n")
    $lines = @(Get-SnapshotLines)
    Write-SnapshotFile $preFile $lines
    Write-Kv 'BASE_REF' $head
    Write-Kv 'SNAPSHOT' $preFile
    Write-Kv 'DIRTY_PATHS' $lines.Count
    Write-Kv 'STATUS' 'OK'
    exit 0
}
if ($SaveReport) {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false)))
    $stdinText = $reader.ReadToEnd()
    if (-not (Test-Path -LiteralPath $implDir)) { New-Item -ItemType Directory -Path $implDir -Force | Out-Null }
    Write-TextFile $reportPath $stdinText
    Write-Kv 'SAVED' $reportPath
    $ReportFile = $reportPath
    if (-not (Test-Path -LiteralPath $baseFile)) {
        Write-Kv 'REPORT_FILE' $ReportFile
        Complete-Check 'MALFORMED' "no base ref for label '$Label' ($baseFile)" "Run impl-check.ps1 -Prepare -Label $Label before delegating; then judge again."
    }
    $BaseRef = (Read-TextFile $baseFile).Trim()
    if (Test-Path -LiteralPath $preFile) { $PreexistingFile = $preFile }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\impl-check.tests.ps1`
Expected: `ALL PASS`

- [ ] **Step 5: コミット**

```bash
git add skills/r-super-loop-powers/bin/impl-check.ps1 tests/impl-check.tests.ps1
git commit -m "feat: impl-check に委譲前の -Prepare と報告の保存・判定 -SaveReport を足す"
```

---

### Task 7: codex のプロンプト上限とグラレコ effort(F)

**Files:**
- Modify: `skills/r-super-loop-powers/bin/codex-run.ps1`(effort 既定・WARN・grareco brief)
- Modify: `skills/r-super-loop-powers/policy.md`(責任分担表の画像生成行: `medium` → `low`)
- Modify: `skills/r-super-loop-powers/references/codex-invocation.md`(2-2 の effort 既定)
- Test: `tests/codex-run.tests.ps1`

**Interfaces:**
- Produces: grareco の既定 effort `low`。本文 40,960 バイト超で `WARN: prompt is <N> KB (> 40 KB); pass long documents by path and let codex read them.`。grareco brief は `Do not read the imagegen system skill` と `call image_gen directly` と `NO_IMAGE_GENERATED` を含む

- [ ] **Step 1: テストを変える・足す**

`tests/codex-run.tests.ps1`:
(a) `Invoke-Run` を `function Invoke-Run([string]$EnvFile, [string]$Label, [string[]]$Extra, [string]$PromptPath = $prompt)` にし、本体の `'-PromptFile', $prompt` を `'-PromptFile', $PromptPath` にする。
(b) `Check 'grareco-read-only-medium' (... -and $m.effort -eq 'medium') $r.Out` → `Check 'grareco-read-only-low' (... -and $m.effort -eq 'low') $r.Out`。
(c) クリーンアップ行の直前に追加:

```powershell
# v0.9 (F): long prompts warn; grareco calls image_gen without reading the imagegen skill first.
$longPrompt = Join-Path $t 'long.md'
[IO.File]::WriteAllText($longPrompt, ('x' * 41000))
$r = Invoke-Run $env1 'lp' @('-Role', 'techpm') $longPrompt
Check 'long-prompt-warns' ($r.Code -eq 0 -and $r.Out -match '(?m)^WARN: prompt is \d+ KB') $r.Out
$r = Invoke-Run $env1 'sp' @('-Role', 'techpm')
Check 'short-prompt-no-warn' ($r.Out -notmatch '(?m)^WARN: prompt is') $r.Out
Check 'grareco-skips-skill-read' ($grPrompt -match 'Do not read the imagegen system skill' -and $grPrompt -match 'call image_gen directly' -and $grPrompt -match 'NO_IMAGE_GENERATED') 'grareco brief'
```

- [ ] **Step 2: 失敗を確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\codex-run.tests.ps1`
Expected: `grareco-read-only-low` / `long-prompt-warns` / `grareco-skips-skill-read` が FAIL。

- [ ] **Step 3: `codex-run.ps1` を変更する**

(a) `if ($Role -eq 'grareco') { $Effort = 'medium' } else { $Effort = 'max' }` → `'low'`。param コメント `grareco: medium` → `grareco: low`。
(b) `$warnings = @()` の直後(`$normalizedPrompt = ...` の前)に:

```powershell
# A 300 KB prompt was measured once (hearing-log + spec + plan pasted whole). codex is
# read-only but can READ: pass documents by path instead of pasting them.
$promptBytes = [System.Text.Encoding]::UTF8.GetByteCount($rawPrompt)
if ($promptBytes -gt 40960) {
    $warnings += ("prompt is {0} KB (> 40 KB); pass long documents by path and let codex read them." -f [int][Math]::Ceiling($promptBytes / 1024.0))
}
```

(c) `$RoleBriefs.grareco` のコメントと本文を置き換える:

```powershell
    # image_gen is a built-in tool. Its system skill (~/.codex/skills/.system/imagegen/
    # SKILL.md) costs 15 round trips per run when read first (survey 2026-10-10), so the
    # brief says to call the tool directly; reading that one SKILL.md stays allowed only
    # if the tool refuses to run without it (v0.8.1 lesson: two runs ended with no image).
    grareco = @'
== ROLE: GRAPHIC RECORDER ==
Read only the input file named in the task. Generate the image with your built-in
image_gen tool and do not try to save or copy it anywhere -- the orchestrator
collects it.
Do not read the imagegen system skill (SKILL.md under ~/.codex/skills/.system/imagegen/)
first: call image_gen directly. EXCEPTION to contract item 1, only if the tool refuses
to run without it: you MAY read that one SKILL.md. Nothing else under skills/,
SKILL.md, ~/.codex/ or ~/.claude/.
If you did not actually call image_gen (or it failed), your final message MUST
start with "NO_IMAGE_GENERATED:" and the reason. Never say an image was made
unless image_gen returned one; the orchestrator checks for the file.
== END ROLE ==

'@
```

(d) `policy.md` 責任分担表: `| 画像生成(Codex組み込み image_gen ツール) | Codex `gpt-6.1-sol` / `medium` / read-only(`-Role grareco`) |` の `medium` → `low`。
(e) `references/codex-invocation.md` 2-2: `effort の既定は techpm / reviewer = `max`、grareco = `medium`` → `low`。

- [ ] **Step 4: テストが通ることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\codex-run.tests.ps1`
Expected: `ALL PASS`

- [ ] **Step 5: コミット**

```bash
git add skills/r-super-loop-powers/bin/codex-run.ps1 skills/r-super-loop-powers/policy.md skills/r-super-loop-powers/references/codex-invocation.md tests/codex-run.tests.ps1
git commit -m "feat: codex の長いプロンプトに警告し、グラレコを effort low・image_gen 直接呼びにする"
```

---

### Task 8: 実装役の読取例外(D64)

**Files:**
- Modify: `agents/builder.md:54`(実行契約 1)
- Test: `tests/roles-sync.tests.ps1`(変更なし。マーカー区間の外の変更なので通る)

- [ ] **Step 1: 実行契約 1 を置き換える**

```markdown
1. **スコープ**: 作業ディレクトリ内の、`## SCOPE` で許された範囲だけを変更する。`~/.claude/`・`.claude/`・`~/.codex/`・`.codex/`・`~/.agents/`・`docs/r-super-loop-powers/` は読み書きしない(オーケストレーターの領域)。それらの配下にあるエージェント用スキルファイル(`SKILL.md` など)を読んだり使ったりしない。対象プロジェクト自身の `skills/` や `SKILL.md` は、SCOPE で許されていれば通常のファイルとして扱ってよい。**読み取りだけの例外**: `docs/r-super-loop-powers/*/impl-runs/*.prompt.md`(あなたへの依頼文)と `docs/r-super-loop-powers/*/tech-assessment.md`(技術PMのアセス)は読んでよい(書かない)。依頼文にファイルのパスが示されたら、まずそのファイルを**全部**読んでから作業する。`## 再委譲の差分` が示されたら、初回の依頼文も読んだうえで差分を優先する。
```

- [ ] **Step 2: 回帰**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\roles-sync.tests.ps1`
Expected: `ALL PASS`

- [ ] **Step 3: コミット**

```bash
git add agents/builder.md
git commit -m "feat: 実装役に依頼文と技術アセスの読取だけを許す"
```

---

### Task 9: SKILL.md の分割と手順の更新(H・A′・B・C・E・I)

**Files:**
- Modify: `skills/r-super-loop-powers/SKILL.md`(共通だけを残す)
- Create: `skills/r-super-loop-powers/references/workflow-a.md`(A-0〜A-8 + 技術PM共通契約)
- Create: `skills/r-super-loop-powers/references/workflow-b.md`(B-1〜B-10 + Learning)
- Test: `tests/skill-layout.tests.ps1`(UTF-8 BOM 付き)

**Interfaces:**
- Consumes: Task 2〜8 のスクリプト名・パラメータ・見出し(`# 再開パケット — <slug>`、`resume-pending`、`loop-log.ps1 -Set*`、`impl-check.ps1 -Prepare / -SaveReport`、`## 再委譲の差分`)
- Produces: 3 ファイル。見出しの契約: SKILL.md に `## 起動時チェック` / `## 記録ルール` / `## 境界リセット` / `## Fableサブエージェント共通契約` / `## 読むものと読まないもの`。workflow-a.md に `## 技術PM(Codex)共通契約` と `**A-0 ` 〜 `**A-8 `。workflow-b.md に `**B-1 ` 〜 `**B-10 ` と `## Learning フェーズ`

- [ ] **Step 1: 失敗するテストを書く**

`tests/skill-layout.tests.ps1`(保存後に BOM):

```powershell
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
function R([string]$Path) { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path, $utf8) } return '' }
$skillFile = Join-Path $skillDir 'SKILL.md'
$s = R $skillFile
$a = R (Join-Path $skillDir 'references\workflow-a.md')
$b = R (Join-Path $skillDir 'references\workflow-b.md')

Check 'workflow-files-exist' ($a -ne '' -and $b -ne '') 'references/workflow-a.md / workflow-b.md missing'
Check 'skill-size' ((Get-Item -LiteralPath $skillFile).Length -le 24KB) ("SKILL.md is " + (Get-Item -LiteralPath $skillFile).Length + " bytes")
Check 'skill-points-to-workflows' ($s -match 'references/workflow-a\.md' -and $s -match 'references/workflow-b\.md') 'workflow references'
Check 'skill-common-sections' ($s -match '(?m)^## 起動時チェック' -and $s -match '(?m)^## 記録ルール' -and $s -match '(?m)^## 境界リセット' -and $s -match '(?m)^## Fableサブエージェント共通契約' -and $s -match '(?m)^## 読むものと読まないもの') 'common sections'
Check 'skill-mentions-tools' ($s -match 'loop-log\.ps1' -and $s -match 'resume-packet\.ps1' -and $s -match 'resume-pending' -and $s -match 'context-meter\.ps1' -and $s -match '再開パケット') 'tool names'
Check 'skill-recitation' ($s -match '復唱') 'recitation rule'
Check 'skill-roles-jit' ($s -match 'roles\.md' -and $s -notmatch 'policy\.md` と `references/roles\.md`(ロール憲章)を読む') 'roles.md must be read just in time'
Check 'skill-failures-only' ($s -match 'FAIL\|ALL PASS') 'shell results: failures only'
Check 'skill-no-image-read' ($s -match 'SendUserFile') 'image rule'
foreach ($step in @('A-0', 'A-1a', 'A-1b', 'A-5', 'A-6', 'A-7', 'A-8')) {
    Check "a-$step-in-workflow-a" ($a -match ('(?m)^\*\*' + [regex]::Escape($step) + ' ')) "$step missing in workflow-a"
    Check "a-$step-not-in-skill" ($s -notmatch ('(?m)^\*\*' + [regex]::Escape($step) + ' ')) "$step still in SKILL.md"
}
Check 'a-2-4-in-workflow-a' ($a -match '(?m)^\*\*A-2') 'A-2〜A-4 missing'
Check 'techpm-contract-in-a' ($a -match '(?m)^## 技術PM(Codex)共通契約' -and $s -notmatch '(?m)^## 技術PM(Codex)共通契約') 'techpm contract placement'
Check 'a-techpm-paths' ($a -match '40 KB' -and $a -match 'パスで渡') 'techpm prompt by path'
foreach ($step in @('B-1', 'B-2', 'B-3', 'B-4', 'B-5', 'B-6', 'B-7', 'B-8', 'B-9', 'B-10')) {
    Check "b-$step-in-workflow-b" ($b -match ('(?m)^\*\*' + [regex]::Escape($step) + ' ')) "$step missing in workflow-b"
    Check "b-$step-not-in-skill" ($s -notmatch ('(?m)^\*\*' + [regex]::Escape($step) + ' ')) "$step still in SKILL.md"
}
Check 'learning-in-b' ($b -match '(?m)^## Learning' -and $s -notmatch '(?m)^## Learning') 'Learning placement'
Check 'b2-prepare-save' ($b -match '-Prepare' -and $b -match '-SaveReport' -and $b -match '## 再委譲の差分' -and $b -match '\.prompt\.md にある') 'B-2 delegation wording'
Check 'b-grareco-low' ($b -match 'effort `low`') 'grareco effort'
Check 'b-retro-ctx' ($b -match 'CTX' -and $b -match 'RESUME') 'retro observation'
Check 'boundary-list' ($s -match '人間待ち' -and $s -match 'B-6 PASS' -and $s -match 'ACCEPT' -and $s -match 'A-8' -and $s -match '/clear') 'boundary rule'
Check 'policy-grareco-low' ((R (Join-Path $skillDir 'policy.md')) -match '`low` / read-only\(`-Role grareco`\)') 'policy.md grareco effort'
Check 'builder-read-exception' ((R (Join-Path $root 'agents\builder.md')) -match 'impl-runs/\*\.prompt\.md' -and (R (Join-Path $root 'agents\builder.md')) -match 'tech-assessment\.md') 'builder exception'
$ver = (Get-Content -Raw (Join-Path $root '.claude-plugin\plugin.json') | ConvertFrom-Json).version
Check 'version-0.9.0' ($ver -eq '0.9.0') "version=$ver"
& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\sync-templates.ps1') -Mode Verify | Out-Null
Check 'templates-in-sync' ($LASTEXITCODE -eq 0) 'sync-templates Verify failed'
& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\sync-roles.ps1') -Mode Verify | Out-Null
Check 'roles-in-sync' ($LASTEXITCODE -eq 0) 'sync-roles Verify failed'

if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
```

- [ ] **Step 2: 失敗を確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\skill-layout.tests.ps1`
Expected: `workflow-files-exist` 以下が FAIL(`version-0.9.0` は Task 10 まで FAIL のまま)。

- [ ] **Step 3: `references/workflow-a.md` を作る**

冒頭:

```markdown
# ワークフローA: Goal Definition(A-0〜A-8)

SKILL.md(共通)の起動時チェック 9 から読まれる。state.md の phase が `goal-definition` の間(新規ゴールを含む)だけ使う。共通の規則(起動時チェック・ディレクトリ契約・記帳・ゲート保護・Fable 共通契約・境界リセット・読むもの)は SKILL.md にある。この区間は代理Fable(SendMessage 継続)が生きているので、A-8 の承認まで境界リセットをしない。
```

続けて、現行 SKILL.md の `## 技術PM(Codex)共通契約` 節(見出しから `- 呼び出しごとに call-log へ記録(codex-techpm)。` まで)を**原文のまま**移し、次の 3 点だけ直す:
  - プロンプト必須要素 2: `goal-frame.md 全文 + hearing-log.md の関連部分 + (2ラウンド目以降)前ラウンドまでのQ&A要約` → `goal-frame.md 全文(貼る)。hearing-log.md・spec・plan は**貼らずにパスで渡し**(codex は read-only で読める)、関連する節名を示す。(2ラウンド目以降)前ラウンドの回答は `codex-runs/<前ラベル>.last.txt` のパスで渡す。本文が 40 KB を超えると `codex-run.ps1` が `WARN: prompt is N KB` を出す(全文貼りで 300 KB に達した実測がある)`
  - 実装アセス: `goal-frame.md + spec + plan + 主要設計判断を渡し` → `goal-frame.md を貼り、spec・plan・goal-plan.md(主要設計判断)はパスで渡し`
  - `- 呼び出しごとに call-log へ記録(codex-techpm)。` → `- 呼び出しごとに `loop-log.ps1 -Who codex-techpm` で記録する。`

続けて `## ワークフローA: Goal Definition` の見出し以下 `**A-0` 〜 `**A-8` の本文を**原文のまま**移し(`## ワークフローA` 見出し自体は `## 工程` に変える)、次だけ直す:
  - A-0: `空の call-log.md、` → `空の call-log.md(`loop-log.ps1` が作る)、`
  - A-1a 末尾 `往復ごとにcall-logへ記録(fable)。` → `往復ごとに `loop-log.ps1 -Who fable -Purpose "A-1a …"` で記録する。`
  - A-2〜A-4 末尾の `往復ごとにcall-logへ記録(fable / codex-techpm)。` → `往復ごとに `loop-log.ps1 -Who fable|codex-techpm` で記録する。`
  - A-8 末尾: `承認されたら state.md を milestone-implementation へ更新する(「次のCheckpoint」欄も記入)。` → `承認されたら **境界リセット**(SKILL.md)を行う: `loop-log.ps1 -GoalDir "<goal-dir>" -SetPhase milestone-implementation -SetMilestone "1-<名前>" -SetCheckpoint "<n>-<名前>" -SetGate impl-gate -SetWait "-" -Mark` の 1 回で state.md を更新して印を置き、人間に `/clear` と「続けて」を頼んでターンを終える。再開後に `references/workflow-b.md` を読んで B-1 へ。`

- [ ] **Step 4: `references/workflow-b.md` を作る**

冒頭:

```markdown
# ワークフローB: Milestone Implementation(B-1〜B-10)と Learning

SKILL.md(共通)の起動時チェック 9 から読まれる。state.md の phase が `milestone-implementation` / `human-acceptance` / `finalization` / `learning` のときに使う。共通の規則(起動時チェック・ディレクトリ契約・記帳・ゲート保護・Fable 共通契約・境界リセット・読むもの)は SKILL.md にある。各工程の入口(B-1・B-5・B-7・Learning)で state.md を読み直す。
```

続けて現行 SKILL.md の `## ワークフローB: Milestone Implementation(マイルストーンごとに繰り返す)` 見出し(→ `## 工程(マイルストーンごとに繰り返す)`)以下、`**B-1` 〜 `**B-10` と `## Learning フェーズ` 全体を**原文のまま**移し、次を直す:

  - B-1 末尾に `呼び出しは `loop-log.ps1 -Who fable -Purpose "B-1 <n>"` で記録する。` を足す。
  - B-2 の **(1)** を次に置き換える:

```markdown
**(1) 委譲前の基準を記録する(1 回の呼び出し)**
ラベルは `m<n>-impl`(再委譲は `m<n>-impl-2` …。高信頼でタスクごとに委譲する場合は `m<n>-t<k>-impl`)。
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" -Prepare `
  -Label "<ラベル>" -GoalDir "<goal-dir>" -WorkDir "<対象プロジェクトのルート>"
```
`BASE_REF:`(HEAD)と `SNAPSHOT:`(未コミット変更の指紋)が `impl-runs/<ラベル>.base.txt` / `.pre.txt` に書かれる。B-3 はこのスナップショットと比べて**今回の委譲で変わったものだけ**を判定に使うので、未コミット変更があっても判定は混ざらない。同じマイルストーンの未コミット変更(以前の委譲・再委譲・高信頼の先行タスクの分)は**そのまま残して**委譲する。`DIRTY_PATHS:` が 0 でないとき、`docs/r-super-loop-powers/` 以外で**このマイルストーンと無関係な**未コミット変更(このマイルストーンの過去の `impl-runs/*.report.md` の `changed_files` に無いもの)がある場合だけ、委譲前にそれをユーザーに提示し、扱い(コミット / そのまま残す等)の指示を受けてから委譲する。`STATUS: REFUSED` はラベルの再利用(同じラベルの `.report.md` がある)なので、新しいラベルにする。
```

  - B-2 の **(2)** は原文のまま(6 要素)。その直後に **(2′)** を足す:

```markdown
**(2′) 再委譲のプロンプト**
`impl-check.ps1` が `OK` 以外を返して再委譲するときは、全文を書き直さない。`<goal-dir>/impl-runs/<ラベル>-2.prompt.md`(以後 `-3` …)に次の 2 節だけを書く:
  1. `## 再委譲の差分` — impl-check の `STATUS` / `REASON` / `CRITERION_UNMET` / `WARN` の行をそのまま引用し、今回直すべき点を箇条書きにする(受け入れ条件・スコープは変えない)
  2. `## 初回の依頼` — `初回の依頼文: <goal-dir>/impl-runs/<初回ラベル>.prompt.md(先に全部読むこと。TECHNICAL ASSESSMENT・受け入れ条件・SCOPE・検証・仮定・出力契約はそこにある)`
```

  - B-2 の **(3)** を次に置き換える:

```markdown
**(3) 起動し、報告を保存して判定する**
Agentツール: `subagent_type: "r-super-loop-powers:builder"`、description `B-2 <ラベル>`。prompt には**ファイルのパスだけ**を渡す(本文を Agent の引数に二度書かない。実装役は `impl-runs/*.prompt.md` と `tech-assessment.md` を読める):
```
依頼文は <goal-dir>/impl-runs/<ラベル>.prompt.md にある。まずそのファイルを全部読み、そこに書かれた TECHNICAL ASSESSMENT・受け入れ条件・SCOPE・検証に従って作業せよ。最終メッセージは impl-report 形式の JSON を ```json フェンス 1 つで返すこと。
```
返ってきた最終メッセージを**そのまま** stdin で渡して保存し、同じ呼び出しで判定する(B-3。転記の Write と判定を 1 ターンにまとめる。整形・補完しない):
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" -SaveReport -Label "<ラベル>" -GoalDir "<goal-dir>" -WorkDir "<対象プロジェクトのルート>" <<'EOF'
<実装役の最終メッセージをそのまま貼る>
EOF
```
(PowerShell ツールから呼ぶ場合は `@'…'@ | powershell … -SaveReport …`。)`SAVED:` に `impl-runs/<ラベル>.report.md` が出る。同じシェル呼び出しの末尾で `loop-log.ps1 -Who sonnet-builder -Purpose "B-2 <ラベル>"` を続けて実行する(記帳を別ターンにしない)。
```

  - B-3 のコマンドブロックを次に置き換える(表はそのまま):

```markdown
**B-3 受け入れ判定は `impl-check.ps1` の `STATUS` で行う**
判定は (3) の `-SaveReport` の出力に含まれている。保存済みの報告を判定し直すときは:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" `
  -ReportFile "<goal-dir>\impl-runs\<ラベル>.report.md" `
  -WorkDir "<対象プロジェクトのルート>" `
  -BaseRef (Get-Content "<goal-dir>\impl-runs\<ラベル>.base.txt") `
  -PreexistingFile "<goal-dir>\impl-runs\<ラベル>.pre.txt"
```
出力は KV 形式で短い。実装役が実行したテストの生ログは読まない(報告の `verification` の要点で足りる。自分でテストを再実行するときは失敗行だけを見る: `… | Select-String -Pattern 'FAIL|ALL PASS'`)。
```

  - B-3 の表の `MALFORMED` 行の `.base.txt / .pre.txt を直して B-3 をやり直す` の前に `(`-Prepare` をやり直すか)` を足す。
  - B-4 末尾 `call-logに記録。` → ``loop-log.ps1 -Who fable` で記録する。`
  - B-5 高信頼の末尾 `call-logに記録(codex-review)。` → ``loop-log.ps1 -Who codex-review` で記録する。`
  - B-6: `結果を `gate-decision.md` に保存、call-logに記録。` → `結果を `gate-decision.md` に保存し、`loop-log.ps1 -Who fable` で記録する。`。中間クローズの文 `→ 中間コミット → state.md を次マイルストーンへ更新し、**人間承認なしで次のB-1へ**` → `→ 中間コミット → `loop-log.ps1 -SetMilestone "<次>" -SetGate impl-gate`(文脈メーターの通知「境界リセットの目安を超えている」が出ていれば `-Mark` も付けて**境界リセット**し、人間に `/clear` と「続けて」を頼む。出ていなければ)**人間承認なしで次のB-1へ**`
  - B-6 の `PASS + Checkpoint … → state.md を human-acceptance に更新し、B-7へ` → `→ `loop-log.ps1 -SetPhase human-acceptance -SetGate human-acceptance` の後、B-7 へ`
  - B-7 に 1 行足す: `受け入れテストの証拠にスクショや画像を含める場合、Opus は画像を Read せず、パスを human-report.md に書く(人間に見せるなら SendUserFile)。`
  - B-8: `ACCEPTの場合は state.md を finalization に更新する。` → `ACCEPT の場合は `loop-log.ps1 -SetPhase finalization` にする。`。人間に提示してターンを終えるときは**境界(a)**: `loop-log.ps1 -SetWait "Checkpoint <n> の受け入れテスト結果(ACCEPT / REJECT とコメント)" -Mark` を先に行い、依頼文の末尾に `/clear` と「続けて」を添える。
  - B-9 末尾 `call-logに記録。` → ``loop-log.ps1 -Who fable` で記録する。`
  - B-10: `state.md を learning へ更新する。` → ``loop-log.ps1 -SetPhase learning` にする。確定処理のあとは**境界(c)**: Learning の retro・グラレコを終えて「次へ」で state.md を更新したら `-Mark` を付け、人間に `/clear` と「続けて」を頼む(次のマイルストーンがある場合。全マイルストーン完了なら印は不要)。`
  - Learning 1(Retrospective)の観測欄の列挙 `…人間向け応答の書き直し回数(hook-log.md の BLOCK 行の数と、主な理由)` の後に `・**最大文脈**(hook-log.md の `CTX` 行の tokens の最大値)・**境界リセットの回数**(`RESUME` 行の数)` を足す。
  - Learning 2(グラレコ): `(effort `medium` が既定)` → `(effort `low` が既定)`。`グラレコ実行では codex が組み込み imagegen の SKILL.md を読むため `BOUNDARY_HIT` の `WARN:` が出るが、これは想定どおりで無視してよい。` → `v0.9 からは imagegen の SKILL.md を読まずに image_gen を直接呼ばせる(ツールが拒んだときだけ読む)。読んだ場合は `BOUNDARY_HIT` の `WARN:` が出るが想定内。` 末尾の `call-logに記録(codex-grareco)。` → ``loop-log.ps1 -Who codex-grareco` で記録する。生成した画像を Opus が Read しない(人間に見せるならパスを示す)。`
  - Learning 3(次へ): `未実装マイルストーンがあれば state.md を milestone-implementation に戻し(「次のCheckpoint」欄を更新)、B-1 から繰り返す。全マイルストーン完了なら state.md を done にし、` → `未実装マイルストーンがあれば `loop-log.ps1 -SetPhase milestone-implementation -SetMilestone "<次>" -SetCheckpoint "<次のCheckpoint>" -SetGate impl-gate -Mark` で戻し(境界(c))、人間に `/clear` と「続けて」を頼む。再開後に B-1 から繰り返す。全マイルストーン完了なら `loop-log.ps1 -SetPhase done -SetGate none` にし、`

- [ ] **Step 5: `SKILL.md` を共通だけに書き換える**

frontmatter(`name` / `description`)はそのまま。本文は次の節構成にする(既存の文を残す節は「原文のまま」、変える節は本文を示す):

1. 冒頭 3 段落: 原文のまま。ただし 2 段落目の末尾に `文脈は使い捨てにする: 正本はファイルで、境界ごとに `/clear` して再開パケットから続ける(「境界リセット」)。` を足す。
2. `## 起動時チェック(毎回必ず実行)`: 項目 2・4〜8 は原文のまま。1・3 を置き換え、9 を足す:

```markdown
1. **ポリシー読込**: このスキルと同じディレクトリの `policy.md` を読む。以後の全判断はこのポリシーに従う。`references/roles.md`(ロール憲章)は起動時には読まず、Fable への依頼文を組む直前に「全体図 (overview)」と該当ロールの節だけを読む(「Fableサブエージェント共通契約」)。自分(Opus)の憲章の要点: ゲートの合否(ゲートFable)・受け入れ(人間)・委譲の成否(impl-check / codex-status)・実装方式(技術PM)は自分では決めない。実装は実装役に委譲する。人間向けの応答はフックが検査する。
```

```markdown
3. **状態復元**:
   - **再開パケットが注入されている場合**(会話の先頭に `# 再開パケット — <goal-slug>` がある): それが state.md の正本である。Glob で探し直さない。最初の応答で「フェーズ / 強度 / マイルストーン / 次のゲート / 待ち」をパケットの state.md の文面どおりに**復唱**してから手順に入る。パケットの「未完了の委譲」に codex のラベルがあれば `codex-status.ps1` で判定し、実装役のラベルがあれば `git status` を見てから次を決める。「待ち」が人間の回答待ちなら、ユーザーの今回のメッセージをその回答として扱う。
   - **注入されていない場合**: 対象プロジェクトで `docs/r-super-loop-powers/*/state.md` を探す(Globツール)。見つかった場合: 最新の state.md を読み、同じ 5 項目を 1〜3 行でユーザーに報告し、そのフェーズの手順から再開する。見つからない場合: ワークフローA(新規ゴール)を開始する。
   - 各フェーズの入口(A-5・B-1・B-5・B-7・Learning の冒頭)でも state.md を読み直す(文脈の途中にある古い値ではなく、ファイルの値に従う)。
```

```markdown
9. **手順書の読込**: state.md の phase が `goal-definition`(または新規ゴール)なら `references/workflow-a.md` を、それ以外なら `references/workflow-b.md` を読む。**両方は読まない**(A-8 → B-1 の境では境界リセットの後に B を読む)。
```

3. `## ディレクトリ契約`: 原文のまま。ツリーの `hook-log.md` の行の下に 2 行足す:

```
├── resume-pending           # 境界リセットの印(loop-log.ps1 -Mark が置き、SessionStart フックが消す。24 時間で無効)
├── resume-packet.md         # 直近の再開パケット全文(resume-packet.ps1 が書く)
```
`hook-log.md` の説明を `人間向け応答チェック(Stop)・再開注入(RESUME/STALE/ERROR)・文脈メーター(CTX)の記録。フックが自動で追記する` にする。`### state.md フォーマット` は原文のまま。

4. `## フェーズと成果物契約`・`## 仮定台帳の運用`: 原文のまま。
5. `## 記録ルール(PL-007)` を次に置き換える:

```markdown
## 記録ルール(PL-007)と記帳スクリプト

fable / codex-techpm / codex-review / codex-grareco / sonnet-builder を呼ぶたび、および代理Fableとの SendMessage 往復のたびに、直後に `call-log.md` へ 1 行追記する。追記・state.md の更新・再開の印は、すべて `bin/loop-log.ps1` で **1 回の呼び出し**にまとめる(手で `Add-Content` や Write をしない。記帳だけのターンを増やさない):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\loop-log.ps1" -GoalDir "<goal-dir>" `
  -Who sonnet-builder -Purpose "B-2 m1-impl" `
  -SetMilestone "1-<名前>" -SetGate impl-gate -SetWait "-"
```

- `-Who <役> -Purpose <目的> [-Phase <phase>]`: call-log に `YYYY-MM-DD HH:MM | <役> | <phase> | <目的>` を追記(phase 省略時は state.md の値)
- `-SetPhase` / `-SetIntensity`(強度)/ `-SetMilestone` / `-SetCheckpoint`(次のCheckpoint)/ `-SetOwner`(担当)/ `-SetGate`(次のゲート)/ `-SetWait`(待ち)/ `-SetCodexRun`: state.md の欄を更新(`updated:` は自動)。他の欄は `-Set 'key=value'`(1 つ)
- `-Mark`: 境界リセットの印を置く(「境界リセット」)
- `STATUS: OK` を確認する。`FAILED` のときは何も書かれていない(`REASON:` を見る)
- 判定結果や実装役の報告の転記は `impl-check.ps1 -SaveReport` / `codex-status.ps1` が担う。同じ内容を 2 度書かない
```

6. `## ゲート保護ルール(絶対)`: 原文のまま。
7. `## Fableサブエージェント共通契約`: 原文のまま。ロール憲章の項の `<skill-dir>\references\roles.md` の「全体図 (overview)」節と該当ロールの節…を**原文のまま**貼り` の前に `このときだけ roles.md を開き、` を足す。
8. `## 境界リセット(/clear と再開パケット)` を新設:

```markdown
## 境界リセット(/clear と再開パケット)

長い文脈は精度を落とし(context rot)、コンパクションは制約を取りこぼす。このハーネスでは**正本はファイル、セッションは使い捨て**にする: 境界で state.md を更新し、印を置き、人間に `/clear` してもらう。`/clear` の直後に SessionStart フック(`hooks/resume-inject.ps1`)が `bin/resume-packet.ps1` で組んだ**再開パケット**(state.md 全文・待ち・否定リスト・goal-frame の制約/承認基準/終了条件・対象マイルストーン・未検証仮定・直近の判定・直近 retro の「次回変えること」・未完了の委譲)を会話の先頭に注入する。要約を挟まないので取りこぼしが構造的に起きない。フックは `/` コマンドを起こせないので、`/clear` は人間が打つ。

**境界**(ここで切る):
- (a) 人間の入力待ちに入るとき(「待ち」を書いた直後)
- (c) Checkpoint の ACCEPT を確定処理(B-10)し、Learning を終えて次のマイルストーンへ戻るとき
- (d) A-8 の Goal Plan 承認のあと(ワークフローBに入る前)
- (b) **条件付き**: B-6 PASS の中間クローズのあと。PostToolUse フック(`hooks/context-meter.ps1`)が「現在の文脈は約 N 万トークンで、境界リセットの目安(20 万)を超えている」と知らせているときだけ。知らせが無ければ切らずに次の B-1 へ進む
- **切らない区間**: 代理Fable が生きている A-1a〜A-4(SendMessage の相手はセッションを跨げない)

**手順(1 ターン)**:
1. `loop-log.ps1 -GoalDir "<goal-dir>" -SetPhase … -SetMilestone … -SetWait … -Mark`(変える欄だけ。`-Mark` が `resume-packet.md` を組んで印 `resume-pending` を置く。`MARKED:` を確認する)
2. ターンを終える。人間への文の末尾に「`/clear` のあと「続けて」と送ってください(文脈を捨てて、ファイルから再開します)」を添える。(a) では待ちの内容(質問・承認依頼)を先に書く
3. `/clear` 後の最初の応答で、起動時チェック 3 の復唱を行う

- 印は 24 時間で無効になる(その場合は従来どおり state.md から再開する)。印は `/clear` か新規起動でだけ使われ、`/compact` や `--resume` では使われない
- パケットは 9,500 文字に収まるよう後方の節(マイルストーン・仮定・判定・retro)だけが切られ、全文は `<goal-dir>/resume-packet.md` にある。制約系の節は切られない
- 人間が `/clear` せずに続けた場合もそのまま続行してよい(印は残り、次の `/clear` で使われる)
- フックの記録は `hook-log.md` の `RESUME` / `STALE` / `ERROR` / `CTX` 行
```

9. `## 人間向け応答チェック(プラグインの Stop フック)` → 見出しを `## プラグインのフック` にし、冒頭に `プラグインは 3 つのフックを持つ: SessionStart(再開パケットの注入)・PostToolUse(Agent 呼び出し後の文脈メーター)・Stop(人間向け応答チェック)。前 2 つは「境界リセット」、Stop は次のとおり。` を足し、以下原文のまま。
10. `## 読むものと読まないもの(文脈を薄く保つ)` を新設:

```markdown
## 読むものと読まないもの(文脈を薄く保つ)

| いつ | 読む | 読まない |
|---|---|---|
| 起動時 | SKILL.md(これ)・policy.md・再開パケット(あれば)・phase に応じた `references/workflow-a.md` **または** `workflow-b.md` | roles.md 全文・両方の workflow |
| Fable を呼ぶ直前 | roles.md の「全体図 (overview)」と該当ロールの節 | roles.md の他の節 |
| codex を呼ぶとき | `references/codex-invocation.md`(初回) | — |
| 実装役の報告 | Agent の最終メッセージ(文脈に 1 回入る)→ `impl-check.ps1 -SaveReport` で保存と判定 | `.report.md` の読み直し |
| 画像(スクショ・グラレコ) | 読まない。確認が要るなら Agent(model: sonnet)に見せて 5 行で返させる。人間に渡すなら SendUserFile かパス | Read ツールで画像を開く |
| シェルの結果 | 失敗分だけ(テストは `… | Select-String -Pattern 'FAIL|ALL PASS'` のように、`FAIL` / `FAILURES` / `ALL PASS` の行だけを出す)。切り詰めてよいが要約はしない | 全出力 |
| 大きな文書(hearing-log・spec・plan・tech-assessment) | 必要な節だけ(Grep / 行範囲)。codex には貼らずパスで渡す | 全文の Read |
```

11. `## 例外・停止時の扱い`: 原文のまま。先頭の項目を `どのフェーズでも、人間の入力が必要になったら「待ち」を書き、境界リセット(a)を行ってから停止する。` に変える。

- [ ] **Step 6: 分割の整合を目視で確かめる**

- `git diff --stat` で SKILL.md が縮み、workflow-a/b が増えていること。
- `Select-String -Path skills\r-super-loop-powers\SKILL.md -Pattern '^\*\*[AB]-'` が 0 件。
- SKILL.md のサイズが 24 KB 以下(`(Get-Item skills\r-super-loop-powers\SKILL.md).Length`)。超えたら「ゲート保護ルール」と「Fable共通契約」以外の説明文を削る(規則は削らない)。

- [ ] **Step 7: テスト**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\skill-layout.tests.ps1`
Expected: `version-0.9.0` 以外 PASS(version は Task 10)。

- [ ] **Step 8: コミット**

```bash
git add skills/r-super-loop-powers/SKILL.md skills/r-super-loop-powers/references/workflow-a.md skills/r-super-loop-powers/references/workflow-b.md tests/skill-layout.tests.ps1
git commit -m "docs: SKILL.md を共通・ワークフローA・ワークフローBに分け、境界リセットと記帳の手順を入れる"
```

---

### Task 10: README・版・スモーク・統合

**Files:**
- Modify: `README.md`(Claude版節)
- Modify: `.claude-plugin/plugin.json`(version 0.9.0)
- Create: `docs/superpowers/notes/2026-10-10-v0.9-smoke.md`

- [ ] **Step 1: README を更新する**

(a) 「使い方」の `- **再開**: …` の後に:

```markdown
- **境界リセット**: 人間待ち・Checkpoint 確定・Goal Plan 承認の直後(と、文脈が 20 万トークンを超えたマイルストーン境界)で Opus が `state.md` を更新して印 `resume-pending` を置き、`/clear` を頼む。`/clear` のあと「続けて」と送ると、SessionStart フックが `bin/resume-packet.ps1` の再開パケット(state.md・否定リスト・制約/承認基準/終了条件・未検証仮定・直近の判定と retro・未完了の委譲。要約なし)を注入して再開する。コンパクションは使わない(制約の取りこぼしを避けるため)
```

(b) `### 人間向け応答チェック(hooks)` を `### プラグインのフック` に改め、冒頭に表を足す:

```markdown
| フック | 発火 | 役割 | 記録(goal 直下 `hook-log.md`) |
|---|---|---|---|
| `hooks/resume-inject.ps1` | SessionStart(`startup` / `clear`) | `resume-pending` があれば再開パケットを一回限り注入(24 時間で無効) | `RESUME` / `STALE` / `ERROR` |
| `hooks/context-meter.ps1` | PostToolUse(`Agent`) | トランスクリプト末尾から文脈サイズを測り、20 万トークン以上なら通知 | `CTX` |
| `hooks/human-message-check.ps1` | Stop | 人間向け応答の日本語・明瞭さの検査(v0.8) | `PASS` / `BLOCK` / `ERROR` |
```

以下の既存段落(人間向け応答チェックの説明)はそのまま残し、末尾に `- 注入は Claude Code の上限(1 フィールド 10,000 文字)に合わせて 9,500 文字に収める。超える分は後方の節だけ切られ、全文は goal 直下の `resume-packet.md` に残る` を足す。

(c) 「役とモデル(Claude版)」表のグラレコ行 `medium` → `low`。
(d) 「リポジトリ構成」: `skills/r-super-loop-powers/` の説明に `bin/`(…・記帳 loop-log・再開パケット resume-packet)と `references/`(…・workflow-a / workflow-b)を足す。`hooks/` の説明を 3 フック + `hook-common.ps1` にする。`tests/` に新テストを含める。
(e) E2E チェックリストに 4 項目足す:

```markdown
- [ ] 人間待ちに入る応答の末尾に `/clear` の依頼があり、`/clear` 後に再開パケットが注入され、最初の応答でフェーズ / 強度 / マイルストーン / 次のゲート / 待ちが復唱される(hook-log.md に `RESUME`)
- [ ] call-log.md の追記と state.md の更新が `loop-log.ps1` で行われ、記帳だけのターンが無い
- [ ] 実装役への Agent prompt がファイルのパスだけで、再委譲の prompt が `## 再委譲の差分` + 初回のパスになっている
- [ ] hook-log.md に `CTX` 行があり、retro の観測欄に最大文脈と境界リセット回数が書かれている
```

- [ ] **Step 2: 版を上げる**

`.claude-plugin/plugin.json` の `"version": "0.8.1"` → `"0.9.0"`。

- [ ] **Step 3: 全テストを流す**

```powershell
foreach ($f in Get-ChildItem tests\*.tests.ps1) { Write-Output "== $($f.Name)"; & powershell -NoProfile -ExecutionPolicy Bypass -File $f.FullName | Select-String -Pattern 'FAIL|ALL PASS' }
```
Expected: 全ファイルが `ALL PASS`(FAIL 行なし)。`scripts\sync-templates.ps1 -Mode Verify` → `Verify OK`。

- [ ] **Step 4: コミット**

```bash
git add README.md .claude-plugin/plugin.json
git commit -m "docs: README に境界リセットとフック3つを書き、version 0.9.0"
```

- [ ] **Step 5: スモーク(spec §10)**

1. `startup` 経路: 一時プロジェクト(`git init` + 1 コミット、`docs/r-super-loop-powers/smoke/state.md` ほか)を作り、`loop-log.ps1 -GoalDir … -SetWait "スモークの確認" -Mark` → そのディレクトリで `claude -p --model haiku --settings <{"disableAllHooks":false}…>`(プラグインのフックが効く設定のまま)`"state.md の phase と待ちを一言で答えて"` を実行し、答えに `milestone-implementation` と `スモークの確認` が含まれること、印が消えて `hook-log.md` に `RESUME | source=startup` が記録されることを確かめる。プラグイン側のフックは**インストール済みのプラグイン**から読まれるので、先に Step 7 の plugin update を行ってから実行する(順序: Step 6 → 7 → 5 でもよい)。
2. 文脈メーター: このセッションのトランスクリプト(`~/.claude/projects/<このプロジェクト>/<session>.jsonl`)を `context-meter.ps1` に食わせ(cwd は state.md のある一時プロジェクト)、`CTX` 行の tokens が妥当な範囲で出ることを確かめる。
3. グラレコ(F): 一時ディレクトリに `grareco-input.md` を置き、`codex-preflight.ps1` → `codex-run.ps1 -Role grareco` → `codex-status.ps1` で 1 回生成し、`STATUS` / `IMAGE:` / `BOUNDARY_HIT` の有無 / `*.out.jsonl` 末尾 `turn.completed` の累計入力トークンを記録する。
4. 結果を `docs/superpowers/notes/2026-10-10-v0.9-smoke.md` に書く(実行コマンド・出力の要点・所要・未確認事項: `/clear` 経路は対話セッションが要るので未確認と明記)。

```bash
git add docs/superpowers/notes/2026-10-10-v0.9-smoke.md
git commit -m "docs: v0.9 スモーク(startup 経路の注入・文脈メーター・グラレコ low)"
```

- [ ] **Step 6: main へマージして push**

```bash
git checkout main
git merge --no-ff v0.9 -m "Merge branch 'v0.9': 境界リセット(/clear+再開パケット)と記帳の省力化(v0.9.0)"
git push origin main
git push origin v0.9
```

- [ ] **Step 7: plugin update**

インストール済みプラグインを更新する(マーケットプレイスはローカルパス `C:\Users\makyu\Desktop\project\r-super-loop-powers`。main をチェックアウトした状態で):

```
claude plugin update r-super-loop-powers@r-super-loop-powers-marketplace
```
(コマンド名は `claude plugin --help` で確かめる。対話の `/plugin` からでもよい。)更新後 `~/.claude/plugins/cache/r-super-loop-powers-marketplace/r-super-loop-powers/<version>/hooks/resume-inject.ps1` があることを確かめる。Claude Code の再起動後に有効になる。

- [ ] **Step 8: rb に報告**

`rb_report`(要約・成果物 URL = GitHub の v0.9 コミット / spec / plan / smoke ノート)→ `rb_inbox` → `rb_review`。
