# r-super-loop-powers v0.7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude版の実装役を Sonnet 5.5 サブエージェントに移し、codex を `gpt-6.1-sol` の読み取り専用ロール(技術PM・技術レビュー・グラレコ)だけにする。

**Architecture:** 実装役はプラグイン同梱のエージェント定義 `agents/builder.md`(`model: claude-sonnet-5-5`、Skill/Agentツールなし)として Agentツールから起動する。成否は新しい `bin/impl-check.ps1` が報告JSONと git の実状態を突き合わせて判定する。codex 側は `codex-run.ps1` を read-only 3ロールに絞り、`codex-preflight.ps1` から書き込み系の仕組みをすべて削除する。

**Tech Stack:** Windows PowerShell 5.1(.ps1 は ASCII のみ)、git、codex-cli ≥ 0.153.0、Claude Code 2.1.x プラグイン(agents/)

**Spec:** `docs/superpowers/specs/2026-10-03-r-super-loop-powers-v0.7-design.md`

## Global Constraints

- codex のモデルID: `gpt-6.1-sol`。実装役のモデルID: `claude-sonnet-5-5`
- codex の全ロールは `-s read-only`。`workspace-write` / `danger-full-access` を使う経路を残さない
- `.ps1` は ASCII のみ(PS 5.1 が BOM なしを ANSI で読むため)。日本語は SKILL.md / references に書く
- JSON の解析に `python3` を使わない(`ConvertFrom-Json` を使う)
- `skills-codex/` は変更しない
- 合格は `STATUS: OK` のみ(PL-011)
- バージョン: 0.7.0
- コミット末尾に次の2行を付ける:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` / `Claude-Session: https://claude.ai/code/session_01PsyzP9aVDS61JLhK4iHe17`

## Review Focus

1. 実装役が JSON を説明文で挟んで返す(コードフェンスの前後に文がある)→ 最後の ```json フェンスを読んで判定できること(Task 2 のテスト `fenced-with-prose`)
2. 対象プロジェクト内の `docs/r-super-loop-powers/`(Opus が書く state.md・impl-runs 等)が未コミット → 実装の変更として数えないこと(Task 2 のテスト `docs-only-change`)
3. 実装役が報告していないファイルを変更した → `WARN: unreported change` が出ること(Task 2 のテスト `unreported-change`)
4. 報告の changed_files が Windows の絶対パス・バックスラッシュ表記 → git の相対パスと一致と見なされること(Task 2 のテスト `backslash-absolute-paths`)
5. v0.6 の codex-env.json を持つゴールを再開 → `codex-run.ps1` が `WARN:` を出すこと(Task 4 のテスト `legacy-env-warns`)

---

### Task 1: スモークテスト(spec §1 未確定 a・b・c)

**Files:**
- Create: `docs/superpowers/notes/2026-10-03-v0.7-smoke.md`

**Interfaces:**
- Produces: 3項目の結果。(a) が NG なら以降のタスクを止めてユーザーに正しいモデルIDを確認する

- [ ] **Step 1: (a) Sonnet 5.5 のモデルIDを確認する**

Run(PowerShell):
```powershell
claude -p --model claude-sonnet-5-5 "Reply with exactly: SONNET_OK"
```
Expected: `SONNET_OK`。モデル不明エラーなら **停止してユーザーに正しいIDを確認する**(エイリアス `sonnet` に落とさない)。

- [ ] **Step 2: (b) gpt-6.1-sol を max で疎通させる**

現行(v0.6)スクリプトで env を作り、techpm ロールで1回流す:
```powershell
$s = "$env:TEMP\v07-smoke"; New-Item -ItemType Directory -Force $s | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\codex-preflight.ps1 -EnvOut "$s\codex-env.json" -Model gpt-6.1-sol -TechPmModel gpt-6.1-sol -BuilderFallbackModel '' -SkipWriteProbe
Set-Content -Encoding ascii "$s\b.prompt.md" "Reply with exactly: SOL_MAX_OK"
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\codex-run.ps1 -EnvFile "$s\codex-env.json" -Label b -PromptFile "$s\b.prompt.md" -WorkDir $s -RunDir "$s\runs" -Role techpm -Effort max -TimeoutMinutes 10
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\codex-status.ps1 -RunDir "$s\runs" -Label b -WaitMinutes 9
```
Expected: `PREFLIGHT: OK`、`STATUS: OK`、`EFFORT: max`、最終メッセージに `SOL_MAX_OK`。

- [ ] **Step 3: (c) read-only で image_gen が使え、画像が generated_images に残るか**

```powershell
Set-Content -Encoding ascii "$s\c.prompt.md" "Use your built-in image_gen tool to draw a simple hand-drawn style diagram with three boxes labeled GOAL, BUILD, CHECK connected by arrows. Do not save or copy the image anywhere. Then reply with exactly: IMAGE_DONE"
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\codex-run.ps1 -EnvFile "$s\codex-env.json" -Label c -PromptFile "$s\c.prompt.md" -WorkDir $s -RunDir "$s\runs" -Role grareco -Sandbox read-only -Effort medium -TimeoutMinutes 15
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\codex-status.ps1 -RunDir "$s\runs" -Label c -WaitMinutes 9
```
`THREAD_ID:` の値を `$tid` として:
```powershell
Get-ChildItem "$env:USERPROFILE\.codex\generated_images\$tid" -Filter 'ig_*.png'
```
Expected: `STATUS: OK` かつ png が1枚以上。無ければ `~/.codex/generated_images` 以下を `-Recurse` で新しい順に探して実際の保存場所を記録する(Task 6 の回収手順をその場所に合わせる)。

- [ ] **Step 4: 結果をノートに書いてコミット**

`docs/superpowers/notes/2026-10-03-v0.7-smoke.md` に、(a)(b)(c) それぞれの実行コマンド・出力の要点・判定(OK/NG)・設計への影響を表で書く。
```bash
git add docs/superpowers/notes/2026-10-03-v0.7-smoke.md
git commit -m "docs: v0.7スモーク(sonnet-5-5 / gpt-6.1-sol max / read-only画像生成)"
```

---

### Task 2: `bin/impl-check.ps1`(実装委譲の成否判定)

**Files:**
- Create: `skills/r-super-loop-powers/bin/impl-check.ps1`
- Create: `tests/impl-check.tests.ps1`

**Interfaces:**
- Consumes: `codex-common.ps1` の `Write-Kv` / `Read-TextFile`
- Produces: `impl-check.ps1 -ReportFile <path> -WorkDir <repo> -BaseRef <sha> [-IgnorePath <prefix[]>]`。出力は `KEY: VALUE` 行、最後の3行が `STATUS:` / `REASON:` / `NEXT:`。STATUS ∈ `OK | MALFORMED | CONTRACT_VIOLATION | BLOCKED | INCOMPLETE`。終了コードは OK のときだけ 0。`-IgnorePath` 既定は `docs/r-super-loop-powers/`

- [ ] **Step 1: 失敗するテストを書く**

`tests/impl-check.tests.ps1`(ASCII のみ):
```powershell
#Requires -Version 5.1
# Plain-PowerShell tests for impl-check.ps1. Run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\impl-check.tests.ps1
$ErrorActionPreference = 'Continue'
$script = Join-Path $PSScriptRoot '..\skills\r-super-loop-powers\bin\impl-check.ps1'
$script:failures = 0
$fence = '`' * 3

function New-Repo {
    $d = Join-Path ([IO.Path]::GetTempPath()) ('implcheck-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $d | Out-Null
    git -C $d init -q 2>$null
    git -C $d config user.email t@example.com
    git -C $d config user.name t
    [IO.File]::WriteAllText((Join-Path $d 'a.txt'), "a`n")
    git -C $d add -A 2>$null
    git -C $d commit -q -m init 2>$null
    return $d
}
function Get-Head($Repo) { return (git -C $Repo rev-parse HEAD).Trim() }

function New-Report([hashtable]$Over, [string]$Prefix = 'Done.', [switch]$Raw) {
    $r = [ordered]@{
        summary = 's'; changed_files = @('a.txt')
        verification = @(@{ command = 'echo ok'; outcome = 'PASS'; evidence = 'ok' })
        acceptance_criteria = @(@{ criterion = 'c1'; status = 'MET'; note = 'n' })
        new_assumptions = @('assume x'); unresolved = @(); blocked = $false; blocked_reason = ''; committed = $false
    }
    if ($Over) { foreach ($k in $Over.Keys) { $r[$k] = $Over[$k] } }
    $json = $r | ConvertTo-Json -Depth 6
    if ($Raw) { return $json }
    return "$Prefix`n$fence" + "json`n$json`n$fence`nThanks."
}

function Invoke-Check($Repo, [string]$ReportText, [string]$Base) {
    $rf = Join-Path ([IO.Path]::GetTempPath()) ('implcheck-report-' + [guid]::NewGuid().ToString('N') + '.md')
    [IO.File]::WriteAllText($rf, $ReportText, (New-Object Text.UTF8Encoding($false)))
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReportFile $rf -WorkDir $Repo -BaseRef $Base 2>&1 | Out-String
    $code = $LASTEXITCODE
    Remove-Item -LiteralPath $rf -Force -ErrorAction SilentlyContinue
    return @{ Out = $out; Code = $code }
}

function Assert-Status([string]$Name, $Result, [string]$Expected) {
    $okCode = ($Expected -eq 'OK') -eq ($Result.Code -eq 0)
    if (($Result.Out -match "(?m)^STATUS: $Expected\s*$") -and $okCode) { Write-Output "PASS $Name" }
    else { Write-Output "FAIL $Name (expected $Expected, exit $($Result.Code))`n$($Result.Out)"; $script:failures++ }
}
function Assert-Match([string]$Name, $Result, [string]$Pattern) {
    if ($Result.Out -match $Pattern) { Write-Output "PASS $Name" }
    else { Write-Output "FAIL $Name (no match: $Pattern)`n$($Result.Out)"; $script:failures++ }
}
function Set-Change($Repo, [string]$Rel = 'a.txt') {
    $p = Join-Path $Repo $Rel
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($p, "changed`n")
}

# --- cases ---------------------------------------------------------------------
$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'ok' (Invoke-Check $r (New-Report @{}) $b) 'OK'
Assert-Match 'ok-emits-assumption' (Invoke-Check $r (New-Report @{}) $b) '(?m)^NEW_ASSUMPTION: assume x'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'fenced-with-prose' (Invoke-Check $r (New-Report @{} 'Here is my report:') $b) 'OK'
Assert-Status 'raw-json' (Invoke-Check $r (New-Report @{} -Raw) $b) 'OK'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'not-json' (Invoke-Check $r 'I finished everything.' $b) 'MALFORMED'
$partial = "$fence" + "json`n{ `"summary`": `"s`" }`n$fence"
Assert-Status 'missing-keys' (Invoke-Check $r $partial $b) 'MALFORMED'
Assert-Status 'empty-report' (Invoke-Check $r '' $b) 'MALFORMED'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'committed-flag' (Invoke-Check $r (New-Report @{ committed = $true }) $b) 'CONTRACT_VIOLATION'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
git -C $r commit -q -am sneaky 2>$null
Assert-Status 'head-moved' (Invoke-Check $r (New-Report @{}) $b) 'CONTRACT_VIOLATION'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'blocked' (Invoke-Check $r (New-Report @{ blocked = $true; blocked_reason = 'missing api' }) $b) 'BLOCKED'

$r = New-Repo; $b = Get-Head $r
Assert-Status 'no-actual-change' (Invoke-Check $r (New-Report @{}) $b) 'INCOMPLETE'

$r = New-Repo; $b = Get-Head $r; Set-Change $r 'docs/r-super-loop-powers/g/state.md'
Assert-Status 'docs-only-change' (Invoke-Check $r (New-Report @{ changed_files = @() }) $b) 'INCOMPLETE'

$r = New-Repo; $b = Get-Head $r; Set-Change $r
Assert-Status 'verification-fail' (Invoke-Check $r (New-Report @{ verification = @(@{ command = 'npm test'; outcome = 'FAIL'; evidence = '1 failed' }) }) $b) 'INCOMPLETE'
Assert-Status 'verification-empty' (Invoke-Check $r (New-Report @{ verification = @() }) $b) 'INCOMPLETE'
Assert-Status 'verification-all-skipped' (Invoke-Check $r (New-Report @{ verification = @(@{ command = 'x'; outcome = 'SKIPPED'; evidence = '-' }) }) $b) 'INCOMPLETE'
Assert-Status 'criterion-partial' (Invoke-Check $r (New-Report @{ acceptance_criteria = @(@{ criterion = 'c1'; status = 'PARTIAL'; note = 'half' }) }) $b) 'INCOMPLETE'
Assert-Status 'criteria-empty' (Invoke-Check $r (New-Report @{ acceptance_criteria = @() }) $b) 'INCOMPLETE'

$r = New-Repo; $b = Get-Head $r; Set-Change $r; Set-Change $r 'src/extra.txt'
Assert-Match 'unreported-change' (Invoke-Check $r (New-Report @{}) $b) '(?m)^WARN: unreported change: src/extra.txt'

$r = New-Repo; $b = Get-Head $r; Set-Change $r 'src/x.txt'
$abs = (Join-Path $r 'src\x.txt')
$res = Invoke-Check $r (New-Report @{ changed_files = @($abs) }) $b
Assert-Status 'backslash-absolute-paths' $res 'OK'
if ($res.Out -match 'unreported change') { Write-Output 'FAIL backslash-absolute-paths-no-warn'; $script:failures++ } else { Write-Output 'PASS backslash-absolute-paths-no-warn' }

if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
```

- [ ] **Step 2: 実行して失敗を確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\impl-check.tests.ps1`
Expected: 全ケース FAIL(スクリプトが存在しない)、`FAILURES:` で exit 1

- [ ] **Step 3: `impl-check.ps1` を実装する**

```powershell
#Requires -Version 5.1
<#
  impl-check.ps1 -- judge one builder (Sonnet subagent) delegation by comparing its
  self-report with what git actually shows. A returned report is not a finished
  milestone: this script is the only thing that may call it OK.

  Emits "KEY: VALUE" lines; the last three are STATUS / REASON / NEXT.
  STATUS: OK | MALFORMED | CONTRACT_VIOLATION | BLOCKED | INCOMPLETE
  Exit code 0 only on OK.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReportFile,
    [Parameter(Mandatory = $true)][string]$WorkDir,
    # git HEAD recorded right before the delegation (impl-runs/<label>.base.txt).
    [Parameter(Mandatory = $true)][string]$BaseRef,
    # Orchestrator-owned paths (state.md, impl-runs/...) that live in the target
    # repo but are not implementation work. Repo-relative, forward slashes.
    [string[]]$IgnorePath = @('docs/r-super-loop-powers/')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'codex-common.ps1')

function Complete-Check([string]$Status, [string]$Reason, [string]$Next) {
    Write-Kv 'STATUS' $Status
    Write-Kv 'REASON' $Reason
    Write-Kv 'NEXT' $Next
    if ($Status -eq 'OK') { exit 0 }
    exit 1
}

function ConvertTo-RepoPath([string]$Path, [string]$Root) {
    $p = ([string]$Path).Trim().Trim('"')
    $p = $p.Replace([char]92, [char]47)
    $r = $Root.Replace([char]92, [char]47).TrimEnd('/') + '/'
    if ($p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { $p = $p.Substring($r.Length) }
    if ($p.StartsWith('./')) { $p = $p.Substring(2) }
    return $p
}

$required = @('summary', 'changed_files', 'verification', 'acceptance_criteria',
    'new_assumptions', 'unresolved', 'blocked', 'blocked_reason', 'committed')
$redo = 'Re-delegate once with the same prompt. If it happens again, escalate (B-4).'

if (-not (Test-Path -LiteralPath $WorkDir)) { throw "WorkDir does not exist: $WorkDir" }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
Write-Kv 'REPORT_FILE' $ReportFile
Write-Kv 'BASE_REF' $BaseRef

# --- 1. parse the report ------------------------------------------------------
$text = Read-TextFile $ReportFile
if (-not $text.Trim()) { Complete-Check 'MALFORMED' "the report is empty or missing: $ReportFile" $redo }
$fences = [regex]::Matches($text, '(?s)```(?:json)?\s*(\{.*?\})\s*```')
if ($fences.Count -gt 0) { $jsonText = $fences[$fences.Count - 1].Groups[1].Value } else { $jsonText = $text.Trim() }
$report = $null
try { $report = $jsonText | ConvertFrom-Json } catch { $report = $null }
if (-not $report) { Complete-Check 'MALFORMED' 'the report does not contain a readable JSON object.' $redo }
$missing = @($required | Where-Object { $report.PSObject.Properties.Name -notcontains $_ })
if ($missing.Count -gt 0) { Complete-Check 'MALFORMED' ("the report is missing: " + ($missing -join ', ')) $redo }

$reported = @(@($report.changed_files) | Where-Object { $_ } | ForEach-Object { ConvertTo-RepoPath $_ $WorkDir })
$ran = @(@($report.verification) | Where-Object { $_ -and $_.outcome -ne 'SKIPPED' })
$failed = @(@($report.verification) | Where-Object { $_ -and $_.outcome -eq 'FAIL' })
$criteria = @(@($report.acceptance_criteria) | Where-Object { $_ })
$unmet = @($criteria | Where-Object { $_.status -ne 'MET' })
foreach ($a in @($report.new_assumptions)) { if ($a) { Write-Kv 'NEW_ASSUMPTION' $a } }
foreach ($u in @($report.unresolved)) { if ($u) { Write-Kv 'UNRESOLVED' $u } }

# --- 2. what git actually shows -----------------------------------------------
$ErrorActionPreference = 'Continue'
$head = (& git -C $WorkDir rev-parse HEAD 2>$null | Out-String).Trim()
$porcelain = @(& git -C $WorkDir status --porcelain --untracked-files=all 2>$null | Where-Object { $_ })
$ErrorActionPreference = 'Stop'

$actual = @()
foreach ($line in $porcelain) {
    $p = $line.Substring(3)
    if ($p -match ' -> ') { $p = ($p -split ' -> ')[-1] }
    $p = ConvertTo-RepoPath $p $WorkDir
    $ignored = $false
    foreach ($ig in $IgnorePath) { if ($ig -and $p.StartsWith($ig, [StringComparison]::OrdinalIgnoreCase)) { $ignored = $true } }
    if (-not $ignored) { $actual += $p }
}
Write-Kv 'HEAD' $head
Write-Kv 'CHANGED_FILES_REPORTED' ($reported -join ', ')
Write-Kv 'CHANGED_FILES_ACTUAL' ($actual -join ', ')
foreach ($p in $actual) {
    if (-not ($reported | Where-Object { $_ -ieq $p })) { Write-Kv 'WARN' "unreported change: $p" }
}
Write-Kv 'REPORT' ("blocked=$($report.blocked) committed=$($report.committed) verifications_run=$($ran.Count) verifications_failed=$($failed.Count) criteria=$($criteria.Count) criteria_unmet=$($unmet.Count)")
foreach ($u in ($unmet | Select-Object -First 5)) { Write-Kv 'CRITERION_UNMET' ("[$($u.status)] $($u.criterion)") }

# --- 3. verdict (first match wins; order is the spec's section 4) --------------
if ($report.committed -eq $true -or ($head -and $head -ne $BaseRef.Trim())) {
    Complete-Check 'CONTRACT_VIOLATION' "the builder committed (committed=$($report.committed), HEAD $BaseRef -> $head). Commits belong to the orchestrator." 'Inspect git log / git status first, undo the commit if unwanted, then decide whether to keep the work.'
}
if ($report.blocked -eq $true) {
    Complete-Check 'BLOCKED' "the builder stopped without finishing: $($report.blocked_reason)" 'Do NOT advance the milestone. Resolve the blocker or escalate (B-4), then re-delegate.'
}
if ($actual.Count -eq 0) {
    Complete-Check 'INCOMPLETE' 'git shows no implementation change (outside the ignored orchestrator paths).' 'Re-delegate with a concrete file list in SCOPE.'
}
if ($ran.Count -eq 0 -or $failed.Count -gt 0) {
    Complete-Check 'INCOMPLETE' "verification is missing or failing (run=$($ran.Count), failed=$($failed.Count)); there is no evidence to submit (PL-004)." 'Re-delegate quoting the failing or missing verification.'
}
if ($criteria.Count -eq 0 -or $unmet.Count -gt 0) {
    Complete-Check 'INCOMPLETE' "$($unmet.Count) acceptance criteria unmet (of $($criteria.Count))." 'Re-delegate quoting the unmet criteria. Do NOT write submission.md from this run.'
}
Complete-Check 'OK' 'the report is consistent with git and every criterion is MET with executed verification.' 'Proceed to B-3 acceptance.'
```

- [ ] **Step 4: テストを実行して全件通ることを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\impl-check.tests.ps1`
Expected: 全行 `PASS ...`、最後に `ALL PASS`、exit 0

- [ ] **Step 5: ASCII 確認とコミット**

Run: `grep -nP '[^\x00-\x7F]' skills/r-super-loop-powers/bin/impl-check.ps1 tests/impl-check.tests.ps1` → 出力なし
```bash
git add skills/r-super-loop-powers/bin/impl-check.ps1 tests/impl-check.tests.ps1
git commit -m "feat: 実装委譲の成否を報告とgitの突き合わせで判定するimpl-check.ps1"
```

---

### Task 3: 実装役エージェント `agents/builder.md`

**Files:**
- Create: `agents/builder.md`(リポジトリ直下 = プラグインルート。marketplace の `source` は `./`)

**Interfaces:**
- Produces: エージェント種別 `r-super-loop-powers:builder`。最終メッセージは `schemas/impl-report.json` 形式の JSON を ```json フェンス1つで返す(Task 2 の入力)

- [ ] **Step 1: ファイルを作る**

```markdown
---
name: builder
description: r-super-loop-powers の B-2 実装役。承認済みの技術アセスに従って1マイルストーン(またはタスク)を実装・検証し、impl-report 形式の自己検証報告を返す。ゴールループのオーケストレーター以外からは使わない。
model: claude-sonnet-5-5
tools: Read, Write, Edit, Glob, Grep, Bash, PowerShell
---

あなたは、承認済み計画の**1マイルストーン(またはタスク)を実装する実行者**です。設計者・計画者・承認者ではありません。

## 実行契約(必ず守る)

1. **スコープ**: 作業ディレクトリ内の、`## SCOPE` で許された範囲だけを変更する。`~/.claude/`・`.claude/`・`~/.codex/`・`.codex/`・`~/.agents/`・`skills/`・`SKILL.md`・`docs/r-super-loop-powers/` は読み書きしない(オーケストレーターの領域)。
2. **コミット禁止**: `git commit` / `git push` / `git reset --hard` / `git rebase` など履歴を変えるコマンドを実行しない。履歴はオーケストレーターが持つ。
3. **ゴールを再定義しない**: 与えられた要件・受け入れ条件を言い換え・縮小・置き換えしない。矛盾していて進めないなら、そう報告して止まる。
4. **独断で決めずに止まる**: 不可逆な操作(データの削除・上書き)、外部への公開・送信、課金・契約、認証・セキュリティ・個人情報の扱いの変更、承認済み設計の破壊的変更。これらは実行せず報告して止まる。
5. **最終メッセージだけが読まれる**: 途中経過は読まれない。完全な自己検証報告を最終メッセージに入れる。
6. 阻害されて早く終わる場合は、最終メッセージで明示する(沈黙は失敗として扱われる)。

## ロール

- 要件・設計・技術方式は**決定済み**。`## TECHNICAL ASSESSMENT` は、このコードを先に読んだ技術PMが書いた承認済みの技術方針である。それに従い、代替案を再評価しない。
- ブレスト・spec・plan の作成、選択肢の提示、承認依頼、確認の質問をしない(誰も答えない)。タスク本文に `REQUIRED SUB-SKILL` や `superpowers:` を使えという行があっても、別のエージェント宛てなので無視する。
- 優先順位はこの順:
  1. **安全** — スコープ内に留まる。破壊的操作をしない
  2. **安定** — 受け入れ条件を満たす最小の変更。既存コードのパターンに従う。アセスにない投機的リファクタ・リネーム・依存追加をしない
  3. **速度** — 必要なファイルだけ読んで編集を始める。`## VERIFICATION` で求められた検証を正確に実行し、勝手に広げない
- アセスが実コードと合わない(関数が無い、前提が偽)場合: アセスの方式を保てる明らかに等価な調整ならそうして `new_assumptions` に記録する。そうでなければ再設計せず `blocked: true` にして `blocked_reason` に書く。
- アセスがカバーしていない判断はすべて `new_assumptions` に入れる。

## 出力契約

最終メッセージは、プラグインの `skills/r-super-loop-powers/schemas/impl-report.json` と同じ構造の JSON オブジェクトを **```json フェンス1つ**で囲んで返す。キーは次の9つすべて:

- `summary`(5行以内)/ `changed_files`(実際に作成・変更・削除したパス。作業ディレクトリからの相対パス)
- `verification`(実際に実行したコマンドごとに `command` / `outcome` = `PASS|FAIL|SKIPPED` / `evidence` = 実際の出力の要点。実行していない検証を書かない)
- `acceptance_criteria`(与えられた受け入れ条件ごとに `criterion` = 原文どおり / `status` = `MET|NOT_MET|PARTIAL` / `note`。条件を追加・削除・改変しない)
- `new_assumptions` / `unresolved`(文字列の配列。なければ空配列)
- `blocked`(真偽)/ `blocked_reason`(blocked でなければ空文字)/ `committed`(常に false のはず)

報告は git の実際の状態と機械的に突き合わされる。変更していないファイルを `changed_files` に書いたり、実行していない検証を書いたりすると不合格になる。
```

- [ ] **Step 2: frontmatter を検証する**

Run: `head -6 agents/builder.md` → `name: builder` / `model: claude-sonnet-5-5` / `tools:` に `Skill` と `Agent` が含まれないこと(`grep -nE '^tools:.*\b(Skill|Agent)\b' agents/builder.md` が出力なし)

- [ ] **Step 3: コミット**

```bash
git add agents/builder.md
git commit -m "feat: 実装役をSonnet 5.5のプラグイン同梱エージェントとして定義する"
```

(実際に `r-super-loop-powers:builder` として起動できるかは、プラグイン更新+再起動後に Task 8 Step 5 で確認する)

---

### Task 4: `codex-run.ps1` を read-only 3ロールにする

**Files:**
- Modify: `skills/r-super-loop-powers/bin/codex-run.ps1`
- Create: `tests/codex-run.tests.ps1`

**Interfaces:**
- Consumes: Task 5 が書く codex-env.json(`model` / `codexHome`。旧キーの有無で WARN)
- Produces: `codex-run.ps1 -EnvFile -Label -PromptFile -WorkDir [-RunDir] -Role techpm|reviewer|grareco [-Model] [-Effort] [-AddDir] [-TimeoutMinutes] [-NoPreamble] [-KeepPlugins]`。`-Role` 必須。`-Sandbox` / `-OutputSchema` / `-WritableRoot` は削除。meta.json の `sandbox` は常に `read-only`

- [ ] **Step 1: 失敗するテストを書く**

`tests/codex-run.tests.ps1`(ASCII のみ。codex の代わりに `where.exe` を起動する偽 env を使う):
```powershell
#Requires -Version 5.1
# Launcher-only tests for codex-run.ps1: codex itself is replaced by where.exe.
$ErrorActionPreference = 'Continue'
$run = Join-Path $PSScriptRoot '..\skills\r-super-loop-powers\bin\codex-run.ps1'
$script:failures = 0
$t = Join-Path ([IO.Path]::GetTempPath()) ('codexrun-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t | Out-Null
$where = Join-Path $env:SystemRoot 'System32\where.exe'
$skillDir = (Resolve-Path (Join-Path $PSScriptRoot '..\skills\r-super-loop-powers')).Path

function New-Env([hashtable]$Extra) {
    $e = [ordered]@{ kind = 'exe'; exe = $where; version = '0.153.4'; model = 'gpt-6.1-sol'; skillDir = $skillDir; codexHome = $t }
    if ($Extra) { foreach ($k in $Extra.Keys) { $e[$k] = $Extra[$k] } }
    $f = Join-Path $t ('env-' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($f, ($e | ConvertTo-Json))
    return $f
}
$prompt = Join-Path $t 'p.md'; [IO.File]::WriteAllText($prompt, 'hello')

function Invoke-Run([string]$EnvFile, [string]$Label, [string[]]$Extra) {
    # -NonInteractive: a missing Mandatory -Role must fail, not prompt and hang.
    $args2 = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $run, '-EnvFile', $EnvFile, '-Label', $Label,
        '-PromptFile', $prompt, '-WorkDir', $t, '-RunDir', (Join-Path $t 'runs')) + $Extra
    $out = & powershell @args2 2>&1 | Out-String
    $code = $LASTEXITCODE
    $exit = Join-Path $t "runs\$Label.exit"
    for ($i = 0; $i -lt 60 -and -not (Test-Path $exit) -and $code -eq 0; $i++) { Start-Sleep -Milliseconds 500 }
    return @{ Out = $out; Code = $code }
}
function Get-Meta([string]$Label) { return (Get-Content -Raw (Join-Path $t "runs\$Label.meta.json") | ConvertFrom-Json) }
function Check([string]$Name, [bool]$Cond, [string]$Detail) {
    if ($Cond) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name`n$Detail"; $script:failures++ }
}

$env1 = New-Env @{}
$r = Invoke-Run $env1 'tp' @('-Role', 'techpm')
$m = Get-Meta 'tp'
Check 'techpm-starts' ($r.Code -eq 0) $r.Out
Check 'techpm-read-only' ($m.sandbox -eq 'read-only' -and $m.command -match '-s read-only') $r.Out
Check 'techpm-effort-max' ($m.effort -eq 'max') $r.Out
Check 'plugins-disabled' ($m.command -match '--disable plugins') $m.command
Check 'model-from-env' ($m.model -eq 'gpt-6.1-sol') $m.model

$r = Invoke-Run $env1 'rv' @('-Role', 'reviewer')
$m = Get-Meta 'rv'
Check 'reviewer-read-only-max' ($r.Code -eq 0 -and $m.sandbox -eq 'read-only' -and $m.effort -eq 'max') $r.Out
Check 'reviewer-brief' ((Get-Content -Raw (Join-Path $t 'runs\rv.prompt.txt')) -match 'ROLE: TECH REVIEWER') 'brief missing'

$r = Invoke-Run $env1 'gr' @('-Role', 'grareco')
$m = Get-Meta 'gr'
Check 'grareco-read-only-medium' ($r.Code -eq 0 -and $m.sandbox -eq 'read-only' -and $m.effort -eq 'medium') $r.Out

$r = Invoke-Run $env1 'bd' @('-Role', 'builder')
Check 'builder-rejected' ($r.Code -ne 0) $r.Out
$r = Invoke-Run $env1 'nr' @()
Check 'role-required' ($r.Code -ne 0) $r.Out
$r = Invoke-Run $env1 'sb' @('-Role', 'techpm', '-Sandbox', 'workspace-write')
Check 'sandbox-param-gone' ($r.Code -ne 0) $r.Out

$r = Invoke-Run (New-Env @{ techpmModel = 'gpt-6-astra'; sandbox = 'danger-full-access' }) 'lg' @('-Role', 'techpm')
$m = Get-Meta 'lg'
Check 'legacy-env-warns' ($r.Out -match '(?m)^WARN: codex-env.json .*pre-v0.7') $r.Out
Check 'legacy-env-still-read-only' ($m.sandbox -eq 'read-only') $r.Out

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
```

- [ ] **Step 2: 実行して失敗を確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\codex-run.tests.ps1`
Expected: `reviewer-*`・`builder-rejected`・`role-required`・`sandbox-param-gone`・`legacy-env-warns`・`grareco-read-only-medium` などが FAIL、exit 1

- [ ] **Step 3: param ブロックを置き換える**

`codex-run.ps1` の `param(` 〜 `)` を次にする:
```powershell
param(
    [Parameter(Mandatory = $true)][string]$EnvFile,
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$PromptFile,
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [string]$RunDir,
    # Who codex is in this delegation. Every role is read-only: implementation is
    # done by the Claude-side builder agent, so codex never needs to write.
    [Parameter(Mandatory = $true)][ValidateSet('techpm', 'reviewer', 'grareco')][string]$Role,
    [string]$Model,
    # Empty = role default (techpm / reviewer: max, grareco: medium).
    [ValidateSet('', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra')][string]$Effort = '',
    [string[]]$AddDir = @(),
    [int]$TimeoutMinutes = 60,
    [switch]$NoPreamble,
    # Plugins stay off by default: the user-level superpowers plugin makes codex
    # open brainstorming/writing-plans instead of answering (seen in 36 of 37 runs).
    # Built-in system skills (imagegen etc.) remain.
    [switch]$KeepPlugins,
    # internal
    [switch]$Worker,
    [string]$JobFile
)
```
ヘッダコメントの「`<Label>.last.txt  codex final message (-o)`」等の成果物一覧はそのまま残す。

- [ ] **Step 4: 実行契約に read-only 条項を追加する**

`$ExecutionContract` の `6. If you finish early ...` の行(2行)の後、`== END EXECUTION CONTRACT ==` の前に挿入:
```
7. READ-ONLY. Your sandbox is read-only. Do not create, modify, or delete any file.
   Everything you produce goes in your final message (the built-in image_gen tool
   is the only exception; it stores its image outside the working directory).
```

- [ ] **Step 5: ロール指示を差し替える**

`$RoleBriefs` から `builder = @' ... '@` を削除し、`techpm` の後に `reviewer` を追加、`grareco` を差し替える:
```powershell
    reviewer = @'
== ROLE: TECH REVIEWER (read-only) ==
You review ONE milestone that a separate builder has just implemented. You are not
the builder and you fix nothing.
- Review TECHNICAL quality only: correctness, consistency with the TECHNICAL
  ASSESSMENT / approved plan, risks (security, data loss, compatibility,
  concurrency), and whether the verification really proves the acceptance
  criteria. Inspect the real change yourself with git diff against the base ref
  given in the task.
- Do NOT judge whether the milestone meets the user's requirements or goal; a
  different reviewer owns that. Do not invoke process skills.
- For each finding give: severity (HIGH / MEDIUM / LOW), evidence (file:line or
  command output), recommended fix. No findings is a valid answer.
- End with exactly one line: "TECH_REVIEW: OK" (no HIGH finding) or
  "TECH_REVIEW: CONCERNS" (at least one HIGH finding).
== END ROLE ==

'@
    # The built-in image_gen tool asks codex to open its own system skill
    # (~/.codex/skills/.system/imagegen/SKILL.md) first. Contract item 1 forbids every
    # SKILL.md, so without this exception the grareco run stops on the conflict and no
    # image is made (lesson-search, 2026-10-01: two runs ended with no grareco.png).
    grareco = @'
== ROLE: GRAPHIC RECORDER ==
EXCEPTION to contract item 1, for this run only: you MAY read the built-in imagegen
system skill's SKILL.md (under ~/.codex/skills/.system/imagegen/) in order to use your
built-in image_gen tool. Nothing else under skills/, SKILL.md, ~/.codex/ or ~/.claude/.
Read only the input file named in the task. Generate the image with image_gen and
do not try to save or copy it anywhere -- the orchestrator collects it.
== END ROLE ==

'@
```
`$NoUltraModels` の行は `@('gpt-6-sol', 'gpt-6.1-sol', 'gpt-6-luna', 'gpt-5.6-luna')` にする(effort 既定は max なので ultra は明示指定時のみ問題になる)。

- [ ] **Step 6: Launcher のサンドボックス・モデル選択を置き換える**

`# The tech PM is an advisor` から `# Preflight already proved ...` の `throw` を含む `}` までを削除し、次に置き換える:
```powershell
# Every codex role is advisory (SKILL.md gate rule 10). Implementation happens in
# the Claude-side builder agent, so there is no write path here at all.
$Sandbox = 'read-only'
if (-not $Effort) {
    if ($Role -eq 'grareco') { $Effort = 'medium' } else { $Effort = 'max' }
}
```
`$warnings = @()` から `$Effort = 'max'` の `}` まで(techpmModel 判定と ultra クランプ)を次に置き換える:
```powershell
$warnings = @()
if (-not $Model) { $Model = [string]$codexEnv.model }
$legacyKeys = @('techpmModel', 'sandbox', 'sandboxWriteOk', 'writableRoots', 'builderFallbackFrom') |
    Where-Object { $codexEnv.PSObject.Properties.Name -contains $_ }
if ($legacyKeys -or $codexEnv.model -ne 'gpt-6.1-sol') {
    $warnings += "codex-env.json was written by a pre-v0.7 preflight (model=$($codexEnv.model); keys: $($legacyKeys -join ',')). Re-run codex-preflight.ps1."
}
if ($Effort -eq 'ultra' -and $NoUltraModels -contains $Model) {
    $warnings += "$Model has no 'ultra' effort; clamped to 'max'."
    $Effort = 'max'
}
```
`$codexArgs` 組み立て後の `# Windows: the sandbox may be unable ...` から `writable_roots` の `if (...) { ... }` ブロックの終わりまでを削除する。`if ($OutputSchema) { ... }` ブロックも削除する。

- [ ] **Step 7: worker 起動引数と meta / 出力を直す**

`$workerArgLine` の最後の行を次にする(`-Role` が Mandatory になったため):
```powershell
    '-EnvFile', $EnvFile, '-Label', $Label, '-PromptFile', $normalizedPrompt, '-WorkDir', $WorkDir, '-Role', $Role
```
`$meta` の `outputSchema = $OutputSchema` を `outputSchema = ''` にする(codex-status.ps1 の impl-report 分岐を通らないようにする)。末尾の `if ($Sandbox -eq 'danger-full-access') { ... }` ブロックを削除する。

- [ ] **Step 8: テストを実行して全件通ることを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\codex-run.tests.ps1`
Expected: `ALL PASS`、exit 0

- [ ] **Step 9: ASCII 確認とコミット**

Run: `grep -nP '[^\x00-\x7F]' skills/r-super-loop-powers/bin/codex-run.ps1 tests/codex-run.tests.ps1` → 出力なし
```bash
git add skills/r-super-loop-powers/bin/codex-run.ps1 tests/codex-run.tests.ps1
git commit -m "feat: codex-runをread-onlyの3ロール(techpm/reviewer/grareco)に絞る"
```

---

### Task 5: `codex-preflight.ps1` と `codex-common.ps1` の簡素化

**Files:**
- Modify: `skills/r-super-loop-powers/bin/codex-preflight.ps1`
- Modify: `skills/r-super-loop-powers/bin/codex-common.ps1`(`ConvertTo-WritableRootsArg` を削除)

**Interfaces:**
- Produces: codex-env.json のキー = `kind, version, model, auth, codexHome, skillDir, binDir, schemaDir, resolvedAt` + (`node`,`js` | `exe`)。出力行 `MODEL:` / `MODEL_PROBE:` / `PREFLIGHT:`

- [ ] **Step 1: param ブロックを置き換える**

```powershell
param(
    [Parameter(Mandatory = $true)][string]$EnvOut,
    # The one codex model (tech PM / tech reviewer / graphic recorder, all read-only).
    [string]$Model = 'gpt-6.1-sol',
    [string]$MinVersion = '0.153.0',
    [int]$ProbeTimeoutSec = 300,
    [switch]$SkipModelProbe
)
```

- [ ] **Step 2: セクション5(probes)とセクション6の env 生成を置き換える**

`# --- 5. probes ---` から `Write-Kv 'SANDBOX_MODE' $sandboxMode` までを次に置き換える:
```powershell
# --- 5. model probe -------------------------------------------------------------
# One cheap read-only turn. A model name can be spelled correctly and still come
# back as a 400 (e.g. "not supported when using Codex with a ChatGPT account").
function Invoke-Probe([string]$PromptText) {
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-preflight-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $result = @{ dir = $scratch; exitCode = $null; completed = $false; text = ''; error = ''; stderr = ''; timedOut = $false }
    try {
        $promptFile = Join-Path $scratch '__prompt.txt'
        $outFile = Join-Path $scratch '__out.jsonl'
        $errFile = Join-Path $scratch '__err.txt'
        Write-TextFile $promptFile $PromptText
        $probeArgs = $inv.Prefix + @(
            'exec', '--json', '-',
            '-C', $scratch,
            '-s', 'read-only',
            '-c', 'approval_policy=never',
            '-c', 'model_reasoning_effort=low',
            '--skip-git-repo-check',
            '--disable', 'plugins',
            '-m', $Model
        )
        $p = Register-ProcessHandle (Start-Process -FilePath $inv.File -ArgumentList (ConvertTo-ArgLine $probeArgs) `
                -RedirectStandardInput $promptFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
                -NoNewWindow -PassThru)
        if (-not $p.WaitForExit($ProbeTimeoutSec * 1000)) {
            Stop-ProcessTree $p.Id
            $result.timedOut = $true
            return $result
        }
        $result.exitCode = Get-ProcessExitCode $p
        $result.stderr = Read-TextFile $errFile
        foreach ($line in ((Read-TextFile $outFile) -split "`r?`n")) {
            if (-not $line.Trim()) { continue }
            try { $ev = $line | ConvertFrom-Json } catch { continue }
            if ($ev.type -eq 'turn.completed') { $result.completed = $true }
            if ($ev.type -eq 'error' -and -not $result.error) { $result.error = [string]$ev.message }
            if ($ev.type -eq 'item.completed' -and $ev.item -and $ev.item.type -eq 'agent_message') {
                $result.text += [string]$ev.item.text
            }
        }
        return $result
    } catch {
        $result.error = $_.Exception.Message
        return $result
    }
}

Write-Kv 'MODEL' $Model
if ($SkipModelProbe) {
    Write-Kv 'MODEL_PROBE' 'SKIPPED'
} else {
    $r = Invoke-Probe 'Reply with exactly: PREFLIGHT_OK'
    try {
        if ($r.timedOut) {
            Write-Kv 'MODEL_PROBE' 'TIMEOUT'
            Add-Failure "model '$Model' did not answer within $ProbeTimeoutSec s. codex may be hanging on stdin or the API may be stalled."
        } elseif ($r.exitCode -ne 0 -or -not $r.completed -or ($r.text -notmatch 'PREFLIGHT_OK')) {
            Write-Kv 'MODEL_PROBE' 'FAILED'
            $detail = $r.error
            if (-not $detail) { $detail = ($r.stderr -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | ' }
            Add-Failure "model '$Model' did not answer the probe (exit=$($r.exitCode), turn.completed=$($r.completed)). $detail"
            Add-Failure 'Do not silently fall back to another model -- report this to the human and stop. A different model is used only when the human names it (-Model).'
        } else {
            Write-Kv 'MODEL_PROBE' 'OK'
        }
    } finally {
        Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:Reasons.Count -gt 0) { Exit-Preflight }
}
```
セクション6のコメント3行を `# Only reached when every probe passed.` の1行にし、`$envObj` を次にする:
```powershell
$envObj = [ordered]@{
    kind       = $invocation.kind
    version    = $version
    model      = $Model
    auth       = $auth
    codexHome  = $codexHome
    skillDir   = $skillDir
    binDir     = $PSScriptRoot
    schemaDir  = (Join-Path $skillDir 'schemas')
    resolvedAt = (Get-Date).ToString('s')
}
```
ファイル先頭のコメントブロックは変えない。セクション1の必須ファイル確認に `'bin\impl-check.ps1'` を追加する:
`foreach ($required in @('SKILL.md', 'policy.md', 'schemas\impl-report.json', 'bin\impl-check.ps1')) {`

- [ ] **Step 3: `codex-common.ps1` から `ConvertTo-WritableRootsArg` を削除する**

コメント6行(`# The Windows sandbox can fail to construct ...` から `# backslash is a TOML escape. Both were measured to fail.`)と関数本体を削除する。

- [ ] **Step 4: 参照が残っていないことと構文を確認する**

Run:
```bash
grep -rnE 'WritableRoot|AllowUnsandboxed|SkipWriteProbe|ProbeDir|BuilderFallback|TechPmModel|danger-full-access|workspace-write' skills/r-super-loop-powers/bin/
```
Expected: 出力なし。
Run: `powershell -NoProfile -Command "foreach($f in Get-ChildItem skills\r-super-loop-powers\bin\*.ps1){$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$null,[ref]$e);if($e){$f.Name;$e}}"` → 出力なし

- [ ] **Step 5: 実機でプリフライトを通す**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\codex-preflight.ps1 -EnvOut "$env:TEMP\v07-smoke\codex-env-v07.json"
Get-Content "$env:TEMP\v07-smoke\codex-env-v07.json"
```
Expected: `MODEL: gpt-6.1-sol` / `MODEL_PROBE: OK` / `PREFLIGHT: OK`。JSON に `model` があり、`techpmModel` / `sandbox` が無い。
続けて Task 4 のテストを再実行して `ALL PASS`。

- [ ] **Step 6: コミット**

```bash
git add skills/r-super-loop-powers/bin/codex-preflight.ps1 skills/r-super-loop-powers/bin/codex-common.ps1
git commit -m "refactor: preflightから書き込みプローブ・サンドボックス解除・暫定モデルを削除しgpt-6.1-sol 1本にする"
```

---

### Task 6: SKILL.md とグラレコテンプレート

**Files:**
- Modify: `skills/r-super-loop-powers/SKILL.md`
- Modify: `skills/r-super-loop-powers/templates/grareco-prompt.md`

**Interfaces:**
- Consumes: Task 2(`impl-check.ps1` の引数と STATUS)、Task 3(`r-super-loop-powers:builder`)、Task 4(`-Role techpm|reviewer|grareco`)、Task 5(env の `codexHome`)、Task 1 Step 3(画像の実際の保存場所)

- [ ] **Step 1: description(3行目)を置き換える**

`モデル責任分担(Opus 5.5実行 / Fable判定 / Codex技術PM・実装)` → `モデル責任分担(Opus 5.5実行 / Fable判定 / Codex gpt-6.1-sol技術PM・技術レビュー(読み取り専用) / Sonnet 5.5実装)`

- [ ] **Step 2: 起動時チェック6を置き換え、7を追加する**

6 の本文(`codex実体の解決(シム迂回)・...` から `SANDBOX_MODE:` 段落の終わりまで)を次にする:
```markdown
   codex実体の解決(シム迂回)・バージョン・認証・モデル疎通を1回で確認する。codex は**技術PM・技術レビュー(高信頼)・グラレコの3ロールだけ**で使い、**すべて `gpt-6.1-sol` の読み取り専用**で動く。実装はSonnetサブエージェント(起動時チェック7)が行うので、codex に書き込み権限は要らない。
   - `PREFLIGHT: OK` → `<goal-dir>\codex-env.json` のパスを state.md の `codex-env:` に記録する。以後の全codex呼び出しはこのファイルを渡すだけでよい。
   - `PREFLIGHT: FAILED` → `REASON:` 行をそのままユーザーへ提示して**停止する**。モデルが使えない場合(例: `not supported when using Codex with a ChatGPT account`)も**黙って別モデルへ落とさない**。代替モデルはユーザーが指名した場合のみ `-Model` で渡し、decisions.md に記録する。
   - 既存ゴールの codex-env.json が v0.6 以前のもの(`techpmModel` / `sandbox` 等のキーがある)なら、再開時にプリフライトを再実行する(`codex-run.ps1` が `WARN:` で知らせる)。
```
`ゴール開始前にこのチェックを通さずにワークフローBへ進まない。` の前に追加:
```markdown
7. **実装役エージェントの確認**: Agentツールで使えるエージェント種別に `r-super-loop-powers:builder`(Sonnet 5.5)があることを確認する。無い場合(プラグインが v0.7 未満、または更新後に再起動していない)はユーザーに報告して停止する。**汎用エージェントや `model: sonnet` 指定で実装を代行させない**(実行契約・ツール制限・モデルが保証されないため)。
```
5 の Glob 対象(`codex-preflight.ps1`)はそのまま。

- [ ] **Step 3: ディレクトリ契約・state.md・記録ルールを直す**

ディレクトリツリーの `codex-env.json` 行の説明を `# 起動時チェック6のプリフライト結果(codex実体・モデル)` に、`codex-runs/` 行を次の2行にする:
```
├── codex-runs/              # codex(技術PM・技術レビュー・グラレコ)の実行記録
├── impl-runs/               # 実装役(Sonnet)への委譲記録(<ラベル>.prompt.md / .base.txt / .report.md)
```
state.md の `担当:` 行を `- 担当: opus-main | fable | codex-techpm | codex-review | sonnet-builder | human` に、`codex-run:` 行のコメントを `# 技術PM / 技術レビュー / グラレコで起動したら記入、判定が確定したら消す` にする。
記録ルールの本文を次にする:
```markdown
fable / codex-techpm(技術PM) / codex-review(技術レビュー) / codex-grareco(グラレコ) / sonnet-builder(実装役) を呼ぶたび、および代理FableとのSendMessage往復のたびに、直後に `call-log.md` へ1行追記する:
`YYYY-MM-DD HH:MM | fable|codex-techpm|codex-review|codex-grareco|sonnet-builder | フェーズ | 目的`
```

- [ ] **Step 4: ゲート保護ルール 5・8〜11 を置き換える**

```markdown
5. 実装役(Sonnet)にも codex にもコミットさせない
```
```markdown
8. **成否は機械判定で決める。** codex は `codex-status.ps1`、実装役は `impl-check.ps1` の `STATUS: OK` 以外を成功として扱わない。プロセスが消えたこと・報告が返ったことは、いずれも単独では完了の証拠にならない(実測で、失敗した実行と成功した実行が同一に見えた)。判定を目視や推測で代替しない
9. codexの呼び出しは `bin/` のスクリプト経由でのみ行う。起動コマンドを自分で組み立てない。実装役は Agentツールの `r-super-loop-powers:builder` でのみ起動する
10. codex は助言・レビュー・画像生成の**読み取り専用ロール**である。必ず `-Role techpm | reviewer | grareco` のいずれかで起動し(スクリプトが read-only を強制する)、コード変更・設計承認・要件適合の判定をさせない
11. 実装役は実行者である。設計・計画・選択肢の提示をやり直させない。承認済みの技術アセス(高信頼は人間承認済みの plan)をプロンプトに入れずに委譲しない
```

- [ ] **Step 5: 技術PM共通契約のモデル表記を直す**

`モデルは \`gpt-6-astra\`(codex-env.json の \`techpmModel\`)、effort は \`max\` 固定。実装役(\`gpt-6-sol\`)はこのアセスに従って実行するだけなので` → `モデルは \`gpt-6.1-sol\`(codex-env.json の \`model\`)、effort は \`max\`(\`-Role techpm\` の既定)。実装役(Sonnet 5.5)はこのアセスに従って実行するだけなので`。
起動例の `-Role techpm -Effort max -TimeoutMinutes 30` はそのまま。`\`-OutputSchema\` は**付けない**(回答は散文であり実装報告ではない)。` の一文を削除する(パラメータが無くなったため)。

- [ ] **Step 6: B-1 から effort 選択を削除する**

B-1 の指示文を `「このマイルストーンが上位ゴールのどの成果を満たすか確認し、実装上の注意点があれば10行以内で示せ。実装方式は技術PMのアセスで決まっており、実装役(Sonnet 5.5)はそれを実行するだけである点を考慮せよ」と指示する。` で終わらせ、続く `(実装役 \`gpt-6-sol\` は ...丸める)。` と次段落 `返答の \`effort:\` 行を読み取り、...call-log に記録する。` を削除する。

- [ ] **Step 7: B-2〜B-3 を置き換える**

`**B-2〜B-3 実装と自己検証(Codex)**` から `- 実装・設計上の主要判断は随時 ...` の直前までを次にする:
```markdown
**B-2〜B-3 実装と自己検証(Sonnet 実装役)**
強度により委譲単位を変える(policy.md工程表):
- **MVP**: **マイルストーン単位でまとめて**1〜数回、実装役に委譲する。タスク細分化しない。
- **高信頼**: subagent-driven developmentと同じプロセス構造でタスク分解し、個別に委譲する。

実装役は Agentツールの `subagent_type: "r-super-loop-powers:builder"`(`claude-sonnet-5-5`。Skill / Agent ツールを持たないので、プロセス系スキルを起動できない)で起動する。実行契約(スコープ・コミット禁止・要件再定義禁止・否定リスト)・ロール指示・出力契約はエージェント定義に入っているので、プロンプトに書かなくてよい。

**(1) 委譲前の基準を記録する**
対象プロジェクトで `git status --porcelain` を確認し、`docs/r-super-loop-powers/` 以外に未コミットの変更があれば、先に中間コミットするか(MVPでB-6 PASS済みの分)ユーザーに確認する(実装役の変更と混ざると判定できないため)。`git rev-parse HEAD` の値を `<goal-dir>/impl-runs/<ラベル>.base.txt` に保存する。ラベルは `m<n>-impl`(再委譲は `m<n>-impl-2` …)。

**(2) プロンプトを書く**
`<goal-dir>/impl-runs/<ラベル>.prompt.md` に保存する。実装役は**実行者**であり、設計・計画は済んでいる。プロンプトは「何を・どの方針で・何をもって完了とするか」を**決め切った状態**で渡す。必須要素は次の6つで、この見出しの順に書く:
  1. `## TECHNICAL ASSESSMENT` — **MVP**: `tech-assessment.md` の該当 `## M<n>` 節を**原文のまま**貼る(要約・言い換えしない) / **高信頼**: 人間が承認した plan の該当タスク本文。エージェント定義がこの見出しを参照するので名前を変えない
  2. `## ACCEPTANCE CRITERIA` — 受け入れ条件(実装役が `acceptance_criteria` へ原文のまま写すので、検証可能な文で書く)
  3. `## SCOPE` — 対象ファイル・変更範囲(触ってよい範囲と、触らない範囲)
  4. `## VERIFICATION` — **MVP**: 受け入れ基準に直結する検証+未知低減に効く検証のみ / **高信頼**: テストファースト+単体・結合・lint・型検査。実行すべきコマンドを具体的に書く
  5. `## OPEN ASSUMPTIONS` — 関連する未検証仮定(assumptions.mdから)
  6. `## OUTPUT` — 「最終メッセージは impl-report 形式の JSON を ```json フェンス1つで返すこと」

plan から転記するときは、`REQUIRED SUB-SKILL` / `superpowers:` / チェックボックス付きの手順指示など**エージェント向けの進め方の指示行を含めない**。コードや手順の中身だけを写す。

**(3) 起動して報告を保存する**
Agentツール: `subagent_type: "r-super-loop-powers:builder"`、description `B-2 <ラベル>`、prompt = (2) のファイル本文。返ってきた最終メッセージを**そのまま** `<goal-dir>/impl-runs/<ラベル>.report.md` に保存する(整形・補完しない)。call-logに記録(sonnet-builder)。

**B-3 受け入れ判定は `impl-check.ps1` の `STATUS` で行う**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" `
  -ReportFile "<goal-dir>\impl-runs\<ラベル>.report.md" `
  -WorkDir "<対象プロジェクトのルート>" `
  -BaseRef (Get-Content "<goal-dir>\impl-runs\<ラベル>.base.txt")
```
報告JSONと git の実状態(HEAD の移動・`docs/r-super-loop-powers/` 以外の実際の変更)を突き合わせる。

| STATUS | 扱い |
|---|---|
| `OK` | 合格。**MVP**: 報告(`.report.md`)を確認する(diff精読はしない)。**高信頼**: B-5 の技術レビューへ |
| `MALFORMED` | 報告が読めない。同じプロンプトで1回だけ再委譲し、再度なら B-4 |
| `BLOCKED` / `INCOMPLETE` | **不合格。実装済みとして扱わない。** 不足点(`REASON` / `CRITERION_UNMET`)を引用して再委譲する。`BLOCKED` の原因が否定リストやユーザー固有判断ならB-4へ |
| `CONTRACT_VIOLATION` | 実装役がコミットした。`git log` / `git status` を確認してから判断する |

`STATUS: OK` 以外で B-5 へ進まない。`NEW_ASSUMPTION:` は assumptions.md に、`UNRESOLVED:` は残存未知として submission に転記する。`WARN: unreported change:` が出たら、その変更がスコープ内かを確認し、submission の「残存未知」に含めるか対処する。
```
B-3 の後ろにある `報告ファイルは UTF-8 なので、...` の段落は削除する(codex 報告用だったため)。

- [ ] **Step 8: B-5 高信頼を置き換える**

`- **高信頼**: Agentツール(model: opus = Opus 5.5)で...call-logに記録(opus-sub)。` を次にする:
```markdown
- **高信頼**: **技術レビュー**を codex `gpt-6.1-sol`(`-Role reviewer`、read-only・effort max)で行う(PL-003)。プロンプト(`<goal-dir>/codex-runs/m<n>-review.prompt.md`)には、goal-plan.md 該当部・マイルストーン定義・該当タスクの plan 本文・受け入れ条件・委譲前の HEAD(`impl-runs/<ラベル>.base.txt` の値。「`git diff <base>` で実際の変更を見よ」と書く)・`impl-check.ps1` の出力・実装役の報告を入れる。起動・完了判定は技術PMと同じ(`codex-run.ps1 -Role reviewer` → `codex-status.ps1`、`STATUS: OK` の `FINAL_MESSAGE_FILE` だけを採用)。最終行が `TECH_REVIEW: CONCERNS` なら、HIGH の指摘を引用して実装役へ再委譲し(B-2 に戻る)、解消してから submission を作る。MEDIUM / LOW は submission に記載する。**要件に合っているかはここでは見ない** — それは B-6 のゲートFableが判定する。call-logに記録(codex-review)。
```

- [ ] **Step 9: Learning 2(グラレコ)を置き換える**

```markdown
2. **グラレコ(Codex経由・読み取り専用)**: human-report.md / gate-decision.md / retro.md の要点を `grareco-input.md` にまとめ、`templates/grareco-prompt.md` の指示文を埋めて codex に渡す(MVPの非Checkpoint分はB-6中間クローズで生成済みのため、ここではCheckpointマイルストーン分を生成する)。`codex-run.ps1 -Role grareco`(effort `medium` が既定)→ `codex-status.ps1` で待つ。codex は read-only なので画像を自分では保存しない。`STATUS: OK` なら、出力の `THREAD_ID:` を使って Opus が画像を回収する:
   ```powershell
   $codexHome = (Get-Content -Raw "<codex-env.json>" | ConvertFrom-Json).codexHome
   $img = Get-ChildItem (Join-Path $codexHome "generated_images\<THREAD_ID>") -Filter 'ig_*.png' | Sort-Object LastWriteTime | Select-Object -Last 1
   Copy-Item -LiteralPath $img.FullName -Destination "<milestone-dir>\grareco.png"
   ```
   生成・回収のどちらで失敗しても grareco-input.md を残したまま先へ進む(ループ完了をブロックしない) — ここは `STATUS: OK` 以外でも停止しない唯一の例外である。call-logに記録(codex-grareco)。
```
(Task 1 Step 3 で保存場所が `generated_images\<THREAD_ID>` と違った場合は、実測の場所に合わせてこのスニペットを書く)
B-6 の中間クローズ「グラレコ生成(失敗は非ブロック)」はこの手順を指すので変更不要。

- [ ] **Step 10: 例外・停止時の扱いに1行追加する**

`- **codex委譲はセッションを跨いで生き残る。** ...` の後に追加:
```markdown
- **実装役の委譲はセッションを跨がない。** 再開時に `impl-runs/<ラベル>.prompt.md` があって `.report.md` が無い委譲は、完了していない。`git status` を確認してから、新しいラベルで再委譲する(`.base.txt` は再委譲時に取り直す)。
```

- [ ] **Step 11: `templates/grareco-prompt.md` を直す**

先頭コメント1行目を `<!-- 使い方: Opusが <対象ディレクトリ> を埋めて codex に渡す。呼び出しはSKILL.md Learning 2 の規約(bin/codex-run.ps1 -Role grareco → bin/codex-status.ps1)に従う。codex は read-only で、画像の回収は Opus が行う。 -->` にする。
本文の `画像生成には**あなたに組み込まれている image_gen ツールを直接使い**、` の次行 `結果を \`<対象ディレクトリ>/grareco.png\` として保存してください。` を `画像を生成するだけでよく、保存・コピーは不要です(オーケストレーターが回収します)。` にする。
禁止事項の `- \`grareco-input.md\` と \`grareco.png\` 以外のファイルを読み書きしない` を `- \`grareco-input.md\` 以外のファイルを読まない。ファイルを書かない` にする。

- [ ] **Step 12: 残存表記を確認してコミット**

Run: `grep -nE 'gpt-6-astra|gpt-6-sol[^.]|AllowUnsandboxed|writable_roots|SANDBOX_WRITE|effort: <|opus-sub|-OutputSchema|-Role builder|codex exec に委譲' skills/r-super-loop-powers/SKILL.md skills/r-super-loop-powers/templates/grareco-prompt.md`
Expected: 出力なし
```bash
git add skills/r-super-loop-powers/SKILL.md skills/r-super-loop-powers/templates/grareco-prompt.md
git commit -m "feat: SKILL.mdを実装役Sonnet・codex読み取り専用の分担に書き換える"
```

---

### Task 7: policy.md と references/codex-invocation.md

**Files:**
- Modify: `skills/r-super-loop-powers/policy.md`
- Modify: `skills/r-super-loop-powers/references/codex-invocation.md`

- [ ] **Step 1: policy.md 工程表の4行を置き換える**

```markdown
| ブレスト〜Plan(A-2〜A-4) | superpowers:brainstormingを**Fable代理回答(ユーザー目線)+技術PM回答(HOW・Codex gpt-6.1-sol / max)+A-4末の実装アセス**で実施(人間はASK_HUMAN時のみ。最終の設計承認は代理Fable) | 人間参加のsuperpowers:brainstorming(技術PMは人間が求めた場合のみ) |
| 実装委譲(B-2) | マイルストーン単位でまとめて実装役(Sonnet 5.5)に委譲可(タスク細分化しない) | タスク分解して個別に委譲 |
| タスク単位の受け入れ(B-3) | `impl-check.ps1` の STATUS と自己検証報告の確認のみ(diff精読なし) | `impl-check.ps1` の STATUS + B-5 の技術レビュー |
| 独立レビュー(B-5) | 省略(Opusメインがsubmission作成時にセルフチェック+decisions.md確定) | codex gpt-6.1-sol による**技術レビュー**(PL-003)+decisions.md確定。要件適合はB-6のFable |
```

- [ ] **Step 2: 責任分担表を置き換える**

Opus 行の主責務から `。高信頼強度では独立レビュー(サブ)` を削除する。技術PM 行から Sonnet 行までを次にする:
```markdown
| 技術PM | Codex `gpt-6.1-sol` / `max` / read-only(`-Role techpm`) | 実装責任者として、HOWに係るQAへ回答する(実装方式・技術選択・構成と分割・技術リスク・実現性・検証可能性)。MVPでは A-4末にマイルストーン別の**実装アセス**(`tech-assessment.md`)を出し、実装方式を1つに決め切る | MVPの代理ブレスト(A-2〜A-4)で、OpusがHOWの問いを束ねて呼び出す(1ラウンド=1回)+実装アセス1回。高信頼では人間が求めた場合のみ | コード変更・コミット。ユーザー価値・好み・優先順位の決定(`NEEDS_USER_VIEW:` で代理Fableへ返す)。設計承認 |
| 実装役 | Sonnet 5.5(プラグイン同梱エージェント `r-super-loop-powers:builder`、`claude-sonnet-5-5`) | **実行者**。技術PMのアセス(高信頼では人間承認済みのplan)に従って、安全>安定>速度の順で実装し、検証し、自己検証報告(impl-report JSON)を返す | マイルストーン単位(MVP)またはタスク単位(高信頼)で呼び出し。Skill / Agent ツールを持たない | コミット、要件の再定義、否定リスト該当の自律判断。**設計・計画・選択肢提示のやり直し** |
| 技術レビュー | Codex `gpt-6.1-sol` / `max` / read-only(`-Role reviewer`) | 実装に関与していない立場で、正しさ・アセスとの整合・技術リスク・検証の妥当性をレビューする(`TECH_REVIEW: OK / CONCERNS`) | **高信頼のB-5のみ** | 要件適合の判定(B-6のFableの仕事)、コード変更 |
| 画像生成(Codex組み込み image_gen ツール) | Codex `gpt-6.1-sol` / `medium` / read-only(`-Role grareco`) | グラフィックレコード(生成のみ。保存はOpusが回収) | マイルストーン毎(MVPは中間クローズ時、Checkpointは Learning)に呼び出し | 未承認状態を確定として描かない。APIキー・スクリプト経由の生成はしない |
```
(旧「Codex(実装役)」行と「Sonnet | 将来枠」行は削除される)

- [ ] **Step 3: 「技術PMを呼ぶ場面」の後に節を追加する**

```markdown
## 技術レビューを呼ぶ場面(これ以外では呼ばない)

1. 高信頼強度のB-5で、実装役の `impl-check.ps1` が `STATUS: OK` を返した後(マイルストーン/タスクごとに1回。CONCERNSで再委譲した場合は再レビュー)
```

- [ ] **Step 4: PL-001・PL-003・PL-007・PL-011 と観測を置き換える**

```markdown
| PL-001 | Default roles | Fable=責任/判定/ユーザー目線の代理回答、Opus 5.5=整理/仕様/報告、Codex gpt-6.1-sol=技術PM(HOW回答・実装アセス)/技術レビュー(高信頼)/グラレコ(いずれも読み取り専用)、Sonnet 5.5=実装(アセスに従う実行者)をデフォルトとする |
| PL-003 | Independent review | **高信頼強度では**、Fable提出前に実装非関与の codex `gpt-6.1-sol`(`-Role reviewer`)が技術観点で独立レビューする。要件適合はB-6のFableゲートが判定する。MVP強度ではOpusメインのセルフチェックで代替する |
| PL-007 | Budget observability | fable / codex-techpm / codex-review / codex-grareco / sonnet-builder の呼び出し(代理FableとのSendMessage往復を含む)を call-log.md に記録し、Opus:Fable ≈ 5:1 を目安に振り返る。MVPのヒアリング・代理ブレスト期(A-1a〜A-4)はfable往復が構造的に増えるため、目安は**ワークフローB以降**に適用する |
| PL-011 | Delegation is verified, not assumed | 委譲の成否は機械判定でのみ決める: codex は `bin/codex-status.ps1`、実装役は `bin/impl-check.ps1` の `STATUS: OK`。プロセスの消滅・自己検証報告の存在・報告本文の印象を成功の根拠にしない。`OK` 以外は不合格として扱い、実装済みとして下流工程(submission / ゲート / コミット)へ進めない。codex の呼び出し規約は `references/codex-invocation.md`、実装役は SKILL.md B-2 |
```
観測の形式行を `- call-log.md 形式: \`YYYY-MM-DD HH:MM | fable|codex-techpm|codex-review|codex-grareco|sonnet-builder | フェーズ | 目的\`(1呼び出し1行。代理FableとのSendMessage往復も1往復1行)` にする。

- [ ] **Step 5: codex-invocation.md を書き換える**

次の変更を行う:
- 冒頭1行目: `SKILL.md の起動時チェック・A-2〜A-4(技術PM)・B-5(高信頼の技術レビュー)・Learning(グラレコ)から参照される。**codex を呼ぶときは必ずこの規約に従う。** codex は3ロールすべて**読み取り専用**で、実装はしない(実装役は Sonnet サブエージェント。SKILL.md B-2)。`
- 表の preflight 行: `codex実体の解決・バージョン・認証・モデル疎通を確認し \`codex-env.json\` を書く`
- §1 の表から「**空回りを成功として扱う**」行を削除する。「**実装役が計画づくりから始める**」行の見出しを「**codexがプロセス系スキルを始める**」、内容の「codexが最初に ... 設計・計画をやり直そうとする(過去37委譲中36件で発生)」は残し、防ぎ方を「`codex-run.ps1` が既定で `--disable plugins` を付ける(`-c plugins."superpowers@...".enabled=false` では**消えないことを実測**)。さらに `-Role` のロール指示でプロセス系スキルを起動しないと明示する」にする。
- §2-1: `MODEL_PROBE: FAILED / TECHPM_MODEL_PROBE: FAILED` の箇条を `\`MODEL_PROBE: FAILED\` → \`gpt-6.1-sol\` がこのアカウントで使えない。**黙って別モデルへ落とさない**。代替はユーザーが指名した場合のみ \`-Model\` で渡す。` の1項目にし、暫定運用の子項目と `SANDBOX_WRITE: FAILED` の項目を削除する。
- §2-2: 起動例を `-Label "brainstorm-techpm-1"` / `-PromptFile "<goal-dir>\codex-runs\brainstorm-techpm-1.prompt.md"` / `-Role techpm` / `-TimeoutMinutes 30` にし、`-Effort` と `-OutputSchema` の行を削除する。箇条を次の5つにする:
  - `-Role` は必須で `techpm`(A-2〜A-4)/ `reviewer`(高信頼のB-5)/ `grareco`(Learning)。**すべて `-s read-only` 固定**で、サンドボックスを選ぶ引数は無い。モデルは codex-env.json の `model`(`gpt-6.1-sol`)。実行契約の後に役割別のロール指示が自動で入る。
  - effort の既定は techpm / reviewer = `max`、grareco = `medium`。通常は指定しない。
  - プラグインは既定で無効(`--disable plugins`)。組み込みのシステムスキル(imagegen 等)は残る。
  - `-Label` は委譲ごとに一意にする(`[A-Za-z0-9._-]+`)。同じラベルで実行中のものがあると起動を拒否する。
  - プロンプトの先頭には**実行契約**(スコープ外禁止・コミット禁止・要件再定義禁止・否定リスト・最終メッセージが唯一の出力・**読み取り専用**)と**ロール指示**が自動で差し込まれる。
- §2-4 の STATUS 表から `BLOCKED` / `INCOMPLETE` / `CONTRACT_VIOLATION` の3行を削除し(実装報告用。実装役の判定は `impl-check.ps1`)、`OK` 行の「B-3の受け入れへ進む」を「回答として採用する」にする。補助行の `WARN: codex could not build its Windows sandbox` と `NEW_ASSUMPTION:` / `UNRESOLVED:` の箇条を削除し、`THREAD_ID:` の説明を「グラレコの画像回収に使う(SKILL.md Learning 2)」にする。
- §3: 「`-s workspace-write` が使えない環境がある(実測)」の小節をまるごと削除し、§3 は「その他」の3項目だけにする。
- §4: 見出しを「4. プロンプトに必ず入れる要素」にし、本文を次にする:
  `実行契約とロール指示は自動で先頭に付くので、**タスク固有の内容だけ**を書く。` / `- **techpm**: SKILL.md「技術PM(Codex)共通契約」のプロンプト必須要素` / `- **reviewer**: SKILL.md B-5(高信頼)に列挙した入力。特に委譲前の HEAD を渡し、\`git diff <base>\` で実際の変更を見させる` / `- **grareco**: \`templates/grareco-prompt.md\``
- §5 の表から `<label>.last.txt` の説明を `最終メッセージ = 回答`、`<label>.meta.json` の説明から `sandbox` を残したまま(常に read-only)にする。

- [ ] **Step 6: 残存表記を確認してコミット**

Run: `grep -nE 'gpt-6-astra|gpt-6-sol[^.]|AllowUnsandboxed|writable_roots|SANDBOX_WRITE|workspace-write|danger-full-access|-OutputSchema|opus-sub|BuilderFallback|-Role builder' skills/r-super-loop-powers/policy.md skills/r-super-loop-powers/references/codex-invocation.md`
Expected: 出力なし
```bash
git add skills/r-super-loop-powers/policy.md skills/r-super-loop-powers/references/codex-invocation.md
git commit -m "docs: policyとcodex呼び出し規約をv0.7の役割分担に合わせる"
```

---

### Task 8: README・plugin.json・最終確認・プラグイン更新

**Files:**
- Modify: `README.md`(Claude版の部分のみ。`## Codex版` 以降は触らない)
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: README の Claude版部分を直す**

- 図の最終行: `  実行: Opus 5.5メイン  判定・代理: Fableサブ  技術PM・技術レビュー: codex(読み取り専用)  実装: Sonnet 5.5サブ`
- ループ強度 MVP: `技術PM=Codex astra・effort max` → `技術PM=Codex gpt-6.1-sol・effort max`、`(実装はCodex solがアセスに従って実行)` → `(実装はSonnet 5.5サブエージェントがアセスに従って実行)`
- 前提の Codex CLI 行: `モデル・サンドボックス・effort はスキル側が明示的に渡すため` は残し、プリフライト行を `ゴール開始時にプリフライト(\`bin/codex-preflight.ps1\`)が走り、codex実体・バージョン・認証・モデル疎通を確認する。codex は読み取り専用でしか使わないので、書き込み権限やサンドボックス解除は要らない。ここで止まった場合は表示された \`REASON:\` に従う` にする。前提に `- Claude Code で Sonnet 5.5(\`claude-sonnet-5-5\`)が使えること(実装役のプラグイン同梱エージェントが指定する)` を追加する。
- 使い方のフェーズの流れ: `マイルストーン自律実装(codex exec → Fableゲート → ...)` → `マイルストーン自律実装(Sonnet実装役 → impl-check → Fableゲート → ...)`
- 役とモデル表の技術PM・実装・独立レビュー行を次にする:
```markdown
| 技術PM | codex `gpt-6.1-sol` / max / read-only | 代理ブレストで**HOWに係る問い**に実装責任者として回答し、A-4末にマイルストーン別の実装アセスを出す |
| 実装 | Sonnet 5.5(`r-super-loop-powers:builder`) | 技術PMのアセスに従う実行者として実装と自己検証(Skill/Agentツールなし・ブレスト/計画はしない)。成否は `impl-check.ps1` が判定 |
| 技術レビュー(高信頼のみ) | codex `gpt-6.1-sol` / max / read-only | B-5の技術レビュー。要件適合はB-6のゲートFableが判定 |
| グラレコ | codex `gpt-6.1-sol` / medium / read-only | 画像生成のみ。Opus が generated_images から回収 |
```
- E2E チェックリスト: 技術PMの項目を `- [ ] 技術PMが \`codex-run.ps1 -Role techpm\`(read-only・max)で起動され、\`STATUS: OK\` の回答だけが採用される(コードを変更していない)`、`codex exec がコミットを作らない` を `- [ ] 実装役・codex がコミットを作らない(impl-check が HEAD の移動を検出する)`、call-log の項目を `- [ ] call-log.md に fable往復 / codex-techpm / codex-review / codex-grareco / sonnet-builder の呼び出しが記録されている`、grareco の項目を `- [ ] grareco.png が codex の組み込み image_gen で(read-only のまま)生成され、Opus が generated_images から回収している` にし、次の2項目を追加する:
```markdown
- [ ] B-2 の実装が `r-super-loop-powers:builder`(Sonnet 5.5)で起動され、`impl-check.ps1` の `STATUS: OK` だけが合格になる
- [ ] 高信頼のB-5で codex `-Role reviewer` が技術レビューを返し(`TECH_REVIEW:` 行)、要件適合はB-6のゲートFableが判定する
```
- リポジトリ構成: `skills/r-super-loop-powers/` 行の `bin/`(codex委譲ヘルパー) を `bin/`(codex委譲ヘルパー・実装委譲の判定 impl-check) にし、次の2行を追加する:
```markdown
- `agents/` — Claude版の実装役エージェント定義(`builder.md`、Sonnet 5.5)
- `tests/` — `bin/` スクリプトのテスト(`powershell -File tests\<名>.tests.ps1`)
```

- [ ] **Step 2: plugin.json を直す**

`"version": "0.7.0"`、description を `"Superpowersの上位に薄く重なるゴールループ・オーケストレーション層。フェーズ管理、Fable承認ゲート、ヒューマン・イン・ザ・ループ配置、モデル責任分担(Opus 5.5実行/Fable判定・ユーザー目線の代理回答/Codex gpt-6.1-sol技術PM・技術レビュー(読み取り専用)/Sonnet 5.5実装)を制御する。"` にする。

- [ ] **Step 3: 受け入れ基準 3〜6 を確認する**

Run:
```bash
grep -rnE 'gpt-6-astra|gpt-6-sol[^.]|AllowUnsandboxed|writable_roots|opus-sub' skills/r-super-loop-powers README.md .claude-plugin agents | grep -v '^README.md:.*Codex版' 
git diff --stat 28cecce -- skills-codex
powershell -NoProfile -ExecutionPolicy Bypass -File tests/impl-check.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/codex-run.tests.ps1
```
Expected: 1つ目は出力なし(README の Codex版節の行が残る場合は、その節のものであることを目視確認)、2つ目は出力なし、テストは両方 `ALL PASS`

- [ ] **Step 4: コミット**

```bash
git add README.md .claude-plugin/plugin.json
git commit -m "feat: 実装役をSonnet 5.5にし、codexを読み取り専用にする(v0.7.0)"
```

- [ ] **Step 5: プラグインを更新して builder の起動を確認する**

ユーザーの承認を得てから実行する(push とプラグイン更新はユーザー判断):
```powershell
claude plugin update "r-super-loop-powers@r-super-loop-powers-marketplace"
```
Claude Code を再起動した後、新しいセッションで Agentツールの一覧に `r-super-loop-powers:builder` が出ること、そして `subagent_type: "r-super-loop-powers:builder"` に「何も変更せず、空の impl-report JSON(blocked=true, blocked_reason='smoke')を返せ」と頼んで JSON が返ることを確認し、結果を `docs/superpowers/notes/2026-10-03-v0.7-smoke.md` に追記する。
