# r-super-loop-powers Codex版 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code 用の r-super-loop-powers v0.3.0 と同じ工程・成果物契約・ゲート規律を、Codex CLI 単体で完結して回せるプラグイン(Codex v0.1)として提供する。

**Architecture:** 同一リポジトリに Codex 用のプラグイン骨格(`.codex-plugin/` + `.agents/plugins/marketplace.json`)を追加し、Codex 版スキル本体を `skills-codex/r-super-loop-powers/` に置く。Claude 版 `skills/` と `.claude-plugin/` は凍結。書き換えるのはモデル運用層のみで、サブ役(judge / proxy / builder / reviewer)はすべて `codex exec` サブプロセスとして役ごとのモデル・effort で起動する。

**Tech Stack:** Markdown(SKILL.md / policy.md / templates)、JSON Schema(ゲート判定の構造化出力)、PowerShell 5.1(テンプレート同期スクリプト)、Codex CLI(`codex exec` / `codex exec resume` / `codex plugin`)

**Spec:** `docs/superpowers/specs/2026-08-31-r-super-loop-powers-codex-port-design.md`

## Global Constraints

- 作業ブランチは `codex-port`(仕様書コミット `2509a30` を含む)。
- **Claude版 `skills/r-super-loop-powers/` と `.claude-plugin/` に変更を入れてはならない**(受け入れ基準11)。
- 工程記号(A-0〜A-8 / B-1〜B-10)・成果物名・ディレクトリ契約・ゲート保護ルールの**内容**は Claude版と完全に同一に保つ。
- policy.md の「上位原則」「MVPモードの原則」「仮説自律の否定リスト(6項目)」「エスカレーション発火条件(10項目)」は**一字一句変更しない**。
- モデル分担(固定値): driver = `gpt-5.6-sol` / `medium`、judge = `gpt-5.6-sol` / `ultra`、proxy = `gpt-5.6-sol` / `max`、builder = `gpt-5.6-luna` / `max`、reviewer = `gpt-5.6-sol` / `max`。
- `gpt-5.6-luna` は `ultra` を**サポートしない**(上限 `max`)。
- サンドボックス: judge / proxy = `-C <tmpdir> -s read-only --skip-git-repo-check`、builder = `-s workspace-write -c approval_policy=never`、reviewer = `-s read-only`。
- 一時ディレクトリの場所: `<OSのTEMP>/r-slp/<goal-slug>/<役>-<工程>-<連番>/`。
- 役名は `driver / judge / proxy / builder / reviewer / human` の6語のみを使う(Opus / Fable / Codex を役名として使わない)。
- Codex版プラグインの version は `0.1.0`(Claude版 0.3.0 と独立採番)。
- テンプレートの原本は `skills/r-super-loop-powers/templates/`。`skills-codex/` 側は複写であり直接編集しない。

---

## ファイル構成(このプランで触るもの)

**新規作成:**

| パス | 責務 |
|---|---|
| `docs/superpowers/notes/2026-08-31-codex-smoke.md` | スモークテスト S1〜S6 の実測結果と、失敗時に採用した代替方針の記録 |
| `scripts/sync-templates.ps1` | templates の複写(Copy)と一致検証(Verify)。Verify は差分時に非ゼロ終了 |
| `skills-codex/r-super-loop-powers/schemas/gate-verdict.json` | judge のゲート判定の構造化出力スキーマ |
| `skills-codex/r-super-loop-powers/schemas/escalation-verdict.json` | judge のエスカレーション判定の構造化出力スキーマ |
| `skills-codex/r-super-loop-powers/templates/*.md` | 原本からの複写9枚(スクリプトが生成) |
| `skills-codex/r-super-loop-powers/policy.md` | Codex版モデル運用ポリシー |
| `skills-codex/r-super-loop-powers/SKILL.md` | Codex版オーケストレーター本体 |
| `.codex-plugin/plugin.json` | Codexプラグイン定義(`skills: "./skills-codex/"`) |
| `.agents/plugins/marketplace.json` | Codexマーケットプレイス定義 |

**変更:**

| パス | 変更内容 |
|---|---|
| `README.md` | Codex版セクション(導入手順・役とモデル・E2Eチェックリスト)を追記。Claude版の記述は残す |

**変更禁止:** `skills/r-super-loop-powers/**`、`.claude-plugin/**`

---

### Task 1: スモークテスト(設計前提の確定)

設計が依存する Codex CLI の挙動を先に実測する。ここで失敗したものは、この後のタスクで代替方針に差し替える。**S2 が失敗した場合は実装を止めてユーザーに報告する**(builder 分離が成立せず設計変更になるため)。

**Files:**
- Create: `docs/superpowers/notes/2026-08-31-codex-smoke.md`

**Interfaces:**
- Consumes: なし
- Produces: `docs/superpowers/notes/2026-08-31-codex-smoke.md` — S1〜S6 の判定(OK / FAILED)と、FAILED の場合に採用する代替方針。Task 2〜5 はこの記録を読んでから実装を決める

- [ ] **Step 1: ブランチを確認する**

```bash
cd "C:/Users/makyu/Desktop/project/r-super-loop-powers"
git branch --show-current
```

Expected: `codex-port`

異なる場合は `git checkout codex-port` する。

- [ ] **Step 2: codex CLI のパスを確認する**

```bash
ls "/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/"*/codex.exe
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"; "$CODEX" --version
```

Expected: 1つ以上のパスが表示され、`codex-cli 0.144.2` 以上が返る。表示されたパスが上と異なる場合は、以降の全ステップの `CODEX=` の値を実際のパスに置き換える。

**注意**: Bashツールはツール呼び出しをまたいでシェル変数を保持しない。以降の各ステップは冒頭で `CODEX=` を再定義してある。

- [ ] **Step 3: S2 — ネストした codex exec が起動できるか(最優先)**

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
"$CODEX" exec -m gpt-5.4-mini -c model_reasoning_effort=low \
  -s workspace-write -c approval_policy=never --skip-git-repo-check \
  "Run exactly this shell command and report its final line verbatim: codex exec -m gpt-5.4-mini -c model_reasoning_effort=low -s read-only --skip-git-repo-check \"Reply with exactly: NESTED_OK\"" 2>&1 | tail -20
```

Expected: 出力に `NESTED_OK` が含まれる。

**FAILED の場合**: ここで実装を中断し、ユーザーに「S2失敗。builder / judge / proxy をサブプロセスとして分離できないため、driver 自身が実装を兼ねる設計へ変更が必要」と報告して指示を仰ぐ。以降のステップには進まない。

- [ ] **Step 4: S3 — session id の取得と resume**

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
WORK=$(mktemp -d)
"$CODEX" exec -m gpt-5.6-sol -c model_reasoning_effort=low \
  -s read-only --skip-git-repo-check \
  "Remember the word ALPHA. Reply with exactly: STORED" 2>&1 | tee "$WORK/s3.log" | tail -5
SID=$(grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$WORK/s3.log" | head -1)
echo "SID=$SID"
"$CODEX" exec resume "$SID" -m gpt-5.6-sol -c model_reasoning_effort=low \
  "What word did I ask you to remember? Reply with that word only." 2>&1 | tail -5
```

Expected: `SID=` に UUID が入り、resume の応答に `ALPHA` が含まれる。

**FAILED の場合**: 記録に「C6/C7 破棄。proxy は往復ごとに hearing-log.md 全文を渡して再構築する(Claude版と同じ方式)」と書く。

- [ ] **Step 5: S4 — --output-schema による構造化出力**

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
cat > /tmp/verdict-probe.json <<'JSON'
{
  "type": "object",
  "properties": {
    "verdict": { "type": "string", "enum": ["PASS", "REVISE", "REPLAN", "BLOCKED"] },
    "rationale": { "type": "string" }
  },
  "required": ["verdict", "rationale"],
  "additionalProperties": false
}
JSON
"$CODEX" exec -m gpt-5.6-sol -c model_reasoning_effort=low \
  -s read-only --skip-git-repo-check \
  --output-schema /tmp/verdict-probe.json -o /tmp/verdict-out.json \
  "A submission is missing its verification evidence. Decide the gate verdict." 2>&1 | tail -3
cat /tmp/verdict-out.json
python -c "import json;d=json.load(open('/tmp/verdict-out.json',encoding='utf-8'));print('OK',d['verdict'])"
```

Expected: `verdict` が4値のいずれかである JSON が出力され、python が `OK <verdict>` を表示する。

**FAILED の場合**: 記録に「C8 破棄。judge は自然文で `判定: PASS` の形式で返させ、driver が1行目を読む」と書く。

- [ ] **Step 6: S5 — 一時ディレクトリ隔離で対象リポジトリが読めないか**

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
ISO=$(mktemp -d); echo "これはjudgeに渡す唯一の文書です。" > "$ISO/goal-frame.md"
"$CODEX" exec -m gpt-5.6-sol -c model_reasoning_effort=low \
  -C "$ISO" -s read-only --skip-git-repo-check \
  "List every file in your working directory. Then try to read C:/Users/makyu/Desktop/project/r-super-loop-powers/README.md and state clearly whether the read SUCCEEDED or FAILED." 2>&1 | tail -15
```

Expected(望ましい): 作業ディレクトリには `goal-frame.md` のみが見え、リポジトリ外の読み取りが FAILED になる。

**読み取りが SUCCEEDED した場合**(read-only サンドボックスがリポジトリ外の読み取りを許す想定は十分にありうる): 記録に「S5 部分成功。物理隔離は作業ディレクトリのみ。PL-009 はプロンプトでの探索禁止指示との併用で担保する」と書く。**この場合も設計は続行する**(Task 3 の policy.md PL-009 と Task 4 の judge プロンプトに探索禁止を明記する)。

- [ ] **Step 7: S6 — codex exec セッションで画像生成ができるか**

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
IMG=$(mktemp -d)
"$CODEX" exec -m gpt-5.6-luna -c model_reasoning_effort=low \
  -C "$IMG" -s workspace-write -c approval_policy=never --skip-git-repo-check \
  "Generate a simple illustrative image (any content) and save it as grareco.png in your working directory. If you have no image generation capability, reply with exactly: NO_IMAGE_TOOL" 2>&1 | tail -10
ls -la "$IMG"
```

Expected: `grareco.png` が生成される、または `NO_IMAGE_TOOL` が返る。

**NO_IMAGE_TOOL の場合**: 記録に「S6 失敗。グラレコは grareco-input.md のみ生成する運用。非ブロック規定は既存のまま」と書く。

- [ ] **Step 8: 結果を記録する**

`docs/superpowers/notes/2026-08-31-codex-smoke.md` を次の内容で作成する(判定と実測値は Step 3〜7 の実際の出力で埋める)。

```markdown
# Codex移植 スモークテスト結果 — 2026-08-31

対象仕様: `docs/superpowers/specs/2026-08-31-r-super-loop-powers-codex-port-design.md` §8.1
実行環境: codex-cli <バージョン>、Windows 11

| # | 検証内容 | 判定 | 実測 | 採用方針 |
|---|---|---|---|---|
| S2 | 親Codexセッション内からの `codex exec` ネスト実行 | OK / FAILED | <出力の要点> | <設計どおり / 設計変更> |
| S3 | session id の取得と `resume` による往復 | OK / FAILED | <SIDと応答> | <C6/C7採用 / 破棄して再構築方式> |
| S4 | `--output-schema` による構造化出力 | OK / FAILED | <verdict値> | <C8採用 / 破棄して自然文方式> |
| S5 | `-C <tmpdir>` 隔離下でのリポジトリ読み取り | OK / 部分成功 / FAILED | <SUCCEEDED か FAILED か> | <物理隔離のみ / 探索禁止指示との併用> |
| S6 | `codex exec` セッションでの画像生成 | OK / FAILED | <生成有無> | <グラレコ生成 / grareco-input.mdのみ> |

## S1 について

S1(marketplace add → plugin add → スキル可視)は、プラグイン骨格ができる Task 5 で実施する。

## 後続タスクへの申し送り

<FAILED があった場合、どのタスクの何を変えるかを1行ずつ書く。すべてOKなら「仕様どおり実装する」と書く。>
```

- [ ] **Step 9: コミット**

```bash
cd "C:/Users/makyu/Desktop/project/r-super-loop-powers"
git add docs/superpowers/notes/2026-08-31-codex-smoke.md
git commit -m "test: Codex CLIスモークテスト(S2〜S6)の実測結果を記録"
```

---

### Task 2: テンプレート同期スクリプトと判定スキーマ

**Files:**
- Create: `scripts/sync-templates.ps1`
- Create: `skills-codex/r-super-loop-powers/schemas/gate-verdict.json`
- Create: `skills-codex/r-super-loop-powers/schemas/escalation-verdict.json`
- Generate: `skills-codex/r-super-loop-powers/templates/*.md`(9枚。スクリプトが複写)

**Interfaces:**
- Consumes: `skills/r-super-loop-powers/templates/*.md`(原本9枚。読み取りのみ)
- Produces:
  - `scripts/sync-templates.ps1 -Mode Copy` — 原本を `skills-codex/r-super-loop-powers/templates/` へ複写。終了コード0
  - `scripts/sync-templates.ps1 -Mode Verify` — 一致すれば `Verify OK (9 templates)` を出力して0、差分があれば `DIFF:` / `MISSING:` / `EXTRA:` 行を出力して1
  - `schemas/gate-verdict.json` — 必須プロパティ `verdict` / `rationale` / `return_to` / `target_unknowns` / `blocking_questions`
  - `schemas/escalation-verdict.json` — 必須プロパティ `decision` / `judgement` / `rationale` / `question_for_human`

- [ ] **Step 1: 同期スクリプトを作成する**

`scripts/sync-templates.ps1`:

```powershell
<#
  templates の同期・検証。
  原本: skills/r-super-loop-powers/templates
  複写先: skills-codex/r-super-loop-powers/templates
  Copy   … 原本を複写先へ上書きコピー
  Verify … 内容一致を検証し、差分があれば非ゼロ終了
#>
param([ValidateSet('Copy','Verify')][string]$Mode = 'Copy')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'skills\r-super-loop-powers\templates'
$dst  = Join-Path $root 'skills-codex\r-super-loop-powers\templates'

if (-not (Test-Path $src)) { Write-Output "原本が見つかりません: $src"; exit 1 }

if ($Mode -eq 'Copy') {
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    Get-ChildItem -Path $dst -Filter *.md -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -Path (Join-Path $src '*.md') -Destination $dst -Force
    $n = @(Get-ChildItem -Path $dst -Filter *.md -File).Count
    Write-Output "Copied $n templates -> $dst"
    exit 0
}

if (-not (Test-Path $dst)) { Write-Output "複写先が存在しません: $dst"; Write-Output "Verify FAILED"; exit 1 }

$srcNames = @(Get-ChildItem -Path $src -Filter *.md -File | ForEach-Object { $_.Name })
$dstNames = @(Get-ChildItem -Path $dst -Filter *.md -File | ForEach-Object { $_.Name })
$failed = $false

foreach ($name in $srcNames) {
    if ($dstNames -notcontains $name) { Write-Output "MISSING: $name"; $failed = $true; continue }
    $a = (Get-FileHash (Join-Path $src $name) -Algorithm SHA256).Hash
    $b = (Get-FileHash (Join-Path $dst $name) -Algorithm SHA256).Hash
    if ($a -ne $b) { Write-Output "DIFF: $name"; $failed = $true }
}
foreach ($name in $dstNames) {
    if ($srcNames -notcontains $name) { Write-Output "EXTRA: $name"; $failed = $true }
}

if ($failed) { Write-Output "Verify FAILED"; exit 1 }
Write-Output "Verify OK ($($srcNames.Count) templates)"
exit 0
```

- [ ] **Step 2: Verify が「複写先なし」を検出することを確認する(失敗の確認)**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync-templates.ps1 -Mode Verify; $LASTEXITCODE
```

Expected: `複写先が存在しません: ...` と `Verify FAILED` が出力され、終了コードが `1`

- [ ] **Step 3: Copy を実行する**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync-templates.ps1 -Mode Copy; $LASTEXITCODE
```

Expected: `Copied 9 templates -> ...\skills-codex\r-super-loop-powers\templates` / 終了コード `0`

- [ ] **Step 4: Verify が一致を検出することを確認する**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync-templates.ps1 -Mode Verify; $LASTEXITCODE
```

Expected: `Verify OK (9 templates)` / 終了コード `0`

- [ ] **Step 5: Verify が差分を検出することを確認する**

```powershell
Add-Content -Path skills-codex\r-super-loop-powers\templates\assumptions.md -Value "差分検出テスト"
powershell -ExecutionPolicy Bypass -File scripts\sync-templates.ps1 -Mode Verify; $LASTEXITCODE
powershell -ExecutionPolicy Bypass -File scripts\sync-templates.ps1 -Mode Copy
powershell -ExecutionPolicy Bypass -File scripts\sync-templates.ps1 -Mode Verify; $LASTEXITCODE
```

Expected: 1回目が `DIFF: assumptions.md` / `Verify FAILED` / 終了コード `1`、Copy 後の2回目が `Verify OK (9 templates)` / 終了コード `0`

- [ ] **Step 6: ゲート判定スキーマを作成する**

`skills-codex/r-super-loop-powers/schemas/gate-verdict.json`:

```json
{
  "type": "object",
  "properties": {
    "verdict": {
      "type": "string",
      "enum": ["PASS", "REVISE", "REPLAN", "BLOCKED"]
    },
    "rationale": {
      "type": "string",
      "description": "判定の根拠。5行以内。goal-frameの承認基準・残存未知の許容性・仮定の事実扱い・否定リスト違反の観点で書く"
    },
    "return_to": {
      "type": "string",
      "description": "REVISE / REPLAN の場合の戻り先工程(例: A-4計画, B-2実装)。該当しない場合は空文字"
    },
    "target_unknowns": {
      "type": "array",
      "items": { "type": "string" },
      "description": "戻り先で解消すべき未知・仮定。該当しない場合は空配列"
    },
    "blocking_questions": {
      "type": "array",
      "items": { "type": "string" },
      "description": "BLOCKED の場合に人間へ提示する質問。該当しない場合は空配列"
    }
  },
  "required": ["verdict", "rationale", "return_to", "target_unknowns", "blocking_questions"],
  "additionalProperties": false
}
```

- [ ] **Step 7: エスカレーション判定スキーマを作成する**

`skills-codex/r-super-loop-powers/schemas/escalation-verdict.json`:

```json
{
  "type": "object",
  "properties": {
    "decision": {
      "type": "string",
      "enum": ["DECIDE", "ASK_HUMAN"]
    },
    "judgement": {
      "type": "string",
      "description": "DECIDE の場合の判断内容。ASK_HUMAN の場合は空文字"
    },
    "rationale": {
      "type": "string",
      "description": "判断または人間へ回す理由の根拠"
    },
    "question_for_human": {
      "type": "string",
      "description": "ASK_HUMAN の場合の人間向け質問文。DECIDE の場合は空文字"
    }
  },
  "required": ["decision", "judgement", "rationale", "question_for_human"],
  "additionalProperties": false
}
```

- [ ] **Step 8: スキーマが妥当なJSONであることを確認する**

```bash
python -c "
import json
for p in ['skills-codex/r-super-loop-powers/schemas/gate-verdict.json','skills-codex/r-super-loop-powers/schemas/escalation-verdict.json']:
    d=json.load(open(p,encoding='utf-8')); print(p,'OK',sorted(d['properties']))
"
```

Expected: 2行とも `OK` とプロパティ名一覧が表示される

- [ ] **Step 9: コミット**

```bash
git add scripts/sync-templates.ps1 skills-codex/r-super-loop-powers/schemas skills-codex/r-super-loop-powers/templates
git commit -m "feat: templates同期スクリプトと判定スキーマ2種(Codex版)"
```

---

### Task 3: Codex版 policy.md

**Files:**
- Create: `skills-codex/r-super-loop-powers/policy.md`
- Read only: `skills/r-super-loop-powers/policy.md`(原本。変更しない)

**Interfaces:**
- Consumes: Task 2 の `schemas/escalation-verdict.json`(エスカレーション節から参照)
- Produces: `policy.md` — SKILL.md が起動時チェック1で読み込むポリシー。役名 `driver / judge / proxy / builder / reviewer / human`、PL-001〜PL-010、エスカレーション発火条件10項目、否定リスト6項目を定義する

- [ ] **Step 1: ファイルを作成する**

`skills-codex/r-super-loop-powers/policy.md` を次の内容で作成する。

```markdown
# r-super-loop-powers モデル運用ポリシー(Codex版)

上位要件: `goal_engineering_ai_skill_policy_requirements.docx` 5章・11章・12章・14章、`20260810_ハーネス改善-1.md`(v0.2の入力)、`20260818_ハーネス改善-2.md`(v0.3の入力)、および `docs/superpowers/specs/2026-08-31-r-super-loop-powers-codex-port-design.md`(Codex移植設計)。
本ポリシーは SKILL.md(オーケストレーター)から参照される。数値・比率は観測指標であり、品質や安全に必要な判断を妨げない。

## 上位原則(Goal Loopの目的)

Goal Loopの目的は次の2つであり、品質最大化・速度最大化は目的ではない。

- **A. 要件適合性**: 定義したゴール・要件・制約に成果物が適合している確度を高める。「コードが動く」ではなく「作りたかったものを正しく作れているか」
- **B. 未知の低減**: 開始時に認識できなかった未知(特に無自覚の未知)を、仮説→実装→評価のループで発見・既知化する

AIは未知に対して可能な限り自律的に仮説を立て、人間が評価可能な具体物まで精度を高めてから提示する。人間の役割は生成より評価。**ループ・テスト・レビュー・承認は、それ自体を目的とせず、AまたはBに寄与する場合にのみ実施する**(工程の存在理由テスト)。ループ終了条件は回数ではなく「適合性への十分な確信 + 残存する重要な未知が許容可能」。

**MVPモードの原則(v0.3)**: MVPモードでは、人間にHOWの詳細確定を原則として求めない。その代わり、開発開始前のヒアリングでGoal・Requirements・Constraints・利用文脈・暗黙の期待を十分に探索し、ユーザーの「無自覚の既知」を可能な限り表面化する。Agentはその情報を根拠として、まだ正解の存在しないHOWを仮説として具体化し、自律的に実装・評価・改善する。Human Feedbackは各マイルストーンの必須ゲートではなく、重大な不確実性・不可逆性・低確信度の判断に対するエスカレーションとして用いる。通常はユーザー価値がEnd-to-Endで成立した段階(Checkpoint)でHuman Acceptanceを行う。**「HOWを聞かない」ことと「ヒアリングを減らす」ことを混同しない** — 質問の対象をHOWからGoal / Context / Preferenceへ移す。

## ループ強度

**MVP(既定)** と **高信頼** の2段階。Goal Frame作成時に proxy が提案し、人間がGoal Frame確認時に確定する。マイルストーン単位の一時変更は人間が指示できる。judgeゲートとHuman Acceptanceは両強度で維持する(要件適合性の保証線)— MVPのHuman AcceptanceはCheckpoint単位で行う。一時変更は state.md の強度欄に記録し、そのマイルストーン完了時に goal-frame.md の確定値へ戻す。

| 工程 | MVP(既定) | 高信頼 |
|---|---|---|
| ヒアリング(A-1a) | proxy駆動の往復ヒアリング(無自覚の既知の表面化。目安2〜4往復) | 初回ラウンド(開発タイプ確認)のみ |
| Goal Frame / Goal Gate(A-1b / A-6) | 実施(表面化した既知+未知マップ+強度+終了条件+Checkpoint配置判定) | 実施(未知マップ+強度+終了条件を含む) |
| ブレスト〜Plan(A-2〜A-4) | superpowers:brainstormingを**proxy代理回答**で実施(人間はASK_HUMAN時のみ) | 人間参加のsuperpowers:brainstorming |
| Human Goal Plan承認(A-8) | WHATレベル(ゴール解釈・要件・制約・Checkpoint配置・仮定台帳サマリ) | 従来(spec/planレビュー含む) |
| マイルストーン開始確認(B-1・judge) | 実施(軽量) | 同左 |
| 実装委譲(B-2) | マイルストーン単位でまとめて builder に委譲可(タスク細分化しない) | タスク分解して個別に委譲 |
| タスク単位の受け入れ(B-3) | builderの自己検証報告の確認のみ(diff精読なし) | driverがdiffを確認 |
| テスト要求(B-2) | 受け入れ基準に直結する検証+未知低減に効く検証のみ | 単体・結合・lint・型検査をフル要求 |
| 独立レビュー(B-5) | 省略(driverがsubmission作成時にセルフチェック+decisions.md確定) | reviewerで実施(PL-003)+decisions.md確定 |
| Implementation Gate(B-6・judge) | 実施(適合性+残存未知の許容性)。非CheckpointはPASS後に人間承認なしで次マイルストーンへ | 実施(適合性+残存未知の許容性) |
| Human Report / Acceptance(B-7 / B-8) | **Checkpoint到達時のみ**(評価パッケージ) | マイルストーン毎 |
| コミット | マイルストーン毎に中間コミット、Checkpoint ACCEPTで確定 | ACCEPT後のみ |
| Learning | グラレコ+decisions.md=マイルストーン毎 / retro=Checkpoint毎 | マイルストーン毎(従来通り。decisions.mdもマイルストーン毎に確定) |

## Checkpointとマイルストーン粒度

- **Checkpoint** = 「**ユーザーが1つの価値をEnd-to-Endで利用・評価できる**」点。goal-plan.mdのマイルストーン一覧に印として配置し、A-8で人間が配置を承認する。最終マイルストーンは必ずCheckpoint。人間の受け入れテスト1回で確認できる範囲に収める(時間の上限・下限は定めない)
- **MVPのマイルストーン** = 内部作業単位。judgeゲート(B-6)で判定可能な成果のまとまりであればよく、E2E価値の完成は要求しない。ただし技術タスク単位への細分化はしない
- **高信頼のマイルストーン** = 従来通り「ユーザーが1つの価値をEnd-to-Endで利用できる」単位(全マイルストーンがCheckpoint相当)

## 仮説自律の否定リスト

以下に触れる仮説は自律実行禁止。エスカレーション(judge)または人間確認を必須とする:

1. データ削除・上書き等の**不可逆操作**
2. **外部公開・送信**(デプロイ、外部APIへの送信、メール等)
3. **課金・支払い・契約**
4. **セキュリティ・認証・個人情報**の扱いの変更
5. Goal Frameに明記された**制約・要件の変更**(=要件の再定義)
6. 承認済み設計の**破壊的変更**

上記以外は、仮説を立てて `assumptions.md`(仮定台帳)に記録した上で自律的に進んでよい。各仮定に「ゴールへの寄与」1行を必須とする(局所最適化ガード)。ユーザーが答えを持たない問いを人間へ返し続けない — 仮説化し、評価可能な具体物にして評価してもらう。

## 責任分担

| 担当 | モデル / effort | 主責務 | 通常実行 | 禁止・抑制 |
|---|---|---|---|---|
| human(人間) | — | 意図の提示、ヒアリング回答(暗黙の前提・期待の表面化に協力)、具体物の評価とフィードバック、最終受け入れ、優先順位判断 | Goal Seed入力、ヒアリング回答、ループ強度の確定、A-8承認(MVPはWHATレベル)、ASK_HUMAN応答、Checkpoint受け入れテスト | 生diffの最初からの精読を前提にしない。答えを持たない問い(HOW)への回答を強制されない |
| proxy(代理役) | gpt-5.6-sol / max | ヒアリング駆動(無自覚の既知の探索)、入口の基準設定(Goal Frame・強度提案)、MVPでは**代理ブレスト回答**(人間の代理としてHOW質問に回答・設計承認) | `codex exec` で1インスタンスを起動し `codex exec resume` で往復(A-1a〜A-4) | ブレスト・仕様・実装・レポートの**本文作成**。自分が代理回答した設計のゲート判定(自己承認) |
| judge(判定役) | gpt-5.6-sol / ultra | 全体責任者としての承認ゲート(適合性+残存未知の許容性+仮定の事実扱いチェック)、マイルストーン開始確認、エスカレーション判定(DECIDE / ASK_HUMAN)、Human REJECT後の戻り先決定 | 呼び出しごとに新規セッション+最小コンテキスト(一時ディレクトリ隔離) | 本文作成。proxyセッションの `resume`(自己承認の禁止) |
| driver(進行役) | gpt-5.6-sol / medium | メインセッション。**Solution仮説の設計責任**。整理・仕様化・計画・仮定台帳の管理・decisions.md・承認資料・評価パッケージ・振り返り・確定処理 | 常駐 | ゴール変更の独断確定 |
| builder(実装役) | gpt-5.6-luna / max | 実装担当。コード変更、検証、自己検証報告 | マイルストーン単位(MVP)またはタスク単位(高信頼)で `codex exec` 起動 | コミット、要件の再定義、否定リスト該当の自律判断 |
| reviewer(独立レビュー役) | gpt-5.6-sol / max | 高信頼強度での実装非関与の独立レビュー(PL-003) | B-5でのみ `codex exec` 起動 | 実装の変更、ゲート判定 |
| グラフィックレコード | gpt-5.6-luna / max | グラレコ生成 | マイルストーン毎(MVPは中間クローズ時、Checkpointは Learning)に `codex exec` で呼び出し | 未承認状態を確定として描かない。APIキー・スクリプト経由の生成はしない |
| 将来枠(未使用) | gpt-5.4-mini / gpt-5.3-codex-spark | 軽量探索・補助実装の候補 | — | 必須モデルとして固定しない |

## judge / proxy を呼ぶ場面(これ以外では呼ばない)

1. ヒアリング(MVP・A-1a): 質問の設計・深掘り・充足判定を行うとき(proxy・往復)
2. ループ開始時: Goal Seedから Goal Frame(方向・表面化した既知・制約・未知マップ・承認基準・終了条件・強度提案)を定義するとき(proxy)
3. 代理ブレスト(MVP・A-2〜A-4): superpowers:brainstormingの質問・設計承認に人間の代理として回答するとき(proxy)
4. マイルストーン開始時: 対象マイルストーンが上位ゴールのどの成果を満たすかを確認するとき(judge・注意点のみの軽量呼び出し)
5. 承認ゲート: Approval Submission が揃い、PASS/REVISE/REPLAN/BLOCKED を判定するとき(judge)
6. エスカレーション: 実行担当が「エスカレーション発火条件」を検出したとき(judge。判定は DECIDE / ASK_HUMAN)
7. Human REJECT後: 戻り先(修正 / 再計画 / ゴール修正)を決定するとき(judge)

## judge / proxy を原則呼ばない場面

- Brainstorming / Spec / Plan の**本文作成**(MVPの代理ブレストでも proxy は回答・承認のみ。本文は driver が書く)
- コード実装、単体テスト、軽微な修正
- 承認に必要な情報の整理・要約(driverの仕事)
- 人間向けレポート、振り返りメモの作成
- フォーマット変換や定型ドキュメント生成

## 運用ポリシー

| ID | ポリシー | 要件 |
|---|---|---|
| PL-001 | Default roles | judge=判定、proxy=代理、driver=整理/仕様/レビュー/報告、builder=実装をデフォルトとする |
| PL-002 | No effort inflation | 「高性能だから」という理由だけで effort を上げない。driverは `gpt-5.6-sol` / medium で運用する |
| PL-003 | Independent review | **高信頼強度では**、judge提出前に実装非関与の reviewer(`gpt-5.6-sol` / max)が独立レビューする。MVP強度では driver のセルフチェックで代替する |
| PL-004 | Evidence first | 承認要求には検証証拠・残存未知リスト・未解決事項を必ず含める。推測だけでPASSを求めない |
| PL-005 | Human after AI gate | 人間受け入れは judge PASS後に行う(MVPはCheckpoint到達時のみ) |
| PL-006 | Human rejection routing | Human REJECTは judge へ戻し、戻り工程を judge が決める |
| PL-007 | Budget observability | judge / proxy / builder / reviewer の呼び出し(proxyとの `resume` 往復を含む)を call-log.md に記録し、driver : judge+proxy ≈ 5:1 を目安に振り返る。MVPのヒアリング・代理ブレスト期(A-1a〜A-4)はproxy往復が構造的に増えるため、目安は**ワークフローB以降**に適用する |
| PL-008 | No forced ratio | 比率は目標であり、品質や安全に必要な judge / proxy 呼び出しを禁止しない |
| PL-009 | Context minimization | judge / proxy へは goal-frame + 対象文書 + 仮定台帳の関連部分(+ 必要ならhearing-logの関連部分)のみを渡す。全コード・全会話を常時ロードしない。**渡す文書だけをコピーした一時ディレクトリで `codex exec -C <tmpdir> -s read-only` として起動し、さらにプロンプトで「与えられた文書のみで判断し、他のファイルを探索しない」と明記して担保する**。proxyは自インスタンス内の文脈保持のみ許容 |
| PL-010 | Human cognitive load | 人間向け成果物は、ゴール → 結果 → 証拠 → リスク → 確認手順の順で構造化し、確定事項と仮説による決定を区別する(判断の内訳) |

## エスカレーション発火条件(いずれかを検出したらjudgeへ)

1. 仕様 / Goal Plan 内に矛盾または複数解釈があり、実装選択でユーザー価値が変わる
2. 承認済み設計を変更しないと実装できない
3. 複数マイルストーンや広い影響範囲をまたぐ設計変更が必要
4. テストを繰り返しても原因が特定できず、計画自体の見直しが必要
5. 安全性・データ破壊・互換性など重大リスクを検出
6. 人間が示した Goal Seed と現在の作業がズレている疑いがある
7. 立てるべき仮説が「仮説自律の否定リスト」に触れる
8. **ユーザー固有の判断**(好み・業務文脈・優先順位)が必要で、hearing-log.md / goal-frame.md から答えを導けない
9. **複数の合理的Solutionが存在し、選択でユーザー体験が大きく変わる**
10. **低確信かつ影響が大きい判断**(後から変更すると高コストな構造選択を含む)

形式は `templates/escalation.md` の7点フォーマットを用いる。judgeの判定は **DECIDE**(判断+根拠を返し自律続行)または **ASK_HUMAN**(人間向けに整形した質問を返す。driverが人間へ提示し、回答をhearing-log.mdへ追記してから続行)のいずれかを必ず返す(`schemas/escalation-verdict.json` による構造化出力)。

## 観測

- call-log.md 形式: `YYYY-MM-DD HH:MM | judge|proxy|builder|reviewer | フェーズ | 目的`(1呼び出し1行。proxyとの `resume` 往復も1往復1行)
- driver(メインセッション)自身の消費は記録対象外(常駐のため)
- Retrospective 作成時に、呼び出し比率(5:1目安・ワークフローB以降)に加えて、ループ回数・主要フェーズ所要時間(call-logの時刻から概算)・発見された未知を記載する。ハード制限にしない(PL-008)
```

- [ ] **Step 2: 不変であるべき節が原本と一致することを確認する**

```bash
python - <<'PY'
import io,re
def sec(path, head):
    t = io.open(path, encoding='utf-8').read()
    i = t.index(head)
    j = t.find('\n## ', i+1)
    return t[i:j if j>0 else len(t)].strip()
src='skills/r-super-loop-powers/policy.md'
dst='skills-codex/r-super-loop-powers/policy.md'
for head in ['## 上位原則(Goal Loopの目的)']:
    a, b = sec(src, head), sec(dst, head)
    print(head, 'MATCH' if a==b else 'DIFFER')
# 否定リストは見出し以下の6項目のみ比較
def items(path):
    t = io.open(path, encoding='utf-8').read()
    i = t.index('## 仮説自律の否定リスト')
    j = t.find('\n## ', i+1)
    return [l for l in t[i:j].splitlines() if re.match(r'^\d\. ', l)]
print('否定リスト', 'MATCH' if items(src)==items(dst) else 'DIFFER')
def esc(path):
    t = io.open(path, encoding='utf-8').read()
    i = t.index('## エスカレーション発火条件')
    j = t.find('\n## ', i+1)
    return [l for l in t[i:j].splitlines() if re.match(r'^\d+\. ', l)]
print('エスカレ条件', 'MATCH' if esc(src)==esc(dst) else 'DIFFER')
PY
```

Expected: 3行すべて `MATCH`(上位原則の節には MVPモードの原則も含まれる)

`DIFFER` が出た場合は、原本の該当箇所をそのままコピーして直す。

- [ ] **Step 3: 旧役名が残っていないことを確認する**

```bash
grep -n -E "Fable|Opus|opus-sub|SendMessage|Agentツール" skills-codex/r-super-loop-powers/policy.md
```

Expected: 出力なし(終了コード1)

- [ ] **Step 4: コミット**

```bash
git add skills-codex/r-super-loop-powers/policy.md
git commit -m "feat: Codex版policy.md(役名中立化・モデル分担・PL-009の物理隔離)"
```

---

### Task 4: Codex版 SKILL.md

**Files:**
- Create: `skills-codex/r-super-loop-powers/SKILL.md`
- Read only: `skills/r-super-loop-powers/SKILL.md`(原本。変更しない)

**Interfaces:**
- Consumes: Task 2 の `schemas/gate-verdict.json` / `schemas/escalation-verdict.json` と `templates/*.md`、Task 3 の `policy.md`
- Produces: `SKILL.md` — Codexが `$r-super-loop-powers:r-super-loop-powers` で起動するオーケストレーター本体。frontmatter の `name` は `r-super-loop-powers`

- [ ] **Step 1: ファイルを作成する**

`skills-codex/r-super-loop-powers/SKILL.md` を次の内容で作成する。

````markdown
---
name: r-super-loop-powers
description: Use when starting or resuming a goal-engineering loop (ゴールループ / goal loop / ゴールエンジニアリング開発). Superpowersの上位で、要件適合性と未知低減を目的に、フェーズ管理・成果物契約・承認ゲート・ヒューマン・イン・ザ・ループ配置・役割別モデル分担(sol進行 / sol判定 / sol代理 / luna実装)をオーケストレーションする。MVPモードでは代理役のヒアリングでゴールと文脈を掘り、HOWは代理ブレストでAgentへ委任し、Checkpoint単位でHuman Acceptanceを行う。
---

# r-super-loop-powers — ゴールループ・オーケストレーター(Codex版)

あなた(このスキルを実行するモデル)は **driver(メインセッション)** として、ゴールループの進行管理と成果物作成を担当する。
このスキルは **責任・ゲート層** である: いまどのフェーズか、次に必要な成果物は何か、誰が実行し誰が判定するか、人間へ返すタイミングだけを制御する。
作業の進め方(HOW)はSuperpowersのスキルに完全に委ね、その内部手順には一切干渉しない。MVPモードでは、Superpowersのスキルが人間に求める質問・承認への応答を **proxy(代理役)** が担う(相手が変わるだけで、スキルの手順は変えない)。

Goal Loopの目的は **A. 要件適合性** と **B. 未知の低減** の2つ(policy.md「上位原則」)。MVPモードでは人間にHOWの確定を求めず、ヒアリングで無自覚の既知を表面化した上でAgentがHOWを仮説化する(policy.md「MVPモードの原則」)。ループ・テスト・レビュー・承認は、AまたはBに寄与する場合にのみ実施する。ループ終了条件は回数ではなく「適合性への十分な確信 + 残存する重要な未知が許容可能」。

## 役とモデル

| 役 | モデル / effort | 起動 |
|---|---|---|
| driver(あなた) | gpt-5.6-sol / medium | メインセッション |
| proxy | gpt-5.6-sol / max | `codex exec` で1インスタンス + `codex exec resume` で往復 |
| judge | gpt-5.6-sol / ultra | `codex exec` 新規セッション(呼び出しごと) |
| builder | gpt-5.6-luna / max | `codex exec` 新規セッション |
| reviewer | gpt-5.6-sol / max | `codex exec` 新規セッション(高信頼のB-5のみ) |

## 起動時チェック(毎回必ず実行)

1. **ポリシー読込**: このスキルと同じディレクトリの `policy.md` を読む。以後の全判断はこのポリシーに従う。
2. **モデル確認**: driverが `gpt-5.6-sol` / effort `medium` で動いていない場合、ユーザーに `/model` での切替を提案し、切替またはユーザーの明示的な続行指示があるまでフェーズ作業を開始しない(PL-002)。
3. **状態復元**: 対象プロジェクトで `docs/r-super-loop-powers/*/state.md` を探す(ネイティブのファイル検索)。
   - 見つかった場合: 最新の state.md を読み、「現在フェーズ / 強度 / 対象マイルストーン / 次のCheckpoint / 次のゲート」を1〜3行でユーザーに報告し、そのフェーズの手順から再開する。
   - 見つからない場合: ワークフローA(新規ゴール)を開始する。
4. **強度確認**: goal-frame.md が存在する場合、ループ強度(MVP | 高信頼)を読み、policy.md「ループ強度」の工程表に従って以後の工程を実施する。強度未確定のままワークフローBへ進まない。
5. **前提チェック(このゴールで初回のみ)**: `codex --version` が応答すること、`gpt-5.6-sol` と `gpt-5.6-luna` が利用可能であることを確認する。満たされない場合はユーザーに報告して停止する。

## ディレクトリ契約

対象プロジェクト内に次を作成・維持する:

```
docs/r-super-loop-powers/<goal-slug>/
├── state.md                 # 現在地(下記フォーマット)
├── goal-seed.md             # 人間の意図(原文のまま)
├── hearing-log.md           # A-1aヒアリングとASK_HUMAN中継の記録(MVP。高信頼はASK_HUMAN中継時のみ)
├── goal-frame.md            # 入口出力 = 承認基準・強度・未知マップ・終了条件の原本
├── assumptions.md           # 仮定台帳(全フェーズで追記)
├── goal-plan.md             # spec/planリンク + マイルストーン一覧(Checkpoint印) + 主要設計判断(proxy代理回答による)
├── goal-plan-submission.md  # A-5 Goal Plan承認用submission
├── goal-gate-decision.md    # A-6 Goal Gate判定
├── call-log.md              # 呼び出し記録(PL-007)
└── milestones/<n>-<名前>/
    ├── submission.md / gate-decision.md / decisions.md
    ├── builder-report.md    # B-2〜B-3のbuilder自己検証報告(codex exec の -o 出力)
    ├── review.md            # 高信頼のB-5のみ: reviewerの独立レビュー結果
    ├── grareco-input.md / grareco.png
    ├── human-report.md / acceptance.md / retro.md   # MVPではCheckpointマイルストーンのみ
    └── escalation-<連番>.md  # B-4発生時のみ
```

`<goal-slug>` はGoal Seedの内容から短いkebab-caseで命名する。

### state.md フォーマット

```markdown
# state — <goal-slug>
- phase: goal-definition | milestone-implementation | human-acceptance | finalization | learning | done
- 強度: MVP | 高信頼 | 未確定
- milestone: <n>-<名前> または -
- 次のCheckpoint: <n>-<名前> または -
- 担当: driver | judge | proxy | builder | reviewer | human
- 次のゲート: goal-gate | impl-gate | human-acceptance | none
- proxy-session: <session id> または -
- 待ち: <人間待ちの場合はその内容。なければ ->
- updated: YYYY-MM-DD HH:MM
```

**全フェーズで「state.md更新 → 作業」の順**を守る。フェーズ遷移の前に、下表の必須成果物が揃っているかを必ず確認し、欠落があれば次へ進まない。

## フェーズと成果物契約

| フェーズ | 入口条件 | このフェーズで必須の成果物 | 出口のゲート |
|---|---|---|---|
| goal-definition | goal-seed.md | (MVP: hearing-log.md →) goal-frame.md(強度確定) → spec/plan → goal-plan.md(Checkpoint印) → goal-plan-submission.md | Goal Gate(judge)→ Human承認(MVPはWHATレベル) |
| milestone-implementation | Goal Plan承認済み + 強度確定 | 実装diff + 検証証拠(高信頼のみ: 独立レビュー) → decisions.md → submission.md(残存未知リスト付き) | Implementation Gate(judge)。MVPの非CheckpointはPASS後、人間承認なしで次マイルストーンへ |
| human-acceptance | judge PASS(MVP: Checkpoint到達時のみ) | human-report.md(評価パッケージ) | 人間のACCEPT/REJECT |
| finalization | acceptance.md に ACCEPT | 確定処理(確定コミット) | なし |
| learning | 確定処理済み | retro.md + grareco-input.md(+ grareco.png) | なし |

## 仮定台帳の運用

- `templates/assumptions.md` の形式で goal直下に置き、全フェーズで追記する。
- 追記のタイミング: (1) ヒアリング・ブレスト中に人間または proxy が「決めていない / わからない」と答えたとき (2) 実装・設計で仮説的判断をしたとき (3) エスカレーションや Human Feedback で新しい未知が見つかったとき。
- 各仮定には「ゴールへの寄与」1行を必ず書く(局所最適化ガード)。
- **policy.md「仮説自律の否定リスト」に触れる仮定は自律実行しない** — エスカレーション(B-4)または人間確認へ。
- 検証されたら状態を「検証済み」または「棄却」に更新する。棄却時は必要なら新しい仮定を起こす。

## 記録ルール(PL-007)

judge / proxy / builder / reviewer を呼ぶたび、および proxy との `resume` 往復のたびに、直後に `call-log.md` へ1行追記する:
`YYYY-MM-DD HH:MM | judge|proxy|builder|reviewer | フェーズ | 目的`

## ゲート保護ルール(絶対)

1. judge PASS 前に人間へ受け入れを求めない(SK-007)
2. human-report.md(評価パッケージ)なしで Human Acceptance に進まない(SK-008)
3. Checkpoint(高信頼はマイルストーン)の acceptance.md に ACCEPT がない状態で確定処理をしない(SK-009)。MVPの中間コミット(B-6 PASS後)は可
4. 必須成果物が欠けた状態で judge ゲートを呼ばない — 欠落は自分で差し戻して埋める(NFR-05)
5. **builder にコミットさせない**
6. 否定リストに触れる仮説を自律実行しない — エスカレーションまたは人間確認へ
7. 代理ブレストに参加した proxy にゲート判定(A-6 / B-6)をさせない(自己承認の禁止)(SK-010)。実装上は **proxy の session id を judge に `resume` しない**ことで担保する

## 役の共通契約

### 起動の規定形

サブ役はすべて `codex exec` で起動する。プロンプトは引数ではなく **stdin**(`-`)で渡す。実行の timeout は最長(600000ms)を指定し、長そうな委譲はバックグラウンドで実行する。出力は `-o` でファイルに落とし、driverがそれを読む。

**judge(ゲート・判断。呼び出しごとに新規セッション)**

```bash
codex exec -m gpt-5.6-sol -c model_reasoning_effort=ultra \
  -C "<tmpdir>" -s read-only --skip-git-repo-check \
  --output-schema "<このスキルのディレクトリ>/schemas/gate-verdict.json" \
  -o "<tmpdir>/verdict.json" -
```

**proxy(代理。1インスタンスを継続)**

```bash
# 初回
codex exec -m gpt-5.6-sol -c model_reasoning_effort=max \
  -C "<tmpdir>" -s read-only --skip-git-repo-check \
  -o "<tmpdir>/reply-1.md" - | tee "<tmpdir>/session.log"
# session id は出力に現れる最初のUUIDを拾う
# 往復
codex exec resume "<session id>" -m gpt-5.6-sol -c model_reasoning_effort=max \
  -o "<tmpdir>/reply-<n>.md" "<次の入力>"
```

session id は `state.md` の `proxy-session:` に記録する。UUIDが拾えなかった場合、`--last` は**使わない**(誤ったセッションへ接続するため)。新しい proxy を起動し直し、goal-seed / goal-frame / hearing-log を渡して文脈を再構築する。

**builder(実装)**

```bash
codex exec -m gpt-5.6-luna -c model_reasoning_effort=max \
  -s workspace-write -c approval_policy=never \
  -o "<milestoneディレクトリ>/builder-report.md" -
```

**reviewer(高信頼のB-5のみ)**

```bash
codex exec -m gpt-5.6-sol -c model_reasoning_effort=max \
  -s read-only --skip-git-repo-check \
  -o "<milestoneディレクトリ>/review.md" -
```

### コンテキスト最小化(PL-009)

judge と proxy は `<OSのTEMP>/r-slp/<goal-slug>/<役>-<工程>-<連番>/` に**必要な文書だけをコピーして**起動する。渡す文書:

| 呼び出し | コピーする文書 |
|---|---|
| A-1a / A-1b / A-2〜A-4(proxy) | goal-seed.md、hearing-log.md、goal-frame.md(あれば)、retro抜粋(あれば)、対象テンプレートの構造 |
| A-6(judge) | goal-frame.md 全文、goal-plan-submission.md 全文、assumptions.md の未検証仮定 |
| B-1(judge) | goal-frame.md、対象マイルストーン定義(goal-plan.mdの該当部分)、retro抜粋 |
| B-4(judge) | goal-frame.md、escalation-<連番>.md の1〜6、関連する未検証仮定、hearing-log.md の関連部分 |
| B-6(judge) | goal-frame.md、マイルストーン定義、submission.md、assumptions.md の未検証仮定 |
| B-9(judge) | goal-frame.md、human-report.md、REJECT理由 |

対象プロジェクトの生コード・全会話履歴は渡さない。プロンプトには必ず「**与えられた文書のみで判断し、他のファイルを探索しない**」と明記する。judgeは呼び出し完了後に一時ディレクトリを削除し、proxyはその工程(A-1a〜A-4)の完了時にまとめて削除する。削除に失敗しても処理はブロックしない。

judgeが追加資料を要求した場合のみ、`resume` で1往復だけ追加提供する。

### 判定の出力契約

judgeのゲート判定は `schemas/gate-verdict.json` による構造化出力で受け取る: `verdict`(`PASS | REVISE | REPLAN | BLOCKED`)+ `rationale`(5行以内)+ `return_to`(REVISE/REPLANの戻り先工程)+ `target_unknowns`(対象の未知・仮定)+ `blocking_questions`(BLOCKED時の人間向け質問)。受け取ったJSONは、保存先のMarkdown(`goal-gate-decision.md` / `gate-decision.md`)へ「判定 / 根拠 / 戻り先 / 対象の未知 / 人間への質問」の見出しで整形して書く。

エスカレーション判定は `schemas/escalation-verdict.json` で `decision`(`DECIDE | ASK_HUMAN`)+ `judgement` + `rationale` + `question_for_human` を受け取る。

判定観点(プロンプトに明記する): (1) goal-frame.md の承認基準を満たすか (2) 残存する重要な未知が許容可能か(goal-frameの終了条件と照合) (3) 仮定が事実として扱われていないか (4) 否定リスト違反の仮説がないか。「動くか」ではなくゴール整合を見る。

## ワークフローA: Goal Definition

**A-0 Goal Seed保存(driver)**
ユーザーの「やりたいこと」を原文のまま `goal-seed.md` に保存する。要約・整形しない。`<goal-slug>` を決め、ディレクトリと state.md(phase: goal-definition, 強度: 未確定, proxy-session: -)、空の call-log.md、`templates/assumptions.md` の形式で空の仮定台帳、`templates/hearing-log.md` の形式で空のヒアリング記録を作成する。

**A-1a ヒアリング(proxy・往復)**
直近の `docs/r-super-loop-powers/*/milestones/*/retro.md` を新しい順に最大3件読み、要点を抜粋する。
一時ディレクトリに goal-seed.md 全文・空の hearing-log.md・retro抜粋(あれば)・`templates/hearing-log.md` の構造をコピーし、proxy を起動して次を指示する:
「あなたはこのゴールの全体責任者としてヒアリングを設計・駆動する。目的はユーザーの**無自覚の既知**(暗黙の前提・操作の好み・過去の不満・絶対に避けたい体験・想定利用シーン・実際の業務フロー・優先順位・暗黙の成功条件)の表面化。**HOW(UI形式・機能構成・導線・実装方式の選択)を質問してはならない**。質問は『感情・体験 → 嗜好・制約 → 検証』の順で組み立てる。初回は開発タイプの確認(MVP型か、高信頼・仕様重視型か)を含む3〜7問と、現時点の理解サマリを返せ。以後の往復では、回答を踏まえた深掘り質問を返すか、十分と判断したら『ヒアリング完了』と宣言せよ。」
session id を state.md の `proxy-session:` に記録する。driverは質問をそのまま人間へ提示し、回答を `hearing-log.md` に記録し、更新した hearing-log.md を一時ディレクトリへ同期してから `codex exec resume` で proxy へ返す(目安2〜4往復)。人間が開発タイプで高信頼を選んだ場合は深掘りを打ち切り、A-1bへ進む。往復ごとにcall-logへ記録(proxy)。

**A-1b Goal Frame(proxy)**
- **MVP**: 同じ proxy へ `resume` で `templates/goal-frame.md` の構造を渡し、Goal Frame生成を指示する。
- **高信頼**: proxy と同設定(`gpt-5.6-sol` / max、一時ディレクトリ隔離)の新規セッションを**1回だけ使い捨てで**起動し、`templates/goal-frame.md` の構造 + goal-seed.md 全文 + retro抜粋(あれば)を渡す(session idは記録せず往復もしない)。

指示: 「あなたはこのゴールの全体責任者。ゴールの方向・ヒアリングで表面化した既知・制約・今回確定すべきこと・未知マップ(既知の未知と無自覚の未知の探索方針)・承認基準・終了条件(残存未知の許容基準)を定義し、ループ強度(MVP | 高信頼)を理由付きで提案せよ。既定はMVP(品質最大化は目的ではない)。承認基準と終了条件は後でゲート判定の基準として使われる。検証可能な形で書け。」
出力を `goal-frame.md` に保存し、call-logに記録する。内容をユーザーに提示し、**ループ強度を確定**してもらい、方向のズレがないか確認する。A-1aで高信頼と答えた後にここでMVPへ確定が変わった場合は、A-1aの深掘りヒアリングを再開してからA-2へ進む。確定した強度を goal-frame.md の「人間の確定」欄と state.md に記録する。

**A-2〜A-4 ブレスト → Spec → Plan(driver + Superpowers)**
`$superpowers:brainstorming` を起動し、その標準フロー(spec作成 → writing-plans)に完全に従う。スキル内部の手順・ゲートには干渉しない。強度により質問・承認の相手を変える:
- **高信頼**: 従来通り人間が相手。
- **MVP(proxy代理ブレスト)**: 質問・設計承認の相手を人間ではなく **proxy**(`codex exec resume`)にする。proxyへの依頼文に必ず含める: 「あなたはユーザーの代理として回答する。根拠は goal-frame.md と hearing-log.md。**ユーザー固有の判断(好み・業務文脈・優先順位)が必要でヒアリング記録から導けない問い、否定リスト該当、エスカレーション発火条件該当の問いには、回答せず `ASK_HUMAN: <人間向けの質問文>` と返せ**。」 ASK_HUMANが返った質問のみ人間へ提示し、回答を hearing-log.md に追記して proxy へ共有する。proxyの主要決定(採用アプローチ・設計承認)は goal-plan.md の「主要設計判断(proxy代理回答による)」欄に記録する。往復ごとにcall-logへ記録(proxy)。

**未知の振り分け**: ヒアリング・ブレスト中に人間または proxy が「決めていない / わからない」と答えた問いは、その場で追及せず**仮説化して assumptions.md に記録し、続行する**。goal-frame.md の未知マップと突き合わせる。
完了後、spec/planへの相対リンクとマイルストーン一覧を `goal-plan.md` に集約し、**Checkpoint印を付ける**(policy.md「Checkpointとマイルストーン粒度」: Checkpoint = ユーザー価値をE2Eで評価できる点。最終マイルストーンは必ずCheckpoint)。「主要設計判断(proxy代理回答による)」欄もここに置く。
この工程の完了時に、proxy の一時ディレクトリを削除する。

**A-5 Approval Submission(driver)**
`templates/approval-submission.md` に従い、Goal Plan承認用の submission を作成する(対象: Goal Plan全体。**Checkpoint配置**・残存未知リスト・仮定台帳サマリを含める)。保存先: `goal-plan-submission.md`(goal直下)。

**A-6 Goal Gate(judge・新規セッション)**
前提確認: goal-frame.md と submission が存在すること。
共通契約に従い、一時ディレクトリに goal-frame.md 全文 + submission 全文 + assumptions.md の未検証仮定をコピーして judge を `--output-schema schemas/gate-verdict.json` 付きで起動する。判定観点(適合性・残存未知の許容性・仮定の事実扱い・否定リスト)に加えて「**Checkpoint配置が『人間の受け入れテスト1回でE2E価値を評価できる』単位か**」で「この計画で元の目的を達成できるか」を判定させる。品質の細部ではなくゴール整合性を中心に見る。
返ったJSONを `goal-gate-decision.md`(goal直下)へ整形保存し、call-logに記録する。

**A-7 差し戻し処理(driver)**
- REVISE → 指定された工程(ブレスト/spec/plan)へ戻り、修正後 A-5 から再提出
- REPLAN → A-4(計画)から作り直し
- BLOCKED → `blocking_questions` を人間へ提示し、state.md を「人間待ち」にして停止

**A-8 Human Goal Plan承認(human)**
judge PASS後、人間に提示して実装へ進む承認を得る。
- **MVP(WHATレベル)**: 提示は「ゴール解釈(goal-frameの方向)・要件・制約・マイルストーン一覧とCheckpoint配置・仮定台帳サマリ」に限定し、spec/planは参照リンクとして添付する(HOW詳細は承認対象にしない)。
- **高信頼**: 従来通り Goal Plan(と goal-frame)を提示する。
承認されたら state.md を milestone-implementation へ更新する(「次のCheckpoint」欄も記入)。

## ワークフローB: Milestone Implementation(マイルストーンごとに繰り返す)

**B-1 開始確認(judge・軽量)**
直近の retro.md 最大3件の要点を抜粋し、一時ディレクトリに goal-frame.md + 対象マイルストーン定義(goal-plan.mdの該当部分) + retro抜粋(あれば)をコピーして judge を **`--output-schema` なし**で起動し、「このマイルストーンが上位ゴールのどの成果を満たすか確認し、実装上の注意点があれば10行以内で示せ」と指示する。call-logに記録。

**B-2〜B-3 実装と自己検証(builder)**
強度により委譲単位を変える(policy.md工程表):
- **MVP**: **マイルストーン単位でまとめて**1〜数回の builder 呼び出しに委譲する。タスク細分化しない。
- **高信頼**: subagent-driven developmentと同じプロセス構造でタスク分解し、個別に委譲する。

```bash
codex exec -m gpt-5.6-luna -c model_reasoning_effort=max \
  -s workspace-write -c approval_policy=never \
  -o "<milestoneディレクトリ>/builder-report.md" -
```

- プロンプトの必須要素:
  1. 目的(このマイルストーン/タスクが満たす受け入れ条件)
  2. 対象ファイル・変更範囲
  3. 検証要求 — **MVP**: 受け入れ基準に直結する検証+未知低減に効く検証のみ / **高信頼**: テストファースト+単体・結合・lint・型検査
  4. 関連する未検証仮定(assumptions.mdから)。実装中に新たな仮定を置いた場合は報告させる
  5. 出力要求(変更ファイル一覧・検証結果・未解決事項・新規仮定をテキストで報告)
  6. 禁止事項: **gitコミット禁止**、要件の再定義禁止、否定リスト該当の自律判断禁止、`~/.codex/`・`.codex/`・`~/.claude/`・`.claude/` 配下への接触禁止
- 完了後の受け入れ — **MVP**: `builder-report.md` の自己検証報告を確認する(diff精読はしない)。**高信頼**: diffと検証結果を確認する。不合格なら具体的な指摘とともに再実行させる。報告された新規仮定は assumptions.md に追記する。call-logに記録(builder)。
- 実装・設計上の主要判断は随時 `milestones/<n>-<名前>/decisions.md`(`templates/decisions.md` の形式)に追記する(要件由来とAgent仮説を区別する)。

**B-4 エスカレーション(必要時のみ)**
policy.md の発火条件(否定リスト該当・ユーザー固有判断・Solution分岐・低確信を含む10件)を検出したら、`templates/escalation.md` の1〜6を整形し、一時ディレクトリに goal-frame.md + 1〜6 + 関連する未検証仮定(assumptions.mdの該当行、あれば) + hearing-log.md の関連部分(あれば)をコピーして judge を `--output-schema schemas/escalation-verdict.json` 付きで起動する。judgeは **DECIDE**(判断+根拠)または **ASK_HUMAN**(人間向け質問文)を返す。返った内容を7(判定)欄へ整形して記入する。ASK_HUMANの場合はdriverが人間へ提示し、回答を hearing-log.md に追記してから続行する。文書を milestone ディレクトリに `escalation-<連番>.md` として保存し、call-logに記録。

**B-5 レビューとSubmission作成(driver)**
- **MVP**: driverが**セルフチェック**(goal-frame承認基準との対応・残存未知の列挙・未検証仮定の確認)を行い、`decisions.md` の4区分(要件由来 / Agent仮説HOW / 低確信 / 発見された未知)を確定させ、`templates/approval-submission.md` に従い `milestones/<n>-<名前>/submission.md` を作成する(判断記録欄から decisions.md を参照)。
- **高信頼**: reviewer(`gpt-5.6-sol` / max、**実装に関与していない新規セッション**。PL-003)を起動し、goal-plan.md該当部・マイルストーン定義・diff・検証証拠を渡してレビューさせ、結果を反映してsubmissionを作成する。call-logに記録(reviewer)。
- どちらの場合も**残存未知リスト・仮定台帳サマリ・decisions.mdの確定**を必須とする(欠けたままB-6へ進まない)。

**B-6 Implementation Gate(judge・新規セッション)**
前提確認: submission.md が存在し、検証証拠と残存未知リストが含まれること。
共通契約に従い、一時ディレクトリに goal-frame.md + マイルストーン定義 + submission.md + assumptions.md の未検証仮定をコピーして judge を `--output-schema schemas/gate-verdict.json` 付きで起動し、判定観点で「このマイルストーンのゴールを満たし、残存未知が許容可能か」を判定させる。返ったJSONを `gate-decision.md` へ整形保存、call-logに記録。
- PASS + **MVPの非Checkpointマイルストーン** → **中間クローズ**: grareco-input.md作成(gate-decision.md / decisions.md の要点)+グラレコ生成(失敗は非ブロック)→ 中間コミット → state.md を次マイルストーンへ更新し、**人間承認なしで次のB-1へ**
- PASS + Checkpointマイルストーン(MVP)または高信頼 → state.md を human-acceptance に更新し、B-7へ
- REVISE / REPLAN → `return_to` と `target_unknowns` に従って差し戻す(人間へは出さない)
- BLOCKED → `blocking_questions` を人間へ提示して停止

**B-7 Human Review Report=評価パッケージ(driver)**
`templates/human-review-report.md` に従い `human-report.md` を作成する。
- **MVP**: 対象は**前回Checkpoint以降の全マイルストーン**。各マイルストーンの decisions.md を「3.5 判断の内訳」に集約する(Agent仮説HOW・低確信・実装対象外・新しく発見された未知を含む)。
- **高信頼**: 従来通り対象マイルストーン単体。
受け入れテスト手順は人間が1回のテストで確認できる具体性で書く。

**B-8 Human Acceptance(human)**
human-report.md を人間に提示し、受け入れテストを依頼する(MVPはCheckpoint単位)。結果を `acceptance.md` に記録する(ACCEPT / REJECT + コメント)。**フィードバックから新たに発見された未知・要望は assumptions.md に追記する**(次ループの入力)。ACCEPTの場合は state.md を finalization に更新する。

**B-9 REJECT処理(judge)**
REJECTの場合、一時ディレクトリに goal-frame.md + human-report.md + REJECT理由をコピーして judge を新規セッションで起動し、戻り先(タスク修正 / **Checkpoint配下の任意マイルストーン** / マイルストーン再計画 / ゴール再確認)を決定させる。REJECT理由から発見された未知は assumptions.md に追記する。決定に従い該当フェーズへ戻り、戻り先に応じて state.md を更新する。call-logに記録。

**B-10 確定処理(driver)**
acceptance.md に ACCEPT があることを確認してから、Checkpoint範囲(前回Checkpoint以降の中間コミットを含む)を確定として扱い、未コミット分を確定コミットする。state.md を learning へ更新する。

## Learning フェーズ

1. **Retrospective(driver)**: `templates/retrospective-note.md` に従い `retro.md` を作成する(**MVP: Checkpoint単位** — 対象は前回Checkpoint以降の全マイルストーン / **高信頼**: マイルストーン単位)。観測欄に、ループ回数(REVISE/REPLAN差し戻し数)・呼び出し数(call-log.mdから)・主要フェーズ所要時間(call-logの時刻から概算)・**発見された未知**を記載する(5:1目安はワークフローB以降、ハード制限ではない)。「再利用できる知見・テンプレート候補」に「なし」以外を書いた場合、**このプロジェクトの外でも効くもの**は orca-meta の MCP tool `record_lesson` で送る(軸は person / agent / method。orca-meta が導入されていない環境では省略してよい)。
2. **グラレコ(builder経由)**: human-report.md / gate-decision.md / retro.md の要点を `grareco-input.md` にまとめ、`templates/grareco-prompt.md` の指示文を埋めて builder 規定形(`gpt-5.6-luna` / max)に渡す(MVPの非Checkpoint分はB-6中間クローズで生成済みのため、ここではCheckpointマイルストーン分を生成する)。生成失敗時は grareco-input.md を残したまま先へ進む(ループ完了をブロックしない)。call-logに記録(builder)。
3. **次へ**: 未実装マイルストーンがあれば state.md を milestone-implementation に戻し(「次のCheckpoint」欄を更新)、B-1 から繰り返す。全マイルストーン完了なら state.md を done にし、ゴール全体の完了を人間に報告する。

## 例外・停止時の扱い

- どのフェーズでも、人間の入力が必要になったら state.md の「待ち」に内容を書いてから停止する。
- セッションが切れても、次回 `$r-super-loop-powers:r-super-loop-powers` 起動時に state.md から再開できる(NFR-04)。`proxy-session:` に session id が残っていれば `codex exec resume` で同じ proxy を継続する。resume が失敗した場合のみ、goal-seed / goal-frame / hearing-log を渡して新しい proxy を起動する(記録がある限り文脈は復元できる)。
- このスキルは Superpowers・gstack等の他スキルのファイルを読むことはあっても、**変更してはならない**(SK-001)。
````

- [ ] **Step 2: 旧役名・旧ツール名が残っていないことを確認する**

```bash
grep -n -E "Opusメイン|Fable|opus-sub|SendMessage|Agentツール|Globツール|/r-super-loop-powers\`" skills-codex/r-super-loop-powers/SKILL.md
```

Expected: 出力なし(終了コード1)

- [ ] **Step 3: 工程記号がすべて揃っていることを確認する**

```bash
python - <<'PY'
import io
t = io.open('skills-codex/r-super-loop-powers/SKILL.md', encoding='utf-8').read()
need = ['A-0','A-1a','A-1b','A-2〜A-4','A-5','A-6','A-7','A-8',
        'B-1','B-2〜B-3','B-4','B-5','B-6','B-7','B-8','B-9','B-10']
missing = [x for x in need if f'**{x} ' not in t]
print('MISSING:', missing if missing else 'none')
for k in ['gpt-5.6-sol','gpt-5.6-luna','ultra','proxy-session','gate-verdict.json','escalation-verdict.json','SK-010']:
    print(k, t.count(k))
PY
```

Expected: `MISSING: none`、各キーワードの出現回数が1以上

- [ ] **Step 4: frontmatter が有効であることを確認する**

```bash
head -4 skills-codex/r-super-loop-powers/SKILL.md
```

Expected: 1行目 `---`、2行目 `name: r-super-loop-powers`、3行目が `description:` で始まる、4行目 `---`

- [ ] **Step 5: コミット**

```bash
git add skills-codex/r-super-loop-powers/SKILL.md
git commit -m "feat: Codex版SKILL.md(codex execによる四役分担・resume往復・構造化判定)"
```

---

### Task 5: プラグイン骨格とインストール検証(S1)

**Files:**
- Create: `.codex-plugin/plugin.json`
- Create: `.agents/plugins/marketplace.json`

**Interfaces:**
- Consumes: Task 3/4 の `skills-codex/r-super-loop-powers/{SKILL.md,policy.md}`
- Produces: Codexから `codex plugin add r-super-loop-powers@r-super-loop-powers-marketplace` でインストールできるプラグイン。スキルは `r-super-loop-powers:r-super-loop-powers` として露出する

- [ ] **Step 1: プラグイン定義を作成する**

`.codex-plugin/plugin.json`:

```json
{
  "name": "r-super-loop-powers",
  "version": "0.1.0",
  "description": "Superpowersの上位に薄く重なるゴールループ・オーケストレーション層(Codex版)。フェーズ管理、承認ゲート、ヒューマン・イン・ザ・ループ配置、役割別モデル分担(sol進行/sol判定/sol代理/luna実装)を制御する。",
  "author": {
    "name": "rnakayama",
    "email": "rnakayama831@gmail.com"
  },
  "homepage": "https://github.com/makyua-san/r-super-loop-powers",
  "repository": "https://github.com/makyua-san/r-super-loop-powers",
  "license": "MIT",
  "keywords": [
    "goal-engineering",
    "orchestration",
    "superpowers-overlay",
    "human-in-the-loop",
    "model-routing"
  ],
  "skills": "./skills-codex/",
  "interface": {
    "displayName": "R Super Loop Powers",
    "shortDescription": "ゴールループ・オーケストレーション(要件適合性と未知低減)",
    "developerName": "rnakayama",
    "category": "Developer Tools",
    "capabilities": ["Interactive", "Read", "Write"]
  }
}
```

- [ ] **Step 2: マーケットプレイス定義を作成する**

`.agents/plugins/marketplace.json`:

```json
{
  "name": "r-super-loop-powers-marketplace",
  "interface": {
    "displayName": "R Super Loop Powers"
  },
  "plugins": [
    {
      "name": "r-super-loop-powers",
      "source": {
        "source": "local",
        "path": "./"
      },
      "category": "Developer Tools"
    }
  ]
}
```

- [ ] **Step 3: 両ファイルが妥当なJSONであることを確認する**

```bash
python -c "
import json
for p in ['.codex-plugin/plugin.json','.agents/plugins/marketplace.json']:
    d=json.load(open(p,encoding='utf-8')); print(p,'OK',d['name'])
"
```

Expected: 2行とも `OK` と名前が表示される

- [ ] **Step 4: S1 — ローカルパスでマーケットプレイスを登録する**

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
"$CODEX" plugin marketplace add "C:/Users/makyu/Desktop/project/r-super-loop-powers" --json 2>&1 | tail -20
"$CODEX" plugin list 2>&1 | grep -i "r-super-loop-powers"
```

Expected: マーケットプレイスが追加され、`plugin list` に `r-super-loop-powers` が現れる。

**エラーになった場合**: エラーメッセージが期待するスキーマ(`source` の形式・必須フィールド)に合わせて `.agents/plugins/marketplace.json` を修正し、`codex plugin marketplace remove` してから再実行する。修正内容は Task 6 のスモーク記録追記で残す。

- [ ] **Step 5: プラグインをインストールする**

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
"$CODEX" plugin add "r-super-loop-powers@r-super-loop-powers-marketplace" 2>&1 | tail -10
grep -A2 'plugins."r-super-loop-powers' "/c/Users/makyu/.codex/config.toml"
```

Expected: インストール成功。config.toml に `[plugins."r-super-loop-powers@r-super-loop-powers-marketplace"] enabled = true` が追加される

- [ ] **Step 6: スキルがCodexから見えることを確認する**

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
"$CODEX" exec -m gpt-5.4-mini -c model_reasoning_effort=low -s read-only --skip-git-repo-check \
  "Without running any commands: list the exact names of every skill available to you that starts with 'r-super'. If none, print NONE." 2>&1 | tail -6
```

Expected: `r-super-loop-powers:r-super-loop-powers` が表示される

**NONE の場合**: `.codex-plugin/plugin.json` の `skills` パスと `skills-codex/r-super-loop-powers/SKILL.md` の frontmatter を確認し、修正して Step 4 から再実行する。

- [ ] **Step 7: コミット**

```bash
git add .codex-plugin/plugin.json .agents/plugins/marketplace.json
git commit -m "feat: Codexプラグイン骨格(.codex-plugin + marketplace)とインストール検証"
```

---

### Task 6: README更新と最終整合検証

**Files:**
- Modify: `README.md`(末尾にCodex版セクションを追加。既存のClaude版記述は残す)
- Modify: `docs/superpowers/notes/2026-08-31-codex-smoke.md`(S1の結果を追記)

**Interfaces:**
- Consumes: Task 1〜5 のすべての成果物
- Produces: Codex版の導入手順とE2Eチェックリストを含む README。`git diff` による Claude版無変更の証明

- [ ] **Step 1: README にCodex版セクションを追記する**

`README.md` の末尾に次を追加する(外側は4バックティックのフェンス。内側の3バックティックのブロックも含めてすべてREADMEへ書く)。

````markdown
---

## Codex版(Codex CLI)

Claude Code 版と同じゴールループを Codex CLI 単体で回すための移植版です。工程(A-0〜A-8 / B-1〜B-10)・成果物契約・ゲート規律は Claude 版と同一で、モデル運用層だけが異なります。

設計仕様: `docs/superpowers/specs/2026-08-31-r-super-loop-powers-codex-port-design.md`

### 導入

```bash
codex plugin marketplace add makyua-san/r-super-loop-powers
codex plugin add r-super-loop-powers@r-super-loop-powers-marketplace
```

起動: Codex セッション内で `$r-super-loop-powers:r-super-loop-powers`

### 役とモデル

| 役 | モデル / effort | 担当 |
|---|---|---|
| driver | gpt-5.6-sol / medium | メインセッション。進行管理と成果物作成 |
| proxy | gpt-5.6-sol / max | ヒアリング駆動・Goal Frame・MVPの代理ブレスト回答 |
| judge | gpt-5.6-sol / ultra | 承認ゲート・エスカレーション判定・REJECT後の戻り先決定 |
| builder | gpt-5.6-luna / max | 実装と自己検証 |
| reviewer | gpt-5.6-sol / max | 高信頼強度の独立レビュー(B-5) |

サブ役はすべて `codex exec` サブプロセスとして起動され、proxy のみ `codex exec resume` で往復します。judge と proxy は必要文書だけをコピーした一時ディレクトリで起動し、対象プロジェクトの生コードを渡しません(PL-009)。

### Claude版との差分

- 役名: Opus / Fable / Codex → driver / judge / proxy / builder / reviewer
- ゲート判定は `schemas/gate-verdict.json` による構造化出力(PASS / REVISE / REPLAN / BLOCKED)
- 代理役の文脈は `state.md` の `proxy-session:` に記録され、**セッションを跨いで復元できる**(Claude版にはない)
- テンプレート9枚は Claude 版と同一。原本は `skills/r-super-loop-powers/templates/` で、`scripts/sync-templates.ps1` が `skills-codex/` 側へ複写する

### E2Eチェックリスト(Codex版)

新規の小規模プロジェクトで MVP 強度・中間マイルストーン1つ以上・Checkpoint1つ以上を完走して確認する。

- [ ] 1. `$r-super-loop-powers:r-super-loop-powers` で起動し、起動時チェック5項目が実行される
- [ ] 2. driver が `gpt-5.6-sol` / medium でない場合に `/model` 切替提案が出て、承諾か明示的続行までフェーズ作業が始まらない
- [ ] 3. `docs/r-super-loop-powers/<goal-slug>/` 一式が作成される(state.md / goal-seed.md / hearing-log.md / assumptions.md / call-log.md)
- [ ] 4. A-1a で proxy が起動し、session id が `state.md` の `proxy-session:` に記録される
- [ ] 5. A-1a の質問がそのまま人間へ提示され、回答が hearing-log.md に記録され、`codex exec resume` で往復する
- [ ] 6. proxy が HOW を質問せず、無自覚の既知(暗黙の前提・避けたい体験・優先順位)を掘る質問を返す
- [ ] 7. A-1b で goal-frame.md が生成され、人間がループ強度を確定する
- [ ] 8. A-2〜A-4 で `$superpowers:brainstorming` が起動し、質問の相手が proxy になる
- [ ] 9. proxy がユーザー固有判断の問いに `ASK_HUMAN:` を返し、それだけが人間へ提示される
- [ ] 10. goal-plan.md にマイルストーン一覧と Checkpoint 印、「主要設計判断(proxy代理回答による)」欄がある
- [ ] 11. A-6 で judge が一時ディレクトリで起動し、`gate-verdict.json` 準拠のJSONを返す
- [ ] 12. A-8 の承認提示が WHAT レベル(spec/plan は参照リンクのみ)である
- [ ] 13. B-2 で builder が `gpt-5.6-luna` / max で起動し、`builder-report.md` に自己検証報告を残す
- [ ] 14. builder が git コミットをしていない
- [ ] 15. decisions.md が4区分で作成される
- [ ] 16. B-6 の PASS 後、非Checkpointマイルストーンは人間承認なしで次のB-1へ進む
- [ ] 17. Checkpoint到達時のみ human-report.md が作られ、受け入れテストが依頼される
- [ ] 18. proxy の session id が judge に `resume` されていない(call-log.md と実行履歴で確認)
- [ ] 19. call-log.md が `judge|proxy|builder|reviewer` の4語のみで記録されている
- [ ] 20. Checkpoint の ACCEPT 後に確定コミットが行われ、retro.md が作成される
````

- [ ] **Step 2: S1 の結果をスモーク記録に追記する**

`docs/superpowers/notes/2026-08-31-codex-smoke.md` の「S1 について」節を、Task 5 で実際に起きたこと(marketplace.json のスキーマ修正の有無、`plugin list` と スキル可視化の結果)で置き換える。

- [ ] **Step 3: Claude版が無変更であることを確認する**

```bash
git diff --stat main -- skills/ .claude-plugin/
```

Expected: 出力なし(変更ファイル0件)

**出力があった場合**: 該当ファイルを `git checkout main -- <path>` で戻し、変更が Codex 版のみに閉じるよう修正する。

- [ ] **Step 4: templates の一致を再確認する**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync-templates.ps1 -Mode Verify; $LASTEXITCODE
```

Expected: `Verify OK (9 templates)` / 終了コード `0`

- [ ] **Step 5: 成果物一覧を確認する**

```bash
git diff --name-only main
```

Expected: 次のファイルのみが並ぶ(順不同)

```
.agents/plugins/marketplace.json
.codex-plugin/plugin.json
README.md
docs/superpowers/notes/2026-08-31-codex-smoke.md
docs/superpowers/plans/2026-08-31-r-super-loop-powers-codex-port.md
docs/superpowers/specs/2026-08-31-r-super-loop-powers-codex-port-design.md
scripts/sync-templates.ps1
skills-codex/r-super-loop-powers/SKILL.md
skills-codex/r-super-loop-powers/policy.md
skills-codex/r-super-loop-powers/schemas/escalation-verdict.json
skills-codex/r-super-loop-powers/schemas/gate-verdict.json
skills-codex/r-super-loop-powers/templates/approval-submission.md
skills-codex/r-super-loop-powers/templates/assumptions.md
skills-codex/r-super-loop-powers/templates/decisions.md
skills-codex/r-super-loop-powers/templates/escalation.md
skills-codex/r-super-loop-powers/templates/goal-frame.md
skills-codex/r-super-loop-powers/templates/grareco-prompt.md
skills-codex/r-super-loop-powers/templates/hearing-log.md
skills-codex/r-super-loop-powers/templates/human-review-report.md
skills-codex/r-super-loop-powers/templates/retrospective-note.md
```

- [ ] **Step 6: コミット**

```bash
git add README.md docs/superpowers/notes/2026-08-31-codex-smoke.md
git commit -m "docs: READMEにCodex版セクション(導入手順・役とモデル・E2E20項目)を追加"
```

---

## 完了後

E2Eテスト(README のCodex版チェックリスト20項目)は、新規の小規模プロジェクトで別途実施する。実施までは `codex-port` ブランチのまま置き、E2E完了後に `superpowers:finishing-a-development-branch` で main への統合を判断する。
