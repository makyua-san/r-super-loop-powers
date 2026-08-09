# r-super-loop-powers プラグイン実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Superpowersの上位に薄く重なるゴールループ・オーケストレーション層(プラグイン)を作り、フェーズ管理・Fable承認ゲート・ヒューマンインザループ配置・モデル責任分担を制御可能にする。

**Architecture:** 純Markdown契約のオーバーレイスキル(スクリプト・hooksなし)。プラグインは `.claude-plugin/`(マニフェスト) + `skills/r-super-loop-powers/`(SKILL.md + policy.md + templates/) + README で構成。実行時はOpus主駆動セッションがSKILL.mdの手順に従い、Fableを`Agent(model: fable)`サブエージェントで、Codexを`codex exec`で呼び出す。

**Tech Stack:** Claude Codeプラグイン形式(plugin.json / marketplace.json)、Markdown、Superpowers v6.2.0(呼び出しのみ・非改造)、Codex CLI(gpt-5.6-sol設定はユーザーのconfig.tomlに従う)。

**Spec:** `docs/superpowers/specs/2026-08-09-r-super-loop-powers-design.md`(以下「spec」)

## Global Constraints

- 名称はすべて `r-super-loop-powers` で統一(プラグイン名・スキルディレクトリ名・frontmatter name・成果物ディレクトリ名)。`goal-loop` という名称を新規ファイルに書かない(spec D9)。
- Superpowers本体のファイルには一切触れない。呼び出しはスキル名のみ、成果物は標準形式をそのまま消費(spec SK-001, §1.1)。
- スクリプト・hooksを追加しない。ゲート・状態管理は純Markdown契約(spec D6)。
- ユーザー向け文書・テンプレートは日本語。SKILL.mdのfrontmatter descriptionにはトリガー用に英語キーワードも含める。
- ゲート4値は `PASS / REVISE / REPLAN / BLOCKED` 固定(spec SK-005)。
- Fableサブエージェントへの初回入力は goal-frame + 対象文書のみ(spec §9)。
- `codex exec` にはコミットさせない(spec D8)。
- 各タスク完了時にコミットする。コミットメッセージ末尾: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- 作業ディレクトリ: `C:\Users\makyu\Desktop\project\r-super-loop-powers`(git初期化済み、mainブランチ)。

## ファイル構成(このプランで作るもの)

| ファイル | 責務 |
|---|---|
| `.claude-plugin/plugin.json` | プラグインマニフェスト |
| `.claude-plugin/marketplace.json` | ローカルマーケットプレイス定義 |
| `skills/r-super-loop-powers/SKILL.md` | オーケストレーター本体(フェーズ・ゲート・手順) |
| `skills/r-super-loop-powers/policy.md` | モデル運用ポリシー(PL-001〜010、エスカレーション条件) |
| `skills/r-super-loop-powers/templates/goal-frame.md` | A-1 Fable入口出力の型 |
| `skills/r-super-loop-powers/templates/approval-submission.md` | A5 承認提出パッケージの型 |
| `skills/r-super-loop-powers/templates/escalation.md` | 6点エスカレーションの型 |
| `skills/r-super-loop-powers/templates/human-review-report.md` | A7 人間向けレポートの型 |
| `skills/r-super-loop-powers/templates/retrospective-note.md` | A9 振り返りの型 |
| `skills/r-super-loop-powers/templates/grareco-prompt.md` | A10 グラレコ生成指示の型 |
| `README.md` | インストール・運用・E2Eテスト手順 |

---

### Task 1: プラグインマニフェストとマーケットプレイス定義

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`

**Interfaces:**
- Produces: プラグイン名 `r-super-loop-powers`(全タスクがこの名称を参照)。スキルは `skills/` 配下から自動検出される。

- [ ] **Step 1: plugin.json を作成**

`.claude-plugin/plugin.json`:

```json
{
  "name": "r-super-loop-powers",
  "description": "Superpowersの上位に薄く重なるゴールループ・オーケストレーション層。フェーズ管理、Fable承認ゲート、ヒューマン・イン・ザ・ループ配置、モデル責任分担(Opus実行/Fable判定/Codex実装)を制御する。",
  "version": "0.1.0",
  "author": {
    "name": "rnakayama",
    "email": "rnakayama831@gmail.com"
  },
  "keywords": [
    "goal-engineering",
    "orchestration",
    "superpowers-overlay",
    "human-in-the-loop",
    "model-routing"
  ]
}
```

- [ ] **Step 2: marketplace.json を作成**

`.claude-plugin/marketplace.json`:

```json
{
  "name": "r-super-loop-powers-marketplace",
  "owner": {
    "name": "rnakayama",
    "email": "rnakayama831@gmail.com"
  },
  "plugins": [
    {
      "name": "r-super-loop-powers",
      "source": "./",
      "description": "Superpowersの上位に薄く重なるゴールループ・オーケストレーション層(オーバーレイスキル + モデル運用ポリシー + テンプレート)"
    }
  ]
}
```

- [ ] **Step 3: JSON構造を検証**

Run: `python -m json.tool .claude-plugin/plugin.json && python -m json.tool .claude-plugin/marketplace.json`
Expected: 両ファイルが整形出力される(パースエラーなし)

- [ ] **Step 4: コミット**

```bash
git add .claude-plugin/
git commit -m "feat: プラグインマニフェストとローカルマーケットプレイス定義を追加

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: モデル運用ポリシー policy.md

**Files:**
- Create: `skills/r-super-loop-powers/policy.md`

**Interfaces:**
- Consumes: なし
- Produces: `policy.md`(SKILL.mdが起動時に参照する。見出し「責任分担」「Fableを呼ぶ場面」「Fableを原則呼ばない場面」「運用ポリシー」「エスカレーション発火条件」「マイルストーン粒度」「観測」を後続タスクが参照)

- [ ] **Step 1: policy.md を作成**

`skills/r-super-loop-powers/policy.md`:

````markdown
# r-super-loop-powers モデル運用ポリシー

上位要件: `goal_engineering_ai_skill_policy_requirements.docx` 5章・11章・12章・14章。
本ポリシーは SKILL.md(オーケストレーター)から参照される。数値・比率は観測指標であり、品質や安全に必要な判断を妨げない。

## 責任分担

| 担当 | 主責務 | 通常実行 | 禁止・抑制 |
|---|---|---|---|
| 人間 | 意図の提示、最終受け入れ、優先順位判断 | Goal Seed入力、受け入れテスト | 生diffの最初からの精読を前提にしない |
| Fable | 全体責任者。入口の基準設定(Goal Frame)、承認ゲート、エスカレーション判断、Human REJECT後の戻り先決定 | サブエージェントとしてのみ起動 | ブレスト・仕様・実装・レポートの本文作成 |
| Opus | メインセッション。整理・仕様化・計画・独立レビュー・承認資料・人間向けレポート・振り返り・確定処理 | 常駐 | ゴール変更の独断確定 |
| Codex | 実装担当(`codex exec`)。コード変更、テスト、自己検証 | タスク単位で呼び出し | コミット、要件の再定義 |
| 画像生成(Codex経由 gpt-image-1) | グラフィックレコード | Learning フェーズで呼び出し | 未承認状態を確定として描かない |
| Sonnet | 将来枠(MVPでは未使用)。軽量探索・補助実装の候補 | — | 必須モデルとして固定しない |

## Fableを呼ぶ場面(これ以外では呼ばない)

1. ループ開始時: Goal Seedから Goal Frame(方向・制約・承認基準)を定義するとき
2. 承認ゲート: Approval Submission が揃い、PASS/REVISE/REPLAN/BLOCKED を判定するとき
3. エスカレーション: 実行担当が「エスカレーション発火条件」を検出したとき
4. Human REJECT後: 戻り先(修正 / 再計画 / ゴール修正)を決定するとき

## Fableを原則呼ばない場面

- Brainstorming / Spec / Plan の本文作成
- コード実装、単体テスト、軽微な修正
- 承認に必要な情報の整理・要約(Opusの仕事)
- 人間向けレポート、振り返りメモの作成
- フォーマット変換や定型ドキュメント生成

## 運用ポリシー

| ID | ポリシー | 要件 |
|---|---|---|
| PL-001 | Default roles | Fable=責任/判定、Opus=整理/仕様/レビュー/報告、Codex=実装をデフォルトとする |
| PL-002 | No Fable by default | 「高性能だから」という理由だけでFableへ上げない。メインセッションはOpusで運用する |
| PL-003 | Independent review | Fable提出前に、実装非関与のOpusサブエージェントが独立レビューする |
| PL-004 | Evidence first | 承認要求には検証証拠と未解決事項を必ず含める。推測だけでPASSを求めない |
| PL-005 | Human after AI gate | 人間受け入れはFable PASS後に行う |
| PL-006 | Human rejection routing | Human REJECTはFableへ戻し、戻り工程をFableが決める |
| PL-007 | Budget observability | fable / opus-sub / codex の呼び出しを call-log.md に記録し、Opus:Fable ≈ 5:1 を目安に振り返る |
| PL-008 | No forced ratio | 比率は目標であり、品質や安全に必要なFable呼び出しを禁止しない |
| PL-009 | Context minimization | Fableへは goal-frame + 対象文書のみを渡す。全コード・全会話を常時ロードしない |
| PL-010 | Human cognitive load | 人間向け成果物は、ゴール → 結果 → 証拠 → リスク → 確認手順の順で構造化する |

## エスカレーション発火条件(いずれかを検出したらFableへ)

1. 仕様 / Goal Plan 内に矛盾または複数解釈があり、実装選択でユーザー価値が変わる
2. 承認済み設計を変更しないと実装できない
3. 複数マイルストーンや広い影響範囲をまたぐ設計変更が必要
4. テストを繰り返しても原因が特定できず、計画自体の見直しが必要
5. 安全性・データ破壊・互換性など重大リスクを検出
6. 人間が示した Goal Seed と現在の作業がズレている疑いがある

形式は `templates/escalation.md` の6点フォーマットを用いる。

## マイルストーン粒度ガイドライン

- 1マイルストーン = 人間が **5〜15分の受け入れテスト1回** で確認できる振る舞い変化
- 実装タスク2〜8個が目安。超える場合は分割、下回る場合は隣接マイルストーンと統合を検討

## 観測

- call-log.md 形式: `YYYY-MM-DD HH:MM | fable|opus-sub|codex | フェーズ | 目的`(1呼び出し1行)
- Opusメインセッション自身の消費は記録対象外(常駐のため)
- Retrospective 作成時に比率を概算し、5:1目安から大きく外れた場合は retro.md に記載する。ハード制限にしない(PL-008)
````

- [ ] **Step 2: 構造を検証**

Run: `grep -c "^## " skills/r-super-loop-powers/policy.md`
Expected: `7`(責任分担 / Fableを呼ぶ場面 / 原則呼ばない場面 / 運用ポリシー / エスカレーション発火条件 / マイルストーン粒度 / 観測)

- [ ] **Step 3: コミット**

```bash
git add skills/r-super-loop-powers/policy.md
git commit -m "feat: モデル運用ポリシー(PL-001〜010、エスカレーション条件)を追加

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: ゲート系テンプレート(goal-frame / approval-submission / escalation)

**Files:**
- Create: `skills/r-super-loop-powers/templates/goal-frame.md`
- Create: `skills/r-super-loop-powers/templates/approval-submission.md`
- Create: `skills/r-super-loop-powers/templates/escalation.md`

**Interfaces:**
- Consumes: policy.md のゲート4値・エスカレーション6点定義
- Produces: 3テンプレート(SKILL.mdのA-1・A-5/B-5・B-4手順がファイル名で参照する。見出し構造は変更しないこと)

- [ ] **Step 1: goal-frame.md を作成**

`skills/r-super-loop-powers/templates/goal-frame.md`:

````markdown
# Goal Frame — <goal-slug>

<!-- 作成者: Fable(入口の責任設定)。このフレームは後でFable自身がゲート判定の基準として使う。 -->

## ゴールの方向
<Goal Seedから読み取った、このゴールが達成すべき本質的な価値。1〜3行>

## 制約
<技術・時間・互換性・スコープ上の制約。箇条書き>

## 今回のループで確定すべきこと
<Goal Plan承認までに決まっていなければならない事項。箇条書き>

## 承認基準
<!-- ゲート判定はこの基準に対して行われる。検証可能な形で書く -->
1. <基準1>
2. <基準2>
3. <基準3>

## 参照した学習メモ
<直近のRetrospective Noteから反映した点。なければ「なし」>
````

- [ ] **Step 2: approval-submission.md を作成**

`skills/r-super-loop-powers/templates/approval-submission.md`:

````markdown
# Approval Submission — <goal-slug> / <対象: Goal Plan | Milestone n>

<!-- 作成者: Opus。Fableゲートへの提出物。生コード・全会話は含めない(PL-009)。 -->

## 元ゴールと対象
- Goal Frame: <goal-frame.mdの「ゴールの方向」を1行で再掲>
- 対象: <Goal Plan全体 | Milestone n: 名前>

## 変更の要約(最大5項目)
1. <要約1>

## 承認基準との対応表

| Goal Frameの承認基準 | 対応する成果・証拠 | 状態 |
|---|---|---|
| <基準1> | <spec/plan/diff/テスト名> | 満たす / 一部 / 未 |

## テスト・検証証拠の要約
<実行したテスト・lint・型検査と結果。コマンドと結果の要点のみ>

## 既知リスク・未解決事項・意図的対象外
- <なければ「なし」と明記>

## Opusの推奨判定
- 推奨: PASS | REVISE | REPLAN | BLOCKED
- 根拠: <3行以内>
````

- [ ] **Step 3: escalation.md を作成**

`skills/r-super-loop-powers/templates/escalation.md`:

````markdown
# Escalation — <goal-slug> / <フェーズ>

<!-- 作成者: Opus(検出者がCodexの場合もOpusが整形)。Fableへ goal-frame.md と本文書のみを渡す。 -->

1. **何をしようとしたか**: <1〜2行>
2. **何が判断不能か**: <1〜2行>
3. **選択肢**: <A / B (/ C) を1行ずつ>
4. **影響**: <各選択肢がゴール・スケジュール・品質に与える影響>
5. **推奨案**: <どれを推すか + 1行の理由>
6. **いま必要な判断**: <Fableに求める決定を疑問文で1行>
````

- [ ] **Step 4: 3ファイルの存在と見出しを検証**

Run: `ls skills/r-super-loop-powers/templates/ && grep -l "承認基準" skills/r-super-loop-powers/templates/*.md`
Expected: 3ファイルが列挙され、goal-frame.md と approval-submission.md が「承認基準」を含む

- [ ] **Step 5: コミット**

```bash
git add skills/r-super-loop-powers/templates/
git commit -m "feat: ゲート系テンプレート(goal-frame / approval-submission / escalation)を追加

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: 人間向け・学習系テンプレート(human-review-report / retrospective-note / grareco-prompt)

**Files:**
- Create: `skills/r-super-loop-powers/templates/human-review-report.md`
- Create: `skills/r-super-loop-powers/templates/retrospective-note.md`
- Create: `skills/r-super-loop-powers/templates/grareco-prompt.md`

**Interfaces:**
- Consumes: policy.md PL-010(構造順: ゴール→結果→証拠→リスク→確認手順)
- Produces: 3テンプレート(SKILL.mdのB-7・Learning手順がファイル名で参照する)

- [ ] **Step 1: human-review-report.md を作成**

`skills/r-super-loop-powers/templates/human-review-report.md`:

````markdown
# Human Review Report — <goal-slug> / Milestone <n>: <名前>

<!-- 作成者: Opus(Fable PASS後)。1〜2画面で読み切れる長さにする(NFR-02)。 -->

## 1. 何を達成したか
<1〜3行でMilestoneの成果>

## 2. 何が変わったか
<ユーザー視点の挙動変更を優先。内部実装は必要な範囲のみ>

## 3. なぜ正しいと言えるか

| 受け入れ基準 | 証拠(テスト・実行結果) |
|---|---|
| <基準> | <テスト名と結果> |

## 4. 確認してほしいこと(受け入れテスト手順)
1. <手順1: コマンドや操作> → 期待結果: <...>
2. <手順2> → 期待結果: <...>

## 5. リスク・制約
<既知の問題、残課題、影響範囲。なければ「なし」>

## 6. 詳細への導線
- 関連ファイル: <パス>
- コミット候補: <ブランチ/未コミットの旨>
- 詳細diff: <参照方法>
````

- [ ] **Step 2: retrospective-note.md を作成**

`skills/r-super-loop-powers/templates/retrospective-note.md`:

````markdown
# Retrospective — <goal-slug> / Milestone <n>

<!-- 作成者: Opus(Human ACCEPT + 確定コミット後)。次回のGoal Frame作成時に自動参照される。短く保つ。 -->

## うまく機能したこと(最大3点)
- <...>

## 無駄だった呼び出し・手戻り(最大3点)
- <...>

## 次回変えること(最大3点)
- <...>

## 再利用できる知見・テンプレート候補
- <なければ「なし」>

## 観測
- 呼び出し概算: opus-sub <n>回 / codex <n>回 / fable <n>回(目安 Opus:Fable ≈ 5:1)
- 特記: <比率が大きく外れた場合の理由。なければ「なし」>
````

- [ ] **Step 3: grareco-prompt.md を作成**

`skills/r-super-loop-powers/templates/grareco-prompt.md`:

````markdown
# グラフィックレコード生成指示テンプレート

<!-- 使い方: Opusが <対象ディレクトリ> と <入力ファイル> を埋めて codex exec に渡す。 -->
<!-- 前提: grareco-input.md(human-report / gate-decision / retro の要約)が同ディレクトリに存在すること。 -->

以下を `codex exec` のプロンプトとして使う:

---

あなたはグラフィックレコーダーです。`<対象ディレクトリ>/grareco-input.md` を読み、
その内容を1枚のグラフィックレコード画像にまとめ、gpt-image-1で生成して
`<対象ディレクトリ>/grareco.png` として保存してください。

要件:
- 「目的 → 実装 → 検証 → 判断 → 結果」の流れが左上から右下へ一目で追える構成
- 後から見返して30秒〜1分で作業内容を思い出せることを最優先
- コードの詳細図解より、意思決定・変更点・結果の関係を視覚化する
- 日本語ラベル、手描き風グラレコスタイル、A4横相当
- 未承認・未確定の事項を確定済みとして描かない

禁止事項:
- `grareco-input.md` と `grareco.png` 以外のファイルを読み書きしない
- git操作をしない
````

- [ ] **Step 4: テンプレート6種が揃ったことを検証**

Run: `ls skills/r-super-loop-powers/templates/ | sort`
Expected: `approval-submission.md` `escalation.md` `goal-frame.md` `grareco-prompt.md` `human-review-report.md` `retrospective-note.md` の6ファイル

- [ ] **Step 5: コミット**

```bash
git add skills/r-super-loop-powers/templates/
git commit -m "feat: 人間向け・学習系テンプレート(human-review-report / retrospective-note / grareco-prompt)を追加

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: オーケストレーター本体 SKILL.md

**Files:**
- Create: `skills/r-super-loop-powers/SKILL.md`

**Interfaces:**
- Consumes: `policy.md`(起動時参照)、`templates/*.md` 6種(各手順が参照)。ファイル名は Task 2〜4 で確定したものを使う。
- Produces: スキル `/r-super-loop-powers`。対象プロジェクトに `docs/r-super-loop-powers/<goal-slug>/` レイアウト(spec §5)を生成する。

- [ ] **Step 1: SKILL.md を作成**

`skills/r-super-loop-powers/SKILL.md`:

`````markdown
---
name: r-super-loop-powers
description: Use when starting or resuming a goal-engineering loop (ゴールループ / goal loop / ゴールエンジニアリング開発). Superpowersの上位で、フェーズ管理・成果物契約・Fable承認ゲート・ヒューマン・イン・ザ・ループ配置・モデル責任分担(Opus実行 / Fable判定 / Codex実装)をオーケストレーションする。
---

# r-super-loop-powers — ゴールループ・オーケストレーター

あなた(このスキルを実行するモデル)は **Opusメインセッション** として、ゴールループの進行管理と成果物作成を担当する。
このスキルは **責任・ゲート層** である: いまどのフェーズか、次に必要な成果物は何か、誰が実行し誰が判定するか、人間へ返すタイミングだけを制御する。
作業の進め方(HOW)はSuperpowersのスキルに完全に委ね、その内部手順には一切干渉しない。

## 起動時チェック(毎回必ず実行)

1. **ポリシー読込**: このスキルと同じディレクトリの `policy.md` を読む。以後の全判断はこのポリシーに従う。
2. **モデル確認**: 自分がOpusで動いていない場合(特にFableの場合)、ユーザーに `/model opus` への切替を提案し、切替またはユーザーの明示的な続行指示があるまでフェーズ作業を開始しない(PL-002)。
3. **状態復元**: 対象プロジェクトで `docs/r-super-loop-powers/*/state.md` を探す(Globツール)。
   - 見つかった場合: 最新の state.md を読み、「現在フェーズ / 対象マイルストーン / 次のゲート」を1〜3行でユーザーに報告し、そのフェーズの手順から再開する。
   - 見つからない場合: ワークフローA(新規ゴール)を開始する。

## ディレクトリ契約

対象プロジェクト内に次を作成・維持する:

```
docs/r-super-loop-powers/<goal-slug>/
├── state.md             # 現在地(下記フォーマット)
├── goal-seed.md         # 人間の意図(原文のまま)
├── goal-frame.md        # Fable入口出力 = 承認基準の原本
├── goal-plan.md         # Superpowers spec/planへのリンク + マイルストーン一覧
├── call-log.md          # 呼び出し記録(PL-007)
└── milestones/<n>-<名前>/
    ├── submission.md / gate-decision.md / human-report.md
    ├── acceptance.md / retro.md / grareco-input.md / grareco.png
```

`<goal-slug>` はGoal Seedの内容から短いkebab-caseで命名する。

### state.md フォーマット

```markdown
# state — <goal-slug>
- phase: goal-definition | milestone-implementation | human-acceptance | finalization | learning | done
- milestone: <n>-<名前> または -
- 担当: opus-main | fable | codex | human
- 次のゲート: goal-gate | impl-gate | human-acceptance | none
- 待ち: <人間待ちの場合はその内容。なければ ->
- updated: YYYY-MM-DD HH:MM
```

**全フェーズで「state.md更新 → 作業」の順**を守る。フェーズ遷移の前に、下表の必須成果物が揃っているかを必ず確認し、欠落があれば次へ進まない。

## フェーズと成果物契約

| フェーズ | 入口条件 | このフェーズで必須の成果物 | 出口のゲート |
|---|---|---|---|
| goal-definition | goal-seed.md | goal-frame.md → spec/plan → goal-plan.md → submission.md | Goal Gate(Fable)→ Human承認 |
| milestone-implementation | Goal Plan承認済み | 実装diff + テスト証拠 → 独立レビュー → submission.md | Implementation Gate(Fable) |
| human-acceptance | Fable PASS | human-report.md | 人間のACCEPT/REJECT |
| finalization | acceptance.md に ACCEPT | 確定コミット | なし |
| learning | 確定コミット済み | retro.md + grareco-input.md(+ grareco.png) | なし |

## 記録ルール(PL-007)

fable / opus-sub(Opusサブエージェント) / codex を呼ぶたびに、直後に `call-log.md` へ1行追記する:
`YYYY-MM-DD HH:MM | fable|opus-sub|codex | フェーズ | 目的`

## ゲート保護ルール(絶対)

1. Fable PASS 前に人間へ受け入れを求めない(SK-007)
2. human-report.md なしで Human Acceptance に進まない(SK-008)
3. acceptance.md の ACCEPT なしで確定コミットしない(SK-009)
4. 必須成果物が欠けた状態でFableゲートを呼ばない — 欠落は自分で差し戻して埋める(NFR-05)
5. `codex exec` にコミットさせない

## Fableサブエージェント共通契約

- Agentツールで `model: "fable"` を指定して起動する。
- **初回入力は goal-frame.md 全文 + 対象文書(submission / escalation / milestone定義)のみ**。対象プロジェクトの生コード・全会話履歴を渡さない(PL-009)。
- Fableが追加資料を要求した場合のみ、SendMessageで1往復の追加提供を行う。
- ゲート判定の出力契約: `PASS | REVISE | REPLAN | BLOCKED` のいずれか1つ + 根拠(5行以内) + REVISE/REPLANの場合は戻り先工程。
- 判定は「動くか」ではなく「goal-frame.md の承認基準を満たすか」で行うことをプロンプトに明記する。

## ワークフローA: Goal Definition

**A-0 Goal Seed保存(Opus)**
ユーザーの「やりたいこと」を原文のまま `goal-seed.md` に保存する。要約・整形しない。`<goal-slug>` を決め、ディレクトリと state.md(phase: goal-definition)、空の call-log.md を作成する。

**A-1 Goal Frame(Fable)**
直近の `docs/r-super-loop-powers/*/milestones/*/retro.md` を新しい順に最大3件読み、要点を抜粋する。
Agentツール(model: fable)に次を渡す:
- `templates/goal-frame.md` の構造
- goal-seed.md 全文
- retro抜粋(あれば)
- 指示: 「あなたはこのゴールの全体責任者。ゴールの方向・制約・今回確定すべきこと・承認基準を定義せよ。承認基準は後であなた自身がゲート判定の基準として使う。検証可能な形で書け。」

出力を `goal-frame.md` に保存し、call-logに記録する。内容をユーザーに提示し、人間の意図とズレていないか確認してもらう。

**A-2〜A-4 ブレスト → Spec → Plan(Opus + Superpowers)**
`superpowers:brainstorming` を起動し、その標準フロー(spec作成 → writing-plans)に完全に従う。スキル内部の手順・ゲートには干渉しない。
完了後、spec/planへの相対リンクとマイルストーン一覧(粒度は policy.md のガイドライン: 受け入れテスト5〜15分 / 実装タスク2〜8個)を `goal-plan.md` に集約する。

**A-5 Approval Submission(Opus)**
`templates/approval-submission.md` に従い、Goal Plan承認用の submission を作成する(対象: Goal Plan全体)。保存先: `goal-plan-submission.md`(goal直下)。

**A-6 Goal Gate(Fable)**
前提確認: goal-frame.md と submission が存在すること。
Agentツール(model: fable)に goal-frame.md 全文 + submission 全文を渡し、指示する:
「あなたはこのゴールの全体責任者として入口でGoal Frameを定義した。いまOpusからGoal Planの承認提出があった。goal-frame.md の承認基準に対してこの計画で元の目的を達成できるかを判定せよ。品質の細部ではなくゴール整合性を中心に見よ。出力: PASS/REVISE/REPLAN/BLOCKED のいずれか + 根拠5行以内 + (REVISE/REPLANなら)戻り先工程。」
結果を `goal-gate-decision.md`(goal直下)に保存し、call-logに記録する。

**A-7 差し戻し処理(Opus)**
- REVISE → 指定された工程(ブレスト/spec/plan)へ戻り、修正後 A-5 から再提出
- REPLAN → A-4(計画)から作り直し
- BLOCKED → 根拠に含まれる質問を人間へ提示し、state.md を「人間待ち」にして停止

**A-8 Human Goal Acceptance(人間)**
Fable PASS後、Goal Plan(と goal-frame)を人間に提示し、実装へ進む承認を得る。承認されたら state.md を milestone-implementation へ更新する。

## ワークフローB: Milestone Implementation(マイルストーンごとに繰り返す)

**B-1 開始確認(Fable・軽量)**
Agentツール(model: fable)に goal-frame.md + 対象マイルストーン定義(goal-plan.mdの該当部分)を渡し、「このマイルストーンが上位ゴールのどの成果を満たすか確認し、実装上の注意点があれば10行以内で示せ」と指示する。call-logに記録。

**B-2〜B-3 タスク実装と自己検証(Codex)**
Superpowersのsubagent-driven-developmentと同じプロセス構造(タスク分解 → 実装 → レビューのループ)を自分(Opus)が駆動し、**各タスクの実装は `codex exec` に委譲する**:

```bash
codex exec "<タスクプロンプト>"
```

- モデル・reasoning effort・sandboxはユーザーの `~/.codex/config.toml` に従う(上書きしない)
- Bashのtimeoutは最長(600000ms)を指定し、長そうなタスクは run_in_background で実行する
- タスクプロンプトの必須要素:
  1. 目的(このタスクが満たす受け入れ条件)
  2. 対象ファイル・変更範囲
  3. テスト要求(可能な限りテストファースト。実行すべき検証コマンド)
  4. 出力要求(変更ファイル一覧・テスト結果・未解決事項をテキストで報告)
  5. 禁止事項: **gitコミット禁止**、要件の再定義禁止、`~/.claude/`・`.claude/` 配下への接触禁止
- 各 `codex exec` 完了後、自分でdiffと検証結果を確認し、不合格なら具体的な指摘とともに再実行させる。call-logに記録(codex)。

**B-4 エスカレーション(必要時のみ)**
policy.md の発火条件を検出したら、`templates/escalation.md` の6点に整形し、Agentツール(model: fable)に goal-frame.md + 6点のみを渡す。判断結果を milestone ディレクトリに `escalation-<連番>.md` として保存し、call-logに記録。判断に従って続行する。

**B-5 独立レビュー(Opusサブ)**
実装が完了したら、Agentツール(model: opus)で**実装に関与していない**レビューアを起動し、goal-plan.md該当部・マイルストーン定義・diff・テスト証拠を渡して「Goal Planとの整合・証拠の妥当性・見落としリスク」をレビューさせる。call-logに記録(opus-sub)。
結果を反映して `templates/approval-submission.md` に従い `milestones/<n>-<名前>/submission.md` を作成する。

**B-6 Implementation Gate(Fable)**
前提確認: submission.md が存在し、テスト証拠が含まれること。
A-6と同じ形式で、goal-frame.md + マイルストーン定義 + submission.md を渡し、「このマイルストーンのゴールを満たしているか」を判定させる。結果を `gate-decision.md` に保存、call-logに記録。
- PASS → B-7へ
- REVISE / REPLAN → 指定工程へ差し戻し(人間へは出さない)
- BLOCKED → 人間へ質問して停止

**B-7 Human Review Report(Opus)**
`templates/human-review-report.md` に従い `human-report.md` を作成する。受け入れテスト手順は人間が5〜15分で実行できる具体性で書く。

**B-8 Human Acceptance(人間)**
human-report.md を人間に提示し、受け入れテストを依頼する。結果を `acceptance.md` に記録する(ACCEPT / REJECT + コメント)。

**B-9 REJECT処理(Fable)**
REJECTの場合、Agentツール(model: fable)に goal-frame.md + human-report.md + REJECT理由を渡し、戻り先(タスク修正 / マイルストーン再計画 / ゴール再確認)を決定させる。決定に従い該当フェーズへ戻る。call-logに記録。

**B-10 確定処理(Opus)**
acceptance.md に ACCEPT があることを確認してから、変更を確定コミットする。state.md を learning へ更新する。

## Learning フェーズ

1. **Retrospective(Opus)**: `templates/retrospective-note.md` に従い `retro.md` を作成する。call-log.md から opus-sub / codex / fable の呼び出し数を数えて記載する(5:1目安、ハード制限ではない)。
2. **グラレコ(Codex経由)**: human-report.md / gate-decision.md / retro.md の要点を `grareco-input.md` にまとめ、`templates/grareco-prompt.md` の指示文を埋めて `codex exec` に渡す。生成失敗時は grareco-input.md を残したまま先へ進む(ループ完了をブロックしない)。call-logに記録(codex)。
3. **次へ**: 未実装マイルストーンがあれば state.md を milestone-implementation に戻して B-1 から繰り返す。全マイルストーン完了なら state.md を done にし、ゴール全体の完了を人間に報告する。

## 例外・停止時の扱い

- どのフェーズでも、人間の入力が必要になったら state.md の「待ち」に内容を書いてから停止する。
- セッションが切れても、次回 `/r-super-loop-powers` 起動時に state.md から再開できる(NFR-04)。
- このスキルは Superpowers・gstack等の他スキルのファイルを読むことはあっても、**変更してはならない**(SK-001)。
`````

- [ ] **Step 2: frontmatter と主要セクションを検証**

Run: `head -4 skills/r-super-loop-powers/SKILL.md && grep -c "^## " skills/r-super-loop-powers/SKILL.md`
Expected: frontmatterに `name: r-super-loop-powers` が含まれ、`## ` 見出しが10個(起動時チェック/ディレクトリ契約/フェーズと成果物契約/記録ルール/ゲート保護ルール/Fable契約/ワークフローA/ワークフローB/Learning/例外)

- [ ] **Step 3: 旧名称が混入していないことを検証**

Run: `grep -rn "goal-loop" skills/ .claude-plugin/ || echo "CLEAN"`
Expected: `CLEAN`

- [ ] **Step 4: コミット**

```bash
git add skills/r-super-loop-powers/SKILL.md
git commit -m "feat: ゴールループ・オーケストレーターSKILL.mdを追加

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: README(インストール・運用・E2Eテスト手順)

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: Task 1のプラグイン名 / Task 5のスキル起動名 `/r-super-loop-powers`
- Produces: ユーザー向け導入手順とE2Eテストチェックリスト(spec §15-§16)

- [ ] **Step 1: README.md を作成**

`README.md`:

````markdown
# r-super-loop-powers

Superpowersの上位に薄く重なる**ゴールループ・オーケストレーション層**。
目的は (1) ゴールループの管理 (2) 適切なヒューマン・イン・ザ・ループの配置 (3) 適切なモデルの使用 — による効率化・安定化・精度向上。作業そのものの進め方はSuperpowersに委ね、内部には一切干渉しない。

```
人間  ──(Goal Seed / 受け入れ)──┐
                                │
┌───────────────────────────────▼──────────────┐
│ r-super-loop-powers(責任・ゲート層)          │
│  フェーズ / 成果物契約 / Fableゲート / HITL  │
├──────────────────────────────────────────────┤
│ Superpowers(実行プロセス層)                  │
│  brainstorming / writing-plans / TDD ...     │
└──────────────────────────────────────────────┘
  実行: Opusメイン  判定: Fableサブ  実装: codex exec
```

## 前提

- Claude Code + Superpowersプラグイン(改造不要)
- Codex CLI(`codex login` 済み。モデル等は `~/.codex/config.toml` に従う)
- メインセッションは **`/model opus`** で運用する(Fable消費を承認ゲートに限定するため)

## インストール

```
/plugin marketplace add C:\Users\makyu\Desktop\project\r-super-loop-powers
/plugin install r-super-loop-powers@r-super-loop-powers-marketplace
```

インストール後、Claude Codeを再起動し、スキル一覧に `r-super-loop-powers` が出ることを確認する。

## 使い方

- **新規ゴール**: 対象プロジェクトで `/r-super-loop-powers` を起動し、やりたいこと(Goal Seed)を伝える
- **再開**: 同じコマンドで起動すると `docs/r-super-loop-powers/*/state.md` から現在地を復元する

フェーズの流れ: Goal Frame(Fable) → ブレスト/Spec/Plan(Opus+Superpowers) → Goal Gate(Fable) → 人間承認 → タスク実装(codex exec) → 独立レビュー(Opus) → Implementation Gate(Fable) → Human Review Report → 人間受け入れ → 確定コミット → 振り返り+グラレコ

## E2Eテスト(初回導入時に1周まわす)

小さなダミープロジェクトで1ゴール1マイルストーンを実行し、以下を確認する:

- [ ] state.md 不在時に新規ゴール開始フローに入る
- [ ] goal-frame.md がFableサブエージェントにより生成される
- [ ] brainstorming / writing-plans がSuperpowers標準フローのまま動く
- [ ] Goal Gate が PASS するまで人間承認を求められない
- [ ] codex exec がコミットを作らない
- [ ] 独立レビュー(opus-sub)が submission.md に反映される
- [ ] Implementation Gate PASS 前に human-report.md が出てこない
- [ ] ACCEPT 記録前に確定コミットが行われない
- [ ] retro.md と grareco-input.md(+ grareco.png)が生成される
- [ ] call-log.md に fable / opus-sub / codex の呼び出しが記録されている
- [ ] セッションを切って再起動 → state.md から現在地が復元される

## リポジトリ構成

- `.claude-plugin/` — プラグインマニフェスト・マーケットプレイス定義
- `skills/r-super-loop-powers/` — SKILL.md(オーケストレーター) / policy.md(運用ポリシー) / templates/(6種)
- `docs/superpowers/specs/` — 設計仕様書
- `docs/superpowers/plans/` — 実装計画
````

- [ ] **Step 2: 検証**

Run: `grep -c "r-super-loop-powers" README.md`
Expected: 10以上(名称が統一されている)

- [ ] **Step 3: コミット**

```bash
git add README.md
git commit -m "docs: インストール・運用・E2Eテスト手順のREADMEを追加

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: 全体構造検証とインストール準備

**Files:**
- Modify: なし(検証のみ。問題があれば該当ファイルを修正)

**Interfaces:**
- Consumes: Task 1〜6の全成果物

- [ ] **Step 1: ファイル一式の存在検証**

Run: `ls .claude-plugin/plugin.json .claude-plugin/marketplace.json skills/r-super-loop-powers/SKILL.md skills/r-super-loop-powers/policy.md && ls skills/r-super-loop-powers/templates/ | wc -l`
Expected: 4ファイルが列挙され、テンプレート数 `6`

- [ ] **Step 2: JSON再検証と名称統一の最終確認**

Run: `python -m json.tool .claude-plugin/plugin.json > /dev/null && python -m json.tool .claude-plugin/marketplace.json > /dev/null && grep -rn "goal-loop" skills/ .claude-plugin/ README.md || echo "ALL CLEAN"`
Expected: `ALL CLEAN`

- [ ] **Step 3: spec受け入れ基準との照合**

spec §15 の4項目について、対応する記述がSKILL.md/READMEに存在することを目視確認する:
1. 新規ゴール開始フロー → SKILL.md「起動時チェック」3
2. state.md復元 → SKILL.md「起動時チェック」3 + 「例外・停止時の扱い」
3. Fable初回入力の限定 → SKILL.md「Fableサブエージェント共通契約」
4. codex execコミット禁止 → SKILL.md「B-2〜B-3」禁止事項 + 「ゲート保護ルール」5

- [ ] **Step 4: 最終コミットとユーザーへの引き渡し**

```bash
git add -A
git commit -m "chore: v0.1.0 構造検証完了

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" --allow-empty
git log --oneline
```

ユーザーに以下を案内する:
1. `/plugin marketplace add C:\Users\makyu\Desktop\project\r-super-loop-powers` を実行
2. `/plugin install r-super-loop-powers@r-super-loop-powers-marketplace` を実行
3. Claude Code再起動後、ダミープロジェクトでREADMEのE2Eチェックリストを1周実行(このE2EがMVPの受け入れテスト。spec §16)

---

## Self-Review 結果

- **Spec coverage**: SK-001〜012 → SKILL.md(非侵襲=例外節/フェーズ表/担当表記/成果物契約表/ゲート4値/差し戻し/保護ルール1〜3/レポート必須/確定制御/Learning/エスカレーション/純Markdown)。PL-001〜010 → policy.md。A1〜A10成果物 → ディレクトリ契約+テンプレート。ワークフローA/B → SKILL.md該当節。§12グラレコ → grareco-prompt.md+Learning節。§13観測 → 記録ルール+retroテンプレート。§15受け入れ基準 → Task 7 Step 3。§16 E2E → README。
- **Placeholder scan**: 全タスクに実コンテンツを記載済み。テンプレート内の `<...>` は成果物の記入欄であり、プランの placeholder ではない。
- **型整合**: ゲート4値・call-logフォーマット・state.mdフォーマット・テンプレートファイル名は全タスクで一致(Task 2/3/4で定義 → Task 5が参照)。
