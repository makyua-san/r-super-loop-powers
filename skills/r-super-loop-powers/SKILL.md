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
