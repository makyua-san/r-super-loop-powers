# r-super-loop-powers v0.2 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Goal Loopの目的をA(要件適合性)+B(未知低減)に再定義し、ループ強度(MVP/高信頼)・仮定台帳・工程の軽量化をプラグインに実装する。

**Architecture:** 既存プラグインのMarkdown成果物の改訂(6ファイル)+新規テンプレート1つ+バージョン更新。実行コードなし。改訂対象ファイルは各タスクに**改訂後の完全な内容**を記載し、実装者はファイル全体を置き換える(部分編集のアンカーずれを防ぐ)。

**Tech Stack:** Markdown / JSON。Claude Codeプラグイン形式。

**Spec:** `docs/superpowers/specs/2026-08-10-r-super-loop-powers-v0.2-design.md`(以下「spec」。前版v0.1 specの決定はspecに書かれた差分以外有効)

## Global Constraints

- 作業ブランチ: `feature/v0.2-goal-loop-redefinition`(作成済み。このブランチ上で作業)
- 名称はすべて `r-super-loop-powers` で統一。`goal-loop` という文字列を新規内容に書かない。
- Superpowers本体には一切触れない。スクリプト・hooksを追加しない。
- ゲート4値は `PASS / REVISE / REPLAN / BLOCKED` 固定。
- ループ強度の表記は `MVP` / `高信頼` の2値で統一(「標準」を作らない)。
- 各ファイル末尾に改行を1つ入れる。日本語で記述。
- コミットメッセージ末尾: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- 「ファイル全体を以下の内容に置き換える」と指示されたタスクでは、内容を一字一句そのまま書く(勝手な改善をしない)。
- 作業ディレクトリ: `C:\Users\makyu\Desktop\project\r-super-loop-powers`

## ファイル構成(このプランで触るもの)

| ファイル | 変更 | 責務 |
|---|---|---|
| `skills/r-super-loop-powers/templates/goal-frame.md` | 改訂 | 強度・未知マップ・終了条件を追加 |
| `skills/r-super-loop-powers/templates/assumptions.md` | **新規** | 仮定台帳(D12) |
| `skills/r-super-loop-powers/templates/approval-submission.md` | 改訂 | 残存未知リスト・台帳サマリ(D16) |
| `skills/r-super-loop-powers/templates/human-review-report.md` | 改訂 | 判断の内訳(D17) |
| `skills/r-super-loop-powers/templates/retrospective-note.md` | 改訂 | 観測拡張・発見された未知(D18) |
| `skills/r-super-loop-powers/policy.md` | 全面改訂 | 上位原則・強度・否定リスト(D10/11/13/15) |
| `skills/r-super-loop-powers/SKILL.md` | 全面改訂 | 強度分岐・台帳運用・終了判定(D14/16/19) |
| `README.md` | 改訂 | 上位原則・強度・E2E更新 |
| `.claude-plugin/plugin.json` | 1行変更 | version 0.2.0 |

---

### Task 1: 入口系テンプレート(goal-frame改訂 + assumptions新規)

**Files:**
- Modify: `skills/r-super-loop-powers/templates/goal-frame.md`(全置き換え)
- Create: `skills/r-super-loop-powers/templates/assumptions.md`

**Interfaces:**
- Produces: goal-frame.mdの見出し「ループ強度」「未知マップ」「終了条件(残存未知の許容基準)」、assumptions.mdの7列表形式(ID/仮定内容/確信度/根拠/ゴールへの寄与/検証方法/状態)。Task 3〜4がこれらの見出し・列名をそのまま参照する。

- [ ] **Step 1: goal-frame.md をファイル全体で以下の内容に置き換える**

````markdown
# Goal Frame — <goal-slug>

<!-- 作成者: Fable(入口の責任設定)。このフレームは後でFable自身がゲート判定の基準として使う。 -->

## ゴールの方向
<Goal Seedから読み取った、このゴールが達成すべき本質的な価値。1〜3行>

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

- [ ] **Step 2: assumptions.md を新規作成**

````markdown
# Assumptions — <goal-slug> 仮定台帳

<!-- 全フェーズで追記可。ブレスト中の未回答質問、実装中の仮説判断、Human Feedbackで発見された未知をここに集約する。 -->
<!-- policy.md「仮説自律の否定リスト」に触れる仮定は自律実行せず、エスカレーションまたは人間確認へ。 -->

| ID | 仮定内容 | 確信度 | 根拠 | ゴールへの寄与 | 検証方法 | 状態 |
|---|---|---|---|---|---|---|
| A1 | <仮定> | <高・中・低> | <なぜそう仮定したか> | <この仮定がゴール達成にどう効くか1行> | <どう検証するか> | <未検証・検証済み・棄却> |

<!-- 状態の運用: 実装・評価で確認できたら「検証済み」、誤りと判明したら「棄却」にし、必要なら新しい仮定を起こす。 -->
````

- [ ] **Step 3: 検証**

Run: `grep -c "^## " skills/r-super-loop-powers/templates/goal-frame.md && grep -c "ゴールへの寄与" skills/r-super-loop-powers/templates/assumptions.md`
Expected: `8`(ゴールの方向/ループ強度/制約/確定すべきこと/未知マップ/承認基準/終了条件/参照した学習メモ)と `1`

- [ ] **Step 4: コミット**

```bash
git add skills/r-super-loop-powers/templates/goal-frame.md skills/r-super-loop-powers/templates/assumptions.md
git commit -m "feat: goal-frameに強度・未知マップ・終了条件を追加、仮定台帳テンプレートを新設

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: 提出・報告系テンプレート改訂(approval-submission / human-review-report / retrospective-note)

**Files:**
- Modify: `skills/r-super-loop-powers/templates/approval-submission.md`(全置き換え)
- Modify: `skills/r-super-loop-powers/templates/human-review-report.md`(全置き換え)
- Modify: `skills/r-super-loop-powers/templates/retrospective-note.md`(全置き換え)

**Interfaces:**
- Consumes: Task 1のassumptions.md(ID参照の記法)
- Produces: submissionの見出し「残存未知リスト」「仮定台帳サマリ」、reportの見出し「3.5 判断の内訳」、retroの見出し「発見された未知」。Task 3〜4が参照する。

- [ ] **Step 1: approval-submission.md をファイル全体で以下の内容に置き換える**

````markdown
# Approval Submission — <goal-slug> / <対象: Goal Plan | Milestone n>

<!-- 作成者: Opus。Fableゲートへの提出物。生コード・全会話は含めない(PL-009)。 -->

## 元ゴールと対象
- Goal Frame: <goal-frame.mdの「ゴールの方向」を1行で再掲>
- 対象: <Goal Plan全体 | Milestone n: 名前>
- ループ強度: <MVP | 高信頼>

## 変更の要約(最大5項目)
1. <要約1>

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

- [ ] **Step 2: human-review-report.md をファイル全体で以下の内容に置き換える**

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

## 3.5 判断の内訳
- **確定(検証済み)**: <テスト・実行で確認済みの事項>
- **要件から直接導出**: <Goal Frame・要件に明記されていた事項>
- **仮説による決定**: <AIが仮定して決めた事項。assumptions.md のID参照>
- **低確信・要確認**: <特に人間に評価してほしい点>

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

- [ ] **Step 3: retrospective-note.md をファイル全体で以下の内容に置き換える**

````markdown
# Retrospective — <goal-slug> / Milestone <n>

<!-- 作成者: Opus(Human ACCEPT + 確定コミット後)。次回のGoal Frame作成時に自動参照される。短く保つ。 -->

## うまく機能したこと(最大3点)
- <...>

## 無駄だった呼び出し・手戻り(最大3点)
- <...>

## 次回変えること(最大3点)
- <...>

## 発見された未知
- <このマイルストーンで新たに既知化された未知・学び。次回の入力になる。なければ「なし」>

## 再利用できる知見・テンプレート候補
- <なければ「なし」>

## 観測
- ループ回数: <Fableゲート差し戻し(REVISE/REPLAN)の回数を含む>
- 呼び出し概算: opus-sub <n>回 / codex <n>回 / fable <n>回(目安 Opus:Fable ≈ 5:1)
- 主要フェーズ所要時間: <call-log.mdの時刻から概算(実装 / ゲート / レポート等)>
- 特記: <比率が大きく外れた場合の理由。なければ「なし」>
````

- [ ] **Step 4: 検証**

Run: `grep -c "残存未知リスト" skills/r-super-loop-powers/templates/approval-submission.md && grep -c "判断の内訳" skills/r-super-loop-powers/templates/human-review-report.md && grep -c "発見された未知" skills/r-super-loop-powers/templates/retrospective-note.md`
Expected: `1` `1` `1`

- [ ] **Step 5: コミット**

```bash
git add skills/r-super-loop-powers/templates/
git commit -m "feat: submission残存未知リスト、レポート判断の内訳、retro観測拡張を追加

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: policy.md 全面改訂

**Files:**
- Modify: `skills/r-super-loop-powers/policy.md`(全置き換え)

**Interfaces:**
- Consumes: Task 1〜2の見出し名(assumptions.md / 残存未知リスト)
- Produces: 見出し「上位原則(Goal Loopの目的)」「ループ強度」「仮説自律の否定リスト」と強度別工程表。Task 4のSKILL.mdがこの表と否定リストを参照する。`## ` 見出しは10個。

- [ ] **Step 1: policy.md をファイル全体で以下の内容に置き換える**

````markdown
# r-super-loop-powers モデル運用ポリシー

上位要件: `goal_engineering_ai_skill_policy_requirements.docx` 5章・11章・12章・14章、および `20260810_ハーネス改善-1.md`(v0.2の入力)。
本ポリシーは SKILL.md(オーケストレーター)から参照される。数値・比率は観測指標であり、品質や安全に必要な判断を妨げない。

## 上位原則(Goal Loopの目的)

Goal Loopの目的は次の2つであり、品質最大化・速度最大化は目的ではない。

- **A. 要件適合性**: 定義したゴール・要件・制約に成果物が適合している確度を高める。「コードが動く」ではなく「作りたかったものを正しく作れているか」
- **B. 未知の低減**: 開始時に認識できなかった未知(特に無自覚の未知)を、仮説→実装→評価のループで発見・既知化する

AIは未知に対して可能な限り自律的に仮説を立て、人間が評価可能な具体物まで精度を高めてから提示する。人間の役割は生成より評価。**ループ・テスト・レビュー・承認は、それ自体を目的とせず、AまたはBに寄与する場合にのみ実施する**(工程の存在理由テスト)。ループ終了条件は回数ではなく「適合性への十分な確信 + 残存する重要な未知が許容可能」。

## ループ強度

**MVP(既定)** と **高信頼** の2段階。Goal Frame作成時にFableが提案し、人間がGoal Frame確認時に確定する。マイルストーン単位の一時変更は人間が指示できる。FableゲートとHuman Acceptanceは両強度で維持する(要件適合性の保証線)。

| 工程 | MVP(既定) | 高信頼 |
|---|---|---|
| Goal Frame / Goal Gate | 実施(未知マップ+強度+終了条件を含む) | 同左 |
| マイルストーン開始確認(Fable) | 実施(軽量) | 同左 |
| 実装委譲 | E2E価値単位でまとめて codex exec に委譲可(タスク細分化しない) | タスク分解して個別に委譲 |
| タスク単位の受け入れ | codex自己検証報告の確認のみ(diff精読なし) | Opusメインがdiffを確認 |
| テスト要求 | 受け入れ基準に直結する検証+未知低減に効く検証のみ | 単体・結合・lint・型検査をフル要求 |
| 独立レビュー | 省略(Opusメインがsubmission作成時にセルフチェック) | Opusサブで実施(PL-003) |
| Implementation Gate(Fable) | 実施(適合性+残存未知の許容性) | 同左 |
| Human Report / Acceptance | 実施(判断の内訳つき) | 同左 |
| Learning(Retro+グラレコ) | 実施(グラレコ失敗は非ブロック) | 同左 |

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
| 人間 | 意図の提示、具体物の評価とフィードバック、最終受け入れ、優先順位判断 | Goal Seed入力、ループ強度の確定、受け入れテスト | 生diffの最初からの精読を前提にしない。答えを持たない問いへの回答を強制されない |
| Fable | 全体責任者。入口の基準設定(Goal Frame・強度提案)、マイルストーン開始確認、承認ゲート(適合性+残存未知の許容性+仮定の事実扱いチェック)、エスカレーション判断、Human REJECT後の戻り先決定 | サブエージェントとしてのみ起動 | ブレスト・仕様・実装・レポートの本文作成 |
| Opus | メインセッション。整理・仕様化・計画・仮定台帳の管理・承認資料・人間向けレポート・振り返り・確定処理。高信頼強度では独立レビュー(サブ) | 常駐 | ゴール変更の独断確定 |
| Codex | 実装担当(`codex exec`)。コード変更、検証、自己検証報告 | E2E価値単位(MVP)またはタスク単位(高信頼)で呼び出し | コミット、要件の再定義、否定リスト該当の自律判断 |
| 画像生成(Codex組み込み image_gen ツール) | グラフィックレコード | Learning フェーズで呼び出し | 未承認状態を確定として描かない。APIキー・スクリプト経由の生成はしない |
| Sonnet | 将来枠(未使用)。軽量探索・補助実装の候補 | — | 必須モデルとして固定しない |

## Fableを呼ぶ場面(これ以外では呼ばない)

1. ループ開始時: Goal Seedから Goal Frame(方向・制約・未知マップ・承認基準・終了条件・強度提案)を定義するとき
2. マイルストーン開始時: 対象マイルストーンが上位ゴールのどの成果を満たすかを確認するとき(注意点のみの軽量呼び出し)
3. 承認ゲート: Approval Submission が揃い、PASS/REVISE/REPLAN/BLOCKED を判定するとき
4. エスカレーション: 実行担当が「エスカレーション発火条件」を検出したとき
5. Human REJECT後: 戻り先(修正 / 再計画 / ゴール修正)を決定するとき

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
| PL-003 | Independent review | **高信頼強度では**、Fable提出前に実装非関与のOpusサブエージェントが独立レビューする。MVP強度ではOpusメインのセルフチェックで代替する |
| PL-004 | Evidence first | 承認要求には検証証拠・残存未知リスト・未解決事項を必ず含める。推測だけでPASSを求めない |
| PL-005 | Human after AI gate | 人間受け入れはFable PASS後に行う |
| PL-006 | Human rejection routing | Human REJECTはFableへ戻し、戻り工程をFableが決める |
| PL-007 | Budget observability | fable / opus-sub / codex の呼び出しを call-log.md に記録し、Opus:Fable ≈ 5:1 を目安に振り返る |
| PL-008 | No forced ratio | 比率は目標であり、品質や安全に必要なFable呼び出しを禁止しない |
| PL-009 | Context minimization | Fableへは goal-frame + 対象文書 + 仮定台帳の関連部分のみを渡す。全コード・全会話を常時ロードしない |
| PL-010 | Human cognitive load | 人間向け成果物は、ゴール → 結果 → 証拠 → リスク → 確認手順の順で構造化し、確定事項と仮説による決定を区別する(判断の内訳) |

## エスカレーション発火条件(いずれかを検出したらFableへ)

1. 仕様 / Goal Plan 内に矛盾または複数解釈があり、実装選択でユーザー価値が変わる
2. 承認済み設計を変更しないと実装できない
3. 複数マイルストーンや広い影響範囲をまたぐ設計変更が必要
4. テストを繰り返しても原因が特定できず、計画自体の見直しが必要
5. 安全性・データ破壊・互換性など重大リスクを検出
6. 人間が示した Goal Seed と現在の作業がズレている疑いがある
7. 立てるべき仮説が「仮説自律の否定リスト」に触れる

形式は `templates/escalation.md` の6点フォーマットを用いる。

## マイルストーン粒度ガイドライン

- 1マイルストーン = 「**ユーザーが1つの価値をEnd-to-Endで利用できる**」単位
- 人間の受け入れテスト1回で確認できる範囲に収める(時間の上限・下限は定めない)
- 技術タスク単位への細分化はしない

## 観測

- call-log.md 形式: `YYYY-MM-DD HH:MM | fable|opus-sub|codex | フェーズ | 目的`(1呼び出し1行)
- Opusメインセッション自身の消費は記録対象外(常駐のため)
- Retrospective 作成時に、呼び出し比率(5:1目安)に加えて、ループ回数・主要フェーズ所要時間(call-logの時刻から概算)・発見された未知を記載する。ハード制限にしない(PL-008)
````

- [ ] **Step 2: 検証**

Run: `grep -c "^## " skills/r-super-loop-powers/policy.md && grep -c "MVP(既定)" skills/r-super-loop-powers/policy.md`
Expected: `10`(上位原則/ループ強度/否定リスト/責任分担/呼ぶ場面/呼ばない場面/運用ポリシー/エスカレーション/粒度/観測)と `2以上`

- [ ] **Step 3: コミット**

```bash
git add skills/r-super-loop-powers/policy.md
git commit -m "feat: policyに上位原則・ループ強度・仮説自律の否定リストを追加(v0.2)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: SKILL.md 全面改訂

**Files:**
- Modify: `skills/r-super-loop-powers/SKILL.md`(全置き換え)

**Interfaces:**
- Consumes: Task 1〜3の見出し名・列名(assumptions.md 7列 / 残存未知リスト / 判断の内訳 / policy.mdの強度表・否定リスト)
- Produces: `/r-super-loop-powers` の実行手順v0.2。`## ` 見出しは11個。

- [ ] **Step 1: SKILL.md をファイル全体で以下の内容に置き換える**

`````markdown
---
name: r-super-loop-powers
description: Use when starting or resuming a goal-engineering loop (ゴールループ / goal loop / ゴールエンジニアリング開発). Superpowersの上位で、要件適合性と未知低減を目的に、フェーズ管理・成果物契約・Fable承認ゲート・ヒューマン・イン・ザ・ループ配置・モデル責任分担(Opus実行 / Fable判定 / Codex実装)をオーケストレーションする。
---

# r-super-loop-powers — ゴールループ・オーケストレーター

あなた(このスキルを実行するモデル)は **Opusメインセッション** として、ゴールループの進行管理と成果物作成を担当する。
このスキルは **責任・ゲート層** である: いまどのフェーズか、次に必要な成果物は何か、誰が実行し誰が判定するか、人間へ返すタイミングだけを制御する。
作業の進め方(HOW)はSuperpowersのスキルに完全に委ね、その内部手順には一切干渉しない。

Goal Loopの目的は **A. 要件適合性** と **B. 未知の低減** の2つ(policy.md「上位原則」)。ループ・テスト・レビュー・承認は、AまたはBに寄与する場合にのみ実施する。ループ終了条件は回数ではなく「適合性への十分な確信 + 残存する重要な未知が許容可能」。

## 起動時チェック(毎回必ず実行)

1. **ポリシー読込**: このスキルと同じディレクトリの `policy.md` を読む。以後の全判断はこのポリシーに従う。
2. **モデル確認**: 自分がOpusで動いていない場合(特にFableの場合)、ユーザーに `/model opus` への切替を提案し、切替またはユーザーの明示的な続行指示があるまでフェーズ作業を開始しない(PL-002)。
3. **状態復元**: 対象プロジェクトで `docs/r-super-loop-powers/*/state.md` を探す(Globツール)。
   - 見つかった場合: 最新の state.md を読み、「現在フェーズ / 強度 / 対象マイルストーン / 次のゲート」を1〜3行でユーザーに報告し、そのフェーズの手順から再開する。
   - 見つからない場合: ワークフローA(新規ゴール)を開始する。
4. **強度確認**: goal-frame.md が存在する場合、ループ強度(MVP | 高信頼)を読み、policy.md「ループ強度」の工程表に従って以後の工程を実施する。強度未確定のままワークフローBへ進まない。

## ディレクトリ契約

対象プロジェクト内に次を作成・維持する:

```
docs/r-super-loop-powers/<goal-slug>/
├── state.md                 # 現在地(下記フォーマット)
├── goal-seed.md             # 人間の意図(原文のまま)
├── goal-frame.md            # Fable入口出力 = 承認基準・強度・未知マップ・終了条件の原本
├── assumptions.md           # 仮定台帳(全フェーズで追記)
├── goal-plan.md             # Superpowers spec/planへのリンク + マイルストーン一覧
├── goal-plan-submission.md  # A-5 Goal Plan承認用submission
├── goal-gate-decision.md    # A-6 Goal Gate判定
├── call-log.md              # 呼び出し記録(PL-007)
└── milestones/<n>-<名前>/
    ├── submission.md / gate-decision.md / human-report.md
    ├── acceptance.md / retro.md / grareco-input.md / grareco.png
    └── escalation-<連番>.md  # B-4発生時のみ
```

`<goal-slug>` はGoal Seedの内容から短いkebab-caseで命名する。

### state.md フォーマット

```markdown
# state — <goal-slug>
- phase: goal-definition | milestone-implementation | human-acceptance | finalization | learning | done
- 強度: MVP | 高信頼 | 未確定
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
| goal-definition | goal-seed.md | goal-frame.md(強度確定) → spec/plan → goal-plan.md → goal-plan-submission.md | Goal Gate(Fable)→ Human承認 |
| milestone-implementation | Goal Plan承認済み + 強度確定 | 実装diff + 検証証拠(高信頼のみ: 独立レビュー) → submission.md(残存未知リスト付き) | Implementation Gate(Fable) |
| human-acceptance | Fable PASS | human-report.md(判断の内訳付き) | 人間のACCEPT/REJECT |
| finalization | acceptance.md に ACCEPT | 確定コミット | なし |
| learning | 確定コミット済み | retro.md + grareco-input.md(+ grareco.png) | なし |

## 仮定台帳の運用

- `templates/assumptions.md` の形式で goal直下に置き、全フェーズで追記する。
- 追記のタイミング: (1) ブレスト中にユーザーが「決めていない / わからない」と答えたとき (2) 実装・設計で仮説的判断をしたとき (3) Human Feedbackで新しい未知が見つかったとき。
- 各仮定には「ゴールへの寄与」1行を必ず書く(局所最適化ガード)。
- **policy.md「仮説自律の否定リスト」に触れる仮定は自律実行しない** — エスカレーション(B-4)または人間確認へ。
- 検証されたら状態を「検証済み」または「棄却」に更新する。棄却時は必要なら新しい仮定を起こす。

## 記録ルール(PL-007)

fable / opus-sub(Opusサブエージェント) / codex を呼ぶたびに、直後に `call-log.md` へ1行追記する:
`YYYY-MM-DD HH:MM | fable|opus-sub|codex | フェーズ | 目的`

## ゲート保護ルール(絶対)

1. Fable PASS 前に人間へ受け入れを求めない(SK-007)
2. human-report.md なしで Human Acceptance に進まない(SK-008)
3. acceptance.md の ACCEPT なしで確定コミットしない(SK-009)
4. 必須成果物が欠けた状態でFableゲートを呼ばない — 欠落は自分で差し戻して埋める(NFR-05)
5. `codex exec` にコミットさせない
6. 否定リストに触れる仮説を自律実行しない — エスカレーションまたは人間確認へ

## Fableサブエージェント共通契約

- Agentツールで `model: "fable"` を指定して起動する。
- **初回入力は goal-frame.md 全文 + 対象文書(submission / escalation / milestone定義) + assumptions.md の関連部分(未検証仮定)のみ**。対象プロジェクトの生コード・全会話履歴を渡さない(PL-009)。
- Fableが追加資料を要求した場合のみ、SendMessageで1往復の追加提供を行う。
- ゲート判定の出力契約: `PASS | REVISE | REPLAN | BLOCKED` のいずれか1つ + 根拠(5行以内) + REVISE/REPLANの場合は戻り先工程と対象の未知・仮定。
- 判定観点(プロンプトに明記する): (1) goal-frame.md の承認基準を満たすか (2) 残存する重要な未知が許容可能か(goal-frameの終了条件と照合) (3) 仮定が事実として扱われていないか (4) 否定リスト違反の仮説がないか。「動くか」ではなくゴール整合を見る。

## ワークフローA: Goal Definition

**A-0 Goal Seed保存(Opus)**
ユーザーの「やりたいこと」を原文のまま `goal-seed.md` に保存する。要約・整形しない。`<goal-slug>` を決め、ディレクトリと state.md(phase: goal-definition, 強度: 未確定)、空の call-log.md、`templates/assumptions.md` の形式で空の仮定台帳を作成する。

**A-1 Goal Frame(Fable)**
直近の `docs/r-super-loop-powers/*/milestones/*/retro.md` を新しい順に最大3件読み、要点を抜粋する。
Agentツール(model: fable)に次を渡す:
- `templates/goal-frame.md` の構造
- goal-seed.md 全文
- retro抜粋(あれば)
- 指示: 「あなたはこのゴールの全体責任者。ゴールの方向・制約・今回確定すべきこと・未知マップ(既知の未知と無自覚の未知の探索方針)・承認基準・終了条件(残存未知の許容基準)を定義し、ループ強度(MVP | 高信頼)を理由付きで提案せよ。既定はMVP(品質最大化は目的ではない)。承認基準と終了条件は後であなた自身がゲート判定の基準として使う。検証可能な形で書け。」

出力を `goal-frame.md` に保存し、call-logに記録する。内容をユーザーに提示し、**ループ強度を確定**してもらい、方向のズレがないか確認する。確定した強度を goal-frame.md の「人間の確定」欄と state.md に記録する。

**A-2〜A-4 ブレスト → Spec → Plan(Opus + Superpowers)**
`superpowers:brainstorming` を起動し、その標準フロー(spec作成 → writing-plans)に完全に従う。スキル内部の手順・ゲートには干渉しない。
**未知の振り分け**: ブレスト中にユーザーが「決めていない / わからない」と答えた問いは、その場で追及せず**仮説化して assumptions.md に記録し、続行する**。goal-frame.md の未知マップと突き合わせる。
完了後、spec/planへの相対リンクとマイルストーン一覧を `goal-plan.md` に集約する。マイルストーン粒度は「**ユーザーが1つの価値をEnd-to-Endで利用できる**」単位(policy.md)。技術タスク単位に細分化しない。

**A-5 Approval Submission(Opus)**
`templates/approval-submission.md` に従い、Goal Plan承認用の submission を作成する(対象: Goal Plan全体。残存未知リストと仮定台帳サマリを含める)。保存先: `goal-plan-submission.md`(goal直下)。

**A-6 Goal Gate(Fable)**
前提確認: goal-frame.md と submission が存在すること。
共通契約に従い goal-frame.md 全文 + submission 全文 + assumptions.md の未検証仮定を渡し、判定観点(適合性・残存未知の許容性・仮定の事実扱い・否定リスト)で「この計画で元の目的を達成できるか」を判定させる。品質の細部ではなくゴール整合性を中心に見る。
結果を `goal-gate-decision.md`(goal直下)に保存し、call-logに記録する。

**A-7 差し戻し処理(Opus)**
- REVISE → 指定された工程(ブレスト/spec/plan)へ戻り、修正後 A-5 から再提出
- REPLAN → A-4(計画)から作り直し
- BLOCKED → 根拠に含まれる質問を人間へ提示し、state.md を「人間待ち」にして停止

**A-8 Human Goal Acceptance(人間)**
Fable PASS後、Goal Plan(と goal-frame)を人間に提示し、実装へ進む承認を得る。承認されたら state.md を milestone-implementation へ更新する。

## ワークフローB: Milestone Implementation(マイルストーンごとに繰り返す)

**B-1 開始確認(Fable・軽量)**
直近の retro.md 最大3件の要点を抜粋し、Agentツール(model: fable)に goal-frame.md + 対象マイルストーン定義(goal-plan.mdの該当部分) + retro抜粋(あれば)を渡し、「このマイルストーンが上位ゴールのどの成果を満たすか確認し、実装上の注意点があれば10行以内で示せ」と指示する。call-logに記録。

**B-2〜B-3 実装と自己検証(Codex)**
強度により委譲単位を変える(policy.md工程表):
- **MVP**: マイルストーンの**E2E価値単位でまとめて**1〜数回の `codex exec` に委譲する。タスク細分化しない。
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

**B-4 エスカレーション(必要時のみ)**
policy.md の発火条件(否定リスト該当を含む)を検出したら、`templates/escalation.md` の6点に整形し、Agentツール(model: fable)に goal-frame.md + 6点のみを渡す。判断結果を milestone ディレクトリに `escalation-<連番>.md` として保存し、call-logに記録。判断に従って続行する。

**B-5 レビューとSubmission作成(Opus)**
- **MVP**: Opusメインが**セルフチェック**(goal-frame承認基準との対応・残存未知の列挙・未検証仮定の確認)を行い、`templates/approval-submission.md` に従い `milestones/<n>-<名前>/submission.md` を作成する。
- **高信頼**: Agentツール(model: opus)で**実装に関与していない**独立レビューア(PL-003)を起動し、goal-plan.md該当部・マイルストーン定義・diff・検証証拠を渡してレビューさせ、結果を反映してsubmissionを作成する。call-logに記録(opus-sub)。
- どちらの場合も**残存未知リストと仮定台帳サマリを必須**とする(欠けたままB-6へ進まない)。

**B-6 Implementation Gate(Fable)**
前提確認: submission.md が存在し、検証証拠と残存未知リストが含まれること。
共通契約に従い goal-frame.md + マイルストーン定義 + submission.md + assumptions.md の未検証仮定を渡し、判定観点で「このマイルストーンのゴールを満たし、残存未知が許容可能か」を判定させる。結果を `gate-decision.md` に保存、call-logに記録。
- PASS → state.md を human-acceptance に更新し、B-7へ
- REVISE / REPLAN → 指定された工程へ差し戻す(対象の未知・仮定が指定される。人間へは出さない)
- BLOCKED → 人間へ質問して停止

**B-7 Human Review Report(Opus)**
`templates/human-review-report.md` に従い `human-report.md` を作成する。**「3.5 判断の内訳」(確定 / 要件由来 / 仮説による決定 / 低確信・要確認)を必ず含める**。受け入れテスト手順は人間が1回のテストで確認できる具体性で書く。

**B-8 Human Acceptance(人間)**
human-report.md を人間に提示し、受け入れテストを依頼する。結果を `acceptance.md` に記録する(ACCEPT / REJECT + コメント)。**フィードバックから新たに発見された未知・要望は assumptions.md に追記する**(次ループの入力)。ACCEPTの場合は state.md を finalization に更新する。

**B-9 REJECT処理(Fable)**
REJECTの場合、Agentツール(model: fable)に goal-frame.md + human-report.md + REJECT理由を渡し、戻り先(タスク修正 / マイルストーン再計画 / ゴール再確認)を決定させる。REJECT理由から発見された未知は assumptions.md に追記する。決定に従い該当フェーズへ戻り、戻り先に応じて state.md を更新する。call-logに記録。

**B-10 確定処理(Opus)**
acceptance.md に ACCEPT があることを確認してから、変更を確定コミットする。state.md を learning へ更新する。

## Learning フェーズ

1. **Retrospective(Opus)**: `templates/retrospective-note.md` に従い `retro.md` を作成する。観測欄に、ループ回数(REVISE/REPLAN差し戻し数)・呼び出し数(call-log.mdから)・主要フェーズ所要時間(call-logの時刻から概算)・**発見された未知**を記載する(5:1目安、ハード制限ではない)。
2. **グラレコ(Codex経由)**: human-report.md / gate-decision.md / retro.md の要点を `grareco-input.md` にまとめ、`templates/grareco-prompt.md` の指示文を埋めて `codex exec` に渡す。生成失敗時は grareco-input.md を残したまま先へ進む(ループ完了をブロックしない)。call-logに記録(codex)。
3. **次へ**: 未実装マイルストーンがあれば state.md を milestone-implementation に戻して B-1 から繰り返す。全マイルストーン完了なら state.md を done にし、ゴール全体の完了を人間に報告する。

## 例外・停止時の扱い

- どのフェーズでも、人間の入力が必要になったら state.md の「待ち」に内容を書いてから停止する。
- セッションが切れても、次回 `/r-super-loop-powers` 起動時に state.md から再開できる(NFR-04)。
- このスキルは Superpowers・gstack等の他スキルのファイルを読むことはあっても、**変更してはならない**(SK-001)。
`````

- [ ] **Step 2: 検証**

Run: `head -4 skills/r-super-loop-powers/SKILL.md && grep -c "^## " skills/r-super-loop-powers/SKILL.md && grep -c "assumptions.md" skills/r-super-loop-powers/SKILL.md`
Expected: frontmatterに `name: r-super-loop-powers`、見出し `11`(起動時チェック/ディレクトリ契約/フェーズと成果物契約/仮定台帳の運用/記録ルール/ゲート保護ルール/Fable共通契約/ワークフローA/ワークフローB/Learning/例外)、assumptions.md言及 `8以上`

- [ ] **Step 3: コミット**

```bash
git add skills/r-super-loop-powers/SKILL.md
git commit -m "feat: SKILL.mdを強度分岐・仮定台帳・終了判定対応に改訂(v0.2)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: README改訂 + バージョン更新

**Files:**
- Modify: `README.md`(全置き換え)
- Modify: `.claude-plugin/plugin.json`(versionのみ変更)

**Interfaces:**
- Consumes: Task 1〜4の用語(ループ強度 / assumptions.md / 判断の内訳 / image_gen)

- [ ] **Step 1: README.md をファイル全体で以下の内容に置き換える**

````markdown
# r-super-loop-powers

Superpowersの上位に薄く重なる**ゴールループ・オーケストレーション層**。

Goal Loopの目的は **A. 要件適合性**(作りたかったものを正しく作れているか)と **B. 未知の低減**(最初には分からなかった正解を、作りながら発見する)の2つ。品質最大化・速度最大化は目的ではない。AIが未知に仮説を立てて評価可能な具体物まで作り、人間は評価とフィードバックを担う。作業そのものの進め方はSuperpowersに委ね、内部には一切干渉しない。

```
人間  ──(Goal Seed / 強度確定 / 評価)──┐
                                       │
┌──────────────────────────────────────▼───────┐
│ r-super-loop-powers(責任・ゲート層)          │
│  フェーズ / 成果物契約 / Fableゲート / HITL  │
│  ループ強度 / 仮定台帳 / 残存未知の管理      │
├──────────────────────────────────────────────┤
│ Superpowers(実行プロセス層)                  │
│  brainstorming / writing-plans / TDD ...     │
└──────────────────────────────────────────────┘
  実行: Opusメイン  判定: Fableサブ  実装: codex exec
```

## ループ強度

- **MVP(既定)**: E2E価値単位でまとめて実装。独立レビュー省略。検証は受け入れ基準+未知低減に効くもののみ
- **高信頼**: タスク分解・diff確認・独立レビュー・フルテスト
- Goal Frame作成時にFableが提案し、人間が確定する。FableゲートとHuman Acceptanceは両強度で維持される

## 前提

- Claude Code + Superpowersプラグイン(改造不要)
- Codex CLI(`codex login` 済み。モデル等は `~/.codex/config.toml` に従う)
- 対象プロジェクトによっては Codex の `trust_level` 設定(`~/.codex/config.toml` の `[projects]`)が必要になる場合がある
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

フェーズの流れ: Goal Frame(Fable・強度提案) → ブレスト/Spec/Plan(Opus+Superpowers、未回答の問いは仮定台帳へ) → Goal Gate(Fable) → 人間承認 → 実装(codex exec) → Submission(残存未知リスト付き) → Implementation Gate(Fable) → Human Review Report(判断の内訳付き) → 人間受け入れ → 確定コミット → 振り返り+グラレコ

## E2Eテスト(導入・改訂時に1周まわす)

小さなプロジェクトで1ゴール1マイルストーンを実行し、以下を確認する:

- [ ] state.md 不在時に新規ゴール開始フローに入る
- [ ] goal-frame.md がFableにより生成され、ループ強度が提案→人間確定される
- [ ] ブレスト中の未回答質問が assumptions.md に記録され、ループが停止しない
- [ ] brainstorming / writing-plans がSuperpowers標準フローのまま動く
- [ ] Goal Gate が PASS するまで人間承認を求められない
- [ ] codex exec がコミットを作らない
- [ ] MVP強度で独立レビュー(opus-sub)とタスク単位のdiff精読が発生しない
- [ ] submission.md に残存未知リストと仮定台帳サマリがある
- [ ] Implementation Gate PASS 前に human-report.md が出てこない
- [ ] human-report.md に判断の内訳(確定/仮説の区別)がある
- [ ] ACCEPT 記録前に確定コミットが行われない
- [ ] 人間フィードバックで発見された未知が assumptions.md に追記される
- [ ] retro.md にループ回数・所要時間・発見された未知が記録される
- [ ] grareco.png が組み込み image_gen ツールで生成される(スクリプト・APIキー使用なし)
- [ ] セッションを切って再起動 → state.md から現在地が復元される

## リポジトリ構成

- `.claude-plugin/` — プラグインマニフェスト・マーケットプレイス定義
- `skills/r-super-loop-powers/` — SKILL.md(オーケストレーター) / policy.md(運用ポリシー) / templates/(7種)
- `docs/superpowers/specs/` — 設計仕様書
- `docs/superpowers/plans/` — 実装計画
````

- [ ] **Step 2: plugin.json のversionを変更**

`.claude-plugin/plugin.json` の `"version": "0.1.0"` を `"version": "0.2.0"` に変更する(他は触らない)。

- [ ] **Step 3: 検証**

Run: `python -m json.tool .claude-plugin/plugin.json > /dev/null && grep '"version"' .claude-plugin/plugin.json && grep -c "ループ強度" README.md`
Expected: JSONパース成功、`"version": "0.2.0"`、`2以上`

- [ ] **Step 4: コミット**

```bash
git add README.md .claude-plugin/plugin.json
git commit -m "docs: READMEをv0.2(上位原則・強度・E2E15項目)に更新、version 0.2.0

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: 全体整合検証

**Files:**
- Modify: なし(検証のみ。問題があれば該当ファイルを修正)

**Interfaces:**
- Consumes: Task 1〜5の全成果物

- [ ] **Step 1: ファイル・構造検証**

Run: `ls skills/r-super-loop-powers/templates/ | sort && grep -c "^## " skills/r-super-loop-powers/policy.md && grep -c "^## " skills/r-super-loop-powers/SKILL.md`
Expected: テンプレート7ファイル(approval-submission / assumptions / escalation / goal-frame / grareco-prompt / human-review-report / retrospective-note)、policy見出し `10`、SKILL見出し `11`

- [ ] **Step 2: 名称・強度表記の統一検証**

Run: `grep -rn "goal-loop" skills/ .claude-plugin/ README.md || echo "ALL CLEAN"` および `grep -rn "標準強度\|強度: 標準" skills/ README.md || echo "NO_CHUKAN"`
Expected: `ALL CLEAN` と `NO_CHUKAN`(強度は MVP / 高信頼 の2値のみ)

- [ ] **Step 3: クロスリファレンス検証**

以下を目視確認(それぞれの参照元と参照先が一致すること):
1. SKILL.mdが参照するテンプレート名7種が `templates/` の実ファイル名と一致
2. policy.mdの強度別工程表とSKILL.mdのB-2/B-3/B-5の強度分岐が矛盾しない(MVP=E2E委譲・自己検証確認・セルフチェック / 高信頼=タスク分解・diff確認・独立レビュー)
3. spec §7の受け入れ基準のうち静的に確認可能な項目: 2(MVPで独立レビュー工程が省略と明記), 4(submissionに残存未知リスト必須), 5(レポートに判断の内訳), 7(否定リストとゲート保護ルール6), 8(grareco-promptにimage_gen明記)
4. assumptions.mdの列名(ID/仮定内容/確信度/根拠/ゴールへの寄与/検証方法/状態)がSKILL.md「仮定台帳の運用」の記述と整合

- [ ] **Step 4: 最終コミットと引き渡し**

```bash
git add -A
git commit -m "chore: v0.2.0 整合検証完了

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" --allow-empty
git log --oneline main..HEAD
```

ユーザーへの案内: PR作成 → マージ → `claude plugin update r-super-loop-powers`(または marketplace update)→ Claude Code再起動 → `loop-test-sales-dashboard` をMVP強度で再開してE2E確認(spec §8)。

---

## Self-Review 結果

- **Spec coverage**: D10(上位原則→policy/SKILL/README冒頭)、D11(強度→goal-frame/policy/SKILL起動時チェック4/A-1)、D12(台帳→assumptions.md/SKILL仮定台帳の運用)、D13(否定リスト→policy/ゲート保護6/B-4/エスカレーション条件7)、D14(粒度→policy粒度/SKILL A-2〜A-4)、D15(工程表→policy/SKILL B系強度分岐)、D16(終了判定→submission残存未知/Fable契約判定観点/B-6)、D17(判断の内訳→human-review-report/B-7)、D18(計測→retro観測/Learning 1)、D19(振り分け→SKILL A-2〜A-4/B-8/B-9)、D20(image_gen→コミット済み+README E2E項目)。spec §5の8ファイル変更すべてにタスクあり。
- **Placeholder scan**: なし。テンプレート内の `<...>` は成果物の記入欄。
- **型整合**: 強度2値表記・台帳7列・ゲート4値・テンプレ名7種・見出し数(policy 10 / SKILL 11)をTask間で一致させた。
