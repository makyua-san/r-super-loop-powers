# Fable 直接ヒアリング Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ゴール開始時のヒアリングを、メインセッションの Fable が利用者と直接会話する形に変え、MVP の受け入れを「稼働テスト+短い要件確認」に絞る(v0.11.0)。

**Architecture:** ヒアリングの手順は新しい `references/hearing.md` に置く。workflow-a は A-0 の準備、モデル切り替えの案内、A-2 での新しい代理 Fable への引き継ぎを担う。state.md の既存欄 `担当:` に値 `hearing-fable` を足し、モデル確認と Stop フックはこの値でヒアリング中を判別する。受け入れ条件の扱い(10 分の既定)は、テンプレート、workflow-a/b、policy に通す。

**Tech Stack:** Markdown(スキル文書)、PowerShell 5.1(フック、bin スクリプト、`tests/*.tests.ps1`)

**Spec:** `docs/superpowers/specs/2026-11-06-fable-direct-hearing-design.md`

## Global Constraints

- 対象は Claude 版 `skills/r-super-loop-powers/` のみ。`skills-codex/` へはテンプレートのコピー(`scripts/sync-templates.ps1 -Mode Copy`)だけを反映する。
- `SKILL.md` は LF 換算で 24KB(24,576 バイト)以下にする(`tests/skill-layout.tests.ps1` の `skill-size`)。着手時点で 24,572 バイトなので、SKILL.md の変更は差し引きで増やさない。
- 版: `.claude-plugin/plugin.json` を `0.11.0`、`.codex-plugin/plugin.json` を `0.1.2` にする。
- 10 分の基準: 「1 回の確認に 10 分を超える実測は、既定で運用で見る懸念に送る」。MVP のみ。高信頼には適用しない。
- 否定リスト(課金、不可逆な操作、セキュリティなど)に触れる確認は、10 分の既定で省略しない。
- ヒアリング中の `担当:` の値は、正確に `hearing-fable`。
- 日本語の .ps1 を編集するときは UTF-8 BOM 付きを保つ(PowerShell 5.1 のため)。
- 各タスクの終わりに、全テストを実行する: `for t in tests/*.tests.ps1; do powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$t" | grep -E '^FAIL|FAILURES|ALL PASS'; done`
- 着手時点の既知の失敗: `skill-layout.tests.ps1` の `version-0.10.0`(plugin.json は 0.10.1)。Task 7 で直す。

## Review Focus

1. ヒアリング中でない(`担当:` が `hearing-fable` 以外)ゴールの Stop フックの判定は、今と同じ判定文で動く。Task 1 の `judge-prompt-normal` で固定する。
2. `担当: hearing-fable` が完了(`phase: done`)のゴールに残っていても、フックは動かない。Task 1 の `hearing-done-skips` で固定する。
3. テンプレートを変えた後、Codex 版との完全一致検証が通る。Task 3 の `templates-in-sync` で固定する。
4. ヒアリングが「やらない」で終わったゴールで、state.md が `phase: done` になり、フックと再開が止まる。Task 4 の `a-close-route` で文書を固定する。動作は既存の done 判定(Task 1 の `done-goal-skips`)で担保する。
5. `/model fable` に切り替えずに Opus のまま A-1a に入ろうとしたとき、利用者の明示的な指示なしにヒアリングを始めない。Task 7 の `skill-model-check-hearing` で文書を固定する。

---

### Task 1: Stop フックのヒアリング中の判定

**Files:**
- Modify: `hooks/judge-prompt.md`
- Create: `hooks/judge-prompt-hearing.md`
- Modify: `hooks/human-message-check.ps1:135-137`
- Test: `tests/human-message-check.tests.ps1`

**Interfaces:**
- Produces: `judge-prompt.md` のプレースホルダ `{{MODE_NOTE}}`。`hearing-fable` の値の意味(Task 4、Task 7 が文書で使う)。

- [ ] **Step 1: 失敗するテストを書く**

`tests/human-message-check.tests.ps1` に、標準入力を保存する判定役の stub と、ヒアリング中のゴールを足す。

```powershell
$judgeCapture = New-Judge 'capture' ("findstr `"^`" > `"%~dp0stdin.txt`"`r`n" + 'echo {"ok": true}')
$hearProj = Join-Path $t 'hearproj'
$hearGoal = Join-Path $hearProj 'docs\r-super-loop-powers\g1'
New-Item -ItemType Directory -Path $hearGoal -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $hearGoal 'state.md'), "- phase: goal-definition`n- 担当: hearing-fable`n", $utf8)
$hearDoneProj = Join-Path $t 'heardoneproj'
$hearDone = Join-Path $hearDoneProj 'docs\r-super-loop-powers\g1'
New-Item -ItemType Directory -Path $hearDone -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $hearDone 'state.md'), "- phase: done`n- 担当: hearing-fable`n", $utf8)
$stdinFile = Join-Path $t 'stdin.txt'

$r = Invoke-Hook (New-Input $ja $hearProj) $judgeCapture
$sent = [IO.File]::ReadAllText($stdinFile, $utf8)
Check 'judge-prompt-hearing' ($r.Out -eq '' -and $sent -match 'ヒアリング中' -and $sent -notmatch '\{\{MODE_NOTE\}\}') $sent

$r = Invoke-Hook (New-Input $ja $proj) $judgeCapture
$sent = [IO.File]::ReadAllText($stdinFile, $utf8)
Check 'judge-prompt-normal' ($sent -notmatch 'ヒアリング中' -and $sent -notmatch '\{\{MODE_NOTE\}\}') $sent

$r = Invoke-Hook (New-Input $en $hearDoneProj) $judgeOk
Check 'hearing-done-skips' ($r.Out -eq '' -and -not (Was-Called 'ok')) $r.Out
```

- [ ] **Step 2: 失敗を確認する**

Run: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/human-message-check.tests.ps1 | grep -E '^FAIL|ALL PASS'`
Expected: `FAIL judge-prompt-hearing`。`judge-prompt-normal` と `hearing-done-skips` は通ってよい。

- [ ] **Step 3: 実装する**

- `hooks/judge-prompt.md`: 不合格条件の一覧の直後に、1 行の `{{MODE_NOTE}}` を置く。
- `hooks/judge-prompt-hearing.md`(新規、UTF-8): 「ヒアリング中」という語を含む短い注記。趣旨: 「ヒアリング中の応答は、理解を整理して返し、最後に問いを 1 つ置く形をとる。最後の問いで何をどう答えるかが分かれば、基準 1 の違反としない」。
- `hooks/human-message-check.ps1`: `$template` を読んだ後、`$goalDir\state.md` に `(?m)^\s*-\s*担当:\s*hearing-fable\b` が一致すれば `judge-prompt-hearing.md` の本文、そうでなければ空文字で `{{MODE_NOTE}}` を置き換える。読み込みの失敗は空文字として扱う(fail-open を保つ)。

- [ ] **Step 4: 通ることを確認する**

Run: Step 2 と同じ。
Expected: `ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add hooks/judge-prompt.md hooks/judge-prompt-hearing.md hooks/human-message-check.ps1 tests/human-message-check.tests.ps1
git commit -m "hook: relax the lead-with-the-ask rule while the Fable hearing is running"
```

---

### Task 2: loop-log に haiku を足す

**Files:**
- Modify: `skills/r-super-loop-powers/bin/loop-log.ps1:40`
- Test: `tests/loop-log.tests.ps1`

**Interfaces:**
- Produces: `loop-log.ps1 -Who haiku -Purpose <text>`(Task 4 の hearing.md が使う)。

- [ ] **Step 1: 失敗するテストを書く**

既存の `-Who fable` のケースに倣い、`$r = Invoke-Log $g @('-Who', 'haiku', '-Purpose', 'A-1a 事例調査')` を足す。`Check 'who-haiku'` で終了コード 0、かつ call-log.md の最終行が `| haiku | ` を含むことを確かめる。

- [ ] **Step 2: 失敗を確認する**

Run: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/loop-log.tests.ps1 | grep -E '^FAIL|ALL PASS'`
Expected: `FAIL who-haiku`

- [ ] **Step 3: `$Roles` に `'haiku'` を足す**

- [ ] **Step 4: 通ることを確認する**

Expected: `ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add skills/r-super-loop-powers/bin/loop-log.ps1 tests/loop-log.tests.ps1
git commit -m "loop-log: accept haiku as a caller"
```

---

### Task 3: テンプレート(Goal Frame・ヒアリング記録・評価パッケージ)

**Files:**
- Modify: `skills/r-super-loop-powers/templates/goal-frame.md`
- Modify: `skills/r-super-loop-powers/templates/hearing-log.md`
- Modify: `skills/r-super-loop-powers/templates/human-review-report.md`
- Copy to: `skills-codex/r-super-loop-powers/templates/`(上の 3 ファイル)
- Modify: `.codex-plugin/plugin.json`(`0.1.2`)
- Test: `tests/skill-layout.tests.ps1`

**Interfaces:**
- Produces: goal-frame の節見出し `## 運用で見る懸念`、hearing-log の節見出し `## 結論`(Task 4、Task 5 が参照する)。

- [ ] **Step 1: 失敗するテストを書く**

`tests/skill-layout.tests.ps1` に足す。

```powershell
$tpl = Join-Path $skillDir 'templates'
$gf = Get-Text (Join-Path $tpl 'goal-frame.md')
$hl = Get-Text (Join-Path $tpl 'hearing-log.md')
$hr = Get-Text (Join-Path $tpl 'human-review-report.md')
Check 'tpl-goal-frame-concerns' ($gf -match '(?m)^## 運用で見る懸念' -and $gf -match '10 分') 'goal-frame concerns section'
Check 'tpl-hearing-log-direct' ($hl -match '(?m)^## 結論' -and $hl -match '整理して返した内容' -and $hl -notmatch '過去の不満・避けたい体験') 'hearing-log template'
Check 'tpl-report-concerns' ($hr -match '運用で見る懸念') 'human report lists concerns'
$cver = ((Get-Text (Join-Path $root '.codex-plugin\plugin.json')) | ConvertFrom-Json).version
Check 'codex-version-0.1.2' ($cver -eq '0.1.2') "codex version=$cver"
```

- [ ] **Step 2: 失敗を確認する**

Run: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/skill-layout.tests.ps1 | grep -E '^FAIL|FAILURES|ALL PASS'`
Expected: 上の 4 件が FAIL。

- [ ] **Step 3: テンプレートを直す**

- `goal-frame.md`: 「承認基準」の直後に `## 運用で見る懸念` を足す。説明コメントには、受け入れ条件 = 稼働テスト+短時間の要件確認であること、10 分を超える実測は既定でここに置くこと、利用者が選んだ場合だけ承認基準へ上げること、MVP のみであることを書く。各項目は「懸念 / いつ・どう見るか」の形にする。「承認基準」のコメントに、10 分を超える実測は利用者の確認なしに入れないことを 1 行足す。
- `hearing-log.md`: 作成者を「ヒアリング Fable(会話のたびに追記)。ASK_HUMAN 中継は Opus」に直す。ラウンドの欄を「利用者の話(原文)/ 整理して返した内容 / 利用者の修正(原文)/ 問いと回答(原文)/ 表面化した既知 / 仮説化して台帳へ送った未知」にする。「表面化した既知」の説明から「過去の不満・避けたい体験」の列挙を外す。末尾に `## 結論` の節を足す。値は「Goal Frame へ進む」または「やらない / 後回し / 合流」で、後者には理由、再開の条件、合流先と引き継ぐ内容を書く。
- `human-review-report.md`: 受け入れの手順の近くに「運用で見る懸念(goal-frame.md から転記。今回は確かめていない)」の欄を足す。

- [ ] **Step 4: Codex 版へコピーし、版を上げる**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-templates.ps1 -Mode Copy`
`.codex-plugin/plugin.json` の version を `0.1.2` にする。

- [ ] **Step 5: 通ることを確認する**

Run: Step 2 と同じ。
Expected: 新しい 4 件と `templates-in-sync` が PASS。`version-0.10.0` の FAIL は Task 7 まで残る。

- [ ] **Step 6: Commit**

```bash
git add skills/r-super-loop-powers/templates skills-codex/r-super-loop-powers/templates .codex-plugin/plugin.json tests/skill-layout.tests.ps1
git commit -m "templates: operational concerns, direct-hearing log, report lists concerns (codex plugin v0.1.2)"
```

---

### Task 4: ヒアリング手順(hearing.md)と workflow-a

**Files:**
- Create: `skills/r-super-loop-powers/references/hearing.md`
- Modify: `skills/r-super-loop-powers/references/workflow-a.md:3,27,35-47,58`
- Test: `tests/skill-layout.tests.ps1`

**Interfaces:**
- Consumes: `担当: hearing-fable`(Task 1)、`-Who haiku`(Task 2)、`## 運用で見る懸念` と `## 結論`(Task 3)。
- Produces: `references/hearing.md`(Task 7 の SKILL.md が参照する)。

- [ ] **Step 1: 失敗するテストを書く**

```powershell
$h = Get-Text (Join-Path $skillDir 'references\hearing.md')
Check 'hearing-file' ($h -ne '') 'references/hearing.md missing'
Check 'hearing-purposes' ($h -match '認識' -and $h -match '方針' -and $h -match 'スコープ' -and $h -match 'メタ' -and $h -match '利用場面') 'five purposes'
Check 'hearing-no-fixed-list' ($h -notmatch '3〜7問' -and $h -notmatch '感情・体験 → 嗜好・制約 → 検証' -and $a -notmatch '3〜7問') 'fixed list removed'
Check 'hearing-one-question' ($h -match '1 つだけ' -and $h -match 'AskUserQuestion') 'one question / selection UI'
Check 'hearing-haiku' ($h -match 'model: "haiku"' -and $h -match '-Who haiku') 'haiku delegation'
Check 'hearing-scout' ($h -match 'scout\.ps1') 'fable may ask the scout'
Check 'hearing-ten-min' ($h -match '10 分' -and $h -match '運用で見る懸念') 'acceptance default'
Check 'a-model-switch' ($a -match '/model fable' -and $a -match '/model opus' -and $a -match 'hearing-fable' -and $a -match 'references/hearing\.md') 'workflow-a hand-offs'
Check 'a-close-route' ($a -match 'phase: done' -and $a -match '## 結論') 'close route when not doing it'
Check 'a-proxy-starts-at-a2' ($a -notmatch '代理Fable\(SendMessage 継続\)が生きているので、A-8') 'boundary wording updated'
Check 'a-gate-ten-min' ($a -match '10 分') 'A-6 / assessment / proxy use the 10-minute default'
```

- [ ] **Step 2: 失敗を確認する**

Run: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/skill-layout.tests.ps1 | grep -E '^FAIL|FAILURES|ALL PASS'`
Expected: 上の 11 件が FAIL。

- [ ] **Step 3: `references/hearing.md` を書く**

ヒアリング Fable が自分で読む手順書である。仕様の 4.2(途中のスカウト)、4.3、4.4、4.5、4.6、4.8 の要素をすべて入れる。冒頭に「誰が読むか(メインセッションの Fable)」「始め方(roles.md の全体図と `ヒアリング Fable (hearing-fable)` 節を読む → A-0 の材料を読む)」を置く。文言は builder に任せる。

- [ ] **Step 4: workflow-a を直す**

- 3 行目: 代理 Fable が生きている区間を `A-2〜A-4` に変える。
- A-0: 末尾に次を足す。
  - スカウトによる照合(仕様 4.2 の 1)と Linear の一覧(4.2 の 3)。
  - `loop-log.ps1 -SetOwner hearing-fable` で担当を記録する。
  - 利用者に `/model fable` を案内して止まる。Fable が使えないときの代替(仕様 4.1)。
- A-1a: 37〜41 行を、「メインセッションの Fable が `references/hearing.md` に従う」という短い節に置き換える。
- A-1b(MVP): メインの Fable が `templates/goal-frame.md` で作る。運用で見る懸念の分け方を指示に足す。確定後に `loop-log.ps1 -SetOwner opus-main` を実行し、`/model opus` を案内する。
- 「やらない」で終わる経路: hearing-log の `## 結論` を書く → `loop-log.ps1 -SetPhase done` → `/model opus` を案内する。retro は作らない。rb のタスクなら結論を報告する。
- A-2 の冒頭: 新しい名前付きの代理 Fable を起動する。入力は、ロール憲章(全体図+代理 Fable 節)、goal-seed、goal-frame、hearing-log。
- 58 行の代理 Fable への依頼文: 新しい懸念を 10 分の基準で分類し、10 分を超える実測を承認基準にしたいときは `ASK_HUMAN:` を返す、を足す。
- 27 行の実装アセス: 「完了を示す検証コマンド」に 10 分の既定を足す(超えるものは運用で見る懸念として書く)。
- A-6 の判定観点: MVP では「10 分を超える実測が、利用者の確認なしに承認基準に入っていないか」を足す。

- [ ] **Step 5: 通ることを確認する**

Run: Step 2 と同じ。
Expected: 新しい 11 件と既存の A 系チェックが PASS。

- [ ] **Step 6: Commit**

```bash
git add skills/r-super-loop-powers/references/hearing.md skills/r-super-loop-powers/references/workflow-a.md tests/skill-layout.tests.ps1
git commit -m "workflow-a: Fable runs the hearing directly in the main session"
```

---

### Task 5: workflow-b の受け入れ既定

**Files:**
- Modify: `skills/r-super-loop-powers/references/workflow-b.md:30,81-87`
- Test: `tests/skill-layout.tests.ps1`

- [ ] **Step 1: 失敗するテストを書く**

```powershell
Check 'b-verification-ten-min' ($b -match '10 分') 'B-2 verification uses the 10-minute default'
Check 'b6-concerns-accepted' ($b -match '運用で見る懸念') 'B-6 treats operational concerns as accepted unknowns'
```

- [ ] **Step 2: 失敗を確認する**

Expected: 2 件が FAIL。

- [ ] **Step 3: 直す**

- 30 行の `## VERIFICATION`(MVP): 1 回 10 分を超える実測は求めず、運用で見る懸念として報告させる。
- B-5〜B-6(81〜87 行付近): 運用で見る懸念は許容済みの未知として扱い、差し戻しの理由にしない。
- Checkpoint の評価パッケージを作る箇所: goal-frame の運用で見る懸念を転記させる。

- [ ] **Step 4: 通ることを確認する**

Expected: 2 件が PASS。

- [ ] **Step 5: Commit**

```bash
git add skills/r-super-loop-powers/references/workflow-b.md tests/skill-layout.tests.ps1
git commit -m "workflow-b: long measurements become operational concerns in MVP"
```

---

### Task 6: ロール憲章

**Files:**
- Modify: `skills/r-super-loop-powers/references/roles.md:16,40,48-52,96`
- Regenerate: `agents/builder.md`(`scripts/sync-roles.ps1 -Mode Copy` があればそれ、なければスクリプトの既定の動作)
- Test: `tests/skill-layout.tests.ps1`、`tests/roles-sync.tests.ps1`

**Interfaces:**
- Produces: 見出し `## ヒアリング Fable (hearing-fable)`(Task 4 の hearing.md が読む)。

- [ ] **Step 1: 失敗するテストを書く**

```powershell
$roles = Get-Text (Join-Path $skillDir 'references\roles.md')
Check 'roles-hearing-fable' ($roles -match '(?m)^## ヒアリング Fable \(hearing-fable\)') 'hearing-fable section'
Check 'roles-opus-not-only-talker' ($roles -notmatch '人間と直接話すのはあなただけ') 'Opus is no longer the only one talking to the human'
Check 'roles-proxy-a2' ($roles -match 'A-2〜A-4' -and $roles -notmatch '(?m)^- \*\*あなたの立場\*\*: MVP強度のヒアリングから') 'proxy range'
Check 'roles-scout-from-fable' ($roles -match 'ヒアリング中の Fable') 'scout accepts questions from the hearing Fable'
```

- [ ] **Step 2: 失敗を確認する**

Expected: 4 件が FAIL。

- [ ] **Step 3: 直す**

- 全体図: ヒアリング行の「作る」を「ヒアリング Fable(メインセッションで利用者と直接会話)」、Goal Frame 行の「作る」を「ヒアリング Fable」にする。
- Opus 節: 人間と話すのは Opus と、ヒアリング中の Fable の 2 者であることに直す。
- 代理 Fable 節: 範囲を A-2〜A-4 にし、入力に「ヒアリングの会話は見ていない。記録だけが根拠」を足す。
- 新しい節 `## ヒアリング Fable (hearing-fable)`: 立場、受け取るもの / 返すもの、決めること / 決めないこと、判定のされ方を、既存の節と同じ 4 項目の型で書く。決めないことには、技術の詳細(Codex)、ゲート判定、A-2 以降の代理回答を入れる。
- スカウト節: 問いの出し手に「ヒアリング中の Fable」を足す。
- `scripts/sync-roles.ps1` で `agents/builder.md` を同期する。

- [ ] **Step 4: 通ることを確認する**

Run: `skill-layout.tests.ps1` と `roles-sync.tests.ps1`
Expected: 新しい 4 件と `roles-in-sync` が PASS。

- [ ] **Step 5: Commit**

```bash
git add skills/r-super-loop-powers/references/roles.md agents/builder.md tests/skill-layout.tests.ps1
git commit -m "roles: add the hearing Fable, narrow the proxy to A-2..A-4"
```

---

### Task 7: SKILL.md・policy・README・版

**Files:**
- Modify: `skills/r-super-loop-powers/SKILL.md:17,43,139,154,184,185`
- Modify: `skills/r-super-loop-powers/policy.md:23,30,60,61,73,111`
- Modify: `README.md`(流れ、役割表、E2E チェック 91〜92 行)
- Modify: `.claude-plugin/plugin.json`(`0.11.0`)
- Test: `tests/skill-layout.tests.ps1`

- [ ] **Step 1: 失敗するテストを書く**

`version-0.10.0` のチェックを `version-0.11.0`(`$ver -eq '0.11.0'`)に置き換え、次を足す。

```powershell
Check 'skill-model-check-hearing' ($s -match 'hearing-fable' -and $s -match '/model fable') 'model check knows the hearing'
Check 'skill-hearing-ref' ($s -match 'references/hearing\.md') 'SKILL points to hearing.md'
Check 'skill-proxy-a2' ($s -notmatch 'A-1a〜A-4') 'proxy alive range is A-2..A-4'
Check 'policy-fable-direct' ($policyText -match 'メインセッション' -and $policyText -match '10 分') 'policy rows updated'
$readme = Get-Text (Join-Path $root 'README.md')
Check 'readme-direct-hearing' ($readme -match '/model fable' -and $readme -notmatch 'A-1aでFable駆動のヒアリング往復が行われ') 'README flow and E2E list'
```

- [ ] **Step 2: 失敗を確認する**

Expected: 上の 5 件と `version-0.11.0` が FAIL。

- [ ] **Step 3: SKILL.md を直す(差し引きで増やさない)**

- 17 行のモデル確認: `担当: hearing-fable` の間は Fable を正とする。Fable でなければ `/model fable` を案内し、利用者の明示的な指示があるまでヒアリングを始めない。それ以外は今のまま Opus。
- 43 行のディレクトリ契約: `hearing-log.md` の注記を直し、`hearing/`(モック等)の行を足す。
- 139 行の Fable 共通契約: 代理 Fable を「A-2〜A-4」とし、ヒアリングは `references/hearing.md` を参照する、と 1 行で書く。
- 154、184、185 行: `A-1a〜A-4` を `A-2〜A-4` に変える。
- 増えた分は、「## プラグインのフック」節の 5 点の検査項目の列挙を `hooks/judge-prompt.md` への参照に置き換えるなどして削る。規則そのものは消さない。
- 確認: `skill-size` が PASS すること。

- [ ] **Step 4: policy.md と README を直す**

- policy.md: 23 行(ヒアリング: メインセッションの Fable が直接会話、往復の目安を削除)、30 行(MVP のテスト要求に 10 分の既定)、60 行(人間)、61 行(Fable: サブエージェントのみの記述にメインセッションでのヒアリングを足す)、73 行、111 行の PL-009(ヒアリング Fable は対象コードを直接読まず、スカウトを使う)。
- README: 流れの図と表、E2E チェックの 91〜92 行を新しい流れに合わせる(`/model fable` → 直接ヒアリング → `/model opus`)。
- `.claude-plugin/plugin.json` を `0.11.0` にする。

- [ ] **Step 5: 全テストを通す**

Run: Global Constraints の全テストコマンド。
Expected: すべて `ALL PASS`。

- [ ] **Step 6: Commit**

```bash
git add skills/r-super-loop-powers/SKILL.md skills/r-super-loop-powers/policy.md README.md .claude-plugin/plugin.json tests/skill-layout.tests.ps1
git commit -m "v0.11.0: Fable runs the hearing in the main session"
```

---

## 実装後(このプランの外)

- plugin の再インストールとキャッシュの確認(同じ版番号では更新されないため、0.11.0 で入れて `cmp` で比べる)。
- 実ゴール 1 件のスモーク(仕様 5 章の 1〜5)。結果に応じて 10 分の基準と、`/clear` で再開する方式への切り替えを判断する。
