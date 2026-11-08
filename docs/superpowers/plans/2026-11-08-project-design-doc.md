# プロジェクト設計書の必須化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 対象プロジェクトに 1 つの設計書(`docs/r-super-loop-powers/design.md`)を Codex の第 5 ロール「設計書役(surveyor)」が作成・更新し、更新なしではループが進まない仕組み(記帳スクリプトの拒否 + Stop フック)と、ヒアリングでの照合への接続を入れる(v0.12.0)。

**Architecture:** `bin/design-doc.ps1` が `scout.ps1` と同じ形で「プロンプト → `codex-run.ps1 -Role surveyor` → `codex-status.ps1` → 型の検査 → 保存(更新履歴の行はスクリプトが足す)→ 記帳」を 1 回で行う。`loop-log.ps1` は 3 つの遷移で更新履歴の行を要求し、`human-message-check.ps1` はヒアリング担当の状態で A-0 の行が無ければ差し戻す。工程文書(workflow-a/b・hearing・codex-invocation・policy・roles・SKILL)に設計書の工程を通す。

**Tech Stack:** PowerShell 5.1(`bin/*.ps1`・`hooks/*.ps1`・`tests/*.tests.ps1`)、Markdown(スキル文書・テンプレート)、git(SHA と差分の取得)

**Spec:** `docs/superpowers/specs/2026-11-08-project-design-doc-design.md`

## Global Constraints

- 対象は Claude 版 `skills/r-super-loop-powers/` と `hooks/`・`tests/`・`README.md`。`skills-codex/` へはテンプレートのコピー(`scripts/sync-templates.ps1 -Mode Copy`)だけを反映する。
- `SKILL.md` は LF 換算で 24,576 バイト以下(`tests/skill-layout.tests.ps1` の `skill-size`)。着手時点で 24,564 バイト。足す分は削って作る(Task 7)。
- 版: `.claude-plugin/plugin.json` を `0.12.0`、`.codex-plugin/plugin.json` を `0.1.3`。
- 設計書のパス: `<GoalDir の親>\design.md`(= 対象プロジェクトの `docs/r-super-loop-powers/design.md`)。design-doc.ps1・loop-log.ps1・human-message-check.ps1 の 3 本が同じ求め方をする。
- ロール名は `surveyor`(codex-run の `-Role`、roles.md の識別子 `(surveyor)`)。call-log の役名は `codex-surveyor`。
- 更新履歴の行: `| YYYY-MM-DD HH:MM | <goal-slug> | <節目> | <短い SHA> | <書き手> |`。節目は `A-0` か `CP:<state.md の milestone の値>`。書き手は `codex` / `unchanged` / `opus(代行: <理由>)` のどれか。行を書くのはスクリプトだけ(Codex が書いた行は捨てる)。
- 行の照合: `(?m)^\|[^|]*\|\s*<slug>\s*\|\s*<節目>\s*\|`(slug・節目は `[regex]::Escape`)。CRLF と BOM があっても一致する。
- 必須見出し(`## ` に任意の番号を許す): `更新履歴`・`構成`・`機能の地図`・`取り組んだが足りない`・`要望はあるが未着手`・`運用で見る懸念`。
- effort の既定: codex-run の `surveyor` は `medium`。design-doc.ps1 は作成で `-Effort high`、更新で既定(medium)を渡す。タイムアウト: 作成 30 分、更新 15 分。
- 日本語を含む `.ps1` は UTF-8 BOM 付きで保存する(PowerShell 5.1)。スクリプトが書く `.md` は UTF-8 BOM 無し(`Write-TextFile`)。
- `loop-log.ps1` の標準出力は ASCII を保つ(`stdout-ascii`)。REASON は英文で書き、節目の値だけをそのまま埋める。
- 各タスクの終わりに全テストを実行する: `for t in tests/*.tests.ps1; do powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$t" | grep -E '^FAIL|FAILURES|ALL PASS'; done`
- 着手時点の既知の失敗: なし(全テスト `ALL PASS` を Task 1 の最初に確かめる)。

## Review Focus

1. 利用者が Windows のエディタで `design.md` を開いて保存し、CRLF と BOM が付いても、loop-log の照合とフックの照合は行を見つける。Task 4 `owner-hearing-ok-crlf-bom` / Task 5 `design-doc-row-crlf-passes` で固定する。
2. ゴール名に正規表現の記号(`.`)が入っても(例 `rb-84.85`)、照合が別の行に誤って一致したり落ちたりしない。Task 4 `slug-with-dot-escaped` で固定する。
3. `state.md` の `milestone:` に空白や括弧が入っていても(実例 `3-orders-and-degradation (CP1) — ACCEPT`)、design-doc.ps1 が足す `CP:` の節目と loop-log が要求する節目が一致する。両方が state.md の同じ値から組む。Task 3 `cp-tag-from-state` / Task 4 `learning-next-ok-decorated-milestone` で固定する。
4. Codex が設計書の全文を ```` ```markdown ```` のフェンスで包んで返しても、型の検査で落とさず、外側のフェンスを外して保存する。Task 3 `collect-unwraps-fence` で固定する。
5. 代筆(`opus(代行…)`)で作った雛形が残っていると、HEAD が変わらないかぎり「変更なし」になって Codex が二度と呼ばれない。直前の行の書き手が `codex` のときだけ `unchanged` にする。Task 3 `fallback-then-not-unchanged` で固定する。

---

### Task 1: codex-run.ps1 の `surveyor` ロールとロール憲章

**Files:**
- Modify: `skills/r-super-loop-powers/bin/codex-run.ps1:30`(ValidateSet)、`:32`(コメント)、`:87-135`(`$RoleBriefs`)、`:258-263`(effort 既定)
- Modify: `skills/r-super-loop-powers/references/roles.md:28`(全体図の表)、`:102` の後(新しい節)
- Modify: `skills/r-super-loop-powers/policy.md:67` の後(責任分担の行)
- Modify: `agents/builder.md`(`scripts/sync-roles.ps1 -Mode Copy` で同期。手では触らない)
- Test: `tests/codex-run.tests.ps1`、`tests/roles-sync.tests.ps1`

**Interfaces:**
- Produces: `codex-run.ps1 -Role surveyor`(read-only、effort 既定 `medium`、`web_search` の設定を渡さない、ロール指示 `== ROLE: SURVEYOR (design-doc writer, read-only) ==`)。Task 3 が呼ぶ。

- [ ] **Step 1: 全テストが通る状態を確かめる**

Run: Global Constraints のテストコマンド
Expected: 11 本すべて `ALL PASS`

- [ ] **Step 2: 失敗するテストを書く**

`tests/codex-run.tests.ps1` の scout の節(121 行目付近)の後に足す:

```powershell
# v0.12: surveyor role (design document writer; read-only, medium, no web_search key).
$r = Invoke-Run $env1 'sv' @('-Role', 'surveyor')
$m = Get-Meta 'sv'
Check 'surveyor-read-only-medium' ($r.Code -eq 0 -and $m.sandbox -eq 'read-only' -and $m.effort -eq 'medium') $r.Out
$svPrompt = Get-Content -Raw -Encoding UTF8 (Join-Path $t 'runs\sv.prompt.txt')
Check 'surveyor-brief' ($svPrompt -match 'ROLE: SURVEYOR' -and $svPrompt -match 'design document' -and $svPrompt -match 'do not write the update-history rows' -and $svPrompt -match 'Do not invoke process skills') 'surveyor brief'
Check 'charter-surveyor-section' ($svPrompt -match '\(surveyor\)' -and $svPrompt -notmatch '\(scout\)') 'surveyor charter section'
Check 'surveyor-no-web-key' ($m.command -notmatch 'web_search') $m.command
$r = Invoke-Run $env1 'svh' @('-Role', 'surveyor', '-Effort', 'high')
Check 'surveyor-effort-override' ((Get-Meta 'svh').effort -eq 'high') $r.Out
```

`tests/roles-sync.tests.ps1:22` の id 一覧に `'surveyor'` を足す。

- [ ] **Step 3: テストが失敗することを確かめる**

Run: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/codex-run.tests.ps1 | grep -E '^FAIL|FAILURES|ALL PASS'` と同じく `tests/roles-sync.tests.ps1`
Expected: `FAIL surveyor-read-only-medium`(ValidateSet で拒否)、`FAIL section-surveyor`

- [ ] **Step 4: codex-run.ps1 に `surveyor` を足す**

- `:30` の ValidateSet に `'surveyor'` を足し、`:32` のコメントに `surveyor: medium` を足す。
- `:258-263`: `elseif ($Role -eq 'scout' -or $Role -eq 'surveyor') { $Effort = 'medium' }`。
- `$RoleBriefs.surveyor`(英文。次の要素を含む): `== ROLE: SURVEYOR (design-doc writer, read-only) ==` / You write the project's design document (a map of what exists, how the main features flow through the components, how far each feature has got, and why the unfinished ones stopped) from the code, the existing docs and the goal records named in the task / You decide nothing about design, requirements or priorities and propose nothing: you record / Mark guesses with "(推測)" and give a source for every "足りない" claim / When updating, start from the previous document, keep its section layout and rows, and change only what the listed git range and goal records change / The final message is the whole document in the template's section order and nothing else; do not write the update-history rows (the orchestrator's script adds them) / Do not invoke process skills / `== END ROLE ==`。
- `-Web` の扱いは変えない(`:354` の分岐は scout だけ)。

- [ ] **Step 5: roles.md と policy.md に設計書役を足す**

- `roles.md:28` の後に行: `| 設計書(ゴールの最初と Checkpoint の振り返り後) | 設計書役(codex。設計書の全文を返す) | Opus(保存。型は design-doc.ps1 が機械で確かめる) |`
- `roles.md` の末尾(スカウトの節の後)に `## 設計書役 (surveyor)` の節。他の節と同じ 5 項目(`- **あなたの立場**` / `- **受け取るもの / 返すもの**` / `- **あなたが決めること**` / `- **あなたが決めないこと**` / `- **あなたの出力の判定のされ方**`)。立場: codex(読み取り専用)。Opus から渡された材料(対象プロジェクト・既存文書・ゴールの記録・前回の設計書)を読み、テンプレートの章立てで設計書の全文を書く記録係。決めること: どの機能を「主要」として行にするか、到達度の 5 語のどれか、何を出典に引くか。決めないこと: 設計・要件・優先順位・提案、更新履歴の行。判定: 実行は `codex-status.ps1` の `STATUS: OK`、型は `design-doc.ps1` が機械で確かめる(必須見出しが無ければ不合格で保存されない)。
- `policy.md:67` の後に行: `| 設計書役 | Codex `gpt-6.1-sol` / 作成 `high`・更新 `medium` / read-only(`-Role surveyor`) | 対象プロジェクトの設計書(全体概要・主要な機能の流れ・機能の地図と到達度・足りない理由)の全文を書く。Opus が保存する | A-0 と Checkpoint の Learning で `bin/design-doc.ps1` 経由。2 回失敗したら Opus が履歴行だけ代筆 | コード変更。設計・要件・優先順位の判断や提案。更新履歴の行 |`

- [ ] **Step 6: 同期して、テストが通ることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-roles.ps1 -Mode Copy` の後、Global Constraints のテストコマンド
Expected: 全部 `ALL PASS`(`roles-sync` の `section-surveyor`・`five-items-surveyor`、`skill-layout` の `roles-in-sync` を含む)

- [ ] **Step 7: Commit**

```bash
git add skills/r-super-loop-powers/bin/codex-run.ps1 skills/r-super-loop-powers/references/roles.md skills/r-super-loop-powers/policy.md agents/builder.md tests/codex-run.tests.ps1 tests/roles-sync.tests.ps1
git commit -m "codex-run: add the read-only surveyor role (design-doc writer)"
```

---

### Task 2: 設計書テンプレート

**Files:**
- Create: `skills/r-super-loop-powers/templates/design-doc.md`
- Modify: `skills-codex/r-super-loop-powers/templates/`(`sync-templates.ps1 -Mode Copy` で複写)
- Test: `tests/skill-layout.tests.ps1`

**Interfaces:**
- Produces: `templates/design-doc.md`。Task 3 がプロンプトに全文を貼り、`-Fallback` の雛形にする。見出しは Global Constraints の必須見出しのとおり。

- [ ] **Step 1: 失敗するテストを書く**

`tests/skill-layout.tests.ps1` の `tpl-report-concerns` の後に足す:

```powershell
# v0.12: project design document template (written by the surveyor, saved by design-doc.ps1).
$dd = Get-Text (Join-Path $tpl 'design-doc.md')
Check 'tpl-design-doc-sections' ($dd -match '(?m)^## 更新履歴' -and $dd -match '(?m)^## 0\. 構成' -and $dd -match '(?m)^### 0\.1 全体概要' -and $dd -match '(?m)^### 0\.2 主要な機能の流れ' -and $dd -match '(?m)^## 1\. 機能の地図' -and $dd -match '(?m)^## 2\. 取り組んだが足りない' -and $dd -match '(?m)^## 3\. 要望はあるが未着手' -and $dd -match '(?m)^## 4\. 運用で見る懸念') 'design-doc template sections'
Check 'tpl-design-doc-vocab' ($dd -match 'できている / 一部 / 取り組んだが足りない / 進行中 / 未着手' -and $dd -match '\| 日時 \| ゴール \| 節目 \| 見たコミット \| 書き手 \|' -and $dd -match '\(推測\)') 'design-doc vocabulary'
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `tests/skill-layout.tests.ps1`
Expected: `FAIL tpl-design-doc-sections`、`FAIL tpl-design-doc-vocab`

- [ ] **Step 3: テンプレートを書く**

`templates/design-doc.md`。spec 4.1 の表の順と決まりをそのまま章にする:

- 1 行目 `# 設計書 — <プロジェクト名>`
- HTML コメント: 読み手(利用者。次の要求の前に「もうできているか / どの機能の拡張か / 前に試して足りなかった件か」を確かめる)、書き手(Codex の設計書役。A-0 と Checkpoint の振り返り後に更新、Opus がそのまま保存)、到達度の語彙 `できている / 一部 / 取り組んだが足りない / 進行中 / 未着手`、推測は `(推測)`、出典はゴール名とファイル
- `## 更新履歴` + 表の見出し行 `| 日時 | ゴール | 節目 | 見たコミット | 書き手 |` と区切り行(本文の行は書かない、とコメント)
- `## このプロジェクトは何か`(3 行以内)
- `## 0. 構成` / `### 0.1 全体概要(どこで何が動いているか)`(機械・プロセス・話す相手を 1 画面。細部は「詳しい資料」に列挙して繰り返さない)/ `### 0.2 主要な機能の流れ(使うコンポーネントの順)`(表 `| 機能 | 流れ |`。1 機能 1 行「入口 → コンポーネントの順 → 出口」)/ `**詳しい資料**`
- `## 1. 機能の地図(到達度)`(表 `| 機能 | 何をする | どこにある(拡張の入口) | つながり | 到達度 |`。1 行 1 機能。「一部」「取り組んだが足りない」は `→ 2 章`)
- `## 2. 取り組んだが足りない(頼み直しでは解決しない件)`(機能ごとに `### <機能>` と `- **試したこと**` / `- **足りないこと**` / `- **止まっている理由**` / `- **出典**`)
- `## 3. 要望はあるが未着手`(1 行 1 件、出典付き)
- `## 4. 運用で見る懸念(使いながら確かめる)`(1 行 1 件、出典付き)

- [ ] **Step 4: Codex 版へ複写し、テストが通ることを確かめる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-templates.ps1 -Mode Copy` の後、`tests/skill-layout.tests.ps1`
Expected: `ALL PASS`(`templates-in-sync` を含む)

- [ ] **Step 5: Commit**

```bash
git add skills/r-super-loop-powers/templates/design-doc.md skills-codex/r-super-loop-powers/templates/design-doc.md tests/skill-layout.tests.ps1
git commit -m "templates: add the project design-doc template"
```

---

### Task 3: `bin/design-doc.ps1`

**Files:**
- Create: `skills/r-super-loop-powers/bin/design-doc.ps1`
- Create: `tests/design-doc.tests.ps1`
- Modify: `skills/r-super-loop-powers/bin/loop-log.ps1:38`(役一覧に `codex-surveyor`)
- Test: `tests/loop-log.tests.ps1`(`who-codex-surveyor`)
- Reference: `skills/r-super-loop-powers/bin/scout.ps1`(同じ形。`Invoke-Ps` / `Get-KvValue` / `Get-Section` / `Get-Lines` / `Limit-Text` / `Stop-Failed` はコピーしてよい)

**Interfaces:**
- Consumes: Task 1 の `codex-run.ps1 -Role surveyor`、Task 2 の `templates/design-doc.md`、既存の `codex-status.ps1`・`loop-log.ps1`。
- Produces(loop-log): `loop-log.ps1 -Who codex-surveyor` が受理される。
- Produces:
  ```
  design-doc.ps1 -GoalDir <path> -WorkDir <path> -Milestone <A-0 | CP> [-Effort <low|medium|high|xhigh|max>] [-WaitMinutes 9] [-Label <l>] [-EnvFile <p>]
  design-doc.ps1 -GoalDir <path> -Collect <label> [-WaitMinutes 9]
  design-doc.ps1 -GoalDir <path> -WorkDir <path> -Milestone <A-0 | CP> -Fallback -Reason "<理由>"
  ```
  - `-Milestone CP` は節目 `CP:<state.md の milestone の値(前後の空白を除く)>` に展開する。`A-0` はそのまま。それ以外は `STATUS: FAILED`。
  - 標準出力(KV)。成功: `STATUS: OK` / `LABEL` / `MODE: create | update | unchanged | fallback` / `DESIGN_DOC: <パス>` / `FEATURES: <1 章の表の本文行数>` / `INSUFFICIENT: <2 章の ### の数>` / `HISTORY: <足した行>` / `ELAPSED_MIN`。`WARN: design.md is N KB (> 40 KB)`。失敗: `STATUS: INCOMPLETE | REFUSED | FAILED | TIMEOUT | RUNNING | STALLED | …`(`codex-status.ps1` の値を中継)/ `REASON` / `NEXT`(そのまま実行できる再実行コマンド)/ `RAW`(INCOMPLETE のとき)。終了コードは `OK` だけ 0。
  - 設計書のパス: `(Split-Path -Parent $GoalDir)\design.md`。
  - ラベル既定: `design-<節目を [^A-Za-z0-9._-] → '.' に置換>-<連番>`(例 `design-A-0-1`、`design-CP.3-x-1`)。
  - 保存時: 前の設計書を `<goal-dir>\codex-runs\<label>.design-prev.md` に写す → 本文の `## 更新履歴` 節の本文を「前の設計書の履歴行 + 新しい行」で置き換える(Codex が書いた行は捨てる)→ `design.md` を書く → `loop-log.ps1 -Who codex-surveyor -Purpose "<節目>: <mode>"`。
  - 本文が全体で 1 つのコードフェンス(```` ``` ```` または ```` ```markdown ````)に包まれていれば、外側のフェンスを外してから検査する。
  - `MODE: unchanged` の条件(全部満たす): 設計書がある / 直前の履歴行の書き手が `codex` / その行の SHA が `git -C <WorkDir> rev-parse --short HEAD` と同じ / `git -C <WorkDir> status --porcelain --untracked-files=all` の行のうち、パスが今回の GoalDir(WorkDir からの相対)で始まらないものが 0 行。満たせば Codex を呼ばず、行(書き手 `unchanged`)を足して記帳し `STATUS: OK`。
  - 再実行の `NEXT`: `TIMEOUT` は `-Effort` を 1 段下げた同じコマンド(`high → medium`、`medium → low`、`low → low`。元の effort は `<label>.meta.json` の `effort`)。`INCOMPLETE / FAILED / SUSPECT / LOST` は同じコマンド。`RUNNING / STALLED` は `-Collect <label>`。
  - `-Fallback`: 設計書が無ければテンプレートの各章の本文を `(未作成: Codex 失敗のため — <理由>)` の 1 行にして作る。あれば本文はそのまま。行の書き手は `opus(代行: <理由>)`。`loop-log.ps1 -Who codex-surveyor -Purpose "<節目>: FAILED→Opus が代行"`。`MODE: fallback`。

- [ ] **Step 1: 失敗するテストを書く**

`tests/design-doc.tests.ps1`。`tests/scout.tests.ps1` と同じ骨組み(`Check` / `W` / `Get-Text` / `Get-Kv`、`where.exe` を実体にした `codex-env.json`、手作りの完了 run `New-FinishedRun`。ただし role は `surveyor`)。各テストの WorkDir は `git init` + 空コミット 1 つの一時リポジトリ(`git -C $proj init -q`、`git -C $proj -c user.name=t -c user.email=t@t commit -q --allow-empty -m init`)で、GoalDir は `$proj\docs\r-super-loop-powers\g1`。`$good` は Task 2 の見出しを全部持ち、1 章の表に本文 3 行、2 章に `### ` が 2 つ、更新履歴の節は見出し行と区切り行だけの本文。

```powershell
$r = Invoke-DesignDoc $g1 @('-WorkDir', $proj, '-Milestone', 'A-0')
$p = Get-Text (Join-Path $g1 'codex-runs\design-A-0-1.prompt.md')
Check 'create-prompt' ($p -match '== TASK: DESIGN DOC ==' -and $p -match 'モード: 作成' -and $p -match '## 更新履歴' -and $p -match '更新履歴の行は書かない' -and $p -match [regex]::Escape($proj)) $p
Check 'create-effort-high' ((Get-Meta $g1 'design-A-0-1').effort -eq 'high') 'create must pass -Effort high'
Check 'create-label' ($r.Out -match '(?m)^LABEL: design-A-0-1$') $r.Out
# update: an existing design.md whose last row points at an older SHA
W $design1 ($goodWithRow -f 'deadbee')
$r = Invoke-DesignDoc $g1 @('-WorkDir', $proj, '-Milestone', 'A-0')
$p = Get-Text (Join-Path $g1 'codex-runs\design-A-0-2.prompt.md')
Check 'update-prompt' ($p -match 'モード: 更新' -and $p -match 'git log --oneline deadbee\.\.HEAD' -and $p -match 'git diff --stat deadbee\.\.HEAD' -and $p -match [regex]::Escape($design1)) $p
Check 'update-effort-medium' ((Get-Meta $g1 'design-A-0-2').effort -eq 'medium') 'update uses the role default'
# unchanged: last row SHA == HEAD, writer codex, nothing dirty outside the goal dir
W $design2 ($goodWithRow -f (git -C $proj2 rev-parse --short HEAD))
$r = Invoke-DesignDoc $g2 @('-WorkDir', $proj2, '-Milestone', 'A-0')
Check 'unchanged-skips-codex' ($r.Code -eq 0 -and $r.Out -match '(?m)^MODE: unchanged$' -and -not (Test-Path (Join-Path $g2 'codex-runs\design-A-0-1.meta.json'))) $r.Out
Check 'unchanged-appends-row' ((Get-Text $design2) -match '(?m)^\| \d{4}-\d{2}-\d{2} \d{2}:\d{2} \| g2 \| A-0 \| [0-9a-f]{7,} \| unchanged \|$') (Get-Text $design2)
Check 'unchanged-logged' ((Get-Text (Join-Path $g2 'call-log.md')) -match '\| codex-surveyor \| [^|]+ \| A-0: unchanged$') 'call-log'
W (Join-Path $proj2 'src\x.js') 'dirty'
$r = Invoke-DesignDoc $g2 @('-WorkDir', $proj2, '-Milestone', 'A-0')
Check 'dirty-tree-is-update' ($r.Out -match '(?m)^LABEL: design-A-0-1$') $r.Out
# collect: a hand-made finished run
New-FinishedRun $g3 'design-A-0-1' $good 'A-0'
W $design3 $previous
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-1')
$d3 = Get-Text $design3
Check 'collect-ok' ($r.Code -eq 0 -and $r.Out -match '(?m)^STATUS: OK$' -and $r.Out -match '(?m)^MODE: update$' -and $r.Out -match '(?m)^FEATURES: 3$' -and $r.Out -match '(?m)^INSUFFICIENT: 2$') $r.Out
Check 'collect-saves-prev' ((Get-Text (Join-Path $g3 'codex-runs\design-A-0-1.design-prev.md')) -eq $previous) 'previous design.md not kept'
Check 'collect-history-row' ($d3 -match '(?m)^\| \d{4}-\d{2}-\d{2} \d{2}:\d{2} \| g3 \| A-0 \| [0-9a-f]{7,} \| codex \|$' -and $d3 -match '\| g3 \| CP:1-one \| 0000000 \| codex \|') 'new row missing or previous rows lost'
Check 'collect-strips-codex-rows' ($d3 -notmatch 'BOGUS-ROW') 'rows written by codex must be dropped'
Check 'collect-logged' ((Get-Text (Join-Path $g3 'call-log.md')) -match '\| codex-surveyor \| [^|]+ \| A-0: update$') 'call-log'
New-FinishedRun $g3 'design-A-0-2' ("``````markdown`n" + $good + "`n``````") 'A-0'
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-2')
Check 'collect-unwraps-fence' ($r.Out -match '(?m)^STATUS: OK$' -and -not (Get-Text $design3).StartsWith('```')) $r.Out
New-FinishedRun $g3 'design-A-0-3' ($good -replace '## 1\. 機能の地図\(到達度\)', '## 1. 機能') 'A-0'
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-3')
Check 'collect-incomplete' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: INCOMPLETE$' -and $r.Out -match '機能の地図' -and (Test-Path (Join-Path $g3 'codex-runs\design-A-0-3.raw.md'))) $r.Out
Check 'incomplete-keeps-design' ((Get-Text $design3) -notmatch '## 1\. 機能$') 'design.md must not be overwritten on INCOMPLETE'
New-FinishedRun $g3 'design-A-0-4' $good 'A-0' -ExitCode 124 -TimedOut $true -Effort 'high'
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-4')
Check 'timeout-next-lower-effort' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: TIMEOUT$' -and $r.Out -match '(?m)^NEXT: .*-Effort medium') $r.Out
# CP tag comes from state.md
W (Join-Path $g4 'state.md') ($stateLf -replace '- milestone: 1-one', '- milestone: 3-orders-and-degradation (CP1) — ACCEPT')
$r = Invoke-DesignDoc $g4 @('-WorkDir', $proj4, '-Milestone', 'CP')
$pf = Get-ChildItem (Join-Path $g4 'codex-runs') -Filter 'design-CP.*-1.prompt.md' | Select-Object -First 1
$p = if ($pf) { Get-Text $pf.FullName } else { '' }
Check 'cp-tag-from-state' ($pf -and $pf.Name -match '^design-CP\.3-orders-and-degradation[.A-Za-z0-9_-]*-1\.prompt\.md$' -and $p -match '節目: CP:3-orders-and-degradation \(CP1\) — ACCEPT') "$($pf.Name) / $p"
$r = Invoke-DesignDoc $g4 @('-WorkDir', $proj4, '-Milestone', 'M3')
Check 'bad-milestone-fails' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: FAILED$' -and $r.Out -match '-Milestone') $r.Out
# fallback
$r = Invoke-DesignDoc $g5 @('-WorkDir', $proj5, '-Milestone', 'A-0', '-Fallback', '-Reason', 'codex TIMEOUT x2')
$d5 = Get-Text $design5
Check 'fallback-create' ($r.Code -eq 0 -and $r.Out -match '(?m)^MODE: fallback$' -and $d5 -match '(?m)^## 1\. 機能の地図' -and $d5 -match '\(未作成: Codex 失敗のため — codex TIMEOUT x2\)' -and $d5 -match '\| g5 \| A-0 \| [0-9a-f]{7,} \| opus\(代行: codex TIMEOUT x2\) \|') $d5
Check 'fallback-logged' ((Get-Text (Join-Path $g5 'call-log.md')) -match 'A-0: FAILED→Opus が代行') 'call-log'
$r = Invoke-DesignDoc $g5 @('-WorkDir', $proj5, '-Milestone', 'A-0')
Check 'fallback-then-not-unchanged' ($r.Out -match '(?m)^LABEL: design-A-0-1$' -and $r.Out -notmatch 'unchanged') 'a fallback row must not count as an up-to-date codex run'
W $design6 $previous
$r = Invoke-DesignDoc $g6 @('-WorkDir', $proj6, '-Milestone', 'CP', '-Fallback', '-Reason', 'x')
Check 'fallback-append-keeps-body' ((Get-Text $design6) -match 'BODY-MARKER' -and (Get-Text $design6) -match '\| g6 \| CP:1-one \| [0-9a-f]{7,} \| opus\(代行: x\) \|') (Get-Text $design6)
# size warning
New-FinishedRun $g3 'design-A-0-5' ($good + "`n" + ('x' * 41000)) 'A-0'
$r = Invoke-DesignDoc $g3 @('-Collect', 'design-A-0-5')
Check 'size-warn' ($r.Out -match '(?m)^WARN: design\.md is \d+ KB') $r.Out
# goal dir outside the work dir gets -AddDir (same as scout)
$r = Invoke-DesignDoc $gOut @('-WorkDir', $projOut, '-Milestone', 'A-0')
Check 'goal-outside-workdir-adddir' ((Get-Meta $gOut 'design-A-0-1').command -match [regex]::Escape($gOut)) 'AddDir missing'
$b = [IO.File]::ReadAllBytes($designDoc)
Check 'script-has-bom' ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'save design-doc.ps1 as UTF-8 with BOM'
```

`tests/loop-log.tests.ps1` の `who-haiku` の後に足す:

```powershell
$r = Invoke-Log $g @('-Who', 'codex-surveyor', '-Purpose', 'A-0: create')
Check 'who-codex-surveyor' ($r.Code -eq 0 -and (Get-Text (Join-Path $g 'call-log.md')) -match '\| codex-surveyor \| milestone-implementation \| A-0: create$') $r.Out
```

`$goodWithRow` は `$good` の更新履歴に行 `| 2026-11-01 10:00 | g | A-0 | {0} | codex |` を入れたもの。`$previous` は `$good` に `BODY-MARKER` の 1 行と履歴行 `| 2026-11-01 10:00 | g3 | CP:1-one | 0000000 | codex |` を持つもの。`$good` の更新履歴には `| BOGUS-ROW |` を 1 行入れて、捨てられることを見る。`New-FinishedRun` は `-ExitCode` / `-TimedOut` / `-Effort` を取り、`done.json` の `timedOut` と `meta.json` の `effort` に反映する(`codex-status.ps1` が `TIMEOUT` を返す条件は `tests/codex-status.tests.ps1` の timeout ケースに合わせる)。

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/design-doc.tests.ps1 | grep -E '^FAIL|FAILURES|ALL PASS'` と `tests/loop-log.tests.ps1`
Expected: design-doc は全ケース `FAIL`(スクリプトが無い)、loop-log は `FAIL who-codex-surveyor`

- [ ] **Step 3: `loop-log.ps1:38` の `$Roles` に `'codex-surveyor'` を足し、`design-doc.ps1` を書く**

`scout.ps1` の構造(ヘッダーコメント → param → 共通関数 → `-List` / `-Collect` / start)を踏襲し、Interfaces のとおりに作る。決めておく点:

- `[Console]::OutputEncoding` を UTF-8 にする(scout と同じ。節目に日本語が入る)。
- `Get-DesignPath($GoalDir)`、`Get-MilestoneTag($Milestone, $stateText)`、`Get-HistoryRows($designText)`(更新履歴節の `| … |` 行のうち見出し・区切り以外)、`Set-HistorySection($body, $rows)`、`Test-Unchanged(...)`、`Get-LowerEffort($e)`、`Unwrap-Fence($body)`、`Measure-Doc($body)`(FEATURES / INSUFFICIENT)。
- 検査する見出しは Global Constraints の 6 つ。`Get-Section` は scout のもの(番号付き見出しを許す)。
- プロンプト(`<goal-dir>\codex-runs\<label>.prompt.md`): `== TASK: DESIGN DOC ==` / `## 目的と読み手` / `## モード: 作成|更新` / `## 節目: <tag>` / `## 読む材料`(作成: WorkDir・既存文書の探し方・`docs/r-super-loop-powers/*/` の読むファイル一覧と読む順。更新: 前回の設計書のパス・前回の SHA・実行する `git log --oneline <sha>..HEAD` と `git diff --stat <sha>..HEAD`・今回のゴールディレクトリ・他ゴールで増えた acceptance / retro / hearing-log の結論)/ `## 書き方の決まり`(spec 4.1 の表の右列)/ `## テンプレート`(全文)/ `## 出力`(設計書の全文のみ。更新履歴の行は書かない。フェンスで包まない)。
- `codex-run.ps1` の引数: `-Role surveyor`、作成なら `-Effort high -TimeoutMinutes 30`、更新なら `-TimeoutMinutes 15`(`-Effort` は指定があれば渡す)。GoalDir が WorkDir の外なら `-AddDir $GoalDir`(scout と同じ判定)。
- `-Collect` の失敗系は scout の `Complete-Run` と同じ中継。`NEXT` だけ Interfaces の規則で組む。

- [ ] **Step 4: テストが通ることを確かめる**

Run: `tests/design-doc.tests.ps1`、`tests/loop-log.tests.ps1`、`tests/scout.tests.ps1`
Expected: すべて `ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add skills/r-super-loop-powers/bin/design-doc.ps1 skills/r-super-loop-powers/bin/loop-log.ps1 tests/design-doc.tests.ps1 tests/loop-log.tests.ps1
git commit -m "bin: add design-doc.ps1 (surveyor run, shape check, history rows, fallback)"
```

---

### Task 4: `loop-log.ps1` の遷移拒否と `codex-surveyor`

**Files:**
- Modify: `skills/r-super-loop-powers/bin/loop-log.ps1:42-47`(Stop-Failed の隣に Stop-Refused)、`:86-95`(state.md を読んだ直後、書く前)
- Test: `tests/loop-log.tests.ps1`

**Interfaces:**
- Consumes: Task 3 の履歴行の形と節目の組み方(`CP:<state.md の milestone の値>`)。
- Produces: `-SetOwner hearing-fable` / `learning → milestone-implementation` / `learning → done` が、設計書に行が無いと `STATUS: REFUSED`(exit 1、何も書かない)。`REASON: design.md has no row for '<slug>' / '<節目>'`、`NEXT: run design-doc.ps1 -GoalDir "<goal-dir>" -WorkDir "<project-root>" -Milestone <A-0 | CP>`。

- [ ] **Step 1: 失敗するテストを書く**

`tests/loop-log.tests.ps1` の `who-codex-surveyor`(Task 3)の後に足す(`$design = Join-Path $proj 'docs\r-super-loop-powers\design.md'`、`$row = "| 2026-11-08 10:00 | g1 | {0} | abc1234 | {1} |"`):

```powershell
# v0.12: the three gated transitions need a design.md history row.
$r = Invoke-Log $g @('-SetOwner', 'hearing-fable')
Check 'owner-hearing-refused-without-design' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED$' -and $r.Out -match "design\.md has no row for 'g1' / 'A-0'" -and $r.Out -match '(?m)^NEXT: .*design-doc\.ps1 .*-Milestone A-0') $r.Out
Check 'refused-writes-nothing' ((Get-Text (Join-Path $g 'state.md')) -notmatch 'hearing-fable') 'state.md changed on REFUSED'
W $design ("# 設計書`n## 更新履歴`n| 日時 | ゴール | 節目 | 見たコミット | 書き手 |`n|---|---|---|---|---|`n" + ($row -f 'CP:0-old', 'codex') + "`n")
$r = Invoke-Log $g @('-SetOwner', 'hearing-fable')
Check 'owner-hearing-refused-wrong-tag' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED$') $r.Out
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
Check 'learning-next-refused' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED$' -and $r.Out -match "/ 'CP:3-orders-and-degradation \(CP1\) — ACCEPT'" -and (Get-Text (Join-Path $g 'state.md')) -match '(?m)^- phase: learning$') $r.Out
$r = Invoke-Log $g @('-SetPhase', 'done')
Check 'learning-done-refused' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED$') $r.Out
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
Check 'slug-with-dot-escaped' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED$') 'rb-84.85 must not match rb-84x85'
W (Join-Path $g 'state.md') $stateLf
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `tests/loop-log.tests.ps1`
Expected: `FAIL owner-hearing-refused-without-design`、`FAIL owner-hearing-refused-wrong-tag`、`FAIL learning-next-refused`、`FAIL learning-done-refused`、`FAIL slug-with-dot-escaped`(拒否されないので)

- [ ] **Step 3: `loop-log.ps1` に拒否を実装する**

- `function Stop-Refused([string]$Reason, [string]$Next)`: `STATUS: REFUSED` / `REASON` / `NEXT` を出して exit 1。
- `function Test-DesignRow([string]$GoalDir, [string]$Slug, [string]$Tag)`: `(Split-Path -Parent $GoalDir)\design.md` を `Read-TextFile` で読み(BOM・CRLF を吸収)、Global Constraints の正規表現で一致を返す。
- state.md を読んだ直後(`:88` の後)に判定を入れる。`$curPhase = Get-Field $stateText 'phase'`、`$curMilestone = Get-Field $stateText 'milestone'`、`$slug = Split-Path -Leaf $GoalDir`:
  - `$updates['担当'] -eq 'hearing-fable'` → 節目 `A-0`。
  - `$curPhase -eq 'learning'` かつ `$updates['phase']` が `milestone-implementation` または `done` → 節目 `"CP:$curMilestone"`。
  - どちらかに当たり、行が無ければ `Stop-Refused`。`NEXT` の `-Milestone` は `A-0` か `CP`。project root は `Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $GoalDir))`(`-Mark` と同じ)。
- `[Console]::OutputEncoding` を UTF-8 にする(scout と同じ 1 行)。`stdout-ascii` のケースは影響を受けない(その呼び出しの出力は変わらない)。

- [ ] **Step 4: テストが通ることを確かめる**

Run: `tests/loop-log.tests.ps1`
Expected: `ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add skills/r-super-loop-powers/bin/loop-log.ps1 tests/loop-log.tests.ps1
git commit -m "loop-log: refuse the hearing and post-learning transitions without a design.md row"
```

---

### Task 5: Stop フックの設計書検査

**Files:**
- Modify: `hooks/human-message-check.ps1:119-136`(`Send-Block` の隣に `Send-BlockRaw`、`$goalDir` 確定直後の検査)
- Test: `tests/human-message-check.tests.ps1:153-175`(ヒアリングの fixture に設計書を足す)と新しいケース

**Interfaces:**
- Consumes: Task 3 の履歴行の形。
- Produces: `担当: hearing-fable` の活動中ゴールで `design.md` に `| <slug> | A-0 |` の行が無いとき、判定役を呼ばずに `{"decision":"block","reason":"[r-super-loop-powers] 設計書が未更新です: docs/r-super-loop-powers/design.md に <slug> の A-0 の行がありません。bin/design-doc.ps1 を実行してから返答してください"}` を返し、`hook-log.md` に `BLOCK | design-doc | <slug> A-0 missing` を残す。

- [ ] **Step 1: 失敗するテストを書く**

`tests/human-message-check.tests.ps1`。まず既存のヒアリング fixture(`:155-162`)の `$hearGoal` と `$hearDone` の親に設計書を置く(置かないと新しい検査が先に差し戻し、`judge-prompt-hearing` が落ちる):

```powershell
$hearDesign = Join-Path $hearProj 'docs\r-super-loop-powers\design.md'
[IO.File]::WriteAllText($hearDesign, "# 設計書`n## 更新履歴`n| 2026-11-08 10:00 | g1 | A-0 | abc1234 | codex |`n", $utf8)
```

`judge-prompt-hearing` の後に足す:

```powershell
# v0.12: during the hearing the design.md must carry this goal's A-0 row.
$noDesignProj = Join-Path $t 'nodesignproj'
$noDesignGoal = Join-Path $noDesignProj 'docs\r-super-loop-powers\g1'
New-Item -ItemType Directory -Path $noDesignGoal -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $noDesignGoal 'state.md'), "- phase: goal-definition`n- 担当: hearing-fable`n", $utf8)
Reset-Called
$r = Invoke-Hook (New-Input $ja $noDesignProj) $judgeOk
Check 'design-doc-missing-blocks' ($r.Code -eq 0 -and $r.Out -match '"decision"\s*:\s*"block"' -and $r.Out -match '設計書が未更新' -and $r.Out -match 'g1 の A-0' -and -not (Was-Called 'ok')) $r.Out
Check 'design-doc-missing-logged' ((Get-Content -Encoding UTF8 (Join-Path $noDesignGoal 'hook-log.md'))[-1] -match '\| BLOCK \| design-doc \| g1 A-0 missing') 'hook-log'
[IO.File]::WriteAllText((Join-Path $noDesignProj 'docs\r-super-loop-powers\design.md'), "# 設計書`r`n## 更新履歴`r`n| 2026-11-08 10:00 | g1 | CP:1-x | abc1234 | codex |`r`n", (New-Object System.Text.UTF8Encoding($true)))
$r = Invoke-Hook (New-Input $ja $noDesignProj) $judgeOk
Check 'design-doc-wrong-tag-blocks' ($r.Out -match '設計書が未更新' -and -not (Was-Called 'ok')) $r.Out
[IO.File]::AppendAllText((Join-Path $noDesignProj 'docs\r-super-loop-powers\design.md'), "| 2026-11-08 10:05 | g1 | A-0 | abc1234 | opus(代行: x) |`r`n", $utf8)
Reset-Called
$r = Invoke-Hook (New-Input $ja $noDesignProj) $judgeOk
Check 'design-doc-row-crlf-passes' ($r.Out -eq '' -and (Was-Called 'ok')) $r.Out
$r = Invoke-Hook (New-Input $ja $noDesignProj $true) $judgeOk
Check 'design-doc-stop-hook-active-skips' ($r.Out -eq '') $r.Out
Remove-Item (Join-Path $noDesignProj 'docs\r-super-loop-powers\design.md')
[IO.File]::WriteAllText((Join-Path $noDesignGoal 'state.md'), "- phase: goal-definition`n- 担当: opus-main`n", $utf8)
Reset-Called
$r = Invoke-Hook (New-Input $ja $noDesignProj) $judgeOk
Check 'design-doc-not-checked-outside-hearing' ($r.Out -eq '' -and (Was-Called 'ok')) $r.Out
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `tests/human-message-check.tests.ps1`
Expected: `FAIL design-doc-missing-blocks`、`FAIL design-doc-missing-logged`、`FAIL design-doc-wrong-tag-blocks`

- [ ] **Step 3: フックに検査を足す**

- `function Send-BlockRaw([string]$Reason)`: `{ decision = 'block'; reason = $Reason }` をそのまま出す(`Send-Block` の定型を付けない)。
- `$goalDir` が決まり `stop_hook_active` を抜けた後、`$ratioText` の前に: state.md を読んで `担当: hearing-fable` なら `(Split-Path -Parent $goalDir)\design.md` を読み(`[System.IO.File]::ReadAllText(..., $Utf8)` は BOM を吸収する)、Global Constraints の正規表現で `| <slug> | A-0 |` を探す。無ければ `Send-BlockRaw` と `Write-HookLogLine $goalDir 'BLOCK' 'design-doc' "<slug> A-0 missing"` を行い `exit 0`。読めない・壊れている場合は fail-open(既存の try/catch の方針)。
- ファイル先頭のコメントの「Checks, cheapest first」に 0 番として足す。

- [ ] **Step 4: テストが通ることを確かめる**

Run: `tests/human-message-check.tests.ps1`
Expected: `ALL PASS`(既存の `judge-prompt-hearing` を含む)

- [ ] **Step 5: Commit**

```bash
git add hooks/human-message-check.ps1 tests/human-message-check.tests.ps1
git commit -m "stop hook: block the hearing hand-off while design.md lacks this goal's A-0 row"
```

---

### Task 6: 工程文書(workflow-a / workflow-b / hearing / codex-invocation / policy / goal-frame / README)

**Files:**
- Modify: `skills/r-super-loop-powers/references/workflow-a.md:3`(冒頭段落)、`:36-42`(A-0)、`:47`(やらないと決まったとき)
- Modify: `skills/r-super-loop-powers/references/workflow-b.md:112-118`(Learning 1.5 と 3)
- Modify: `skills/r-super-loop-powers/references/hearing.md:9`、`:23`、`:46`
- Modify: `skills/r-super-loop-powers/references/codex-invocation.md:3`、`:5`、`:12` の後(表の行)、`:111` の後(2-7)、`:153` の後(4 章)
- Modify: `skills/r-super-loop-powers/policy.md:86` の後(「設計書役を呼ぶ場面」)、`:111`(PL-009)
- Modify: `skills/r-super-loop-powers/templates/goal-frame.md:9`(表面化した既知の例)→ `sync-templates -Mode Copy`
- Modify: `README.md:56-70`(役とモデルの表)、`:124-137`(リポジトリ構成)
- Test: `tests/skill-layout.tests.ps1`

**Interfaces:**
- Consumes: Task 3 の呼び方(`design-doc.ps1 -GoalDir … -WorkDir … -Milestone A-0 | CP`、`-Collect`、`-Fallback -Reason`、再実行の方針)、Task 4 の拒否の文言。

- [ ] **Step 1: 失敗するテストを書く**

`tests/skill-layout.tests.ps1` に足す。`invocation-four-scripts` は置き換える:

```powershell
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
```

`invocation-four-scripts` の行は削除する。

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `tests/skill-layout.tests.ps1`
Expected: 上の 9 ケースが `FAIL`

- [ ] **Step 3: workflow-a を直す**

- `:3` の冒頭段落の末尾に 1 文: 「設計書(`docs/r-super-loop-powers/design.md`)は A-0 で Codex が作成・更新し、行が無いと `loop-log.ps1 -SetOwner hearing-fable` が拒否される。」
- A-0(`:36-42`)を spec 4.7 の 5 手順に書き換える。2 の設計書の手順に: 呼び方(`-Milestone A-0`、`RUNNING` なら `-Collect`、待つ間に 4 を進めてよい、3 は直列)、利用者への一言「設計書を作っています(初回は十数分、長いと 1 時間)」、再実行(`INCOMPLETE / FAILED / SUSPECT / LOST` は同じ依頼で 1 回、`TIMEOUT` は `NEXT:` の effort 1 段下げで 1 回、2 回目も OK でなければ `-Fallback -Reason`)、「並行ゴールで `design.md` が衝突したらどちらかを採って合流してよい(次の A-0 で作り直す)」。3 の照合の問いに「`docs/r-super-loop-powers/design.md` の 1〜3 章を先に読み、goal-seed に関係する機能の行(到達度)・『取り組んだが足りない』の該当・『要望はあるが未着手』の該当を挙げよ。見つからなければコードから探せ」を入れる。5 に「設計書の行が無ければ `STATUS: REFUSED` で拒否される」。
- `:47` やらないと決まったとき: `-SetPhase done …` の後に「`docs/r-super-loop-powers/` の未コミット分(ゴール記録と A-0 の設計書)を Opus がコミットする。設計書は更新しない。」

- [ ] **Step 4: workflow-b を直す**

- 1(retro)と 2(グラレコ)の間に `1.5. **設計書の更新(Codex 設計書役)**: design-doc.ps1 -Milestone CP …`(MVP は Checkpoint 単位、高信頼はマイルストーン単位。再実行と `-Fallback` は workflow-a A-0 と同じ。`codex-surveyor` の記帳はスクリプトが行う)。
- 3(次へ)の冒頭に「`-SetPhase` の前に `docs/r-super-loop-powers/` の未コミット分(設計書・retro・grareco)を Opus がコミットする。`-SetPhase` は設計書に `CP:<milestone>` の行が無いと拒否される」。

- [ ] **Step 5: hearing.md・codex-invocation.md・policy.md・goal-frame・README を直す**

- `hearing.md:9`: 読む材料に「設計書(`docs/r-super-loop-powers/design.md`)のうち、照合が指した 1 章の行と 2 章の該当節。設計書は文書なので PL-009 には触れない」。`:23` の末尾に「設計書で『取り組んだが足りない』に当たるなら、頼み直しでは解決しない。何を変えるか(やり方・要件・確かめ方)を問う。『一部』や『進行中』に当たるなら、そのゴールの続きとして扱うかを問う」。`:46` に「(設計書は読んでよい)」。
- `codex-invocation.md:3` を「codex は5ロール(techpm / reviewer / grareco / scout / surveyor)」(「5ロール」は空白なし。テストの語)、`:5` を「5本のスクリプト」、表に `| bin/design-doc.ps1 | 設計書の作成・更新を起動から保存・記帳まで 1 回で行う(2-7)。surveyor ロールはこれ経由でだけ呼ぶ | 節目ごとに 1 回 |`。`### 2-7. 設計書 — bin/design-doc.ps1` を 2-6 の後に: 呼び方 3 形、KV 行の表、`unchanged` の条件、再実行の `NEXT`、`-Fallback`。4 章に `- **surveyor**: design-doc.ps1 が目的・モード・材料・テンプレートを組む。Opus は節目(A-0 | CP)だけ指定する`。
- `policy.md:86` の後に `## 設計書役を呼ぶ場面(これ以外では呼ばない)`: 1. A-0(Goal Seed 保存の直後、照合スカウトの前) 2. Learning(retro の後、グラレコの前。MVP は Checkpoint ごと、高信頼はマイルストーンごと)。`:111` PL-009 の末尾に「設計書(`design.md`)は文書なので読んでよい」。
- `templates/goal-frame.md:9` のプレースホルダ末尾に「既存機能との関係(設計書 1 章の行名の拡張 | 新規 | 前に足りなかった件 = 2 章)を 1 行入れる」。`sync-templates -Mode Copy`。
- `README.md` 役の表に `| 設計書役 | codex gpt-6.1-sol / 作成 high・更新 medium / read-only | プロジェクトの設計書(docs/r-super-loop-powers/design.md)を A-0 と Checkpoint 後に書く。bin/design-doc.ps1 が起動から保存・記帳まで行い、行が無いと loop-log が遷移を拒否する |`。リポジトリ構成の `bin/` に `設計書 design-doc`、`templates/` を 11 種に。

- [ ] **Step 6: テストが通ることを確かめる**

Run: Global Constraints のテストコマンド
Expected: 全部 `ALL PASS`

- [ ] **Step 7: Commit**

```bash
git add skills/r-super-loop-powers/references skills/r-super-loop-powers/policy.md skills/r-super-loop-powers/templates/goal-frame.md skills-codex/r-super-loop-powers/templates/goal-frame.md README.md tests/skill-layout.tests.ps1
git commit -m "docs: run the design doc through A-0, Learning, the hearing and the codex guide"
```

---

### Task 7: SKILL.md(サイズ内)・版・プラグイン説明

**Files:**
- Modify: `skills/r-super-loop-powers/SKILL.md:29`、`:44-58`、`:108`、`:132`、`:134`、`:166-168`、`:177-181`
- Modify: `.claude-plugin/plugin.json`(version 0.12.0、description に「設計書役」)、`.codex-plugin/plugin.json`(version 0.1.3)
- Test: `tests/skill-layout.tests.ps1`

**Interfaces:**
- Consumes: Task 3・4・6 の名前(`design-doc.ps1`、`codex-surveyor`、`-Role … | surveyor`)。

- [ ] **Step 1: 失敗するテストを書く**

`tests/skill-layout.tests.ps1`: `version-0.11.0` を `version-0.12.0`(`$ver -eq '0.12.0'`)、`codex-version-0.1.2` を `codex-version-0.1.3` に変え、足す:

```powershell
Check 'skill-design-doc' ($s -match 'docs/r-super-loop-powers/design\.md' -and $s -match 'codex-surveyor' -and $s -match '-Role techpm \| reviewer \| grareco \| scout \| surveyor' -and $s -match '設計書役の失敗' -and $s -match '5ロール') 'SKILL.md design-doc rules'
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `tests/skill-layout.tests.ps1`
Expected: `FAIL version-0.12.0`、`FAIL codex-version-0.1.3`、`FAIL skill-design-doc`

- [ ] **Step 3: SKILL.md を直し、サイズに収める**

足す(合計 約 260 バイト):
- `:29` 「技術PM・技術レビュー(高信頼)・グラレコ・スカウトの4ロールだけ」→「技術PM・技術レビュー(高信頼)・グラレコ・スカウト・設計書役の5ロールだけ」
- `:43` の木の先頭(`docs/r-super-loop-powers/<goal-slug>/` の前)に 1 行 `docs/r-super-loop-powers/design.md   # 設計書(プロジェクトに 1 つ。bin/design-doc.ps1 が書く)` を足す
- `:108` 役一覧に ` / codex-surveyor`
- `:132` 「グラレコとスカウトの失敗だけはループを止めない」→「グラレコ・スカウト・設計書役の失敗だけはループを止めない」
- `:134` `-Role techpm | reviewer | grareco | scout | surveyor`
- `:177` の後に行 `| 設計書(design.md) | 照合スカウトが指した行だけ | 全文の Read |`

削る(足した分以上。候補、上から順に。`skill-mentions-tools` が要る `resume-pending` / `context-meter.ps1` / `resume-packet.ps1` の語は残す):
- `:52` `# フックの記録(PASS/BLOCK/ERROR・RESUME/STALE・CTX)` → `# フックの記録`
- `:53` `# 境界リセットの印(-Mark が置き、SessionStart フックが消す)` → `# 境界リセットの印`
- `:55` `# 起動時チェック6のプリフライト結果` → `# プリフライト結果`
- `:56` `# codex 4 ロールの実行記録` → `# codex の実行記録`
- `:57` `# スカウトの報告(index.md / scout-<n>.md。scout.ps1 が書く)` → `# スカウトの報告(scout.ps1 が書く)`
- `:58` `# 実装役への委譲記録(<ラベル>.prompt.md / .base.txt / .pre.txt / .report.md)` → `# 実装役への委譲記録`
- まだ足りなければ `:166-168` 「プラグインのフック」節の「前 2 つは「境界リセット」のとおり。」の前後で重複する説明を 1 文削る

確認: `node -e "const fs=require('fs');console.log(Buffer.byteLength(fs.readFileSync('skills/r-super-loop-powers/SKILL.md','utf8').replace(/\r\n/g,'\n'),'utf8'))"` が 24576 以下。

- [ ] **Step 4: 版を上げる**

`.claude-plugin/plugin.json` の `version` を `0.12.0`、`description` の「スカウト(読み取り専用)」を「スカウト・設計書役(読み取り専用)」に。`.codex-plugin/plugin.json` の `version` を `0.1.3`。

- [ ] **Step 5: テストが通ることを確かめる**

Run: Global Constraints のテストコマンド
Expected: 全部 `ALL PASS`(`skill-size` を含む)

- [ ] **Step 6: Commit**

```bash
git add skills/r-super-loop-powers/SKILL.md .claude-plugin/plugin.json .codex-plugin/plugin.json tests/skill-layout.tests.ps1
git commit -m "v0.12.0: project design doc (surveyor role, design-doc.ps1, gated transitions)"
```

---

## 実装後(このプランの外)

1. main へマージ・push、plugin update(版を上げたので同じ版のキャッシュ問題は起きない。入れた後に `cmp` でキャッシュと一致を確かめる)。
2. スモーク(spec 5 章・利用者の決定 1): `dev/agent-alert` で `design-doc.ps1 -GoalDir <任意の既存ゴール> -WorkDir <agent-alert のルート> -Milestone A-0` を 1 回実行し、所要時間・`FEATURES` / `INSUFFICIENT`・文書の大きさを `docs/superpowers/notes/2026-11-xx-v0.12-smoke.md` に記録する。利用者が `design.md` を読み、「11/5 の問いに答えられるか」「0.2 が主要な機能を押さえているか」「2 章の止まっている理由が頼み直すかの判断に使えるか」を判断する。
3. 次の実ゴール 1 本で、A-0 の更新・Learning の更新・ヒアリングでの設計書の行の引用が拒否なしに通ることを見る。
