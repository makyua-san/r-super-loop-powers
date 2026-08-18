# r-super-loop-powers v0.3 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MVPモードにFableヒアリング(A-1a)・Fable代理ブレスト・Checkpoint単位のHuman Acceptance・判断記録(decisions.md)・評価パッケージを実装し、HOWをAgentへ委任する。

**Architecture:** 既存プラグインのMarkdown成果物の改訂(7ファイル)+新規テンプレート2つ+バージョン更新。実行コードなし。改訂対象ファイルは各タスクに**改訂後の完全な内容**を記載し、実装者はファイル全体を置き換える(部分編集のアンカーずれを防ぐ)。

**Tech Stack:** Markdown / JSON。Claude Codeプラグイン形式。

**Spec:** `docs/superpowers/specs/2026-08-18-r-super-loop-powers-v0.3-design.md`(以下「spec」。v0.2以前のspecの決定は、specに書かれた差分以外有効)

## Global Constraints

- 作業ブランチ: `feature/v0.3-mvp-how-delegation`(Task 1 Step 1で作成。このブランチ上で作業)
- 名称はすべて `r-super-loop-powers` で統一。`goal-loop` という文字列を新規内容に書かない。
- Superpowers本体には一切触れない。スクリプト・hooksを追加しない。
- ゲート4値は `PASS / REVISE / REPLAN / BLOCKED` 固定。エスカレ判定2値は `DECIDE / ASK_HUMAN` 固定。
- ループ強度の表記は `MVP` / `高信頼` の2値で統一。Checkpointの表記は `Checkpoint` (カタカナにしない)。
- 各ファイル末尾に改行を1つ入れる。日本語で記述。
- コミットメッセージ末尾(2行): `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` / `Claude-Session: https://claude.ai/code/session_01QSS8FQBndgBiEVBHahCXQG`
- 「ファイル全体を以下の内容に置き換える」と指示されたタスクでは、内容を一字一句そのまま書く(勝手な改善をしない)。
- 作業ディレクトリ: `C:\Users\makyu\Desktop\project\r-super-loop-powers`

## ファイル構成(このプランで触るもの)

| ファイル | 変更 | 責務 |
|---|---|---|
| `skills/r-super-loop-powers/templates/hearing-log.md` | **新規** | ヒアリング往復とASK_HUMAN中継の記録(D23/D32) |
| `skills/r-super-loop-powers/templates/decisions.md` | **新規** | マイルストーン毎の判断記録4区分(D28) |
| `skills/r-super-loop-powers/templates/goal-frame.md` | 改訂 | 「ヒアリングで表面化した既知」欄追加(D23) |
| `skills/r-super-loop-powers/templates/escalation.md` | 改訂 | 「7. Fableの判定」DECIDE/ASK_HUMAN追加(D27) |
| `skills/r-super-loop-powers/templates/approval-submission.md` | 改訂 | Checkpoint配置欄・判断記録参照追加(D22/D28) |
| `skills/r-super-loop-powers/templates/human-review-report.md` | 改訂 | Checkpoint評価パッケージ化(D29) |
| `skills/r-super-loop-powers/templates/retrospective-note.md` | 改訂 | Checkpoint単位注記(D31) |
| `skills/r-super-loop-powers/policy.md` | 全面改訂 | MVP原則・工程表・Checkpoint粒度・エスカレ条件8〜10・責任分担(D21〜D33) |
| `skills/r-super-loop-powers/SKILL.md` | 全面改訂 | A-1a/A-1b分割・代理ブレスト・B-6分岐・評価パッケージ(D21〜D32) |
| `README.md` | 改訂 | MVPモード説明・E2Eチェックリスト更新 |
| `.claude-plugin/plugin.json` | 1行変更 | version 0.3.0(marketplace.jsonにはversionフィールドがないため変更なし) |

---

### Task 1: ブランチ作成 + 新規テンプレート2種(hearing-log / decisions)

**Files:**
- Create: `skills/r-super-loop-powers/templates/hearing-log.md`
- Create: `skills/r-super-loop-powers/templates/decisions.md`

**Interfaces:**
- Produces: hearing-log.mdのラウンド記録形式(Fableの質問/人間の回答/表面化した既知/仮説化して台帳へ送った未知)、decisions.mdの4区分見出し(要件由来の決定/Agentが仮説として決めたHOW/低確信の判断/発見された未知)。Task 3〜4がこれらの見出し名をそのまま参照する。

- [ ] **Step 1: 作業ブランチを作成**

```bash
git checkout -b feature/v0.3-mvp-how-delegation
```

- [ ] **Step 2: hearing-log.md を新規作成**

````markdown
# Hearing Log — <goal-slug>

<!-- 作成者: Opus(中継のたびに追記)。A-1aヒアリング往復と、代理ブレスト・エスカレーションでのASK_HUMAN中継をここに集約する。 -->
<!-- 代理Fableはこのログを goal-frame.md とともに「人間の代理回答」の根拠にする。 -->

## ラウンド <n> — <A-1aヒアリング | ASK_HUMAN中継(フェーズ名)>

- Fableの質問:
  1. <質問>
- 人間の回答:
  1. <回答>
- 表面化した既知: <暗黙の前提・操作の好み・過去の不満・避けたい体験・成功条件など。なければ「なし」>
- 仮説化して台帳へ送った未知: <assumptions.md のID参照。なければ「なし」>
````

- [ ] **Step 3: decisions.md を新規作成**

````markdown
# Decisions — <goal-slug> / Milestone <n>: <名前>

<!-- 作成者: Opus。B-2〜B-5の間に随時追記し、B-5セルフチェック時に確定する。 -->
<!-- Checkpoint評価パッケージ(B-7)がこのファイルを集約する。要件由来とAgent仮説を混ぜない。 -->

## 要件由来の決定
- <Requirements → 実装の対応。goal-frame / spec の該当箇所を参照>

## Agentが仮説として決めたHOW
- <内容> — 根拠: <なぜユーザーに受け入れられる可能性が高いと判断したか。hearing-log / assumptions.md のID参照>

## 低確信の判断
- <評価パッケージで特に人間に見てほしい点。なければ「なし」>

## 発見された未知
- <このマイルストーンで新たに発見し assumptions.md へ追記した未知(ID参照)。なければ「なし」>
````

- [ ] **Step 4: 検証**

Run: `grep -c "^## " skills/r-super-loop-powers/templates/decisions.md && grep -c "表面化した既知" skills/r-super-loop-powers/templates/hearing-log.md`
Expected: `4`(要件由来の決定/Agentが仮説として決めたHOW/低確信の判断/発見された未知)と `1以上`

- [ ] **Step 5: コミット**

```bash
git add skills/r-super-loop-powers/templates/hearing-log.md skills/r-super-loop-powers/templates/decisions.md
git commit -m "feat: ヒアリング記録・判断記録テンプレートを新設(v0.3 D23/D28)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QSS8FQBndgBiEVBHahCXQG"
```

---

### Task 2: 既存テンプレート5種の改訂

**Files:**
- Modify: `skills/r-super-loop-powers/templates/goal-frame.md`(全置き換え)
- Modify: `skills/r-super-loop-powers/templates/escalation.md`(全置き換え)
- Modify: `skills/r-super-loop-powers/templates/approval-submission.md`(全置き換え)
- Modify: `skills/r-super-loop-powers/templates/human-review-report.md`(全置き換え)
- Modify: `skills/r-super-loop-powers/templates/retrospective-note.md`(全置き換え)

**Interfaces:**
- Consumes: Task 1の見出し名(decisions.md 4区分 / hearing-logのラウンド記録)
- Produces: goal-frameの見出し「ヒアリングで表面化した既知」、escalationの「7. Fableの判定」(DECIDE/ASK_HUMAN)、submissionの見出し「Checkpoint配置」「判断記録」、reportの評価パッケージ構造(3.5に「実装対象外」「新しく発見された未知」)、retroのCheckpoint単位注記。Task 3〜4が参照する。

- [ ] **Step 1: goal-frame.md をファイル全体で以下の内容に置き換える**

````markdown
# Goal Frame — <goal-slug>

<!-- 作成者: Fable(入口の責任設定)。このフレームは後でFable自身がゲート判定の基準として使う。 -->

## ゴールの方向
<Goal Seedから読み取った、このゴールが達成すべき本質的な価値。1〜3行>

## ヒアリングで表面化した既知
<hearing-log.md の要点サマリ。暗黙の前提・操作の好み・避けたい体験・成功条件・優先順位など。高信頼(ヒアリング省略)時は「なし」>

## ループ強度
- 提案: <MVP | 高信頼> — <理由1行。既定はMVP(品質最大化は目的ではない)>
- 人間の確定: <未確定 | MVP | 高信頼>

## 制約
<技術・時間・互換性・スコープ上の制約。箇条書き>

## 今回のループで確定すべきこと
<Goal Plan承認までに決まっていなければならない事項。箇条書き>

## 未知マップ
### 既知の未知(まだ決まっていないこと)
- <項目。ユーザーが答えを持つものは質問で、持たないものは仮説化して仮定台帳へ>

### 無自覚の未知の探索方針
- <どの領域(UX・エッジケース・設計制約など)を実装・評価で探るか>

## 承認基準
<!-- ゲート判定はこの基準に対して行われる。検証可能な形で書く -->
1. <基準1>
2. <基準2>
3. <基準3>

## 終了条件(残存未知の許容基準)
<このゴールで「残存する重要な未知が許容可能」と言える条件。検証可能な形で>

## 参照した学習メモ
<直近のRetrospective Noteから反映した点。なければ「なし」>
````

- [ ] **Step 2: escalation.md をファイル全体で以下の内容に置き換える**

````markdown
# Escalation — <goal-slug> / <フェーズ>

<!-- 作成者: Opus(検出者がCodexの場合もOpusが1〜6を整形)。7はFableが記入する。 -->
<!-- Fableへ goal-frame.md と本文書 + 関連する未検証仮定 + hearing-log.mdの関連部分(あれば)を渡す。 -->

1. **何をしようとしたか**: <1〜2行>
2. **何が判断不能か**: <1〜2行>
3. **選択肢**: <A / B (/ C) を1行ずつ>
4. **影響**: <各選択肢がゴール・スケジュール・品質に与える影響>
5. **推奨案**: <どれを推すか + 1行の理由>
6. **いま必要な判断**: <Fableに求める決定を疑問文で1行>
7. **Fableの判定**: <DECIDE: 判断+根拠(自律続行) | ASK_HUMAN: 人間向けの質問文(Opusが人間へ提示し、回答をhearing-log.mdへ追記してから続行)>
````

- [ ] **Step 3: approval-submission.md をファイル全体で以下の内容に置き換える**

````markdown
# Approval Submission — <goal-slug> / <対象: Goal Plan | Milestone n>

<!-- 作成者: Opus。Fableゲートへの提出物。生コード・全会話は含めない(PL-009)。 -->

## 元ゴールと対象
- Goal Frame: <goal-frame.mdの「ゴールの方向」を1行で再掲>
- 対象: <Goal Plan全体 | Milestone n: 名前>
- ループ強度: <MVP | 高信頼>

## 変更の要約(最大5項目)
1. <要約1>

## Checkpoint配置(対象がGoal Planの場合のみ。Milestoneでは「対象外」)

| マイルストーン | Checkpoint | 配置理由(E2Eで評価できるユーザー価値) |
|---|---|---|
| <n>-<名前> | <✓ または -> | <Checkpointの場合のみ: 人間が1回の受け入れテストで評価できる価値> |

<最終マイルストーンは必ずCheckpoint>

## 判断記録(対象がMilestoneの場合のみ。Goal Planでは「対象外」)
<milestones/<n>-<名前>/decisions.md への参照と、ゲート判定に関わる主要判断(Agent仮説HOW・低確信)の要約>

## 承認基準との対応表

| Goal Frameの承認基準 | 対応する成果・証拠 | 状態 |
|---|---|---|
| <基準1> | <spec/plan/diff/テスト名> | 満たす / 一部 / 未 |

## テスト・検証証拠の要約
<実行した検証と結果。コマンドと結果の要点のみ。MVP強度では受け入れ基準に直結する検証+未知低減に効く検証のみでよい>

## 残存未知リスト

| 未知 | 重要度 | 許容可否の自己評価と理由 |
|---|---|---|
| <なければ「なし」と明記> | <高・中・低> | <許容可 / 不可 + 理由1行> |

## 仮定台帳サマリ
<assumptions.md の未検証仮定のうち、このゲート判定に関わるもの(ID参照)。なければ「なし」>

## 既知リスク・未解決事項・意図的対象外
- <なければ「なし」と明記>

## Opusの推奨判定
- 推奨: PASS | REVISE | REPLAN | BLOCKED
- 根拠: <3行以内>
````

- [ ] **Step 4: human-review-report.md をファイル全体で以下の内容に置き換える**

````markdown
# Human Review Report(評価パッケージ)— <goal-slug> / <対象: Checkpoint <n>-<名前> | Milestone <n>: <名前>>

<!-- 作成者: Opus(Fable PASS後)。MVPではCheckpoint到達時に作成し、対象は前回Checkpoint以降の全マイルストーン。 -->
<!-- 高信頼ではマイルストーン毎に作成する。1〜2画面で読み切れる長さにする(NFR-02)。 -->

## 1. 何を達成したか(今回のGoalと実装されたユーザー価値)
<1〜3行。End-to-Endで何ができるようになったか>

## 2. 何が変わったか
<ユーザー視点の挙動変更を優先。内部実装は必要な範囲のみ>
- 対象マイルストーン: <MVP: 前回Checkpoint以降の一覧 | 高信頼: 単体>

## 3. なぜ正しいと言えるか(主要Requirementsと実装の対応)

| 受け入れ基準 / 主要Requirements | 証拠(テスト・実行結果) |
|---|---|
| <基準> | <テスト名と結果> |

## 3.5 判断の内訳(各マイルストーンの decisions.md を集約)
- **確定(検証済み)**: <テスト・実行で確認済みの事項>
- **要件から直接導出**: <Goal Frame・要件に明記されていた事項>
- **Agentが仮説として決めたHOW**: <decisions.md の要約+根拠。assumptions.md のID参照>
- **低確信・要確認**: <特に人間に評価してほしい点>
- **実装対象外としたもの**: <意図的に作らなかったもの。なければ「なし」>
- **開発中に新しく発見された未知**: <なければ「なし」>

## 4. 確認してほしいこと(受け入れテスト手順)
1. <手順1: コマンドや操作> → 期待結果: <...>
2. <手順2> → 期待結果: <...>

## 5. リスク・制約(既知の制約)
<既知の問題、残課題、影響範囲。なければ「なし」>

## 6. 詳細への導線
- 関連ファイル: <パス>
- 各マイルストーンの判断記録: <milestones/*/decisions.md のパス一覧>
- グラレコ: <パス。あれば>
- コミット: <中間コミットの範囲(MVP)/ ブランチ・未コミットの旨>
- 詳細diff: <参照方法>
````

- [ ] **Step 5: retrospective-note.md をファイル全体で以下の内容に置き換える**

````markdown
# Retrospective — <goal-slug> / <対象: Checkpoint <n>-<名前> | Milestone <n>>

<!-- 作成者: Opus(Human ACCEPT + 確定処理後)。MVPではCheckpoint単位(対象は前回Checkpoint以降の全マイルストーン)、高信頼ではマイルストーン単位で作成する。次回のGoal Frame作成時に自動参照される。短く保つ。 -->

## うまく機能したこと(最大3点)
- <...>

## 無駄だった呼び出し・手戻り(最大3点)
- <...>

## 次回変えること(最大3点)
- <...>

## 発見された未知
- <この区間で新たに既知化された未知・学び。次回の入力になる。なければ「なし」>

## 再利用できる知見・テンプレート候補
- <なければ「なし」。このプロジェクトの外でも効くものは orca-meta へ `record_lesson` で送る対象(軸: person / agent / method)>

## 観測
- ループ回数: <Fableゲート差し戻し(REVISE/REPLAN)の回数を含む>
- 呼び出し概算: opus-sub <n>回 / codex <n>回 / fable <n>回(目安 Opus:Fable ≈ 5:1。ワークフローB以降に適用)
- 主要フェーズ所要時間: <call-log.mdの時刻から概算(ヒアリング / 設計 / 実装 / ゲート / レポート等)>
- 特記: <比率が大きく外れた場合の理由。なければ「なし」>
````

- [ ] **Step 6: 検証**

Run: `grep -c "^## " skills/r-super-loop-powers/templates/goal-frame.md && grep -c "Fableの判定" skills/r-super-loop-powers/templates/escalation.md && grep -c "Checkpoint配置" skills/r-super-loop-powers/templates/approval-submission.md && grep -c "実装対象外としたもの" skills/r-super-loop-powers/templates/human-review-report.md && grep -c "Checkpoint単位" skills/r-super-loop-powers/templates/retrospective-note.md`
Expected: `9`(ゴールの方向/表面化した既知/ループ強度/制約/確定すべきこと/未知マップ/承認基準/終了条件/参照した学習メモ)、`1`、`1`、`1`、`1`

- [ ] **Step 7: コミット**

```bash
git add skills/r-super-loop-powers/templates/
git commit -m "feat: テンプレ5種をv0.3対応(表面化した既知・DECIDE/ASK_HUMAN・Checkpoint配置・評価パッケージ・Checkpoint単位retro)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QSS8FQBndgBiEVBHahCXQG"
```

---

### Task 3: policy.md 全面改訂

**Files:**
- Modify: `skills/r-super-loop-powers/policy.md`(全置き換え)

**Interfaces:**
- Consumes: Task 1〜2の見出し名(hearing-log.md / decisions.md 4区分 / DECIDE・ASK_HUMAN / Checkpoint配置)
- Produces: 見出し「MVPモードの原則」を含む上位原則、強度別工程表(ヒアリング〜Learningの13行)、「Checkpointとマイルストーン粒度」、エスカレ発火条件10件+判定2値。`## ` 見出しは10個。Task 4のSKILL.mdがこれらを参照する。

- [ ] **Step 1: policy.md をファイル全体で以下の内容に置き換える**

````markdown
# r-super-loop-powers モデル運用ポリシー

上位要件: `goal_engineering_ai_skill_policy_requirements.docx` 5章・11章・12章・14章、`20260810_ハーネス改善-1.md`(v0.2の入力)、および `20260818_ハーネス改善-2.md`(v0.3の入力)。
本ポリシーは SKILL.md(オーケストレーター)から参照される。数値・比率は観測指標であり、品質や安全に必要な判断を妨げない。

## 上位原則(Goal Loopの目的)

Goal Loopの目的は次の2つであり、品質最大化・速度最大化は目的ではない。

- **A. 要件適合性**: 定義したゴール・要件・制約に成果物が適合している確度を高める。「コードが動く」ではなく「作りたかったものを正しく作れているか」
- **B. 未知の低減**: 開始時に認識できなかった未知(特に無自覚の未知)を、仮説→実装→評価のループで発見・既知化する

AIは未知に対して可能な限り自律的に仮説を立て、人間が評価可能な具体物まで精度を高めてから提示する。人間の役割は生成より評価。**ループ・テスト・レビュー・承認は、それ自体を目的とせず、AまたはBに寄与する場合にのみ実施する**(工程の存在理由テスト)。ループ終了条件は回数ではなく「適合性への十分な確信 + 残存する重要な未知が許容可能」。

**MVPモードの原則(v0.3)**: MVPモードでは、人間にHOWの詳細確定を原則として求めない。その代わり、開発開始前のヒアリングでGoal・Requirements・Constraints・利用文脈・暗黙の期待を十分に探索し、ユーザーの「無自覚の既知」を可能な限り表面化する。Agentはその情報を根拠として、まだ正解の存在しないHOWを仮説として具体化し、自律的に実装・評価・改善する。Human Feedbackは各マイルストーンの必須ゲートではなく、重大な不確実性・不可逆性・低確信度の判断に対するエスカレーションとして用いる。通常はユーザー価値がEnd-to-Endで成立した段階(Checkpoint)でHuman Acceptanceを行う。**「HOWを聞かない」ことと「ヒアリングを減らす」ことを混同しない** — 質問の対象をHOWからGoal / Context / Preferenceへ移す。

## ループ強度

**MVP(既定)** と **高信頼** の2段階。Goal Frame作成時にFableが提案し、人間がGoal Frame確認時に確定する。マイルストーン単位の一時変更は人間が指示できる。FableゲートとHuman Acceptanceは両強度で維持する(要件適合性の保証線)— MVPのHuman AcceptanceはCheckpoint単位で行う。一時変更は state.md の強度欄に記録し、そのマイルストーン完了時に goal-frame.md の確定値へ戻す。

| 工程 | MVP(既定) | 高信頼 |
|---|---|---|
| ヒアリング(A-1a) | Fable駆動の往復ヒアリング(無自覚の既知の表面化。目安2〜4往復) | 省略(A-1bのGoal Frame作成のみ) |
| Goal Frame / Goal Gate(A-1b / A-6) | 実施(表面化した既知+未知マップ+強度+終了条件+Checkpoint配置判定) | 実施(未知マップ+強度+終了条件を含む) |
| ブレスト〜Plan(A-2〜A-4) | superpowers:brainstormingを**Fable代理回答**で実施(人間はASK_HUMAN時のみ) | 人間参加のsuperpowers:brainstorming |
| Human Goal Plan承認(A-8) | WHATレベル(ゴール解釈・要件・制約・Checkpoint配置・仮定台帳サマリ) | 従来(spec/planレビュー含む) |
| マイルストーン開始確認(B-1・Fable) | 実施(軽量) | 同左 |
| 実装委譲(B-2) | マイルストーン単位でまとめて codex exec に委譲可(タスク細分化しない) | タスク分解して個別に委譲 |
| タスク単位の受け入れ(B-3) | codex自己検証報告の確認のみ(diff精読なし) | Opusメインがdiffを確認 |
| テスト要求(B-2) | 受け入れ基準に直結する検証+未知低減に効く検証のみ | 単体・結合・lint・型検査をフル要求 |
| 独立レビュー(B-5) | 省略(Opusメインがsubmission作成時にセルフチェック+decisions.md確定) | Opusサブで実施(PL-003) |
| Implementation Gate(B-6・Fable) | 実施(適合性+残存未知の許容性)。非CheckpointはPASS後に人間承認なしで次マイルストーンへ | 実施(適合性+残存未知の許容性) |
| Human Report / Acceptance(B-7 / B-8) | **Checkpoint到達時のみ**(評価パッケージ) | マイルストーン毎 |
| コミット | マイルストーン毎に中間コミット、Checkpoint ACCEPTで確定 | ACCEPT後のみ |
| Learning | グラレコ+decisions.md=マイルストーン毎 / retro=Checkpoint毎 | マイルストーン毎(従来通り) |

## Checkpointとマイルストーン粒度

- **Checkpoint** = 「**ユーザーが1つの価値をEnd-to-Endで利用・評価できる**」点。goal-plan.mdのマイルストーン一覧に印として配置し、A-8で人間が配置を承認する。最終マイルストーンは必ずCheckpoint。人間の受け入れテスト1回で確認できる範囲に収める(時間の上限・下限は定めない)
- **MVPのマイルストーン** = 内部作業単位。Fableゲート(B-6)で判定可能な成果のまとまりであればよく、E2E価値の完成は要求しない。ただし技術タスク単位への細分化はしない
- **高信頼のマイルストーン** = 従来通り「ユーザーが1つの価値をEnd-to-Endで利用できる」単位(全マイルストーンがCheckpoint相当)

## 仮説自律の否定リスト

以下に触れる仮説は自律実行禁止。エスカレーション(Fable)または人間確認を必須とする:

1. データ削除・上書き等の**不可逆操作**
2. **外部公開・送信**(デプロイ、外部APIへの送信、メール等)
3. **課金・支払い・契約**
4. **セキュリティ・認証・個人情報**の扱いの変更
5. Goal Frameに明記された**制約・要件の変更**(=要件の再定義)
6. 承認済み設計の**破壊的変更**

上記以外は、仮説を立てて `assumptions.md`(仮定台帳)に記録した上で自律的に進んでよい。各仮定に「ゴールへの寄与」1行を必須とする(局所最適化ガード)。ユーザーが答えを持たない問いを人間へ返し続けない — 仮説化し、評価可能な具体物にして評価してもらう。

## 責任分担

| 担当 | 主責務 | 通常実行 | 禁止・抑制 |
|---|---|---|---|
| 人間 | 意図の提示、ヒアリング回答(暗黙の前提・期待の表面化に協力)、具体物の評価とフィードバック、最終受け入れ、優先順位判断 | Goal Seed入力、ヒアリング回答、ループ強度の確定、A-8承認(MVPはWHATレベル)、ASK_HUMAN応答、Checkpoint受け入れテスト | 生diffの最初からの精読を前提にしない。答えを持たない問い(HOW)への回答を強制されない |
| Fable | 全体責任者。ヒアリング駆動(無自覚の既知の探索)、入口の基準設定(Goal Frame・強度提案)、MVPでは**代理ブレスト回答**(人間の代理としてHOW質問に回答・設計承認)、マイルストーン開始確認、承認ゲート(適合性+残存未知の許容性+仮定の事実扱いチェック)、エスカレーション判定(DECIDE / ASK_HUMAN)、Human REJECT後の戻り先決定 | サブエージェントとしてのみ起動。**代理Fable**(A-1a〜A-4。SendMessage継続で文脈保持)と**ゲート・判断Fable**(A-6 / B系。呼び出し毎に新規インスタンス+最小コンテキスト)を分離 | ブレスト・仕様・実装・レポートの**本文作成**。自分が代理回答した設計のゲート判定(自己承認) |
| Opus | メインセッション。**Solution仮説の設計責任**。整理・仕様化・計画・仮定台帳の管理・decisions.md・承認資料・評価パッケージ・振り返り・確定処理。高信頼強度では独立レビュー(サブ) | 常駐 | ゴール変更の独断確定 |
| Codex | 実装担当(`codex exec`)。コード変更、検証、自己検証報告 | マイルストーン単位(MVP)またはタスク単位(高信頼)で呼び出し | コミット、要件の再定義、否定リスト該当の自律判断 |
| 画像生成(Codex組み込み image_gen ツール) | グラフィックレコード | マイルストーン毎(MVPは中間クローズ時、Checkpointは Learning)に呼び出し | 未承認状態を確定として描かない。APIキー・スクリプト経由の生成はしない |
| Sonnet | 将来枠(未使用)。軽量探索・補助実装の候補 | — | 必須モデルとして固定しない |

## Fableを呼ぶ場面(これ以外では呼ばない)

1. ヒアリング(MVP・A-1a): 質問の設計・深掘り・充足判定を行うとき(代理Fable・往復)
2. ループ開始時: Goal Seedから Goal Frame(方向・表面化した既知・制約・未知マップ・承認基準・終了条件・強度提案)を定義するとき
3. 代理ブレスト(MVP・A-2〜A-4): superpowers:brainstormingの質問・設計承認に人間の代理として回答するとき(代理Fable)
4. マイルストーン開始時: 対象マイルストーンが上位ゴールのどの成果を満たすかを確認するとき(注意点のみの軽量呼び出し)
5. 承認ゲート: Approval Submission が揃い、PASS/REVISE/REPLAN/BLOCKED を判定するとき
6. エスカレーション: 実行担当が「エスカレーション発火条件」を検出したとき(判定は DECIDE / ASK_HUMAN)
7. Human REJECT後: 戻り先(修正 / 再計画 / ゴール修正)を決定するとき

## Fableを原則呼ばない場面

- Brainstorming / Spec / Plan の**本文作成**(MVPの代理ブレストでもFableは回答・承認のみ。本文はOpusが書く)
- コード実装、単体テスト、軽微な修正
- 承認に必要な情報の整理・要約(Opusの仕事)
- 人間向けレポート、振り返りメモの作成
- フォーマット変換や定型ドキュメント生成

## 運用ポリシー

| ID | ポリシー | 要件 |
|---|---|---|
| PL-001 | Default roles | Fable=責任/判定、Opus=整理/仕様/レビュー/報告、Codex=実装をデフォルトとする |
| PL-002 | No Fable by default | 「高性能だから」という理由だけでFableへ上げない。メインセッションはOpusで運用する |
| PL-003 | Independent review | **高信頼強度では**、Fable提出前に実装非関与のOpusサブエージェントが独立レビューする。MVP強度ではOpusメインのセルフチェックで代替する |
| PL-004 | Evidence first | 承認要求には検証証拠・残存未知リスト・未解決事項を必ず含める。推測だけでPASSを求めない |
| PL-005 | Human after AI gate | 人間受け入れはFable PASS後に行う(MVPはCheckpoint到達時のみ) |
| PL-006 | Human rejection routing | Human REJECTはFableへ戻し、戻り工程をFableが決める |
| PL-007 | Budget observability | fable / opus-sub / codex の呼び出し(代理FableとのSendMessage往復を含む)を call-log.md に記録し、Opus:Fable ≈ 5:1 を目安に振り返る。MVPのヒアリング・代理ブレスト期(A-1a〜A-4)はfable往復が構造的に増えるため、目安は**ワークフローB以降**に適用する |
| PL-008 | No forced ratio | 比率は目標であり、品質や安全に必要なFable呼び出しを禁止しない |
| PL-009 | Context minimization | Fableへは goal-frame + 対象文書 + 仮定台帳の関連部分(+ 必要ならhearing-logの関連部分)のみを渡す。全コード・全会話を常時ロードしない。代理Fableは自インスタンス内の文脈保持のみ許容 |
| PL-010 | Human cognitive load | 人間向け成果物は、ゴール → 結果 → 証拠 → リスク → 確認手順の順で構造化し、確定事項と仮説による決定を区別する(判断の内訳) |

## エスカレーション発火条件(いずれかを検出したらFableへ)

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

形式は `templates/escalation.md` の7点フォーマットを用いる。Fableの判定は **DECIDE**(判断+根拠を返し自律続行)または **ASK_HUMAN**(人間向けに整形した質問を返す。Opusが人間へ提示し、回答をhearing-log.mdへ追記してから続行)のいずれかを必ず返す。

## 観測

- call-log.md 形式: `YYYY-MM-DD HH:MM | fable|opus-sub|codex | フェーズ | 目的`(1呼び出し1行。代理FableとのSendMessage往復も1往復1行)
- Opusメインセッション自身の消費は記録対象外(常駐のため)
- Retrospective 作成時に、呼び出し比率(5:1目安・ワークフローB以降)に加えて、ループ回数・主要フェーズ所要時間(call-logの時刻から概算)・発見された未知を記載する。ハード制限にしない(PL-008)
````

- [ ] **Step 2: 検証**

Run: `grep -c "^## " skills/r-super-loop-powers/policy.md && grep -c "ASK_HUMAN" skills/r-super-loop-powers/policy.md && grep -c "Checkpoint" skills/r-super-loop-powers/policy.md`
Expected: `10`(上位原則/ループ強度/Checkpointとマイルストーン粒度/否定リスト/責任分担/呼ぶ場面/呼ばない場面/運用ポリシー/エスカレーション/観測)、`5以上`、`10以上`

- [ ] **Step 3: コミット**

```bash
git add skills/r-super-loop-powers/policy.md
git commit -m "feat: policyにMVP原則・Checkpoint粒度・代理Fable・エスカレ条件8〜10を追加(v0.3)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QSS8FQBndgBiEVBHahCXQG"
```

---

### Task 4: SKILL.md 全面改訂

**Files:**
- Modify: `skills/r-super-loop-powers/SKILL.md`(全置き換え)

**Interfaces:**
- Consumes: Task 1〜3の見出し名・値(hearing-log.md / decisions.md 4区分 / DECIDE・ASK_HUMAN / policy.mdの工程表・Checkpoint粒度・発火条件10件)
- Produces: `/r-super-loop-powers` の実行手順v0.3(A-1a/A-1b分割・代理ブレスト・B-6分岐・評価パッケージ)。`## ` 見出しは11個。

- [ ] **Step 1: SKILL.md をファイル全体で以下の内容に置き換える**

`````markdown
---
name: r-super-loop-powers
description: Use when starting or resuming a goal-engineering loop (ゴールループ / goal loop / ゴールエンジニアリング開発). Superpowersの上位で、要件適合性と未知低減を目的に、フェーズ管理・成果物契約・Fable承認ゲート・ヒューマン・イン・ザ・ループ配置・モデル責任分担(Opus実行 / Fable判定 / Codex実装)をオーケストレーションする。MVPモードではFableヒアリングでゴールと文脈を掘り、HOWはFable代理ブレストでAgentへ委任し、Checkpoint単位でHuman Acceptanceを行う。
---

# r-super-loop-powers — ゴールループ・オーケストレーター

あなた(このスキルを実行するモデル)は **Opusメインセッション** として、ゴールループの進行管理と成果物作成を担当する。
このスキルは **責任・ゲート層** である: いまどのフェーズか、次に必要な成果物は何か、誰が実行し誰が判定するか、人間へ返すタイミングだけを制御する。
作業の進め方(HOW)はSuperpowersのスキルに完全に委ね、その内部手順には一切干渉しない。MVPモードでは、Superpowersのスキルが人間に求める質問・承認への応答を**代理Fable**が担う(相手が変わるだけで、スキルの手順は変えない)。

Goal Loopの目的は **A. 要件適合性** と **B. 未知の低減** の2つ(policy.md「上位原則」)。MVPモードでは人間にHOWの確定を求めず、ヒアリングで無自覚の既知を表面化した上でAgentがHOWを仮説化する(policy.md「MVPモードの原則」)。ループ・テスト・レビュー・承認は、AまたはBに寄与する場合にのみ実施する。ループ終了条件は回数ではなく「適合性への十分な確信 + 残存する重要な未知が許容可能」。

## 起動時チェック(毎回必ず実行)

1. **ポリシー読込**: このスキルと同じディレクトリの `policy.md` を読む。以後の全判断はこのポリシーに従う。
2. **モデル確認**: 自分がOpusで動いていない場合(特にFableの場合)、ユーザーに `/model opus` への切替を提案し、切替またはユーザーの明示的な続行指示があるまでフェーズ作業を開始しない(PL-002)。
3. **状態復元**: 対象プロジェクトで `docs/r-super-loop-powers/*/state.md` を探す(Globツール)。
   - 見つかった場合: 最新の state.md を読み、「現在フェーズ / 強度 / 対象マイルストーン / 次のCheckpoint / 次のゲート」を1〜3行でユーザーに報告し、そのフェーズの手順から再開する。
   - 見つからない場合: ワークフローA(新規ゴール)を開始する。
4. **強度確認**: goal-frame.md が存在する場合、ループ強度(MVP | 高信頼)を読み、policy.md「ループ強度」の工程表に従って以後の工程を実施する。強度未確定のままワークフローBへ進まない。

## ディレクトリ契約

対象プロジェクト内に次を作成・維持する:

```
docs/r-super-loop-powers/<goal-slug>/
├── state.md                 # 現在地(下記フォーマット)
├── goal-seed.md             # 人間の意図(原文のまま)
├── hearing-log.md           # A-1aヒアリングとASK_HUMAN中継の記録(MVP)
├── goal-frame.md            # Fable入口出力 = 承認基準・強度・未知マップ・終了条件の原本
├── assumptions.md           # 仮定台帳(全フェーズで追記)
├── goal-plan.md             # spec/planリンク + マイルストーン一覧(Checkpoint印) + 主要設計判断
├── goal-plan-submission.md  # A-5 Goal Plan承認用submission
├── goal-gate-decision.md    # A-6 Goal Gate判定
├── call-log.md              # 呼び出し記録(PL-007)
└── milestones/<n>-<名前>/
    ├── submission.md / gate-decision.md / decisions.md
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
- 担当: opus-main | fable | codex | human
- 次のゲート: goal-gate | impl-gate | human-acceptance | none
- 待ち: <人間待ちの場合はその内容。なければ ->
- updated: YYYY-MM-DD HH:MM
```

**全フェーズで「state.md更新 → 作業」の順**を守る。フェーズ遷移の前に、下表の必須成果物が揃っているかを必ず確認し、欠落があれば次へ進まない。

## フェーズと成果物契約

| フェーズ | 入口条件 | このフェーズで必須の成果物 | 出口のゲート |
|---|---|---|---|
| goal-definition | goal-seed.md | (MVP: hearing-log.md →) goal-frame.md(強度確定) → spec/plan → goal-plan.md(Checkpoint印) → goal-plan-submission.md | Goal Gate(Fable)→ Human承認(MVPはWHATレベル) |
| milestone-implementation | Goal Plan承認済み + 強度確定 | 実装diff + 検証証拠(高信頼のみ: 独立レビュー) → decisions.md → submission.md(残存未知リスト付き) | Implementation Gate(Fable)。MVPの非CheckpointはPASS後、人間承認なしで次マイルストーンへ |
| human-acceptance | Fable PASS(MVP: Checkpoint到達時のみ) | human-report.md(評価パッケージ) | 人間のACCEPT/REJECT |
| finalization | acceptance.md に ACCEPT | 確定処理(確定コミット) | なし |
| learning | 確定処理済み | retro.md + grareco-input.md(+ grareco.png) | なし |

## 仮定台帳の運用

- `templates/assumptions.md` の形式で goal直下に置き、全フェーズで追記する。
- 追記のタイミング: (1) ヒアリング・ブレスト中に人間または代理Fableが「決めていない / わからない」と答えたとき (2) 実装・設計で仮説的判断をしたとき (3) エスカレーションや Human Feedback で新しい未知が見つかったとき。
- 各仮定には「ゴールへの寄与」1行を必ず書く(局所最適化ガード)。
- **policy.md「仮説自律の否定リスト」に触れる仮定は自律実行しない** — エスカレーション(B-4)または人間確認へ。
- 検証されたら状態を「検証済み」または「棄却」に更新する。棄却時は必要なら新しい仮定を起こす。

## 記録ルール(PL-007)

fable / opus-sub(Opusサブエージェント) / codex を呼ぶたび、および代理FableとのSendMessage往復のたびに、直後に `call-log.md` へ1行追記する:
`YYYY-MM-DD HH:MM | fable|opus-sub|codex | フェーズ | 目的`

## ゲート保護ルール(絶対)

1. Fable PASS 前に人間へ受け入れを求めない(SK-007)
2. human-report.md(評価パッケージ)なしで Human Acceptance に進まない(SK-008)
3. Checkpoint(高信頼はマイルストーン)の acceptance.md に ACCEPT がない状態で確定処理をしない(SK-009)。MVPの中間コミット(B-6 PASS後)は可
4. 必須成果物が欠けた状態でFableゲートを呼ばない — 欠落は自分で差し戻して埋める(NFR-05)
5. `codex exec` にコミットさせない
6. 否定リストに触れる仮説を自律実行しない — エスカレーションまたは人間確認へ
7. 代理ブレストに参加したFableインスタンスにゲート判定(A-6 / B-6)をさせない(自己承認の禁止)

## Fableサブエージェント共通契約

- Agentツールで `model: "fable"` を指定して起動する。役割は2種類あり、**インスタンスを分離する**:
  - **代理Fable(MVPのA-1a〜A-4)**: nameを付けて1インスタンスを起動し、SendMessageで往復を継続する(ヒアリング文脈の保持)。入力は goal-seed / goal-frame / hearing-log / retro抜粋 / templates構造のみ。
  - **ゲート・判断Fable(A-6 / B-1 / B-4 / B-6 / B-9)**: 呼び出しごとに新規インスタンス。初回入力は goal-frame.md 全文 + 対象文書(submission / escalation / milestone定義) + assumptions.md の関連部分(未検証仮定) + 必要なら hearing-log.md の関連部分のみ。対象プロジェクトの生コード・全会話履歴を渡さない(PL-009)。追加資料を要求した場合のみ、SendMessageで1往復の追加提供を行う。
- ゲート判定の出力契約: `PASS | REVISE | REPLAN | BLOCKED` のいずれか1つ + 根拠(5行以内) + REVISE/REPLANの場合は戻り先工程と対象の未知・仮定。
- 判定観点(プロンプトに明記する): (1) goal-frame.md の承認基準を満たすか (2) 残存する重要な未知が許容可能か(goal-frameの終了条件と照合) (3) 仮定が事実として扱われていないか (4) 否定リスト違反の仮説がないか。「動くか」ではなくゴール整合を見る。

## ワークフローA: Goal Definition

**A-0 Goal Seed保存(Opus)**
ユーザーの「やりたいこと」を原文のまま `goal-seed.md` に保存する。要約・整形しない。`<goal-slug>` を決め、ディレクトリと state.md(phase: goal-definition, 強度: 未確定)、空の call-log.md、`templates/assumptions.md` の形式で空の仮定台帳、`templates/hearing-log.md` の形式で空のヒアリング記録を作成する。

**A-1a ヒアリング(代理Fable・往復)**
直近の `docs/r-super-loop-powers/*/milestones/*/retro.md` を新しい順に最大3件読み、要点を抜粋する。
Agentツール(model: fable、**nameを付けて起動=代理Fable**)に `templates/hearing-log.md` の構造 + goal-seed.md 全文 + retro抜粋(あれば)を渡し、次を指示する:
「あなたはこのゴールの全体責任者としてヒアリングを設計・駆動する。目的はユーザーの**無自覚の既知**(暗黙の前提・操作の好み・過去の不満・絶対に避けたい体験・想定利用シーン・実際の業務フロー・優先順位・暗黙の成功条件)の表面化。**HOW(UI形式・機能構成・導線・実装方式の選択)を質問してはならない**。質問は『感情・体験 → 嗜好・制約 → 検証』の順で組み立てる。初回は開発タイプの確認(MVP型か、高信頼・仕様重視型か)を含む3〜7問と、現時点の理解サマリを返せ。以後の往復では、回答を踏まえた深掘り質問を返すか、十分と判断したら『ヒアリング完了』と宣言せよ。」
Opusは質問をそのまま人間へ提示し、回答を `hearing-log.md` に記録して SendMessage で代理Fableへ返す(目安2〜4往復)。人間が開発タイプで高信頼を選んだ場合は深掘りを打ち切り、A-1bへ進む。往復ごとにcall-logへ記録(fable)。

**A-1b Goal Frame(Fable)**
- **MVP**: 代理FableへSendMessageで `templates/goal-frame.md` の構造を渡し、Goal Frame生成を指示する。
- **高信頼**: 新規Fableインスタンスに `templates/goal-frame.md` の構造 + goal-seed.md 全文 + retro抜粋(あれば)を渡す。
指示: 「あなたはこのゴールの全体責任者。ゴールの方向・ヒアリングで表面化した既知・制約・今回確定すべきこと・未知マップ(既知の未知と無自覚の未知の探索方針)・承認基準・終了条件(残存未知の許容基準)を定義し、ループ強度(MVP | 高信頼)を理由付きで提案せよ。既定はMVP(品質最大化は目的ではない)。承認基準と終了条件は後でゲート判定の基準として使われる。検証可能な形で書け。」
出力を `goal-frame.md` に保存し、call-logに記録する。内容をユーザーに提示し、**ループ強度を確定**してもらい、方向のズレがないか確認する。確定した強度を goal-frame.md の「人間の確定」欄と state.md に記録する。

**A-2〜A-4 ブレスト → Spec → Plan(Opus + Superpowers)**
`superpowers:brainstorming` を起動し、その標準フロー(spec作成 → writing-plans)に完全に従う。スキル内部の手順・ゲートには干渉しない。強度により質問・承認の相手を変える:
- **高信頼**: 従来通り人間が相手。
- **MVP(Fable代理ブレスト)**: 質問・設計承認の相手を人間ではなく**代理Fable**(SendMessage)にする。代理Fableへの依頼文に必ず含める: 「あなたはユーザーの代理として回答する。根拠は goal-frame.md と hearing-log.md。**ユーザー固有の判断(好み・業務文脈・優先順位)が必要でヒアリング記録から導けない問い、否定リスト該当、エスカレーション発火条件該当の問いには、回答せず `ASK_HUMAN: <人間向けの質問文>` と返せ**。」 ASK_HUMANが返った質問のみ人間へ提示し、回答を hearing-log.md に追記して代理Fableへ共有する。代理Fableの主要決定(採用アプローチ・設計承認)は goal-plan.md の「主要設計判断」欄に記録する。往復ごとにcall-logへ記録(fable)。
**未知の振り分け**: ヒアリング・ブレスト中に人間または代理Fableが「決めていない / わからない」と答えた問いは、その場で追及せず**仮説化して assumptions.md に記録し、続行する**。goal-frame.md の未知マップと突き合わせる。
完了後、spec/planへの相対リンクとマイルストーン一覧を `goal-plan.md` に集約し、**Checkpoint印を付ける**(policy.md「Checkpointとマイルストーン粒度」: Checkpoint = ユーザー価値をE2Eで評価できる点。最終マイルストーンは必ずCheckpoint)。「主要設計判断」欄もここに置く。

**A-5 Approval Submission(Opus)**
`templates/approval-submission.md` に従い、Goal Plan承認用の submission を作成する(対象: Goal Plan全体。**Checkpoint配置**・残存未知リスト・仮定台帳サマリを含める)。保存先: `goal-plan-submission.md`(goal直下)。

**A-6 Goal Gate(ゲートFable・新規インスタンス)**
前提確認: goal-frame.md と submission が存在すること。
共通契約に従い goal-frame.md 全文 + submission 全文 + assumptions.md の未検証仮定を渡し、判定観点(適合性・残存未知の許容性・仮定の事実扱い・否定リスト)に加えて「**Checkpoint配置が『人間の受け入れテスト1回でE2E価値を評価できる』単位か**」で「この計画で元の目的を達成できるか」を判定させる。品質の細部ではなくゴール整合性を中心に見る。
結果を `goal-gate-decision.md`(goal直下)に保存し、call-logに記録する。

**A-7 差し戻し処理(Opus)**
- REVISE → 指定された工程(ブレスト/spec/plan)へ戻り、修正後 A-5 から再提出
- REPLAN → A-4(計画)から作り直し
- BLOCKED → 根拠に含まれる質問を人間へ提示し、state.md を「人間待ち」にして停止

**A-8 Human Goal Plan承認(人間)**
Fable PASS後、人間に提示して実装へ進む承認を得る。
- **MVP(WHATレベル)**: 提示は「ゴール解釈(goal-frameの方向)・要件・制約・マイルストーン一覧とCheckpoint配置・仮定台帳サマリ」に限定し、spec/planは参照リンクとして添付する(HOW詳細は承認対象にしない)。
- **高信頼**: 従来通り Goal Plan(と goal-frame)を提示する。
承認されたら state.md を milestone-implementation へ更新する(「次のCheckpoint」欄も記入)。

## ワークフローB: Milestone Implementation(マイルストーンごとに繰り返す)

**B-1 開始確認(Fable・軽量)**
直近の retro.md 最大3件の要点を抜粋し、Agentツール(model: fable、新規インスタンス)に goal-frame.md + 対象マイルストーン定義(goal-plan.mdの該当部分) + retro抜粋(あれば)を渡し、「このマイルストーンが上位ゴールのどの成果を満たすか確認し、実装上の注意点があれば10行以内で示せ」と指示する。call-logに記録。

**B-2〜B-3 実装と自己検証(Codex)**
強度により委譲単位を変える(policy.md工程表):
- **MVP**: **マイルストーン単位でまとめて**1〜数回の `codex exec` に委譲する。タスク細分化しない。
- **高信頼**: subagent-driven developmentと同じプロセス構造でタスク分解し、個別に委譲する。

```bash
codex exec "<プロンプト>"
```

- モデル・reasoning effort・sandboxはユーザーの `~/.codex/config.toml` に従う(上書きしない)
- Bashのtimeoutは最長(600000ms)を指定し、長そうな委譲は run_in_background で実行する
- プロンプトの必須要素:
  1. 目的(このマイルストーン/タスクが満たす受け入れ条件)
  2. 対象ファイル・変更範囲
  3. 検証要求 — **MVP**: 受け入れ基準に直結する検証+未知低減に効く検証のみ / **高信頼**: テストファースト+単体・結合・lint・型検査
  4. 関連する未検証仮定(assumptions.mdから)。実装中に新たな仮定を置いた場合は報告させる
  5. 出力要求(変更ファイル一覧・検証結果・未解決事項・新規仮定をテキストで報告)
  6. 禁止事項: **gitコミット禁止**、要件の再定義禁止、否定リスト該当の自律判断禁止、`~/.claude/`・`.claude/` 配下への接触禁止
- 完了後の受け入れ — **MVP**: codexの自己検証報告を確認する(diff精読はしない)。**高信頼**: diffと検証結果を確認する。不合格なら具体的な指摘とともに再実行させる。報告された新規仮定は assumptions.md に追記する。call-logに記録(codex)。
- 実装・設計上の主要判断は随時 `milestones/<n>-<名前>/decisions.md`(`templates/decisions.md` の形式)に追記する(要件由来とAgent仮説を区別する)。

**B-4 エスカレーション(必要時のみ)**
policy.md の発火条件(否定リスト該当・ユーザー固有判断・Solution分岐・低確信を含む10件)を検出したら、`templates/escalation.md` の1〜6を整形し、Agentツール(model: fable、新規インスタンス)に goal-frame.md + 1〜6 + 関連する未検証仮定(assumptions.mdの該当行、あれば) + hearing-log.md の関連部分(あれば)を渡す。Fableは7(判定)に **DECIDE**(判断+根拠)または **ASK_HUMAN**(人間向け質問文)を記入する。ASK_HUMANの場合はOpusが人間へ提示し、回答を hearing-log.md に追記してから続行する。文書を milestone ディレクトリに `escalation-<連番>.md` として保存し、call-logに記録。

**B-5 レビューとSubmission作成(Opus)**
- **MVP**: Opusメインが**セルフチェック**(goal-frame承認基準との対応・残存未知の列挙・未検証仮定の確認)を行い、`decisions.md` の4区分(要件由来 / Agent仮説HOW / 低確信 / 発見された未知)を確定させ、`templates/approval-submission.md` に従い `milestones/<n>-<名前>/submission.md` を作成する(判断記録欄から decisions.md を参照)。
- **高信頼**: Agentツール(model: opus)で**実装に関与していない**独立レビューア(PL-003)を起動し、goal-plan.md該当部・マイルストーン定義・diff・検証証拠を渡してレビューさせ、結果を反映してsubmissionを作成する。call-logに記録(opus-sub)。
- どちらの場合も**残存未知リスト・仮定台帳サマリ・decisions.mdの確定**を必須とする(欠けたままB-6へ進まない)。

**B-6 Implementation Gate(ゲートFable・新規インスタンス)**
前提確認: submission.md が存在し、検証証拠と残存未知リストが含まれること。
共通契約に従い goal-frame.md + マイルストーン定義 + submission.md + assumptions.md の未検証仮定を渡し、判定観点で「このマイルストーンのゴールを満たし、残存未知が許容可能か」を判定させる。結果を `gate-decision.md` に保存、call-logに記録。
- PASS + **MVPの非Checkpointマイルストーン** → **中間クローズ**: grareco-input.md作成+グラレコ生成(失敗は非ブロック)→ 中間コミット → state.md を次マイルストーンへ更新し、**人間承認なしで次のB-1へ**
- PASS + Checkpointマイルストーン(MVP)または高信頼 → state.md を human-acceptance に更新し、B-7へ
- REVISE / REPLAN → 指定された工程へ差し戻す(対象の未知・仮定が指定される。人間へは出さない)
- BLOCKED → 人間へ質問して停止

**B-7 Human Review Report=評価パッケージ(Opus)**
`templates/human-review-report.md` に従い `human-report.md` を作成する。
- **MVP**: 対象は**前回Checkpoint以降の全マイルストーン**。各マイルストーンの decisions.md を「3.5 判断の内訳」に集約する(Agent仮説HOW・低確信・実装対象外・新しく発見された未知を含む)。
- **高信頼**: 従来通り対象マイルストーン単体。
受け入れテスト手順は人間が1回のテストで確認できる具体性で書く。

**B-8 Human Acceptance(人間)**
human-report.md を人間に提示し、受け入れテストを依頼する(MVPはCheckpoint単位)。結果を `acceptance.md` に記録する(ACCEPT / REJECT + コメント)。**フィードバックから新たに発見された未知・要望は assumptions.md に追記する**(次ループの入力)。ACCEPTの場合は state.md を finalization に更新する。

**B-9 REJECT処理(Fable)**
REJECTの場合、Agentツール(model: fable、新規インスタンス)に goal-frame.md + human-report.md + REJECT理由を渡し、戻り先(タスク修正 / **Checkpoint配下の任意マイルストーン** / マイルストーン再計画 / ゴール再確認)を決定させる。REJECT理由から発見された未知は assumptions.md に追記する。決定に従い該当フェーズへ戻り、戻り先に応じて state.md を更新する。call-logに記録。

**B-10 確定処理(Opus)**
acceptance.md に ACCEPT があることを確認してから、Checkpoint範囲(前回Checkpoint以降の中間コミットを含む)を確定として扱い、未コミット分を確定コミットする。state.md を learning へ更新する。

## Learning フェーズ

1. **Retrospective(Opus)**: `templates/retrospective-note.md` に従い `retro.md` を作成する(**MVP: Checkpoint単位** — 対象は前回Checkpoint以降の全マイルストーン / **高信頼**: マイルストーン単位)。観測欄に、ループ回数(REVISE/REPLAN差し戻し数)・呼び出し数(call-log.mdから)・主要フェーズ所要時間(call-logの時刻から概算)・**発見された未知**を記載する(5:1目安はワークフローB以降、ハード制限ではない)。「再利用できる知見・テンプレート候補」に「なし」以外を書いた場合、**このプロジェクトの外でも効くもの**は orca-meta の MCP tool `record_lesson` で送る(軸は person / agent / method。orca-meta プラグインが導入されていない環境では省略してよい)。
2. **グラレコ(Codex経由)**: human-report.md / gate-decision.md / retro.md の要点を `grareco-input.md` にまとめ、`templates/grareco-prompt.md` の指示文を埋めて `codex exec` に渡す(MVPの非Checkpoint分はB-6中間クローズで生成済みのため、ここではCheckpointマイルストーン分を生成する)。生成失敗時は grareco-input.md を残したまま先へ進む(ループ完了をブロックしない)。call-logに記録(codex)。
3. **次へ**: 未実装マイルストーンがあれば state.md を milestone-implementation に戻し(「次のCheckpoint」欄を更新)、B-1 から繰り返す。全マイルストーン完了なら state.md を done にし、ゴール全体の完了を人間に報告する。

## 例外・停止時の扱い

- どのフェーズでも、人間の入力が必要になったら state.md の「待ち」に内容を書いてから停止する。
- セッションが切れても、次回 `/r-super-loop-powers` 起動時に state.md から再開できる(NFR-04)。代理Fableのインスタンスはセッションを跨いで継続できないため、再開後に代理Fableが必要になった場合は、goal-seed / goal-frame / hearing-log を渡して新しい代理Fableを起動する(記録がある限り文脈は復元できる)。
- このスキルは Superpowers・gstack等の他スキルのファイルを読むことはあっても、**変更してはならない**(SK-001)。
`````

- [ ] **Step 2: 検証**

Run: `head -4 skills/r-super-loop-powers/SKILL.md && grep -c "^## " skills/r-super-loop-powers/SKILL.md && grep -c "ASK_HUMAN" skills/r-super-loop-powers/SKILL.md && grep -c "decisions.md" skills/r-super-loop-powers/SKILL.md`
Expected: frontmatterに `name: r-super-loop-powers`、見出し `11`(起動時チェック/ディレクトリ契約/フェーズと成果物契約/仮定台帳の運用/記録ルール/ゲート保護ルール/Fable共通契約/ワークフローA/ワークフローB/Learning/例外)、ASK_HUMAN言及 `4以上`、decisions.md言及 `6以上`

- [ ] **Step 3: コミット**

```bash
git add skills/r-super-loop-powers/SKILL.md
git commit -m "feat: SKILL.mdをMVPモードのHOW委任対応に改訂(A-1a/A-1b・代理ブレスト・Checkpoint分岐)(v0.3)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QSS8FQBndgBiEVBHahCXQG"
```

---

### Task 5: README改訂 + バージョン更新

**Files:**
- Modify: `README.md`(全置き換え)
- Modify: `.claude-plugin/plugin.json`(versionのみ変更)

**Interfaces:**
- Consumes: Task 1〜4の用語(hearing-log / 代理Fable / Checkpoint / decisions.md / ASK_HUMAN / 評価パッケージ)

- [ ] **Step 1: README.md をファイル全体で以下の内容に置き換える**

````markdown
# r-super-loop-powers

Superpowersの上位に薄く重なる**ゴールループ・オーケストレーション層**。

Goal Loopの目的は **A. 要件適合性**(作りたかったものを正しく作れているか)と **B. 未知の低減**(最初には分からなかった正解を、作りながら発見する)の2つ。品質最大化・速度最大化は目的ではない。AIが未知に仮説を立てて評価可能な具体物まで作り、人間は評価とフィードバックを担う。作業そのものの進め方はSuperpowersに委ね、内部には一切干渉しない。

MVPモード(v0.3)では、人間にHOW(UI・機能構成・実装方式)の確定を求めない。開始前のFableヒアリングでゴール・文脈・暗黙の期待(無自覚の既知)を表面化し、HOWはAgentが仮説化して自律的に実装・評価する。Human Feedbackは定期ゲートではなくエスカレーション(ASK_HUMAN)であり、人間の受け入れは**Checkpoint**(ユーザー価値がEnd-to-Endで成立した点)でのみ行う。

```
人間  ──(Goal Seed / ヒアリング回答 / 強度確定 / ASK_HUMAN応答 / Checkpoint評価)──┐
                                                                                │
┌───────────────────────────────────────────────────────────────────────────────▼┐
│ r-super-loop-powers(責任・ゲート層)                                            │
│  フェーズ / 成果物契約 / Fableゲート / HITL                                    │
│  ヒアリング / 代理ブレスト / Checkpoint / 仮定台帳 / 判断記録                  │
├────────────────────────────────────────────────────────────────────────────────┤
│ Superpowers(実行プロセス層)                                                    │
│  brainstorming / writing-plans / TDD ...                                       │
└────────────────────────────────────────────────────────────────────────────────┘
  実行: Opusメイン  判定・代理: Fableサブ  実装: codex exec
```

## ループ強度

- **MVP(既定)**: Fableヒアリング → HOW委任(Fable代理ブレスト) → マイルストーン自律進行(Fableゲート+中間コミット) → Checkpointでのみ評価パッケージ+Human Acceptance。人間の関与は「ヒアリング回答 / Goal Frame確定 / Goal Plan承認(WHATレベル) / ASK_HUMAN応答 / Checkpoint受け入れ」の5点
- **高信頼**: 人間参加のブレスト・タスク分解・diff確認・独立レビュー・フルテスト・マイルストーン毎Acceptance
- Goal Frame作成時にFableが提案し、人間が確定する。FableゲートとHuman Acceptanceは両強度で維持される

## 前提

- Claude Code + Superpowersプラグイン(改造不要)
- Codex CLI(`codex login` 済み。モデル等は `~/.codex/config.toml` に従う)
- 対象プロジェクトによっては Codex の `trust_level` 設定(`~/.codex/config.toml` の `[projects]`)が必要になる場合がある
- メインセッションは **`/model opus`** で運用する(Fable消費をヒアリング・代理回答・承認ゲートに限定するため)

## インストール

```
/plugin marketplace add C:\Users\makyu\Desktop\project\r-super-loop-powers
/plugin install r-super-loop-powers@r-super-loop-powers-marketplace
```

インストール後、Claude Codeを再起動し、スキル一覧に `r-super-loop-powers` が出ることを確認する。

## 使い方

- **新規ゴール**: 対象プロジェクトで `/r-super-loop-powers` を起動し、やりたいこと(Goal Seed)を伝える
- **再開**: 同じコマンドで起動すると `docs/r-super-loop-powers/*/state.md` から現在地を復元する

フェーズの流れ(MVP): ヒアリング(Fable往復・無自覚の既知の表面化) → Goal Frame(強度確定) → ブレスト/Spec/Plan(Fable代理回答・Checkpoint配置) → Goal Gate(Fable) → 人間承認(WHATレベル) → マイルストーン自律実装(codex exec → Fableゲート → 判断記録+グラレコ+中間コミット) → Checkpoint: 評価パッケージ → 人間受け入れ → 確定 → 振り返り

## E2Eテスト(導入・改訂時に1周まわす)

小さなプロジェクトで1ゴール(中間マイルストーン1つ以上+Checkpoint1つ以上)を実行し、以下を確認する:

- [ ] state.md 不在時に新規ゴール開始フローに入る
- [ ] MVP選択時、A-1aでFable駆動のヒアリング往復が行われ、hearing-log.md に記録される
- [ ] ヒアリングの質問にHOW質問(UI形式・実装方式の選択)が含まれない
- [ ] goal-frame.md に「ヒアリングで表面化した既知」があり、ループ強度が提案→人間確定される
- [ ] MVPのブレスト(A-2〜A-4)で設計質問・設計承認が代理Fableに向かい、人間にはASK_HUMAN該当のみ届く
- [ ] goal-plan.md にCheckpoint印と主要設計判断欄があり、最終マイルストーンがCheckpointである
- [ ] Goal Gate が代理Fableとは別の新規Fableインスタンスで行われ、PASSするまで人間承認を求められない
- [ ] A-8で人間に提示されるのがWHATレベル(ゴール・要件・制約・Checkpoint配置・主要仮定)である
- [ ] codex exec がコミットを作らない
- [ ] 非Checkpointマイルストーンで B-6 PASS後、人間承認なしで次マイルストーンへ進む(decisions.md・グラレコ・中間コミットが残る)
- [ ] Checkpoint到達時のみ評価パッケージ(human-report.md)とHuman Acceptanceが行われる
- [ ] 評価パッケージに各マイルストーンの decisions.md 集約(Agent仮説HOW / 低確信 / 実装対象外 / 新発見の未知)がある
- [ ] エスカレ判定が DECIDE / ASK_HUMAN の2値で返り、ASK_HUMANのみ人間へ届く
- [ ] Checkpoint の ACCEPT 記録前に確定処理が行われない(中間コミットは可)
- [ ] 人間フィードバックで発見された未知が assumptions.md に追記される
- [ ] retro.md がCheckpoint単位で作成され、ループ回数・所要時間・発見された未知が記録される
- [ ] call-log.md に fable往復 / opus-sub / codex の呼び出しが記録されている
- [ ] grareco.png が組み込み image_gen ツールで生成される(スクリプト・APIキー使用なし)
- [ ] セッションを切って再起動 → state.md から現在地が復元される
- [ ] 高信頼強度ではv0.2のフロー(人間参加ブレスト・マイルストーン毎Acceptance)が維持される

## リポジトリ構成

- `.claude-plugin/` — プラグインマニフェスト・マーケットプレイス定義
- `skills/r-super-loop-powers/` — SKILL.md(オーケストレーター) / policy.md(運用ポリシー) / templates/(9種)
- `docs/superpowers/specs/` — 設計仕様書
- `docs/superpowers/plans/` — 実装計画
````

- [ ] **Step 2: plugin.json のversionを変更**

`.claude-plugin/plugin.json` の `"version": "0.2.0"` を `"version": "0.3.0"` に変更する(他は触らない)。

- [ ] **Step 3: 検証**

Run: `python -m json.tool .claude-plugin/plugin.json > /dev/null && grep '"version"' .claude-plugin/plugin.json && grep -c "Checkpoint" README.md`
Expected: JSONパース成功、`"version": "0.3.0"`、`10以上`

- [ ] **Step 4: コミット**

```bash
git add README.md .claude-plugin/plugin.json
git commit -m "docs: READMEをv0.3(MVPモードのHOW委任・Checkpoint・E2E20項目)に更新、version 0.3.0

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QSS8FQBndgBiEVBHahCXQG"
```

---

### Task 6: 全体整合検証

**Files:**
- Modify: なし(検証のみ。問題があれば該当ファイルを修正)

**Interfaces:**
- Consumes: Task 1〜5の全成果物

- [ ] **Step 1: ファイル・構造検証**

Run: `ls skills/r-super-loop-powers/templates/ | sort && grep -c "^## " skills/r-super-loop-powers/policy.md && grep -c "^## " skills/r-super-loop-powers/SKILL.md`
Expected: テンプレート9ファイル(approval-submission / assumptions / decisions / escalation / goal-frame / grareco-prompt / hearing-log / human-review-report / retrospective-note)、policy見出し `10`、SKILL見出し `11`

- [ ] **Step 2: 名称・表記の統一検証**

Run: `grep -rn "goal-loop" skills/ .claude-plugin/ README.md || echo "ALL CLEAN"` および `grep -rn "チェックポイント" skills/ README.md || echo "NO_KATAKANA"`
Expected: `ALL CLEAN` と `NO_KATAKANA`(Checkpoint表記の統一)

- [ ] **Step 3: クロスリファレンス検証**

以下を目視確認(それぞれの参照元と参照先が一致すること):
1. SKILL.mdが参照するテンプレート名9種が `templates/` の実ファイル名と一致
2. policy.mdの強度別工程表とSKILL.mdのA-1a/A-2〜A-4/B-6/B-7の強度分岐が矛盾しない(MVP=ヒアリング・代理ブレスト・Checkpoint時のみB-7 / 高信頼=v0.2フロー)
3. エスカレの2値(DECIDE / ASK_HUMAN)が policy.md・escalation.md・SKILL.md(A-2〜A-4 / B-4)で同一表記
4. decisions.md の4区分(要件由来の決定 / Agentが仮説として決めたHOW / 低確信の判断 / 発見された未知)が templates/decisions.md・SKILL.md B-5・human-review-report.md 3.5 で整合
5. spec §7の受け入れ基準のうち静的に確認可能な項目: 2(ヒアリング指示にHOW質問禁止が明記)、3(ASK_HUMAN中継の仕組み)、4(ゲートFable新規インスタンス+SK-007の7)、5(A-8のWHATレベル限定)、6(Checkpoint印必須+最終マイルストーン)、7(B-6中間クローズ)、8(B-7の集約)、9(2値判定)、10(高信頼分岐が全工程で「従来通り」)
6. state.md フォーマットの「次のCheckpoint」欄が SKILL.md 内の全記載(フォーマット定義・A-8・Learning 3)で一貫

- [ ] **Step 4: 最終コミットと引き渡し**

```bash
git add -A
git commit -m "chore: v0.3.0 整合検証完了

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QSS8FQBndgBiEVBHahCXQG" --allow-empty
git log --oneline main..HEAD
```

ユーザーへの案内: PR作成 → マージ → `/plugin` でプラグイン更新(または marketplace update)→ Claude Code再起動 → **新規の小規模プロジェクトをMVP強度で開始**し、ヒアリング→代理ブレスト→中間マイルストーン1つ以上+Checkpoint1つ以上を完走してREADMEのE2E 20項目を照合する(spec §8)。

---

## Self-Review 結果

- **Spec coverage**: D21(人間関与5点→policy責任分担/README)、D22(Checkpoint→policy「Checkpointとマイルストーン粒度」/goal-plan印/submission配置欄/B-6分岐)、D23(ヒアリング→A-1a/hearing-log.md/工程表)、D24(代理ブレスト→A-2〜A-4/責任分担/呼ぶ場面3)、D25(インスタンス分離→Fable共通契約/ゲート保護7/A-6・B-6「新規インスタンス」)、D26(WHATレベル→A-8/工程表)、D27(エスカレ→発火条件8〜10/escalation.md 7/B-4)、D28(decisions.md→テンプレ/B-2〜B-3/B-5)、D29(評価パッケージ→human-review-report/B-7)、D30(コミット規律→SK-009/B-6中間クローズ/B-10/工程表)、D31(Learning再配置→Learning 1〜2/retroテンプレ)、D32(A段階記録→goal-plan主要設計判断/hearing-log追記/記録ルール)、D33(5:1→PL-007/retro観測)。spec §6の12アーティファクトすべてにタスクあり(§6.12のmarketplace.jsonはversionフィールド非保持のため変更なしと明記)。
- **Placeholder scan**: なし。テンプレート内の `<...>` は成果物の記入欄。
- **型整合**: エスカレ2値(DECIDE/ASK_HUMAN)・ゲート4値・decisions.md 4区分・テンプレ名9種・見出し数(goal-frame 9 / policy 10 / SKILL 11)・state.md「次のCheckpoint」欄をTask間で一致させた。
