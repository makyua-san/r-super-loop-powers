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
