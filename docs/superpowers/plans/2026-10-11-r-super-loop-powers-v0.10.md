# r-super-loop-powers v0.10 Implementation Plan — スカウト(codex による調査の肩代わり)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opus メインが自分で行っていた「調べもの」(Read / Grep の重ね掛け・調査用 Claude サブエージェント)を、codex の 4 つ目の読み取り専用ロール **scout** に移し、起動から保存・記帳までを 1 回のシェル呼び出し(`bin/scout.ps1`)で終えられるようにする。

**Architecture:** `codex-run.ps1 -Role scout`(read-only・`gpt-6.1-sol`・effort 既定 `medium`・`-Web` で Web 検索の設定を渡す)を、まとめ役 `bin/scout.ps1` が呼ぶ。`scout.ps1` は prompt 生成 → `codex-run.ps1` → `codex-status.ps1` 待ち → 報告の型(`## 結論` / `## 根拠`)の機械検査 → `<goal-dir>/scout/<label>.md` 保存 → `scout/index.md` 追記 → `loop-log.ps1 -Who codex-scout` を行い、標準出力には KV 行(結論 5 行以内)だけを返す。規則(「調べものはまずスカウト」)は SKILL.md / workflow-a / workflow-b / policy.md に書く。

**Tech Stack:** Windows PowerShell 5.1、codex-cli 0.160.0(`gpt-6.1-sol`)、git。

**Spec:** `docs/superpowers/specs/2026-10-11-r-super-loop-powers-v0.10-design.md`

## Global Constraints

- 変更対象は Claude 版のみ。`skills-codex/` と `skills/r-super-loop-powers/templates/` は変更しない(`scripts/sync-templates.ps1 -Mode Verify` が通り続ける)
- PowerShell 5.1 で動くこと(`?:` `??` `&&` を使わない。条件代入は `$(if (...) { } else { })`)。`-File` 起動では配列パラメータに複数値を渡せない
- 日本語の文字列リテラルを含む `.ps1` は **UTF-8 BOM 付き**で保存する(PS 5.1 は BOM 無しを ANSI として読む)。`bin/scout.ps1` は日本語見出しを扱うので BOM 付き。`bin/codex-run.ps1` は BOM 無しの ASCII のまま(ロール指示に日本語を書かない)。BOM 付与: `powershell -NoProfile -Command "$p='<path>'; [IO.File]::WriteAllText($p, [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding $false)), (New-Object Text.UTF8Encoding $true))"`
- 書き出すファイル(報告・index・prompt)は UTF-8 **BOM なし**・LF(`codex-common.ps1` の `Write-TextFile`)
- テストは既存の形式(`Check` 関数、最後に `ALL PASS` / `FAILURES: n`、実行は `powershell -NoProfile -ExecutionPolicy Bypass -File tests\<名>.tests.ps1`)。codex は `where.exe` で差し替える
- codex は `codex-run.ps1` 経由でのみ起動する。`scout.ps1` も codex のコマンドを自分で組み立てない
- scout の effort 既定 `medium`、モデルは `codex-env.json` の `model`(`gpt-6.1-sol`)。`-WaitMinutes` 既定 9・上限 9。index の問いは 120 字、call-log の問いは 80 字で切る。`CONCLUSION` は最大 5 行
- Web 検索の設定キーは **Task 1 のスパイクで確定した値だけ**を `codex-run.ps1` の定数に書く(確かめずに書かない)
- SKILL.md は LF 正規化で **24,576 バイト以下**(`tests/skill-layout.tests.ps1`)。今 24,530 バイトなので、Task 6 で足す分だけ削る(削る箇所は Task 6 に列挙)
- version: `0.10.0`
- コミットメッセージ末尾に次の 2 行を付ける:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01A2Cf15iqZVNo59KUVNGGcS
  ```

## Review Focus

1. **報告が CRLF・番号付き見出し(`## 2. 結論`)・見出し末尾の空白で返る** — 節の検出が揺れずに `OK` になること → Task 5 の `collect-crlf-numbered-headings`
2. **問いに `|`・改行・120 字超が含まれる** — index は 1 行のまま、120 字で切られること → Task 5 の `index-one-line-long-question`
3. **`-Collect` の対象に `.prompt.md` が無い**(`codex-run.ps1` を直接呼んだラベル)— 落ちずに `問い: (不明)` で保存すること → Task 5 の `collect-without-prompt-md`
4. **state.md が無いゴールディレクトリ** — 報告は保存され、記帳できないことは `WARN:` で済ませ `STATUS: OK` のままにすること → Task 5 の `collect-without-state-warns`
5. **`-Web` を付けない通常の呼び出し** — Web 検索の設定が 1 つも渡らないこと(他ロールの挙動が変わらない)→ Task 3 の `web-off-by-default`

---

### Task 1: スパイク — codex 0.160.0 の read-only で Web 検索を有効にする設定キー

**Files:**
- Create: `docs/superpowers/notes/2026-10-11-v0.10-smoke.md`(§1 だけ。§2 以降は Task 7)

**Interfaces:**
- Produces: `$WebSearchConfig` の値(例: `web_search="live"`)。Task 3 がそのまま定数にする。どれも効かなければ `''`(空)で Task 3 は「未対応」の分岐を実装する

- [ ] **Step 1: 一時ゴールディレクトリでプリフライトを通し、codex の実体を得る**

```powershell
$t = Join-Path $env:TEMP ('scout-spike-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $t | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\codex-preflight.ps1 -EnvOut "$t\codex-env.json"
```
Expected: `PREFLIGHT: OK`(`FAILED` ならユーザーへ `REASON:` を見せて止まる。黙って別モデルにしない)

- [ ] **Step 2: 候補キーを 1 つずつ試す**

プロンプト `"$t\web.md"` を書く(ASCII):
```
Use your web search tool to find the latest stable release version of the npm package "typescript" on https://www.npmjs.com/package/typescript. Answer in two lines: "VERSION: <version>" and "URL: <the page you read>". If you have no web search tool available, answer exactly: WEB_UNAVAILABLE
```
候補(この順): (1) `web_search="live"` (2) `web_search=live` (3) `tools.web_search=true` (4) `features.web_search_request=true`(deprecated。参考)。PowerShell は `<` の入力リダイレクトを持たないので、**Bash ツール**で行う(codex は stdin を閉じないと止まる: codex-invocation.md §1)。まず `cat "$t/codex-env.json"` で `kind` と `exe`(または `node` と `js`)を読み、その値で:
```bash
T="/c/Users/<user>/AppData/Local/Temp/scout-spike-<id>"   # $t を POSIX 形式で
EXE="<codex-env.json の exe。kind=node なら node のパス>"
JS=""                                                       # kind=node なら js のパス、exe なら空
KEY='web_search="live"'                                     # 候補ごとに差し替える
N=1                                                         # 候補の番号
"$EXE" $JS exec --json - -C "$T" -s read-only -c approval_policy=never -c model_reasoning_effort=low -c windows.sandbox=unelevated --skip-git-repo-check --disable plugins -m gpt-6.1-sol -c "$KEY" -o "$T/web-$N.last.txt" < "$T/web.md" > "$T/web-$N.out.jsonl" 2> "$T/web-$N.err.txt"; echo "exit=$?"
cat "$T/web-$N.last.txt"; grep -o -E '"type":"[a-z_]*web[a-z_]*"' "$T/web-$N.out.jsonl" | sort | uniq -c; tail -c 600 "$T/web-$N.err.txt"
```
Expected: 効くキーでは `VERSION:` と `URL:` が返り、`out.jsonl` に web 検索のイベント(`web_search` を含む item)がある。効かないキーでは `WEB_UNAVAILABLE`、または `-c` の解釈エラーで非ゼロ終了。

- [ ] **Step 3: 結果をスモークノート §1 に書く**

`docs/superpowers/notes/2026-10-11-v0.10-smoke.md`:
```markdown
# v0.10 スモーク — スカウト

対象: spec §10。実施環境: Windows 11、Windows PowerShell 5.1、codex-cli <version> / `gpt-6.1-sol`。

## 1. Web 検索の設定キー(spec §10-1)

| 候補 | exit | 最終メッセージ | out.jsonl の web イベント | 判定 |
|---|---|---|---|---|
| `web_search="live"` | | | | |
| `web_search=live` | | | | |
| `tools.web_search=true` | | | | |
| `features.web_search_request=true` | | | | |

採用: `<キー>`(または「0.160.0 では未対応」)。read-only サンドボックスでも Web 検索は <効いた / 効かない>。
```
表を埋め、採用値を書く。

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/notes/2026-10-11-v0.10-smoke.md
git commit -m "docs: v0.10 スパイク — codex 0.160.0 の Web 検索の設定キー(spec §10-1)"
```

---

### Task 2: ロール憲章にスカウトを足し、実装役の定義へ同期する

**Files:**
- Modify: `skills/r-super-loop-powers/references/roles.md`(全体図の表、末尾に新節)
- Modify: `agents/builder.md`(`scripts/sync-roles.ps1 -Mode Copy` で区間を作り直す)
- Test: `tests/roles-sync.tests.ps1`

**Interfaces:**
- Produces: `## スカウト (scout)` の節(識別子 `scout`)。Task 3 の `codex-run.ps1` が `Get-RoleCharter -Ids @('overview','scout')` で差し込む

- [ ] **Step 1: テストに `scout` を足す**

`tests/roles-sync.tests.ps1` の `foreach ($id in @('overview', 'opus', 'proxy-fable', 'gate-fable', 'techpm', 'reviewer', 'builder', 'grareco'))` を
```powershell
foreach ($id in @('overview', 'opus', 'proxy-fable', 'gate-fable', 'techpm', 'reviewer', 'builder', 'grareco', 'scout')) {
```
にする。

- [ ] **Step 2: 落ちることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\roles-sync.tests.ps1 | grep -E 'FAIL|ALL PASS'`
Expected: `FAIL section-scout`

- [ ] **Step 3: roles.md を変える**

全体図の表の最後の行 `| 振り返り・グラレコ | Opus・グラレコ | — |` の**直後**に 1 行足す:
```markdown
| 調査(どの段階でも) | スカウト(codex。問いに答える報告) | Opus(報告の採否。根拠の無い結論は事実として扱わない) |
```
ファイル末尾(`## グラレコ (grareco)` 節の後)に足す:
```markdown

## スカウト (scout)

- **あなたの立場**: codex(読み取り専用)。Opus から渡された**問い**に、対象プロジェクトとゴール文書(指示があれば Web も)を読んで答える調査役。どの段階でも呼ばれる。設計や判定には関わらない。
- **受け取るもの / 返すもの**: 問い・調べる範囲(作業ディレクトリ・ゴール文書のパス)・Web 可否を受け取る。固定の型(問い / 結論 5 行以内 / 根拠は主張ごとに `file:line` か URL / 未確認)の報告を最終メッセージで返す。
- **あなたが決めること**: どこをどう読むか、何を根拠として示すか、何が未確認か。
- **あなたが決めないこと**: 実装方式(技術PM)、ユーザー価値(代理Fable / 人間)、要件適合(ゲートFable)、コードの変更(実装役)。問いの外のことを提案しない。見つからないものを推測で埋めない(「見つからない」と書き、探した場所を根拠に書く)。
- **あなたの出力の判定のされ方**: 実行の成否は `codex-status.ps1` の `STATUS: OK`、報告の型は `scout.ps1` が機械で確かめる(「結論」と「根拠」の節が無ければ不合格で、index に載らない)。根拠の無い結論は Opus が事実として扱わない。
```

- [ ] **Step 4: 実装役の定義へ同期し、テストを通す**

Run:
```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sync-roles.ps1 -Mode Copy
powershell -NoProfile -ExecutionPolicy Bypass -File tests\roles-sync.tests.ps1 | grep -E 'FAIL|ALL PASS'
```
Expected: `ALL PASS`(`agents/builder.md` の区間に全体図の新しい行が入る)

- [ ] **Step 5: Commit**

```bash
git add skills/r-super-loop-powers/references/roles.md agents/builder.md tests/roles-sync.tests.ps1
git commit -m "feat: ロール憲章にスカウト(scout)の節と全体図の行を足す"
```

---

### Task 3: `codex-run.ps1` — `-Role scout`(effort medium)と `-Web`

**Files:**
- Modify: `skills/r-super-loop-powers/bin/codex-run.ps1:28-36`(param)、`:83-140`(brief)、`:230-235`(effort 既定)、`:305-320`(codexArgs)、`:381-398`(meta)
- Test: `tests/codex-run.tests.ps1`

**Interfaces:**
- Consumes: Task 1 の `$WebSearchConfig` の値、Task 2 の `scout` 節
- Produces: `codex-run.ps1 -Role scout [-Web] [-Effort …]`。`meta.json` に `web`(bool)。Task 5 の `scout.ps1` がこの引数で呼ぶ

- [ ] **Step 1: テストを足す**

`tests/codex-run.tests.ps1` の `# v0.9 (F): long prompts warn; …` ブロックの後、`Remove-Item -LiteralPath $t …` の前に:
```powershell
# v0.10: scout role (read-only, medium) and -Web.
$r = Invoke-Run $env1 'sc' @('-Role', 'scout')
$m = Get-Meta 'sc'
Check 'scout-read-only-medium' ($r.Code -eq 0 -and $m.sandbox -eq 'read-only' -and $m.effort -eq 'medium') $r.Out
$scPrompt = Get-Content -Raw -Encoding UTF8 (Join-Path $t 'runs\sc.prompt.txt')
Check 'scout-brief' ($scPrompt -match 'ROLE: SCOUT' -and $scPrompt -match 'WEB_UNAVAILABLE' -and $scPrompt -match 'four headings') 'scout brief'
Check 'charter-scout-section' ($scPrompt -match '\(scout\)' -and $scPrompt -notmatch '\(techpm\)') 'scout charter section'
Check 'web-off-by-default' ($m.web -eq $false -and $m.command -notmatch 'web_search') $m.command
$r = Invoke-Run $env1 'scw' @('-Role', 'scout', '-Web')
$mw = Get-Meta 'scw'
$runSrc2 = Get-Content -Raw $run
$webKey = [regex]::Match($runSrc2, "(?m)^\`$WebSearchConfig\s*=\s*'([^']*)'").Groups[1].Value
Check 'web-key-is-a-constant' ($runSrc2 -match "(?m)^\`$WebSearchConfig\s*=") 'codex-run.ps1 has no $WebSearchConfig constant'
if ($webKey) {
    Check 'web-flag-passes-key' ($mw.web -eq $true -and $mw.command -match ('-c ' + [regex]::Escape((ConvertTo-Arg $webKey)))) $mw.command
} else {
    Check 'web-flag-unsupported-warns' ($mw.web -eq $false -and $r.Out -match '(?m)^WARN: .*web search') $r.Out
}
```
`ConvertTo-Arg` はテストから見えないので、テストファイル冒頭(`$skillDir = …` の次)に
```powershell
. (Join-Path $skillDir 'bin\codex-common.ps1')
```
を足す。

- [ ] **Step 2: 落ちることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\codex-run.tests.ps1 | grep -E 'FAIL|ALL PASS'`
Expected: `FAIL scout-read-only-medium`(`-Role scout` が ValidateSet で拒否される)ほか

- [ ] **Step 3: param を変える**

```powershell
    # Who codex is in this delegation. Every role is read-only: implementation is
    # done by the Claude-side builder agent, so codex never needs to write.
    [Parameter(Mandatory = $true)][ValidateSet('techpm', 'reviewer', 'grareco', 'scout')][string]$Role,
    [string]$Model,
    # Empty = role default (techpm / reviewer: max, grareco: low, scout: medium).
    [ValidateSet('', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra')][string]$Effort = '',
    # Turn on codex's built-in web search for this run (scout only in practice).
    # Off by default so no other role's behaviour changes.
    [switch]$Web,
```

- [ ] **Step 4: 定数とロール指示を足す**

`$NoUltraModels = …` の直後に(Task 1 で確定した値。効かなければ `''`):
```powershell
# codex config that enables the built-in web search (measured on codex-cli 0.160.0,
# spec v0.10 F19 / smoke note 2026-10-11 section 1). Empty = this codex has no key
# that works, and -Web only warns.
$WebSearchConfig = 'web_search="live"'
```
`$RoleBriefs` に(`grareco = @'…'@` の後、閉じ `}` の前):
```powershell
    scout = @'
== ROLE: SCOUT (investigator, read-only) ==
You answer ONE question by reading the working directory and the goal documents
named in the task (and the web, only when the task says web search is allowed).
You propose no design, judge no requirement, change no file, and do not invoke
process skills (brainstorming, writing-plans or similar). When the answer is in
the files, open them; do not answer from memory.
Your final message MUST use exactly the four headings listed in the task, in that
order: the question restated; the conclusion (at most 5 lines; "not found" plus
where you looked is a valid conclusion); the evidence (one line per claim, each
with file:line or a URL and the quoted text); what you could not verify.
If web search was allowed but no web tool was available to you, write
WEB_UNAVAILABLE as the first line of the last section. Never invent a file, a
line number or a URL.
== END ROLE ==

'@
```

- [ ] **Step 5: effort 既定・codexArgs・meta を変える**

effort:
```powershell
if (-not $Effort) {
    if ($Role -eq 'grareco') { $Effort = 'low' }
    elseif ($Role -eq 'scout') { $Effort = 'medium' }
    else { $Effort = 'max' }
}
```
`if ($Model) { $codexArgs += @('-m', $Model) }` の直後:
```powershell
$webOn = $false
if ($Web) {
    if ($WebSearchConfig) { $codexArgs += @('-c', $WebSearchConfig); $webOn = $true }
    else { $warnings += 'this codex-run.ps1 has no working web search key for this codex version; the run goes out without web search (smoke note 2026-10-11).' }
}
```
`$meta` の `sandbox = $Sandbox` の次の行に `web = $webOn` を足す。`Write-Kv 'SANDBOX' $Sandbox` の次に `Write-Kv 'WEB' $(if ($webOn) { 'on' } else { 'off' })`。
冒頭コメント(行 28-29 付近以外)で「3 roles」と書いている箇所があれば「4 roles」に直す(`grep -n "three\|3 roles" bin/codex-run.ps1` で確認)。

- [ ] **Step 6: テストを通す**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\codex-run.tests.ps1 | grep -E 'FAIL|ALL PASS'`
Expected: `ALL PASS`

- [ ] **Step 7: Commit**

```bash
git add skills/r-super-loop-powers/bin/codex-run.ps1 tests/codex-run.tests.ps1
git commit -m "feat: codex-run.ps1 に scout ロール(read-only・medium)と -Web を足す"
```

---

### Task 4: `loop-log.ps1` の語彙に `codex-scout`

**Files:**
- Modify: `skills/r-super-loop-powers/bin/loop-log.ps1:40`
- Test: `tests/loop-log.tests.ps1`

**Interfaces:**
- Produces: `loop-log.ps1 -Who codex-scout -Purpose <text>` が通る。Task 5 が使う

- [ ] **Step 1: テストを足す**

`tests/loop-log.tests.ps1` の `Check 'log-explicit-phase' …` の直後:
```powershell
$r = Invoke-Log $g @('-Who', 'codex-scout', '-Purpose', 'scout-1: どこで決まるか')
Check 'log-codex-scout' ($r.Code -eq 0 -and (Get-Text (Join-Path $g 'call-log.md')) -match '(?m)\| codex-scout \| milestone-implementation \| scout-1: どこで決まるか$') $r.Out
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\loop-log.tests.ps1 | grep -E 'FAIL|ALL PASS'`
Expected: `FAIL log-codex-scout`

- [ ] **Step 3: 語彙を足す**

```powershell
$Roles = @('fable', 'codex-techpm', 'codex-review', 'codex-grareco', 'codex-scout', 'sonnet-builder')
```

- [ ] **Step 4: テストを通す**

Run: 同上。Expected: `ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add skills/r-super-loop-powers/bin/loop-log.ps1 tests/loop-log.tests.ps1
git commit -m "feat: loop-log.ps1 の -Who に codex-scout を足す"
```

---

### Task 5: `bin/scout.ps1` — 起動から保存・記帳までを 1 回で

**Files:**
- Create: `skills/r-super-loop-powers/bin/scout.ps1`(UTF-8 BOM 付き)
- Test: `tests/scout.tests.ps1`

**Interfaces:**
- Consumes: `codex-run.ps1 -Role scout [-Web] [-Effort]`(Task 3)、`codex-status.ps1 -RunDir -Label -WaitMinutes`(既存。KV 出力 `STATUS:` / `REASON:` / `NEXT:`)、`loop-log.ps1 -Who codex-scout` / `-SetCodexRun` / `-Clear codex-run`(Task 4)、`codex-common.ps1` の `Write-Kv` / `Read-TextFile` / `Write-TextFile`
- Produces: `scout.ps1 -GoalDir <dir> -WorkDir <repo> (-Question <text> | -QuestionFile <path>) [-Web] [-Effort …] [-WaitMinutes 9] [-Label <l>] [-Async] [-EnvFile <path>]` / `scout.ps1 -GoalDir <dir> -Collect <label> [-WaitMinutes 9]` / `scout.ps1 -GoalDir <dir> -List`。stdout は KV 行: `STATUS` / `LABEL` / `REPORT` / `CONCLUSION`(≤5) / `UNVERIFIED` / `WEB` / `ELAPSED_MIN`、失敗時 `STATUS` / `REASON` / `NEXT`(+ `RAW`)。exit 0 は `OK` / `STARTED` / `-List` のみ

- [ ] **Step 1: テストの骨格と「回収」のテストを書く**

`tests/scout.tests.ps1`(UTF-8 BOM 付きで保存。日本語を含む):
```powershell
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
$conc = @([regex]::Matches($r.Out, '(?m)^CONCLUSION: (.*)$') | ForEach-Object { $_.Groups[1].Value })
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

Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Output "FAILURES: $($script:failures)"; exit 1 }
Write-Output 'ALL PASS'
exit 0
```
保存後に BOM を付ける(Global Constraints のコマンド)。

- [ ] **Step 2: 落ちることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\scout.tests.ps1 | grep -E 'FAIL|ALL PASS' | head -5`
Expected: `FAIL collect-ok` ほか(スクリプトが無い)

- [ ] **Step 3: `bin/scout.ps1` を書く**

```powershell
#Requires -Version 5.1
<#
  scout.ps1 -- one codex "scout" (read-only investigation) in ONE call:
    prompt -> codex-run.ps1 -Role scout -> codex-status.ps1 -> format check
    -> <goal-dir>/scout/<label>.md + scout/index.md -> loop-log.ps1 -Who codex-scout

  Modes:
    start    -GoalDir -WorkDir (-Question | -QuestionFile) [-Web] [-Effort] [-WaitMinutes 9]
             [-Label] [-Async] [-EnvFile]
    collect  -GoalDir -Collect <label> [-WaitMinutes 9]
    list     -GoalDir -List

  stdout is KEY: VALUE lines only. STATUS OK -> LABEL / REPORT / CONCLUSION (<= 5 lines,
  one per KV) / UNVERIFIED / WEB / ELAPSED_MIN. Anything else -> STATUS / REASON / NEXT
  (+ RAW for INCOMPLETE) and exit 1. The report file is never read back by the
  orchestrator: CONCLUSION is all it gets.
  Saved as UTF-8 with BOM: the report headings are Japanese.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GoalDir,
    [string]$WorkDir = '',
    [string]$Question = '',
    [string]$QuestionFile = '',
    [switch]$Web,
    [ValidateSet('', 'low', 'medium', 'high', 'xhigh', 'max')][string]$Effort = '',
    # Capped at 9 like codex-status.ps1 (one call must fit a 10-minute tool timeout).
    [int]$WaitMinutes = 9,
    [string]$Label = '',
    [switch]$Async,
    [string]$Collect = '',
    [switch]$List,
    [string]$EnvFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'codex-common.ps1')

$runScript = Join-Path $PSScriptRoot 'codex-run.ps1'
$statusScript = Join-Path $PSScriptRoot 'codex-status.ps1'
$logScript = Join-Path $PSScriptRoot 'loop-log.ps1'

function Stop-Failed([string]$Status, [string]$Reason, [string]$Next) {
    Write-Kv 'STATUS' $Status
    Write-Kv 'REASON' $Reason
    if ($Next) { Write-Kv 'NEXT' $Next }
    exit 1
}
function Invoke-Ps([string]$Script, [string[]]$ScriptArgs) {
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $hostExe)) { $hostExe = 'powershell' }
    $out = & $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script @ScriptArgs 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
function Get-KvValue([string]$Text, [string]$Key) {
    $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Key) + ': ?(.*)$')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}
# Body of "## <Name>" (optional number, trailing spaces tolerated) up to the next
# "## " heading. $null when the heading is absent -- that is the INCOMPLETE signal.
function Get-Section([string]$Text, [string]$Name) {
    $lf = $Text -replace "`r`n", "`n"
    $m = [regex]::Match($lf, '(?m)^##\s*(?:\d+\.?\s*)?' + [regex]::Escape($Name) + '[^\n]*\n([\s\S]*?)(?=^##\s|\z)')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}
function Get-Lines([string]$Body) {
    if ($null -eq $Body) { return @() }
    return @(($Body -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
# One line, no "|" (it would break the index columns), at most $Max characters.
function Limit-Text([string]$Text, [int]$Max) {
    $s = (($Text -replace '\s+', ' ') -replace '\|', '/').Trim()
    if ($s.Length -gt $Max) { return $s.Substring(0, $Max) }
    return $s
}

if (-not (Test-Path -LiteralPath $GoalDir -PathType Container)) { Stop-Failed 'FAILED' "GoalDir does not exist: $GoalDir" '' }
$GoalDir = (Resolve-Path -LiteralPath $GoalDir).Path
$runDir = Join-Path $GoalDir 'codex-runs'
$scoutDir = Join-Path $GoalDir 'scout'
$indexFile = Join-Path $scoutDir 'index.md'
if ($WaitMinutes -gt 9) { $WaitMinutes = 9 }
if ($WaitMinutes -lt 0) { $WaitMinutes = 0 }

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
if ($List) {
    $idx = Read-TextFile $indexFile
    if (-not $idx.Trim()) { Write-Kv 'INDEX' 'none' } else { Write-Output $idx.TrimEnd() }
    Write-Kv 'STATUS' 'OK'
    exit 0
}

# ---------------------------------------------------------------------------
# collect: wait, verify the shape, save, index, log
# ---------------------------------------------------------------------------
function Complete-Run([string]$L) {
    if (-not (Test-Path -LiteralPath (Join-Path $runDir "$L.meta.json"))) {
        Stop-Failed 'FAILED' "no run named '$L' in $runDir" "scout.ps1 -GoalDir '$GoalDir' -List"
    }
    $st = Invoke-Ps $statusScript @('-RunDir', $runDir, '-Label', $L, '-WaitMinutes', $WaitMinutes)
    $status = Get-KvValue $st.Out 'STATUS'
    if ($status -ne 'OK') {
        if (-not $status) { $status = 'FAILED' }
        $next = Get-KvValue $st.Out 'NEXT'
        if ($status -eq 'RUNNING' -or $status -eq 'STALLED') { $next = "scout.ps1 -GoalDir '$GoalDir' -Collect $L" }
        foreach ($k in @('REASON', 'ERROR', 'STDERR_TAIL')) { $v = Get-KvValue $st.Out $k; if ($v) { Write-Kv $k $v } }
        Write-Kv 'LABEL' $L
        Write-Kv 'STATUS' $status
        Write-Kv 'NEXT' $next
        exit 1
    }
    foreach ($w in [regex]::Matches($st.Out, '(?m)^(WARN|BOUNDARY_HIT): .*$')) { Write-Output $w.Value }

    $meta = Read-TextFile (Join-Path $runDir "$L.meta.json") | ConvertFrom-Json
    $body = Read-TextFile (Join-Path $runDir "$L.last.txt")
    if (-not (Test-Path -LiteralPath $scoutDir)) { New-Item -ItemType Directory -Path $scoutDir -Force | Out-Null }
    $missing = @()
    foreach ($n in @('結論', '根拠')) { if ($null -eq (Get-Section $body $n)) { $missing += $n } }
    if ($missing.Count -gt 0) {
        $raw = Join-Path $scoutDir "$L.raw.md"
        Write-TextFile $raw $body
        Write-Kv 'LABEL' $L
        Write-Kv 'RAW' $raw
        Stop-Failed 'INCOMPLETE' ('missing section: ' + ($missing -join ', ')) 'Re-run once with the same question; if it fails again, investigate yourself and log one codex-scout line (SKILL.md).'
    }

    # The question comes from the prompt this script wrote; a hand-launched run has none.
    $question = '(不明)'
    $promptMd = Read-TextFile (Join-Path $runDir "$L.prompt.md")
    if ($promptMd) {
        $q = Get-Section $promptMd '問い'
        if ($null -ne $q -and $q.Trim()) { $question = $q.Trim() }
    }
    $webState = 'not-requested'
    if (($meta.PSObject.Properties.Name -contains 'web') -and $meta.web) { $webState = 'used' }
    $unvLines = Get-Lines (Get-Section $body '未確認')
    if ($webState -eq 'used' -and (($unvLines -join "`n") -match 'WEB_UNAVAILABLE')) { $webState = 'unavailable' }
    $effort = ''
    if ($meta.PSObject.Properties.Name -contains 'effort') { $effort = [string]$meta.effort }
    $elapsed = ''
    try {
        $done = Read-TextFile (Join-Path $runDir "$L.done.json") | ConvertFrom-Json
        if ($done.PSObject.Properties.Name -contains 'durationSec') { $elapsed = [string][Math]::Round([double]$done.durationSec / 60.0, 1) }
    } catch { }
    if (-not $elapsed) {
        try { $elapsed = [string][Math]::Round(((Get-Date) - [datetime]$meta.startedAt).TotalMinutes, 1) } catch { $elapsed = '0' }
    }

    $now = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $report = Join-Path $scoutDir "$L.md"
    $header = "- 日時: $now`n- label: $L`n- web: $webState`n- effort: $effort`n- 問い: $(Limit-Text $question 400)`n`n"
    Write-TextFile $report ($header + $body)

    $webYn = $(if ($webState -eq 'not-requested') { 'n' } else { 'y' })
    $idx = Read-TextFile $indexFile
    if (-not $idx) { $idx = "# scout index — $(Split-Path -Leaf $GoalDir)`n`n" }
    elseif (-not $idx.EndsWith("`n")) { $idx += "`n" }
    if ($idx -notmatch ('(?m)^[^|\n]*\| ' + [regex]::Escape($L) + ' \|')) {
        Write-TextFile $indexFile ($idx + "$now | $L | web:$webYn | $(Limit-Text $question 120)`n")
    }

    $logArgs = @('-GoalDir', $GoalDir, '-Who', 'codex-scout', '-Purpose', ($L + ': ' + (Limit-Text $question 80)))
    $state = Read-TextFile (Join-Path $GoalDir 'state.md')
    if ($state -match ('(?m)^\s*-\s*codex-run:\s*' + [regex]::Escape($L) + '\s*$')) { $logArgs += @('-Clear', 'codex-run') }
    $lg = Invoke-Ps $logScript $logArgs
    if ($lg.Code -ne 0) { Write-Kv 'WARN' ('call-log not written: ' + (Get-KvValue $lg.Out 'REASON')) }

    Write-Kv 'STATUS' 'OK'
    Write-Kv 'LABEL' $L
    Write-Kv 'REPORT' $report
    foreach ($c in (Get-Lines (Get-Section $body '結論') | Select-Object -First 5)) { Write-Kv 'CONCLUSION' $c }
    Write-Kv 'UNVERIFIED' $unvLines.Count
    Write-Kv 'WEB' $webState
    Write-Kv 'ELAPSED_MIN' $elapsed
    exit 0
}
if ($Collect) { Complete-Run $Collect }

# ---------------------------------------------------------------------------
# start
# ---------------------------------------------------------------------------
if (-not $WorkDir) { Stop-Failed 'FAILED' '-WorkDir is required to start a scout run' '' }
if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { Stop-Failed 'FAILED' "WorkDir does not exist: $WorkDir" '' }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
if (($Question -and $QuestionFile) -or (-not $Question -and -not $QuestionFile)) { Stop-Failed 'FAILED' 'pass exactly one of -Question / -QuestionFile' '' }
if ($QuestionFile) { $Question = Read-TextFile $QuestionFile }
$Question = ($Question -replace "`r`n", "`n").Trim()
if (-not $Question) { Stop-Failed 'FAILED' 'the question is empty' '' }
if (-not $EnvFile) { $EnvFile = Join-Path $GoalDir 'codex-env.json' }
if (-not (Test-Path -LiteralPath $EnvFile)) { Stop-Failed 'FAILED' "codex-env.json not found: $EnvFile" 'run codex-preflight.ps1 first (SKILL.md startup check 6)' }
foreach ($d in @($runDir, $scoutDir)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

if (-not $Label) {
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $runDir -Filter 'scout-*.meta.json' -ErrorAction SilentlyContinue)) {
        if ($f.Name -match '^scout-(\d+)\.meta\.json$') { $v = [int]$Matches[1]; if ($v -gt $n) { $n = $v } }
    }
    $Label = 'scout-' + ($n + 1)
}
if ($Label -notmatch '^[A-Za-z0-9._-]+$') { Stop-Failed 'FAILED' "Label must be [A-Za-z0-9._-]+ (got: $Label)" '' }
if (Test-Path -LiteralPath (Join-Path $runDir "$Label.meta.json")) { Stop-Failed 'REFUSED' "label '$Label' already exists in $runDir" "scout.ps1 -GoalDir '$GoalDir' -Collect $Label  (or pass a new -Label)" }

$webLine = $(if ($Web) { '使ってよい(公式ドキュメント・一次情報を優先し、URL を根拠に書く)' } else { '使わない' })
$prompt = @(
    '== TASK: SCOUT ==',
    '## 問い',
    $Question,
    '',
    '## 調べる範囲',
    "- 対象プロジェクト: $WorkDir(作業ディレクトリ。git grep / rg / 直接読む)",
    "- ゴール文書: $GoalDir(state.md・goal-frame.md・goal-plan.md・assumptions.md・decisions.md・scout/ の過去の報告)",
    "- Web: $webLine",
    '',
    '## 報告の型(この 4 節をこの順で。最終メッセージだけが読まれる)',
    '- `## 問い` — 問いをそのまま',
    '- `## 結論` — 5 行以内。見つからなければ「見つからない」と探した場所',
    '- `## 根拠` — 主張ごとに 1 行: file:line(または URL)と引用',
    '- `## 未確認` — 確かめられなかったこと(無ければ空)',
    ''
) -join "`n"
$promptFile = Join-Path $runDir "$Label.prompt.md"
Write-TextFile $promptFile $prompt

$runArgs = @('-EnvFile', $EnvFile, '-Label', $Label, '-PromptFile', $promptFile, '-WorkDir', $WorkDir, '-RunDir', $runDir, '-Role', 'scout')
if ($Effort) { $runArgs += @('-Effort', $Effort) }
if ($Web) { $runArgs += '-Web' }
$rr = Invoke-Ps $runScript $runArgs
if ($rr.Code -ne 0 -or (Get-KvValue $rr.Out 'RUN') -ne 'STARTED') {
    Write-Kv 'LABEL' $Label
    Stop-Failed 'FAILED' ('codex-run.ps1 did not start the run: ' + (Limit-Text $rr.Out 400)) 'fix the cause (references/codex-invocation.md) and re-run'
}
foreach ($w in [regex]::Matches($rr.Out, '(?m)^WARN: .*$')) { Write-Output $w.Value }

if ($Async) {
    $lg = Invoke-Ps $logScript @('-GoalDir', $GoalDir, '-SetCodexRun', $Label)
    if ($lg.Code -ne 0) { Write-Kv 'WARN' ('state.md codex-run not set: ' + (Get-KvValue $lg.Out 'REASON')) }
    Write-Kv 'STATUS' 'STARTED'
    Write-Kv 'LABEL' $Label
    Write-Kv 'NEXT' "scout.ps1 -GoalDir '$GoalDir' -Collect $Label"
    exit 0
}
Complete-Run $Label
```
保存後に BOM を付ける。

- [ ] **Step 4: テストを通す**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\scout.tests.ps1 | grep -E 'FAIL|ALL PASS'`
Expected: `ALL PASS`(`sync-failed-relayed` は where.exe の終了を `codex-status` が 5 秒間隔で見るので十数秒かかる)

落ちたら、落ちた `Check` 名ごとに原因を見る(`| grep -A3 FAIL`)。よくある原因: `Get-Section` の正規表現で `(?m)` と `\z` の組み合わせ(末尾に改行が無い本文)、`$meta.web` が `PSCustomObject` で `$false` 文字列になる(`[bool]` 比較に直す)、`-Collect` と `-List` の両方が指定されたときの順序(`-List` が先)。

- [ ] **Step 5: 既存のテストが通ることを確かめる**

Run: `for f in tests/*.tests.ps1; do powershell -NoProfile -ExecutionPolicy Bypass -File "$f" | grep -E 'FAIL|ALL PASS' | sed "s|^|$f: |"; done`
Expected: すべて `ALL PASS`(`skill-layout` は Task 6 までは `version-0.9.0` のまま通る)

- [ ] **Step 6: Commit**

```bash
git add skills/r-super-loop-powers/bin/scout.ps1 tests/scout.tests.ps1
git commit -m "feat: bin/scout.ps1 — codex スカウトを起動から保存・記帳まで 1 回で行う"
```

---

### Task 6: 規則の文書 — SKILL.md / workflow-a / workflow-b / policy.md / codex-invocation.md / README / 版

**Files:**
- Modify: `skills/r-super-loop-powers/SKILL.md`(起動時チェック 6・ディレクトリ契約・記帳・ゲート保護 8/10・読むもの・例外。加えて削る箇所)
- Modify: `skills/r-super-loop-powers/references/workflow-a.md`(A-2 冒頭・A-4 末尾・技術PM契約)
- Modify: `skills/r-super-loop-powers/references/workflow-b.md`(B-2・B-5・B-9)
- Modify: `skills/r-super-loop-powers/policy.md`(責任分担表・PL-001・PL-007・観測)
- Modify: `skills/r-super-loop-powers/references/codex-invocation.md`(冒頭・表・2-6)
- Modify: `README.md`(役とモデル表・リポジトリ構成)
- Modify: `.claude-plugin/plugin.json`(version)
- Test: `tests/skill-layout.tests.ps1`

**Interfaces:**
- Consumes: Task 5 の `scout.ps1` の引数と出力、Task 1 の Web キーの結果

- [ ] **Step 1: テストを変える**

`tests/skill-layout.tests.ps1`:
- `Check 'version-0.9.0' ($ver -eq '0.9.0') "version=$ver"` → `Check 'version-0.10.0' ($ver -eq '0.10.0') "version=$ver"`
- `Check 'skill-mentions-tools' …` の次に:
```powershell
Check 'skill-scout' ($s -match 'scout\.ps1' -and $s -match 'まずスカウト' -and $s -match '-Role techpm \| reviewer \| grareco \| scout') 'scout rules in SKILL.md'
Check 'a-scout' ($a -match 'scout\.ps1') 'scout in workflow-a'
Check 'b-scout' ($b -match 'scout\.ps1') 'scout in workflow-b'
Check 'policy-scout' ((Get-Text (Join-Path $skillDir 'policy.md')) -match '\| スカウト \| Codex `gpt-6\.1-sol` / `medium` / read-only\(`-Role scout`\)' -and (Get-Text (Join-Path $skillDir 'policy.md')) -match 'codex-scout') 'policy.md scout row / vocabulary'
Check 'invocation-scout' ((Get-Text (Join-Path $skillDir 'references\codex-invocation.md')) -match 'scout\.ps1' -and (Get-Text (Join-Path $skillDir 'references\codex-invocation.md')) -match '-Web') 'codex-invocation.md scout'
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\skill-layout.tests.ps1 | grep -E 'FAIL|ALL PASS'`
Expected: `FAIL skill-scout` / `a-scout` / `b-scout` / `policy-scout` / `invocation-scout` / `version-0.10.0`

- [ ] **Step 3: SKILL.md に足す**

(a) 起動時チェック 6 の文 `codex は**技術PM・技術レビュー(高信頼)・グラレコの3ロールだけ**、**すべて `gpt-6.1-sol` の読み取り専用**で使う(実装はSonnetサブエージェント)。` → `codex は**技術PM・技術レビュー(高信頼)・グラレコ・スカウトの4ロールだけ**、**すべて `gpt-6.1-sol` の読み取り専用**で使う。`

(b) ディレクトリ契約: `├── codex-runs/              # codex(技術PM・技術レビュー・グラレコ)の実行記録` → `├── codex-runs/              # codex 4 ロールの実行記録`、その直後に
```
├── scout/                   # スカウトの報告(index.md / scout-<n>.md。scout.ps1 が書く)
```

(c) 記録ルールの冒頭 `fable / codex-techpm / codex-review / codex-grareco / sonnet-builder を呼ぶたび、` → `fable / codex-techpm / codex-review / codex-grareco / codex-scout / sonnet-builder を呼ぶたび、`。同じ段落の箇条書き最後 `- 報告の転記は …` の次に:
```
- スカウトは `scout.ps1` が成功時に記帳する(Opus は重ねて呼ばない)。手で記帳するのは、再実行しても OK にならず自分で代行したときの 1 行だけ
```

(d) ゲート保護ルール 8 の末尾 `判定を目視や推測で代替しない` → `判定を目視や推測で代替しない。グラレコとスカウトの失敗だけはループを止めない(代行して記帳する)`

(e) ゲート保護ルール 10: `` `-Role techpm | reviewer | grareco` のいずれかで起動し `` → `` `-Role techpm | reviewer | grareco | scout` のいずれかで起動し ``、末尾 `要件適合の判定をさせない` はそのまま。

(f) 「読むものと読まないもの」の表、`| codex を呼ぶとき | …` の行の次に:
```
| 調べもの(場所が分からない・3 ファイル以上・Web) | **まずスカウト**: `bin/scout.ps1 -GoalDir … -WorkDir … -Question "…" [-Web]`(Bash の timeout 600000)を 1 回呼び、`CONCLUSION:` 行だけ使う。投げる前に `scout.ps1 -List`。根拠が要るときだけ `REPORT:` の該当行を Grep | Opus 本体での Read / Grep の重ね掛け、調査用の Claude サブエージェント(Explore / general-purpose / Plan) |
```

(g) 例外・停止時の `**codex委譲はセッションを跨いで生き残る。**` の段落末尾に 1 文: `スカウトは `-Async` のときだけ `codex-run:` に残る。同期のものは再開パケットの「未完了の委譲」に出るので、どちらも `scout.ps1 -Collect <ラベル>` で回収する。`

- [ ] **Step 4: SKILL.md を 24,576 バイト以下に収める(削る)**

測る(PowerShell ツールで):
```powershell
$s=[IO.File]::ReadAllText('skills\r-super-loop-powers\SKILL.md',(New-Object Text.UTF8Encoding $false)); [Text.Encoding]::UTF8.GetByteCount(($s -replace "`r`n","`n"))
```
24,576 を超えていれば、次を上から順に適用し、そのたびに測る。収まったら止める:

- T1 境界リセットの冒頭段落の括弧 `(state.md 全文・待ち・否定リスト・goal-frame の制約/承認基準/終了条件・対象マイルストーン・未検証仮定・直近の判定と retro の「次回変えること」・未完了の委譲。要約なし)` → `(state.md 全文・制約系・未検証仮定・直近の判定・未完了の委譲。要約なし)`
- T2 同節の箇条書き `- パケットは 9,500 文字に収まるよう後方の節(マイルストーン・仮定・判定・retro)だけが切られ、全文は `<goal-dir>/resume-packet.md` にある。制約系の節は切られない(それだけで超えるときは切らずに渡す。`-Mark` の `WARN:` で分かる)` → `- パケットは 9,500 文字に収まるよう後方の節だけが切られる(制約系は切らない)。全文は `<goal-dir>/resume-packet.md``
- T3 ディレクトリ契約の `├── hook-log.md              # フックの記録(Stop: PASS/BLOCK/ERROR、再開注入: RESUME/STALE/ERROR、文脈メーター: CTX)` → `├── hook-log.md              # フックの記録(PASS/BLOCK/ERROR・RESUME/STALE・CTX)`
- T4 起動時チェックの末尾の独立行 `   ゴール開始前にチェック7・8を通さずにワークフローBへ進まない。` を消す(チェック 8 に同じ規則がある)
- T5 冒頭の行 `各担当(あなた自身を含む)の立場・決めること・決めないことは `references/roles.md`(ロール憲章)にまとめてある。` を消す(起動時チェック 1 に同じ案内がある。`roles.md` への言及はチェック 1 に残るので `skill-roles-jit` は通る)

どれを適用したかを Step 9 のコミットメッセージに書く。

- [ ] **Step 5: workflow-a / workflow-b**

`references/workflow-a.md`:
- 「技術PM(Codex)共通契約」の `- **プロンプト必須要素**:` の 2 項末尾(`…に達した実測がある)`)の次の文として: `スカウトの報告(`scout/<label>.md`)があれば `REPORT:` のパスを添え、同じ探索を技術PMに繰り返させない。`
- A-2〜A-4 の段落冒頭 `` `superpowers:brainstorming` を起動し、`` の**前**に 1 文: `現状把握(既存の流れ・該当ファイル・使われ方)は Opus が自分で探索せず `bin/scout.ps1` に投げる(SKILL.md「読むものと読まないもの」)。`
- 同段落の `**MVPでは plan 完成後に技術PMの実装アセスを取る**` の**前**に 1 文: `plan に書く対象ファイル・関数で場所が分からないものはスカウトに投げる。`

`references/workflow-b.md`:
- B-2〜B-3 の `実装役は Agentツールの …` の段落の**前**に 1 文: `委譲文の「対象範囲」に書くファイルの確認はスカウト(`bin/scout.ps1`)に投げ、Opus は自分で探索しない。`
- B-5 の `- **MVP**: Opusメインが**セルフチェック**(…)を行い、` の文末 `を作成する(判断記録欄から decisions.md を参照)。` の次に: `submission の「検証」節に書く事実(テストの所在・設定の既定値など)の確認はスカウトに投げる。判断は Opus が行う。`
- B-9 の `REJECT理由から発見された未知は assumptions.md に追記する。` の次に: `REJECT 理由の原因調査(どこで何が起きたか)はスカウトに投げ、戻り先の決定はゲートFableに委ねる。`

- [ ] **Step 6: policy.md**

- 責任分担表の `| 画像生成(Codex組み込み image_gen ツール) | …` の行の**次**に:
```
| スカウト | Codex `gpt-6.1-sol` / `medium` / read-only(`-Role scout`) | Opus の問いに、対象プロジェクト・ゴール文書(指示があれば Web)を読んで固定の型(問い / 結論 / 根拠 / 未確認)で答える | Opus が調べものを行うとき(どの工程でも)。`bin/scout.ps1` 経由で 1 回 1 問 | コード変更。設計提案・要件判定。問いの外の助言 |
```
- PL-001: `/グラレコ(いずれも読み取り専用)` → `/グラレコ/スカウト(調査。いずれも読み取り専用)`
- PL-007: `fable / codex-techpm / codex-review / codex-grareco / sonnet-builder の呼び出し` → `fable / codex-techpm / codex-review / codex-grareco / codex-scout / sonnet-builder の呼び出し`
- 観測の call-log 形式: `fable|codex-techpm|codex-review|codex-grareco|sonnet-builder` → `fable|codex-techpm|codex-review|codex-grareco|codex-scout|sonnet-builder`

- [ ] **Step 7: codex-invocation.md**

- 冒頭の `codex は3ロールすべて**読み取り専用**で、` → `codex は4ロール(techpm / reviewer / grareco / scout)すべて**読み取り専用**で、`
- 表に 1 行(`bin/codex-status.ps1` の行の次): `| `bin/scout.ps1` | スカウト(調査)を起動から保存・記帳まで**1 回で**行うまとめ役。scout ロールはこれ経由でだけ呼ぶ | 問いごとに 1 回 |`
- `### 2-5. 中断する` の後に:
```markdown
### 2-6. スカウト(調査)— `bin/scout.ps1`

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\scout.ps1" `
  -GoalDir "<goal-dir>" -WorkDir "<対象プロジェクトのルート>" `
  -Question "<問い。長いときは -QuestionFile>" [-Web] [-Effort medium] [-WaitMinutes 9]
```

Bash ツールの `timeout` を 600000 にして呼ぶ。中で `codex-run.ps1 -Role scout` → `codex-status.ps1` → 型の検査 → `scout/<label>.md` と `scout/index.md` → `loop-log.ps1 -Who codex-scout` まで行う。読むのは標準出力の KV 行だけ:

| 行 | 意味 |
|---|---|
| `STATUS: OK` | `REPORT:`(保存先)・`CONCLUSION:`(結論。最大 5 行)・`UNVERIFIED:`(未確認の件数)・`WEB:`(`used` / `not-requested` / `unavailable`)・`ELAPSED_MIN:` |
| `STATUS: INCOMPLETE` | 報告に `## 結論` か `## 根拠` が無い。`RAW:` に本文。index には載らない。同じ問いで 1 回だけ再実行 |
| `STATUS: RUNNING` / `STALLED` | 9 分で終わらなかった。`NEXT:` の `scout.ps1 -Collect <label>` で回収する |
| それ以外(`FAILED` / `SUSPECT` / `LOST` …) | `codex-status.ps1` の判定をそのまま中継。保存も記帳もされていない。1 回だけ再実行し、再度失敗なら Opus が自分で調べて `loop-log.ps1 -Who codex-scout -Purpose "<label>: FAILED→Opus が代行"` と記帳する |

- `-Async` で起動だけして `LABEL:` を受け取り(state.md の `codex-run:` に置かれる)、後で `-Collect <label>` で回収する。並行して何本も走らせるときに使う
- `-List` で `scout/index.md` を出す。投げる前に同じ問いが無いか引く
- `-Web`: codex の組み込み Web 検索を有効にする(`codex-run.ps1 -Web`。設定キーは `<Task 1 のスモークノート §1 の「採用」の値をここに書く>`。read-only で効くかどうかも同 §1 の実測を書く)。報告の `## 未確認` が `WEB_UNAVAILABLE` なら `WEB: unavailable` が出るので、その Web 調査は Opus が行う
- 根拠の無い結論は事実として扱わない。必要な根拠だけ `REPORT:` のファイルを Grep / 行範囲で見る(全文は読まない)
```
- `## 4. プロンプトに必ず入れる要素` に 1 行: `- **scout**: `scout.ps1` が問い・調べる範囲・報告の型を組む。Opus は問いだけ書く(何を知りたいか・どこを見ればよさそうか)`

- [ ] **Step 8: README と版**

- README「役とモデル(Claude版)」の表、`| グラレコ | …` の行の次に: `| スカウト | codex `gpt-6.1-sol` / medium / read-only | Opus の調べもの(リポジトリ・ゴール文書・Web)。`bin/scout.ps1` が起動から保存(`scout/`)・記帳まで 1 回で行い、Opus には結論 5 行だけが入る。失敗してもループは止めない(Opus が代行) |`
- README「リポジトリ構成」の `bin/` の括弧内 `記帳 loop-log・再開パケット resume-packet` → `記帳 loop-log・再開パケット resume-packet・スカウト scout`
- README の Web 検索の前提(「役とモデル」表の下の段落の末尾に 1 文。角括弧は Task 1 の結果で置き換える): `スカウトの `-Web` は codex の組み込み Web 検索を使う(codex-cli 0.160.0 では [設定キー `<採用値>` で効く / 未対応で Opus が Web 調査を行う]: `docs/superpowers/notes/2026-10-11-v0.10-smoke.md` §1)。`
- `.claude-plugin/plugin.json` の `"version": "0.9.0"` → `"version": "0.10.0"`。`description` の `Codex gpt-6.1-sol技術PM・技術レビュー(読み取り専用)` → `Codex gpt-6.1-sol技術PM・技術レビュー・スカウト(読み取り専用)`。SKILL.md の frontmatter `description` も同じ置換(こちらは 24 KB の計算に入るので、Step 4 の測り直しをする)

- [ ] **Step 9: テストを通し、コミット**

Run:
```
powershell -NoProfile -ExecutionPolicy Bypass -File tests\skill-layout.tests.ps1 | grep -E 'FAIL|ALL PASS'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sync-templates.ps1 -Mode Verify; echo "sync-templates exit=$?"
```
Expected: `ALL PASS`、`sync-templates exit=0`

```bash
git add skills/r-super-loop-powers/SKILL.md skills/r-super-loop-powers/references/workflow-a.md skills/r-super-loop-powers/references/workflow-b.md skills/r-super-loop-powers/policy.md skills/r-super-loop-powers/references/codex-invocation.md README.md .claude-plugin/plugin.json tests/skill-layout.tests.ps1
git commit -m "docs: スカウトの規則(まずスカウト・使い所・記帳・4 ロール)と version 0.10.0

SKILL.md の 24 KB 上限のため T<適用した番号> を削った。"
```

---

### Task 7: スモーク — `medium` の実力と Web 1 問(spec §10-2〜3)

**Files:**
- Modify: `docs/superpowers/notes/2026-10-11-v0.10-smoke.md`(§2〜§4)
- Modify(必要なら): `skills/r-super-loop-powers/bin/codex-run.ps1`(scout の effort 既定を変えるときだけ。ユーザーに報告してから)

**Interfaces:**
- Consumes: Task 5 の `scout.ps1`、Task 1 の一時ゴールディレクトリ(`codex-env.json`)

- [ ] **Step 1: このリポジトリで実際の問いを 2 つ投げる**

一時ゴールディレクトリ `$t`(Task 1 のもの。無ければ preflight をやり直す)に `state.md`(`tests/scout.tests.ps1` の `$stateLf` と同じ内容)を置き、Bash ツールの timeout 600000 で:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\scout.ps1 -GoalDir $t -WorkDir (Get-Location).Path -Question "codex-status.ps1 が BOUNDARY_HIT を出す条件と、そのパターンの定義場所は?"
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\scout.ps1 -GoalDir $t -WorkDir (Get-Location).Path -Question "loop-log.ps1 の -Clear が受け付ける欄名はどこで決まるか?"
```
各回の `STATUS` / `ELAPSED_MIN` / `CONCLUSION` / `UNVERIFIED` と、`REPORT` の `## 根拠` の `file:line` を実ファイルと突き合わせた結果(正 / 誤)、`codex-runs/<label>.out.jsonl` 末尾の `turn.completed` の `usage`(累計入力)を記録する。

- [ ] **Step 2: `file:line` に誤りがあれば `high` でも測る**

誤りが 1 つでもあれば同じ問いを `-Effort high` で投げ、同じ項目を記録する。既定を変えるかは**ユーザーに報告して決める**(黙って変えない)。

- [ ] **Step 3: Web ありの 1 問(Task 1 でキーが効いた場合)**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills\r-super-loop-powers\bin\scout.ps1 -GoalDir $t -WorkDir (Get-Location).Path -Web -Question "Claude Code の SessionStart フックの additionalContext の上限文字数は? 公式ドキュメントの URL を根拠に"
```
`WEB:` が `used` で `## 根拠` に URL があることを記録する。

- [ ] **Step 4: ノートに書く**

`docs/superpowers/notes/2026-10-11-v0.10-smoke.md` に:
```markdown
## 2. `medium` の実力(spec §10-2)

| 問い | effort | STATUS | ELAPSED_MIN | 根拠の正誤 | 累計入力トークン | 備考 |
|---|---|---|---|---|---|---|
| BOUNDARY_HIT の条件 | medium | | | | | |
| -Clear の欄名 | medium | | | | | |

既定 effort の判断: <medium のまま / high に変更(ユーザー承認)>

## 3. Web ありの 1 問(spec §10-3)

<結果。`WEB:` と根拠の URL>

## 4. 次の実ゴールで測ること

- Claude 側の消費の減り: `scripts/ctx-breakdown.js` の Read / Grep / Agent の回数とバイト、`call-log.md` の `codex-scout` 行数(spec §10-4)
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/notes/2026-10-11-v0.10-smoke.md
git commit -m "docs: v0.10 スモーク — scout medium の実測と Web 1 問"
```

---

### Task 8: 全テスト・同期検証・メモリ更新

**Files:**
- (変更なし。検証のみ。必要なら `C:\Users\makyu\.claude\projects\C--Users-makyu-Desktop-project-r-super-loop-powers\memory\r-super-loop-powers-status.md`)

- [ ] **Step 1: 全テストを回す**

Run: `for f in tests/*.tests.ps1; do powershell -NoProfile -ExecutionPolicy Bypass -File "$f" | grep -E 'FAIL|ALL PASS' | sed "s|^|$f: |"; done`
Expected: 11 ファイルすべて `ALL PASS`

- [ ] **Step 2: 同期を確かめる**

Run:
```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sync-templates.ps1 -Mode Verify; echo "templates=$?"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sync-roles.ps1 -Mode Verify; echo "roles=$?"
git status --short
```
Expected: `templates=0` / `roles=0` / 未コミットなし

- [ ] **Step 3: 受け入れ基準(spec §11)を 1 行ずつ確認して報告する**

1〜7 を上のテストとノートで指し示す。8(main へのマージ・push・plugin update・`cmp`)は superpowers:finishing-a-development-branch で行い、plugin update の後に `cmp` で `~/.claude/plugins/cache/.../skills/r-super-loop-powers/bin/scout.ps1` とリポジトリのものが一致することを確かめる(同じ版番号では更新されない罠: スモークノート 2026-10-10)。
