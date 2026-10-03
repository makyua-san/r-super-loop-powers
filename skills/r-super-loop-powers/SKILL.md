---
name: r-super-loop-powers
description: Use when starting or resuming a goal-engineering loop (ゴールループ / goal loop / ゴールエンジニアリング開発). Superpowersの上位で、要件適合性と未知低減を目的に、フェーズ管理・成果物契約・Fable承認ゲート・ヒューマン・イン・ザ・ループ配置・モデル責任分担(Opus 5.5実行 / Fable判定 / Codex gpt-6.1-sol技術PM・技術レビュー(読み取り専用) / Sonnet 5.5実装)をオーケストレーションする。MVPモードではFableヒアリングでゴールと文脈を掘り、HOWは代理ブレスト(Fable=ユーザー目線 / Codex技術PM=実装責任者目線)でAgentへ委任し、Checkpoint単位でHuman Acceptanceを行う。
---

# r-super-loop-powers — ゴールループ・オーケストレーター

あなた(このスキルを実行するモデル)は **Opus 5.5メインセッション** として、ゴールループの進行管理と成果物作成を担当する。
このスキルは **責任・ゲート層** である: いまどのフェーズか、次に必要な成果物は何か、誰が実行し誰が判定するか、人間へ返すタイミングだけを制御する。
作業の進め方(HOW)はSuperpowersのスキルに完全に委ね、その内部手順には一切干渉しない。MVPモードでは、Superpowersのスキルが人間に求める質問・承認への応答を**代理Fable**(ユーザー目線)と**技術PM**(Codex。実装責任者目線でHOWに係る問いに回答)が分担する(相手が変わるだけで、スキルの手順は変えない)。
各担当(あなた自身を含む)の立場・決めること・決めないことは `references/roles.md`(ロール憲章)にまとめてある。

Goal Loopの目的は **A. 要件適合性** と **B. 未知の低減** の2つ(policy.md「上位原則」)。MVPモードでは人間にHOWの確定を求めず、ヒアリングで無自覚の既知を表面化した上でAgentがHOWを仮説化する(policy.md「MVPモードの原則」)。ループ・テスト・レビュー・承認は、AまたはBに寄与する場合にのみ実施する。ループ終了条件は回数ではなく「適合性への十分な確信 + 残存する重要な未知が許容可能」。

## 起動時チェック(毎回必ず実行)

1. **ポリシー読込**: このスキルと同じディレクトリの `policy.md` と `references/roles.md`(ロール憲章)を読む。以後の全判断はこのポリシーに従う。
2. **モデル確認**: 自分が **Opus 5.5** で動いていない場合(特にFableの場合)、ユーザーに `/model opus` への切替を提案し(`opus` aliasは最新のOpus=5.5に解決される)、切替またはユーザーの明示的な続行指示があるまでフェーズ作業を開始しない(PL-002)。
3. **状態復元**: 対象プロジェクトで `docs/r-super-loop-powers/*/state.md` を探す(Globツール)。
   - 見つかった場合: 最新の state.md を読み、「現在フェーズ / 強度 / 対象マイルストーン / 次のCheckpoint / 次のゲート」を1〜3行でユーザーに報告し、そのフェーズの手順から再開する。
   - 見つからない場合: ワークフローA(新規ゴール)を開始する。
4. **強度確認**: goal-frame.md が存在する場合、ループ強度(MVP | 高信頼)を読み、policy.md「ループ強度」の工程表に従って以後の工程を実施する。強度未確定のままワークフローBへ進まない。
5. **スキルディレクトリの解決(このゴールで初回のみ。以後は state.md の `skill-dir:` を再利用)**:
   Globツールで `**/skills/r-super-loop-powers/bin/codex-preflight.ps1` を探す(候補: `$CLAUDE_PLUGIN_ROOT` 配下、`~/.claude/plugins/cache/*/r-super-loop-powers/*/skills/r-super-loop-powers/`、`~/.claude/skills/r-super-loop-powers/`、対象プロジェクトの `.claude/skills/`)。複数見つかった場合はバージョンが新しいものを選ぶ。見つからない場合はユーザーに報告して停止する(スクリプトなしでcodexを手書きで呼ばない)。その親ディレクトリを `skill-dir:` として state.md に記録する。

6. **codex実行系のプリフライト(このゴールで初回のみ。以後は state.md の `codex-env:` を再利用)**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\codex-preflight.ps1" -EnvOut "<goal-dir>\codex-env.json"
   ```
   codex実体の解決(シム迂回)・バージョン・認証・モデル疎通を1回で確認する。codex は**技術PM・技術レビュー(高信頼)・グラレコの3ロールだけ**で使い、**すべて `gpt-6.1-sol` の読み取り専用**で動く。実装はSonnetサブエージェント(起動時チェック7)が行うので、codex に書き込み権限は要らない。
   - `PREFLIGHT: OK` → `<goal-dir>\codex-env.json` のパスを state.md の `codex-env:` に記録する。以後の全codex呼び出しはこのファイルを渡すだけでよい。
   - `PREFLIGHT: FAILED` → `REASON:` 行をそのままユーザーへ提示して**停止する**。モデルが使えない場合(例: `not supported when using Codex with a ChatGPT account`)も**黙って別モデルへ落とさない**。代替モデルはユーザーが指名した場合のみ `-Model` で渡し、decisions.md に記録する。
   - 既存ゴールの codex-env.json が v0.7 より前のもの(`envSchema` が無いか 2 未満、または `techpmModel` / `sandbox` 等の旧キーがある)なら、再開時にプリフライトを再実行する(`codex-run.ps1` が `WARN:` で知らせる)。モデル名は判定に使わない(ユーザーが指名した `-Model` は正当)。

7. **実装役エージェントの確認**: Agentツールで使えるエージェント種別に `r-super-loop-powers:builder`(Sonnet 5.5)があることを確認する。無い場合(プラグインが v0.7 未満、または更新後に再起動していない)はユーザーに報告して停止する。**汎用エージェントや `model: sonnet` 指定で実装を代行させない**(実行契約・ツール制限・モデルが保証されないため)。

8. **対象プロジェクトの git 確認**: 対象プロジェクトが git リポジトリでない、またはコミットが1つも無い場合(`git rev-parse HEAD` が失敗する)、`impl-check.ps1` は委譲前の基準コミットが無いと実装役の変更を判定できないことをユーザーに説明し、`git init` + 初回コミットの実行を承認してもらう。**承認なしでワークフローBを開始しない。** Opus が自分の判断で `git init` やコミットをしない。

   ゴール開始前にチェック7・8を通さずにワークフローBへ進まない。

## ディレクトリ契約

対象プロジェクト内に次を作成・維持する:

```
docs/r-super-loop-powers/<goal-slug>/
├── state.md                 # 現在地(下記フォーマット)
├── goal-seed.md             # 人間の意図(原文のまま)
├── hearing-log.md           # A-1aヒアリングとASK_HUMAN中継の記録(MVP。高信頼はASK_HUMAN中継時のみ)
├── goal-frame.md            # Fable入口出力 = 承認基準・強度・未知マップ・終了条件の原本
├── assumptions.md           # 仮定台帳(全フェーズで追記)
├── goal-plan.md             # spec/planリンク + マイルストーン一覧(Checkpoint印) + 主要設計判断(Fable代理回答 / 技術PM回答による)
├── tech-assessment.md       # 技術PMのマイルストーン別実装アセス(MVP・A-4末)。B-2で実装役にそのまま渡す
├── goal-plan-submission.md  # A-5 Goal Plan承認用submission
├── goal-gate-decision.md    # A-6 Goal Gate判定
├── call-log.md              # 呼び出し記録(PL-007)
├── hook-log.md              # 人間向け応答チェック(プラグインの Stop フック)の判定記録。フックが自動で追記する
├── codex-env.json           # 起動時チェック6のプリフライト結果(codex実体・モデル)
├── codex-runs/              # codex(技術PM・技術レビュー・グラレコ)の実行記録
├── impl-runs/               # 実装役(Sonnet)への委譲記録(<ラベル>.prompt.md / .base.txt / .pre.txt / .report.md)
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
- 担当: opus-main | fable | codex-techpm | codex-review | sonnet-builder | human
- 次のゲート: goal-gate | impl-gate | human-acceptance | none
- 待ち: <人間待ちの場合はその内容。なければ ->
- skill-dir: <このスキルのディレクトリの絶対パス>        # 起動時チェック5で解決
- codex-env: <codex-env.json の絶対パス>                 # 起動時チェック6で生成
- codex-run: <実行中の委譲ラベル。なければ ->            # 技術PM / 技術レビュー / グラレコで起動したら記入、判定が確定したら消す
- updated: YYYY-MM-DD HH:MM
```

各欄の値は上の語をそのまま書く(`**done**` のような装飾をしない。`phase` はフックがゴールループ中かどうかの判定に使う)。
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

fable / codex-techpm(技術PM) / codex-review(技術レビュー) / codex-grareco(グラレコ) / sonnet-builder(実装役) を呼ぶたび、および代理FableとのSendMessage往復のたびに、直後に `call-log.md` へ1行追記する:
`YYYY-MM-DD HH:MM | fable|codex-techpm|codex-review|codex-grareco|sonnet-builder | フェーズ | 目的`

## ゲート保護ルール(絶対)

1. Fable PASS 前に人間へ受け入れを求めない(SK-007)
2. human-report.md(評価パッケージ)なしで Human Acceptance に進まない(SK-008)
3. Checkpoint(高信頼はマイルストーン)の acceptance.md に ACCEPT がない状態で確定処理をしない(SK-009)。MVPの中間コミット(B-6 PASS後)は可
4. 必須成果物が欠けた状態でFableゲートを呼ばない — 欠落は自分で差し戻して埋める(NFR-05)
5. 実装役(Sonnet)にも codex にもコミットさせない
6. 否定リストに触れる仮説を自律実行しない — エスカレーションまたは人間確認へ
7. 代理ブレストに参加したFableインスタンスにゲート判定(A-6 / B-6)をさせない(自己承認の禁止)(SK-010)
8. **成否は機械判定で決める。** codex は `codex-status.ps1`、実装役は `impl-check.ps1` の `STATUS: OK` 以外を成功として扱わない。プロセスが消えたこと・報告が返ったことは、いずれも単独では完了の証拠にならない(実測で、失敗した実行と成功した実行が同一に見えた)。判定を目視や推測で代替しない
9. codexの呼び出しは `bin/` のスクリプト経由でのみ行う。起動コマンドを自分で組み立てない。実装役は Agentツールの `r-super-loop-powers:builder` でのみ起動する
10. codex は助言・レビュー・画像生成の**読み取り専用ロール**である。必ず `-Role techpm | reviewer | grareco` のいずれかで起動し(スクリプトが read-only を強制する)、コード変更・設計承認・要件適合の判定をさせない
11. 実装役は実行者である。設計・計画・選択肢の提示をやり直させない。承認済みの技術アセス(高信頼は人間承認済みの plan)をプロンプトに入れずに委譲しない

## Fableサブエージェント共通契約

- Agentツールで `model: "fable"` を指定して起動する。役割は2種類あり、**インスタンスを分離する**:
  - **代理Fable(MVPのA-1a〜A-4)**: nameを付けて1インスタンスを起動し、SendMessageで往復を継続する(ヒアリング文脈の保持)。入力は goal-seed / goal-frame / hearing-log / retro抜粋 / templates構造のみ。
  - **ゲート・判断Fable(A-6 / B-1 / B-4 / B-6 / B-9)**: 呼び出しごとに新規インスタンス。初回入力は goal-frame.md 全文 + 対象文書(submission / escalation / milestone定義) + assumptions.md の関連部分(未検証仮定) + 必要なら hearing-log.md の関連部分のみ。対象プロジェクトの生コード・全会話履歴を渡さない(PL-009)。追加資料を要求した場合のみ、SendMessageで1往復の追加提供を行う。
- **ロール憲章の貼り付け(必須)**: 起動時の依頼文の冒頭に、`<skill-dir>\references\roles.md` の「全体図 (overview)」節と該当ロールの節(代理Fable → 「代理Fable (proxy-fable)」、ゲート・判断Fable → 「ゲートFable (gate-fable)」)を**原文のまま**貼り、その後に各工程の依頼文を続ける。要約・言い換えをしない。代理Fableには初回起動時だけ貼る(SendMessage の往復では再送しない)。
- ゲート判定の出力契約: `PASS | REVISE | REPLAN | BLOCKED` のいずれか1つ + 根拠(5行以内) + REVISE/REPLANの場合は戻り先工程と対象の未知・仮定。
- 判定観点(プロンプトに明記する): (1) goal-frame.md の承認基準を満たすか (2) 残存する重要な未知が許容可能か(goal-frameの終了条件と照合) (3) 仮定が事実として扱われていないか (4) 否定リスト違反の仮説がないか。「動くか」ではなくゴール整合を見る。

## 技術PM(Codex)共通契約

codex の起動・完了判定・STATUS の読み方は `references/codex-invocation.md` に従う。

- **役割**: MVPの代理ブレスト(A-2〜A-4)で、**HOWに係る問い**に**実装責任者**の立場から回答し、A-4末に**実装アセス**(`tech-assessment.md`)を出す。モデルは `gpt-6.1-sol`(codex-env.json の `model`)、effort は `max`(`-Role techpm` の既定)。実装役(Sonnet 5.5)はこのアセスに従って実行するだけなので、**技術判断はここで出し切らせる**。
- **回答範囲**: 実装方式・技術選択・構成と分割・既存コードとの整合・技術リスク・工数感・検証可能性。ユーザー価値・好み・優先順位は決めない — 必要なら `NEEDS_USER_VIEW: <代理Fableへの問い>` を返させる。設計承認もしない(承認は代理Fable)。
- **起動**(B-2と同じスクリプト。必ず `bin/` 経由):
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\codex-run.ps1" `
    -EnvFile "<codex-env.json>" -Label "brainstorm-techpm-<連番>" `
    -PromptFile "<goal-dir>\codex-runs\brainstorm-techpm-<連番>.prompt.md" `
    -WorkDir "<対象プロジェクトのルート>" -RunDir "<goal-dir>\codex-runs" `
    -Role techpm -Effort max -TimeoutMinutes 30
  ```
  `-Role techpm` は必須(ゲート保護ルール10)。スクリプトが read-only を強制し、技術PMのペルソナ(助言役・プロセス系スキルを起動しない・実装役がそのまま実行できる具体度で答える)を実行契約の後に自動で差し込む。既存コードは技術PM自身が読んでよい。ロール憲章(roles.md の全体図+該当ロールの節)もスクリプトが実行契約の直後に自動で差し込むので、プロンプトに貼らない。
- **完了と採否**: `codex-status.ps1` で待ち、`STATUS: OK` のときだけ `FINAL_MESSAGE_FILE` を回答として採用する(ゲート保護ルール8)。OK以外は1回だけ再実行し、再度失敗したらユーザーへ報告し、Opusの判断で代替して続行するかを確認する(黙って代筆しない)。
- **プロンプト必須要素**:
  1. 役割宣言: 「あなたはこのゴールの技術PM(実装責任者)。自分が実装を担当する前提で、HOWに関する問いに答えよ。コードは書かない・変更しない」
  2. goal-frame.md 全文 + hearing-log.md の関連部分 + (2ラウンド目以降)前ラウンドまでのQ&A要約
  3. 質問リスト(番号付き。アプローチ比較の問いは候補案を併記)
  4. 出力要求: 質問ごとに「回答 / 根拠(既存コードの該当箇所があれば引用) / 前提・リスク / 確信度(高・中・低)」。ユーザー判断が要る問いは `NEEDS_USER_VIEW:` 行で返す
- **往復**: codexはセッションを継続しないため、**1ラウンド=1呼び出し**。effort `max` は1回が重いので、brainstormingの進行を止めない範囲でHOWの問いを束ねる(例: アプローチ提示の段階でそれまでのHOW論点をまとめて1回)。
- **実装アセス(MVP・A-4末に1回。ラベル `techpm-assessment`)**: writing-plans が plan を書き終えたら、goal-frame.md + spec + plan + 主要設計判断を渡し、**マイルストーンごと**に次を出させる — 採用する実装方式(1つに決め切る) / 触るファイル・関数 / 作業順 / 既知のリスクと回避策 / 完了を示す検証コマンド / 実装役が迷いそうな点への指示。出力は `## M<n>` 見出しで区切らせる。`STATUS: OK` の `FINAL_MESSAGE_FILE` を `tech-assessment.md`(goal直下)に保存し、goal-plan.md からリンクする。Goal Gate(A-6)の submission にも添付する(ゲートFableが実装方針を確認できるように)。
  - REVISE / REPLAN で plan が変わった場合は、変わったマイルストーンについてのみ再アセスする。
- **高信頼強度**: HOWは人間が決めるため必須ではない。人間が技術的見解を求めた場合のみ同じ契約で呼ぶ。
- 呼び出しごとに call-log へ記録(codex-techpm)。

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
出力を `goal-frame.md` に保存し、call-logに記録する。内容をユーザーに提示し、**ループ強度を確定**してもらい、方向のズレがないか確認する。A-1aで高信頼と答えた後にここでMVPへ確定が変わった場合は、A-1aの深掘りヒアリングを再開してからA-2へ進む。確定した強度を goal-frame.md の「人間の確定」欄と state.md に記録する。

**A-2〜A-4 ブレスト → Spec → Plan(Opus + Superpowers)**
`superpowers:brainstorming` を起動し、その標準フロー(spec作成 → writing-plans)に完全に従う。スキル内部の手順・ゲートには干渉しない。強度により質問・承認の相手を変える:
- **高信頼**: 従来通り人間が相手(人間が技術的見解を求めた場合のみ技術PMを呼ぶ)。
- **MVP(代理ブレスト: Fable + 技術PM)**: 質問・設計承認の相手を人間ではなく**代理Fable**(SendMessage)と**技術PM**(「技術PM(Codex)共通契約」)にする。Opusはbrainstormingが出す問いを次のように振り分ける:
  - ユーザー価値・体験・優先順位・好み・受け入れ観点(WHAT) → **代理Fable**
  - 実装方式・技術選択・構成と分割・技術リスク・実現性(HOW) → **技術PM**
  - 両方に係る問い(アプローチ選択・設計承認など) → 先に技術PMの技術評価を取り、それを添えて代理Fableへ渡す。**最終の回答・設計承認は代理Fable**が行う(ユーザーの代理であるため)
  - 技術PMが `NEEDS_USER_VIEW:` を返した問い → 代理Fableへ回す

  代理Fableへの依頼文に必ず含める: 「あなたはユーザーの代理として**ユーザー目線で**回答する。根拠は goal-frame.md と hearing-log.md。技術PMの見解が添付されている場合、技術的な実現性・リスクの評価はそれを前提とし、ユーザー価値の観点で選べ。技術PMの評価とユーザー価値が衝突し、選択でユーザー体験が大きく変わる場合は回答せず `ASK_HUMAN:` を返せ。**ユーザー固有の判断(好み・業務文脈・優先順位)が必要でヒアリング記録から導けない問い、否定リスト該当、エスカレーション発火条件該当の問いには、回答せず `ASK_HUMAN: <人間向けの質問文>` と返せ**。」 ASK_HUMANが返った質問のみ人間へ提示し、回答を hearing-log.md に追記して代理Fableへ共有する。主要決定(採用アプローチ・設計承認・主要な技術選択)は goal-plan.md の「主要設計判断(Fable代理回答 / 技術PM回答による)」欄に、**どちらの回答を根拠にしたか**を付けて記録する。往復ごとにcall-logへ記録(fable / codex-techpm)。
**未知の振り分け**: ヒアリング・ブレスト中に人間または代理Fableが「決めていない / わからない」と答えた問いは、その場で追及せず**仮説化して assumptions.md に記録し、続行する**。goal-frame.md の未知マップと突き合わせる。
**MVPでは plan 完成後に技術PMの実装アセスを取る**(「技術PM(Codex)共通契約」の実装アセス)。これが無いまま A-5 へ進まない。
完了後、spec/planへの相対リンクとマイルストーン一覧を `goal-plan.md` に集約し、**Checkpoint印を付ける**(policy.md「Checkpointとマイルストーン粒度」: Checkpoint = ユーザー価値をE2Eで評価できる点。最終マイルストーンは必ずCheckpoint)。「主要設計判断(Fable代理回答 / 技術PM回答による)」欄もここに置く。

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
直近の retro.md 最大3件の要点を抜粋し、Agentツール(model: fable、新規インスタンス)に goal-frame.md + 対象マイルストーン定義(goal-plan.mdの該当部分) + retro抜粋(あれば)を渡し、「このマイルストーンが上位ゴールのどの成果を満たすか確認し、実装上の注意点があれば10行以内で示せ。実装方式は技術PMのアセスで決まっており、実装役(Sonnet 5.5)はそれを実行するだけである点を考慮せよ」と指示する。

**B-2〜B-3 実装と自己検証(Sonnet 実装役)**
強度により委譲単位を変える(policy.md工程表):
- **MVP**: **マイルストーン単位でまとめて**1〜数回、実装役に委譲する。タスク細分化しない。
- **高信頼**: subagent-driven developmentと同じプロセス構造でタスク分解し、個別に委譲する。

実装役は Agentツールの `subagent_type: "r-super-loop-powers:builder"`(`claude-sonnet-5-5`。Skill / Agent ツールを持たないので、プロセス系スキルを起動できない)で起動する。実行契約(スコープ・コミット禁止・要件再定義禁止・否定リスト)・ロール指示・出力契約・ロール憲章(roles.md の全体図+実装役の節。`scripts/sync-roles.ps1` で同期)はエージェント定義に入っているので、プロンプトに書かなくてよい。

**(1) 委譲前の基準を記録する**
次の2つを保存する。ラベルは `m<n>-impl`(再委譲は `m<n>-impl-2` …。高信頼でタスクごとに委譲する場合は `m<n>-t<k>-impl`)。
  - `git rev-parse HEAD` の値を `<goal-dir>/impl-runs/<ラベル>.base.txt` に
  - 委譲前の未コミット変更のスナップショットを `<goal-dir>/impl-runs/<ラベル>.pre.txt` に:
    ```powershell
    powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" -Snapshot `
      -WorkDir "<対象プロジェクトのルート>" -OutFile "<goal-dir>\impl-runs\<ラベル>.pre.txt"
    ```
  B-3 はこのスナップショットと比べて**今回の委譲で変わったものだけ**を判定に使うので、未コミット変更があっても判定は混ざらない。同じマイルストーンの未コミット変更(以前の委譲・再委譲・高信頼の先行タスクの分)は**そのまま残して**委譲する。`git status --porcelain` に、`docs/r-super-loop-powers/` 以外で**このマイルストーンと無関係な**未コミット変更(このマイルストーンの過去の `impl-runs/*.report.md` の `changed_files` に無いもの)がある場合だけ、委譲前にそれをユーザーに提示し、扱い(コミット / そのまま残す等)の指示を受けてから委譲する。

**(2) プロンプトを書く**
`<goal-dir>/impl-runs/<ラベル>.prompt.md` に保存する。実装役は**実行者**であり、設計・計画は済んでいる。プロンプトは「何を・どの方針で・何をもって完了とするか」を**決め切った状態**で渡す。必須要素は次の6つで、この見出しの順に書く:
  1. `## TECHNICAL ASSESSMENT` — **MVP**: `tech-assessment.md` の該当 `## M<n>` 節を**原文のまま**貼る(要約・言い換えしない) / **高信頼**: 人間が承認した plan の該当タスク本文。エージェント定義がこの見出しを参照するので名前を変えない
  2. `## ACCEPTANCE CRITERIA` — 受け入れ条件(実装役が `acceptance_criteria` へ原文のまま写すので、検証可能な文で書く)
  3. `## SCOPE` — 対象ファイル・変更範囲(触ってよい範囲と、触らない範囲)
  4. `## VERIFICATION` — **MVP**: 受け入れ基準に直結する検証+未知低減に効く検証のみ / **高信頼**: テストファースト+単体・結合・lint・型検査。実行すべきコマンドを具体的に書く
  5. `## OPEN ASSUMPTIONS` — 関連する未検証仮定(assumptions.mdから)
  6. `## OUTPUT` — 「最終メッセージは impl-report 形式の JSON を ```json フェンス1つで返すこと」

plan から転記するときは、`REQUIRED SUB-SKILL` / `superpowers:` / チェックボックス付きの手順指示など**エージェント向けの進め方の指示行を含めない**。コードや手順の中身だけを写す。

**(3) 起動して報告を保存する**
Agentツール: `subagent_type: "r-super-loop-powers:builder"`、description `B-2 <ラベル>`、prompt = (2) のファイル本文。返ってきた最終メッセージを**そのまま** `<goal-dir>/impl-runs/<ラベル>.report.md` に保存する(整形・補完しない)。call-logに記録(sonnet-builder)。

**B-3 受け入れ判定は `impl-check.ps1` の `STATUS` で行う**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" `
  -ReportFile "<goal-dir>\impl-runs\<ラベル>.report.md" `
  -WorkDir "<対象プロジェクトのルート>" `
  -BaseRef (Get-Content "<goal-dir>\impl-runs\<ラベル>.base.txt") `
  -PreexistingFile "<goal-dir>\impl-runs\<ラベル>.pre.txt"
```
報告JSONと git の実状態(HEAD の移動・`docs/r-super-loop-powers/` 以外で**今回の委譲による**実際の変更)を突き合わせる。委譲前から未コミットで今回変わっていないパスは `PREEXISTING_UNCHANGED:` に出るだけで、判定には使われない。

| STATUS | 扱い |
|---|---|
| `OK` | 合格。**MVP**: 報告(`.report.md`)を確認する(diff精読はしない)。**高信頼**: B-5 の技術レビューへ |
| `MALFORMED` | 報告が読めない。同じプロンプトで1回だけ再委譲し、再度なら B-4。ただし `REASON` が `BaseRef` / `PreexistingFile` に触れている場合は報告ではなく記録側の誤りなので、再委譲せず `.base.txt` / `.pre.txt` を直して B-3 をやり直す |
| `BLOCKED` / `INCOMPLETE` | **不合格。実装済みとして扱わない。** 不足点(`REASON` / `CRITERION_UNMET`)を引用して再委譲する。`BLOCKED` の原因が否定リストやユーザー固有判断ならB-4へ |
| `CONTRACT_VIOLATION` | 実装役がコミットした。`git log` / `git status` を確認してから判断する |

`STATUS: OK` 以外で B-5 へ進まない。`NEW_ASSUMPTION:` は assumptions.md に、`UNRESOLVED:` は残存未知として submission に転記する。`WARN: unreported change:` が出たら、その変更がスコープ内かを確認し、submission の「残存未知」に含めるか対処する。`WARN: reported but unchanged:` は報告と実態のずれなので、報告の該当箇所を割り引いて読み、submission の「残存未知」に記載する。

- 実装・設計上の主要判断は随時 `milestones/<n>-<名前>/decisions.md`(`templates/decisions.md` の形式)に追記する(要件由来とAgent仮説を区別する)。

**B-4 エスカレーション(必要時のみ)**
policy.md の発火条件(否定リスト該当・ユーザー固有判断・Solution分岐・低確信を含む10件)を検出したら、`templates/escalation.md` の1〜6を整形し、Agentツール(model: fable、新規インスタンス)に goal-frame.md + 1〜6 + 関連する未検証仮定(assumptions.mdの該当行、あれば) + hearing-log.md の関連部分(あれば)を渡す。Fableは7(判定)に **DECIDE**(判断+根拠)または **ASK_HUMAN**(人間向け質問文)を記入する。ASK_HUMANの場合はOpusが人間へ提示し、回答を hearing-log.md に追記してから続行する。文書を milestone ディレクトリに `escalation-<連番>.md` として保存し、call-logに記録。

**B-5 レビューとSubmission作成(Opus)**
- **MVP**: Opusメインが**セルフチェック**(goal-frame承認基準との対応・残存未知の列挙・未検証仮定の確認)を行い、`decisions.md` の4区分(要件由来 / Agent仮説HOW / 低確信 / 発見された未知)を確定させ、`templates/approval-submission.md` に従い `milestones/<n>-<名前>/submission.md` を作成する(判断記録欄から decisions.md を参照)。
- **高信頼**: **技術レビュー**を codex `gpt-6.1-sol`(`-Role reviewer`、read-only・effort max)で、**マイルストーンごとに1回**、その全タスクが `STATUS: OK` になった後に行う(PL-003)。ラベルは `m<n>-review`(CONCERNS 後の再レビューは `m<n>-review-2` …)。プロンプト(`<goal-dir>/codex-runs/<ラベル>.prompt.md`)には、goal-plan.md 該当部・マイルストーン定義・各タスクの plan 本文・受け入れ条件・委譲前の HEAD(このマイルストーン最初の委譲の `impl-runs/<ラベル>.base.txt` の値)・各委譲の `impl-check.ps1` の出力(`CHANGED_FILES_ACTUAL:` 行を含む)・実装役の報告を入れ、「`git diff <base>` と `git status --porcelain --untracked-files=all` で実際の変更を見よ。未追跡(新規)ファイルは `git diff` に出ないので直接読め」と書く。起動・完了判定は技術PMと同じ(`codex-run.ps1 -Role reviewer` → `codex-status.ps1`、`STATUS: OK` の `FINAL_MESSAGE_FILE` だけを採用)。最終行が `TECH_REVIEW: CONCERNS` なら、HIGH の指摘を引用して実装役へ再委譲し(B-2 に戻る)、解消してから submission を作る。MEDIUM / LOW は submission に記載する。**要件に合っているかはここでは見ない** — それは B-6 のゲートFableが判定する。call-logに記録(codex-review)。
- どちらの場合も**残存未知リスト・仮定台帳サマリ・decisions.mdの確定**を必須とする(欠けたままB-6へ進まない)。

**B-6 Implementation Gate(ゲートFable・新規インスタンス)**
前提確認: submission.md が存在し、検証証拠と残存未知リストが含まれること。
共通契約に従い goal-frame.md + マイルストーン定義 + submission.md + assumptions.md の未検証仮定を渡し、判定観点で「このマイルストーンのゴールを満たし、残存未知が許容可能か」を判定させる。結果を `gate-decision.md` に保存、call-logに記録。
- PASS + **MVPの非Checkpointマイルストーン** → **中間クローズ**: grareco-input.md作成(gate-decision.md / decisions.md の要点)+グラレコ生成(失敗は非ブロック)→ 中間コミット → state.md を次マイルストーンへ更新し、**人間承認なしで次のB-1へ**
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

1. **Retrospective(Opus)**: `templates/retrospective-note.md` に従い `retro.md` を作成する(**MVP: Checkpoint単位** — 対象は前回Checkpoint以降の全マイルストーン / **高信頼**: マイルストーン単位)。観測欄に、ループ回数(REVISE/REPLAN差し戻し数)・呼び出し数(call-log.mdから)・主要フェーズ所要時間(call-logの時刻から概算)・**発見された未知**・人間向け応答の書き直し回数(hook-log.md の BLOCK 行の数と、主な理由)を記載する(5:1目安はワークフローB以降、ハード制限ではない)。「再利用できる知見・テンプレート候補」に「なし」以外を書いた場合、**このプロジェクトの外でも効くもの**は orca-meta の MCP tool `record_lesson` で送る(軸は person / agent / method。orca-meta プラグインが導入されていない環境では省略してよい)。
2. **グラレコ(Codex経由・読み取り専用)**: human-report.md / gate-decision.md / retro.md の要点を `grareco-input.md` にまとめ、`templates/grareco-prompt.md` の指示文を埋めて codex に渡す(MVPの非Checkpoint分はB-6中間クローズで生成済みのため、ここではCheckpointマイルストーン分を生成する)。`codex-run.ps1 -Role grareco`(effort `medium` が既定)→ `codex-status.ps1` で待つ。codex は read-only なので画像を自分では保存しない。`STATUS: OK` なら、出力の `THREAD_ID:` を使って Opus が画像を回収する:
   ```powershell
   $codexHome = (Get-Content -Raw "<codex-env.json>" | ConvertFrom-Json).codexHome
   $img = Get-ChildItem (Join-Path $codexHome "generated_images\<THREAD_ID>") -Filter '*.png' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
   if ($img) { Copy-Item -LiteralPath $img.FullName -Destination "<milestone-dir>\grareco.png" }
   ```
   グラレコ実行では codex が組み込み imagegen の SKILL.md を読むため `BOUNDARY_HIT` の `WARN:` が出るが、これは想定どおりで無視してよい。生成・回収のどちらで失敗しても grareco-input.md を残したまま先へ進む(ループ完了をブロックしない) — ここは `STATUS: OK` 以外でも停止しない唯一の例外である。call-logに記録(codex-grareco)。
3. **次へ**: 未実装マイルストーンがあれば state.md を milestone-implementation に戻し(「次のCheckpoint」欄を更新)、B-1 から繰り返す。全マイルストーン完了なら state.md を done にし、ゴール全体の完了を人間に報告する。

## 人間向け応答チェック(プラグインの Stop フック)

ゴールループ中(対象プロジェクトに `docs/r-super-loop-powers/*/state.md` があり、phase が done でない)は、あなたが人間へ返す応答をプラグインの Stop フックが検査する。見るのは、日本語で書かれているか / 結論やお願いしたいことが冒頭にあるか / 何をどう答えればよいか明確か / 内部の工程記号・スクリプト名・ステータス語を説明なしに使っていないか / 端的か、の5点。
- 最初からこの基準で書く。工程記号(A-6 など)やスクリプト名を使うときは、人間に分かる言葉を添える。
- `[r-super-loop-powers] 人間向けの応答を書き直してください` で始まる指摘を受けたら、内容(事実・判断・質問)は変えずに、指摘どおり書き直した応答を改めて返す。書き直しを求められるのは1回だけ。
- 判定結果は goal 直下の `hook-log.md` に残る(Learning で回数を見る)。判定役が動かない場合は検査なしで通る(記録は ERROR)。

## 例外・停止時の扱い

- どのフェーズでも、人間の入力が必要になったら state.md の「待ち」に内容を書いてから停止する。
- セッションが切れても、次回 `/r-super-loop-powers` 起動時に state.md から再開できる(NFR-04)。代理Fableのインスタンスはセッションを跨いで継続できないため、再開後に代理Fableが必要になった場合は、goal-seed / goal-frame / hearing-log を渡して新しい代理Fableを起動する(記録がある限り文脈は復元できる)。
- **codex委譲はセッションを跨いで生き残る。** 再開時に state.md の `codex-run:` にラベルが残っていたら、まず `codex-status.ps1` でそのラベルを判定してから次の行動を決める(`LOST` なら何も完了していない、`OK` なら結果を回収できる)。判定せずに再委譲しない。
- **実装役の委譲はセッションを跨がない。** 再開時に `impl-runs/<ラベル>.prompt.md` があって `.report.md` が無い委譲は、完了していない。`git status` を確認してから、新しいラベルで再委譲する(`.base.txt` / `.pre.txt` は再委譲時に取り直す)。
- このスキルは Superpowers・gstack等の他スキルのファイルを読むことはあっても、**変更してはならない**(SK-001)。
