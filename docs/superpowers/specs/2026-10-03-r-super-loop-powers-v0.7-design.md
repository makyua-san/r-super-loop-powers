# r-super-loop-powers v0.7 設計仕様書 — 実装役のSonnet化とcodexの読み取り専用化(Claude版)

- 作成日: 2026-10-03
- 対象: Claude版 `skills/r-super-loop-powers/`・`.claude-plugin/`・README のClaude版節。Codex版 `skills-codex/` は**変更しない**
- 前提: v0.6.0(commit 28cecce)
- ユーザー決定(2026-10-03):
  1. 技術PM = codex `gpt-6.1-sol` / effort `max`
  2. 実装役 = Sonnet 6(Claude サブエージェント)。これにより codex は編集権限を必要としない
  3. 技術レビュー = `gpt-6.1-sol`、要件適合の確認 = Fable
  4. 技術レビューは**高信頼強度のみ**。MVPは従来どおり Opus のセルフチェック。要件適合の確認は B-6 の Fable ゲートが担う(Fable呼び出しは増やさない)
  5. グラレコは codex を read-only で動かし、生成画像を Opus が回収する

## 0. 目的

v0.6 では実装役が codex(`gpt-6-sol`)だったため、codex に書き込み権限が必要だった。その結果、Windows の `workspace-write` サンドボックス不具合への対処(書き込みプローブ・`writable_roots`・ユーザー承認つきのサンドボックス解除 `-AllowUnsandboxed`)と、未展開モデルの暫定フォールバックがスクリプトに積み上がっていた。

v0.7 では実装を Claude 側(Sonnet 6 サブエージェント)へ移し、**codex を助言・レビュー・画像生成だけの読み取り専用ロールにする**。これにより上記の書き込み系の仕組みをすべて削除する。ゴールループの工程(A-0〜A-8 / B-1〜B-10)・成果物契約・ゲート規律は変えない。

## 1. 事実確認(2026-10-03)

| # | 事実 | 根拠 | 設計への影響 |
|---|---|---|---|
| F1 | サブエージェント定義(`.claude/agents/*.md` / プラグインの `agents/`)の `model:` は、エイリアスに加えて**フルのモデルID**を受け付ける | code.claude.com/docs/en/sub-agents.md | `model: claude-sonnet-6` と明記できる |
| F2 | Agentツールの `model` パラメータで指定できるのはエイリアス(`sonnet` 等)。`sonnet` がどの版に解決されるかは文書化されていない | Agentツールのスキーマ / 同上 | 実装役はエイリアスではなく**プラグイン同梱のエージェント定義**で起動する |
| F3 | プラグインは `agents/` を同梱でき、`<plugin名>:<agent名>` として呼べる | code.claude.com/docs/en/plugins/create.md | `subagent_type: "r-super-loop-powers:builder"` |
| F4 | サブエージェント定義に reasoning effort の欄は無い(frontmatter は name / description / tools / disallowedTools / model / permissionMode / skills / maxTurns / hooks 等) | sub-agents.md | B-1 の effort 選択は意味を失う |
| F5 | ユーザーの `~/.codex/config.toml` のモデル表記は `gpt-6.1-sol` | 実ファイル | codex側のモデルIDは `gpt-6.1-sol` とする(ユーザー表記「gpt-6-sol-6.1」と同一のものと解釈) |
| F6 | codex の image_gen は画像を `~/.codex/generated_images/<thread_id>/ig_*.png` に保存する | 実ディレクトリ | read-only でも画像は生成でき、`THREAD_ID` から回収先が決まる(実装時スモークで確定) |

**未確定(実装計画の最初のスモークテストで確定する)**: (a) `claude-sonnet-6` というIDで実際にサブエージェントが起動するか (b) `gpt-6.1-sol` が `max` effort で疎通するか (c) read-only サンドボックスの codex が image_gen を使え、F6 の場所に画像が残るか。(a) が通らない場合はユーザーに正しいIDを確認する(黙ってエイリアスに落とさない)。

## 2. 設計決定(D34〜D45)

| ID | 決定 | 内容 |
|---|---|---|
| D34 | 役割の再配置 | 技術PM・技術レビュー・グラレコ = codex `gpt-6.1-sol`(read-only)。実装役 = Sonnet 6 サブエージェント。Fable・Opus の役割は不変 |
| D35 | 実装役はプラグイン同梱エージェント | `agents/builder.md` を新設(`model: claude-sonnet-6`)。B-2 は Agentツールで `subagent_type: "r-super-loop-powers:builder"` を指定して起動する |
| D36 | プロセス系スキルの遮断 | builder の `tools` から **Skill と Agent を外す**(許可: Read / Write / Edit / Glob / Grep / Bash / PowerShell)。v0.6 の `--disable plugins` の代わりに、superpowers 等のプロセス系スキルを起動する手段そのものを持たせない |
| D37 | 実行契約とロール指示の移設 | v0.6 で `codex-run.ps1` が builder に差し込んでいた実行契約(スコープ外禁止・コミット/push禁止・要件再定義禁止・否定リスト・`~/.claude/` 等への接触禁止)とロール指示(実行者であり設計しない・`TECHNICAL ASSESSMENT` に従う・安全>安定>速度・アセスが実コードと合わないときの扱い)を `agents/builder.md` の本文へ移す |
| D38 | 報告形式は据え置き | builder の最終メッセージは `schemas/impl-report.json` に従うJSON(コードフェンス1つで囲む)。スキーマ本体は変更しない |
| D39 | 成否判定スクリプト `bin/impl-check.ps1` | 入力: 報告ファイル・作業ディレクトリ・委譲前の HEAD。報告JSONと git の実際の状態を突き合わせ、`STATUS: OK / BLOCKED / INCOMPLETE / CONTRACT_VIOLATION / MALFORMED` を返す(§4)。**合格は `OK` のみ**(PL-011 を維持) |
| D40 | B-1 の effort 選択を廃止 | サブエージェントに effort を渡せないため(F4)。B-1 は「上位ゴールのどの成果を満たすか」と注意点(10行以内)のみ |
| D41 | 技術レビューを高信頼のB-5に置く | 高信頼の独立レビューア(PL-003)を Opus サブから codex `gpt-6.1-sol` / `max` / `-Role reviewer` に替える。観点は技術のみ(正しさ・アセスとの整合・リスク・検証の妥当性)。要件適合は見ない(B-6 の Fable の仕事)。MVP は変更なし(Opus セルフチェック) |
| D42 | codex は常に read-only | `codex-run.ps1` のロールは `techpm / reviewer / grareco` の3つ。全ロールで `-s read-only` を固定し、`-Sandbox` 引数・`builder` ロール・`writable_roots` 処理を削除する |
| D43 | preflight の簡素化 | 確認するのは codex 実体の解決・バージョン・認証・`gpt-6.1-sol` の疎通(read-only)のみ。書き込みプローブ・`-AllowUnsandboxed`・`-WritableRoot`・`-ProbeDir`・`-BuilderFallbackModel`・`-TechPmModel` を削除する。codex-env.json のモデルは `model` 1つ |
| D44 | グラレコの回収 | codex(`-Role grareco`、read-only)に画像を生成させ、Opus が `codex-status.ps1` の `THREAD_ID` から `~/.codex/generated_images/<thread_id>/` の最新 `ig_*.png` を `grareco.png` にコピーする。失敗しても非ブロック(従来どおり唯一の例外) |
| D45 | 旧 codex-env.json の扱い | `model` が `gpt-6.1-sol` でない、または `techpmModel` / `sandbox` 等の旧キーを持つ env を `codex-run.ps1` が検出したら `WARN:` を出し、再開時にプリフライトを再実行させる |

## 3. 実装役(Sonnet 6)の契約

### 3-1. `agents/builder.md`

frontmatter:

```yaml
name: builder
description: r-super-loop-powers の B-2 実装役。承認済みの技術アセスに従ってマイルストーンを実装し、impl-report.json 形式の自己検証報告を返す。ゴールループ外では使わない。
model: claude-sonnet-6
tools: Read, Write, Edit, Glob, Grep, Bash, PowerShell
```

本文: D37 の実行契約+ロール指示+出力契約(「最終メッセージは impl-report.json のスキーマに従うJSONを ```json フェンス1つで返す。それ以外の文を付けない」)。

### 3-2. B-2 の起動

1. 委譲前に `git rev-parse HEAD` を記録する(`codex-runs/` と並ぶ `impl-runs/<ラベル>.base.txt`)
2. プロンプトは v0.6 と同じ6見出し(`TECHNICAL ASSESSMENT` / `ACCEPTANCE CRITERIA` / `SCOPE` / `VERIFICATION` / `OPEN ASSUMPTIONS` / `OUTPUT`)で `impl-runs/<ラベル>.prompt.md` に保存し、その本文を Agentツールの prompt として渡す
3. Agentツール: `subagent_type: "r-super-loop-powers:builder"`、description に `B-2 <ラベル>`
4. 返ってきた最終メッセージを**そのまま** `impl-runs/<ラベル>.report.md` に保存する(Opus が整形・補完しない)

### 3-3. B-3 の受け入れ判定

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" `
  -ReportFile "<goal-dir>\impl-runs\<ラベル>.report.md" `
  -WorkDir "<対象プロジェクトのルート>" `
  -BaseRef (Get-Content "<goal-dir>\impl-runs\<ラベル>.base.txt")
```

STATUS の扱いは v0.6 の B-3 表を引き継ぐ(`OK` 以外は不合格、`CONTRACT_VIOLATION` は `git log` を見てから判断)。codex 固有の `FAILED / TIMEOUT / LOST / STALLED / SUSPECT` は実装役には現れなくなり、代わりに `MALFORMED`(報告がJSONとして読めない)が加わる。`MALFORMED` は1回だけ同じプロンプトで再委譲し、再度なら B-4。

## 4. `bin/impl-check.ps1` の判定規則

上から順に評価し、最初に当たったものを返す。

| 条件 | STATUS |
|---|---|
| 報告からJSONを取り出せない / 必須キー欠落 | `MALFORMED` |
| `committed: true`、または `git rev-parse HEAD` が `-BaseRef` と異なる | `CONTRACT_VIOLATION` |
| `blocked: true` | `BLOCKED` |
| `git status --porcelain` が空(実際の変更が0) | `INCOMPLETE`(報告上の changed_files があっても) |
| `verification` が空 / `FAIL` を含む | `INCOMPLETE` |
| `acceptance_criteria` に `NOT_MET` / `PARTIAL` を含む | `INCOMPLETE` |
| 上記いずれでもない | `OK` |

補助出力: `CHANGED_FILES_REPORTED` と `CHANGED_FILES_ACTUAL`(git 上の実際)を並べ、報告に無い変更があれば `WARN: unreported change: <path>` を出す(スコープ逸脱の兆候)。`NEW_ASSUMPTION:` / `UNRESOLVED:` 行は codex-status と同じ形式で出す。終了コードは `OK` のときだけ 0。JSONの解析は PowerShell の `ConvertFrom-Json` で行う(python3 を使わない)。

## 5. codex 実行系(read-only化)

- `codex-run.ps1`: `-Role techpm | reviewer | grareco`(既定なし・必須)。`-s read-only` 固定。effort は techpm / reviewer = `max`、grareco = `medium` を既定とする。`--disable plugins` は維持(技術PM・レビューアがプロセス系スキルを起動しないため)。実行契約から書き込み系の条項を「ファイルを作成・変更しない」に置き換える。`reviewer` のロール指示を新設する(技術観点のみ・要件適合は判定しない・指摘ごとに「重大度 / 根拠(該当箇所) / 推奨対処」・最後に `TECH_REVIEW: OK | CONCERNS` 行)
- `codex-status.ps1`: 変更なし(`-OutputSchema` を使うのは builder だけだったため、実装報告の検査分岐は使われなくなるが残してよい)。ただし `THREAD_ID:` を grareco 回収で使う
- `codex-preflight.ps1`: D43 のとおり。疎通プローブは read-only・`-c model_reasoning_effort=low` の1ターン

## 6. 文書の更新

| ファイル | 変更 |
|---|---|
| SKILL.md | description(モデル分担の表記)/ 起動時チェック6(sol 1本・サンドボックス関連の削除)/ ディレクトリ契約に `impl-runs/` / ゲート保護ルール 8(STATUS 判定を `codex-status` と `impl-check` の両方に)・10・11 / 技術PM共通契約(`gpt-6.1-sol`)/ B-1(effort 削除)/ B-2〜B-3(Sonnet 起動・impl-check)/ B-5 高信頼(codex reviewer)/ Learning 2(回収)/ 記録ルールの語彙 |
| policy.md | 工程表(B-2・B-3・B-5 行)/ 責任分担表(技術PM・実装役・Sonnet 行の統合・技術レビュー行)/ PL-001・PL-003・PL-007(語彙 `sonnet-builder` / `codex-review` を追加)・PL-011 |
| references/codex-invocation.md | 書き込み・サンドボックス・builder・フォールバック関連の節を削除し、read-only 3ロールの規約にする |
| README.md(Claude版の節のみ) | モデル表・E2Eチェックリスト(builder 起動・impl-check・技術レビュー・グラレコ回収の項目) |
| `.claude-plugin/plugin.json` | version 0.7.0、description のモデル分担表記 |
| templates/grareco-prompt.md | 保存先指示を「生成するだけでよい(保存はオーケストレータが行う)」に変更 |

`call-log.md` の語彙: `fable | opus-sub | codex-techpm | codex-review | codex-grareco | sonnet-builder`。

## 7. 受け入れ基準(この改訂の完了条件)

1. スモークで (a)(b)(c)(§1 未確定)が確認され、結果が `docs/superpowers/notes/` に記録されている
2. `impl-check.ps1` が §4 の各 STATUS を、用意した報告ファイル+一時 git リポジトリで正しく返す(各分岐1ケース以上)
3. `codex-run.ps1` がどのロールでも `read-only` 以外で起動しない。`-Role builder` を拒否する
4. `codex-preflight.ps1` が書き込みプローブ無しで `PREFLIGHT: OK` を返し、codex-env.json に `model: gpt-6.1-sol` だけが入る
5. SKILL.md / policy.md / codex-invocation.md / README から `gpt-6-astra`・`gpt-6-sol`(`gpt-6.1-sol` 以外)・`-AllowUnsandboxed`・`writable_roots`・B-1 の effort 選択への参照が消えている(grep で確認)
6. `skills-codex/` に差分が無い

## 8. 範囲外

- Codex版(`skills-codex/`)の追従
- B-1 での実装役モデルの選択(Sonnet 固定)
- E2E の本番実施(v0.3 から持ち越しのまま。本改訂後のE2Eで併せて確認する)
