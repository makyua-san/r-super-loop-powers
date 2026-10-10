---
name: r-super-loop-powers
description: Use when starting or resuming a goal-engineering loop (ゴールループ / goal loop / ゴールエンジニアリング開発). Superpowersの上位で、要件適合性と未知低減を目的に、フェーズ管理・成果物契約・Fable承認ゲート・ヒューマン・イン・ザ・ループ配置・モデル責任分担(Opus 5.5実行 / Fable判定 / Codex gpt-6.1-sol技術PM・技術レビュー(読み取り専用) / Sonnet 5.5実装)をオーケストレーションする。MVPモードではFableヒアリングでゴールと文脈を掘り、HOWは代理ブレスト(Fable=ユーザー目線 / Codex技術PM=実装責任者目線)でAgentへ委任し、Checkpoint単位でHuman Acceptanceを行う。
---

# r-super-loop-powers — ゴールループ・オーケストレーター

あなた(このスキルを実行するモデル)は **Opus 5.5メインセッション** として、ゴールループの進行管理と成果物作成を担当する。
このスキルは **責任・ゲート層** である: いまどのフェーズか、次に必要な成果物は何か、誰が実行し誰が判定するか、人間へ返すタイミングだけを制御する。
作業の進め方(HOW)はSuperpowersのスキルに完全に委ね、その内部手順には一切干渉しない。MVPモードでは、Superpowersのスキルが人間に求める質問・承認への応答を**代理Fable**(ユーザー目線)と**技術PM**(Codex。実装責任者目線でHOWに係る問いに回答)が分担する。文脈は使い捨てにする: 正本はファイルで、境界ごとに `/clear` して再開パケットから続ける(「境界リセット」)。
各担当(あなた自身を含む)の立場・決めること・決めないことは `references/roles.md`(ロール憲章)にまとめてある。

Goal Loopの目的は **A. 要件適合性** と **B. 未知の低減** の2つ(policy.md「上位原則」「MVPモードの原則」)。ループ・テスト・レビュー・承認は、AまたはBに寄与する場合にのみ実施する。ループ終了条件は回数ではなく「適合性への十分な確信 + 残存する重要な未知が許容可能」。

## 起動時チェック(毎回必ず実行)

1. **ポリシー読込**: このスキルと同じディレクトリの `policy.md` を読む。以後の全判断はこのポリシーに従う。`references/roles.md`(ロール憲章)は起動時には読まず、Fable への依頼文を組む直前に「全体図 (overview)」と該当ロールの節だけを読む(「Fableサブエージェント共通契約」)。自分(Opus)の憲章の要点: ゲートの合否(ゲートFable)・受け入れ(人間)・委譲の成否(impl-check / codex-status)・実装方式(技術PM)は自分では決めない。実装は実装役に委譲する。人間向けの応答はフックが検査する。
2. **モデル確認**: 自分が **Opus 5.5** で動いていない場合、ユーザーに `/model opus` への切替を提案し、切替またはユーザーの明示的な続行指示があるまでフェーズ作業を開始しない(PL-002)。
3. **状態復元**:
   - **再開パケットが注入されている場合**(会話の先頭に `# 再開パケット — <goal-slug>` がある): それが state.md の正本である。Glob で探し直さない。パスとプレビューの形で来たら(上限超過)、先に `resume-packet.md` を全部読む。最初の応答で「フェーズ / 強度 / マイルストーン / 次のゲート / 待ち」をパケットの state.md の文面どおりに**復唱**してから手順に入る。パケットの「未完了の委譲」に codex のラベルがあれば `codex-status.ps1` で判定し、実装役のラベルがあれば `git status` を見てから次を決める。「待ち」が人間の回答待ちなら、ユーザーの今回のメッセージをその回答として扱う。
   - **注入されていない場合**: 対象プロジェクトで `docs/r-super-loop-powers/*/state.md` を探す(Globツール)。見つかった場合: 最新の state.md を読み、同じ 5 項目を 1〜3 行でユーザーに報告し、そのフェーズの手順から再開する。見つからない場合: ワークフローA(新規ゴール)を開始する。
   - 各フェーズの入口(A-5・B-1・B-5・B-7・Learning の冒頭)でも state.md を読み直す(ファイルの値に従う)。
4. **強度確認**: goal-frame.md が存在する場合、ループ強度(MVP | 高信頼)を読み、policy.md「ループ強度」の工程表に従って以後の工程を実施する。強度未確定のままワークフローBへ進まない。
5. **スキルディレクトリの解決(このゴールで初回のみ。以後は state.md の `skill-dir:` を再利用)**:
   Globツールで `**/skills/r-super-loop-powers/bin/codex-preflight.ps1` を探す(`$CLAUDE_PLUGIN_ROOT` 配下、`~/.claude/plugins/cache/`、`~/.claude/skills/`、対象プロジェクトの `.claude/skills/`)。複数ならバージョンが新しいもの。見つからなければユーザーに報告して停止する(スクリプトなしでcodexを手書きで呼ばない)。親ディレクトリを `skill-dir:` として state.md に記録する。
6. **codex実行系のプリフライト(このゴールで初回のみ。以後は state.md の `codex-env:` を再利用)**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\codex-preflight.ps1" -EnvOut "<goal-dir>\codex-env.json"
   ```
   codex実体・バージョン・認証・モデル疎通を1回で確認する。codex は**技術PM・技術レビュー(高信頼)・グラレコの3ロールだけ**、**すべて `gpt-6.1-sol` の読み取り専用**で使う(実装はSonnetサブエージェント)。`PREFLIGHT: OK` なら `codex-env.json` のパスを state.md の `codex-env:` に記録する。`FAILED` なら `REASON:` をそのままユーザーへ提示して**停止する**(黙って別モデルへ落とさない。代替はユーザーが指名した場合のみ `-Model`)。旧 codex-env.json の扱いは `references/codex-invocation.md` 2-1。
7. **実装役エージェントの確認**: Agentツールで使えるエージェント種別に `r-super-loop-powers:builder`(Sonnet 5.5)があることを確認する。無い場合(更新後に再起動していない等)はユーザーに報告して停止する。**汎用エージェントや `model: sonnet` 指定で実装を代行させない**。
8. **対象プロジェクトの git 確認**: git リポジトリでない、またはコミットが1つも無い場合、`impl-check.ps1` は基準コミットが無いと実装役の変更を判定できない。そう説明して `git init` + 初回コミットを承認してもらう。**承認なしでワークフローBを開始しない。** Opus が自分の判断で `git init` やコミットをしない。
9. **手順書の読込**: state.md の phase が `goal-definition`(または新規ゴール)なら `references/workflow-a.md` を、それ以外なら `references/workflow-b.md` を読む。**両方は読まない**(A-8 → B-1 の境では境界リセットの後に B を読む)。

   ゴール開始前にチェック7・8を通さずにワークフローBへ進まない。

## ディレクトリ契約

対象プロジェクト内に次を作成・維持する:

```
docs/r-super-loop-powers/<goal-slug>/
├── state.md                 # 現在地(下記フォーマット)
├── goal-seed.md             # 人間の意図(原文のまま)
├── hearing-log.md           # A-1aヒアリングとASK_HUMAN中継の記録
├── goal-frame.md            # Fable入口出力 = 承認基準・強度・未知マップ・終了条件の原本
├── assumptions.md           # 仮定台帳(全フェーズで追記)
├── goal-plan.md             # spec/planリンク + マイルストーン一覧(Checkpoint印) + 主要設計判断
├── tech-assessment.md       # 技術PMのマイルストーン別実装アセス(MVP・A-4末)
├── goal-plan-submission.md  # A-5 Goal Plan承認用submission
├── goal-gate-decision.md    # A-6 Goal Gate判定
├── call-log.md              # 呼び出し記録(PL-007。loop-log.ps1 が追記)
├── hook-log.md              # フックの記録(Stop: PASS/BLOCK/ERROR、再開注入: RESUME/STALE/ERROR、文脈メーター: CTX)
├── resume-pending           # 境界リセットの印(loop-log.ps1 -Mark が置き、SessionStart フックが消す。24 時間で無効)
├── resume-packet.md         # 直近の再開パケット全文(resume-packet.ps1 が書く)
├── codex-env.json           # 起動時チェック6のプリフライト結果
├── codex-runs/              # codex(技術PM・技術レビュー・グラレコ)の実行記録
├── impl-runs/               # 実装役への委譲記録(<ラベル>.prompt.md / .base.txt / .pre.txt / .report.md)
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
- codex-run: <実行中の codex 委譲ラベル。なければ ->     # 起動したら記入、判定が確定したら消す
- updated: YYYY-MM-DD HH:MM
```

各欄の値は上の語をそのまま書く(`**done**` のような装飾をしない。`phase` はフックの判定に使う)。欄の更新は `loop-log.ps1` で行う。
**全フェーズで「state.md更新 → 作業」の順**を守る。フェーズ遷移の前に、下表の必須成果物が揃っているかを必ず確認し、欠落があれば次へ進まない。

## フェーズと成果物契約

| フェーズ | 入口条件 | このフェーズで必須の成果物 | 出口のゲート |
|---|---|---|---|
| goal-definition | goal-seed.md | (MVP: hearing-log.md →) goal-frame.md(強度確定) → spec/plan → goal-plan.md(Checkpoint印) → goal-plan-submission.md | Goal Gate(Fable)→ Human承認(MVPはWHATレベル) |
| milestone-implementation | Goal Plan承認済み + 強度確定 | 実装diff + 検証証拠(高信頼のみ: 独立レビュー) → decisions.md → submission.md(残存未知リスト付き) | Implementation Gate(Fable)。MVPの非CheckpointはPASS後、人間承認なしで次マイルストーンへ |
| human-acceptance | Fable PASS(MVP: Checkpoint到達時のみ) | human-report.md(評価パッケージ) | 人間のACCEPT/REJECT |
| finalization | acceptance.md に ACCEPT | 確定処理(確定コミット) | なし |
| learning | 確定処理済み | retro.md + grareco-input.md(+ grareco.png) | なし |

工程の本文はフェーズごとの手順書にある: ワークフローA(A-0〜A-8)= `references/workflow-a.md`、ワークフローB(B-1〜B-10)と Learning = `references/workflow-b.md`。

## 仮定台帳の運用

- `templates/assumptions.md` の形式で goal直下に置き、全フェーズで追記する。追記のタイミング: (1) ヒアリング・ブレスト中に人間または代理Fableが「決めていない / わからない」と答えたとき (2) 実装・設計で仮説的判断をしたとき (3) エスカレーションや Human Feedback で新しい未知が見つかったとき。
- 各仮定には「ゴールへの寄与」1行を必ず書く(局所最適化ガード)。**policy.md「仮説自律の否定リスト」に触れる仮定は自律実行しない** — エスカレーション(B-4)または人間確認へ。
- 検証されたら状態を「検証済み」または「棄却」に更新する(棄却時は必要なら新しい仮定を起こす)。

## 記録ルール(PL-007)と記帳スクリプト

fable / codex-techpm / codex-review / codex-grareco / sonnet-builder を呼ぶたび、および代理Fableとの SendMessage 往復のたびに、直後に `call-log.md` へ 1 行追記する。追記・state.md の更新・再開の印は、すべて `bin/loop-log.ps1` で **1 回の呼び出し**にまとめる(手で `Add-Content` や Write をしない。記帳だけのターンを増やさない):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\loop-log.ps1" -GoalDir "<goal-dir>" `
  -Who sonnet-builder -Purpose "B-2 m1-impl" `
  -SetMilestone "1-<名前>" -SetGate impl-gate -Clear 待ち
```

- `-Who <役> -Purpose <目的> [-Phase <phase>]`: call-log に `YYYY-MM-DD HH:MM | <役> | <phase> | <目的>` を追記(phase 省略時は state.md の値)
- `-SetPhase` / `-SetIntensity`(強度)/ `-SetMilestone` / `-SetCheckpoint`(次のCheckpoint)/ `-SetOwner`(担当)/ `-SetGate`(次のゲート)/ `-SetWait`(待ち)/ `-SetCodexRun`: state.md の欄を更新(`updated:` は自動)。他の欄は `-Set 'key=value'`(1 つ)。欄を「なし(`-`)」に戻すときは `-Clear '待ち,codex-run'`(単独の `-` は起動引数として渡せない)
- `-Mark`: 境界リセットの印を置く(「境界リセット」)
- `STATUS: OK` を確認する。`FAILED` のときは何も書かれていない(`REASON:` を見る)
- 報告の転記は `impl-check.ps1 -SaveReport` / `codex-status.ps1` が担う(同じ内容を 2 度書かない)

## ゲート保護ルール(絶対)

1. Fable PASS 前に人間へ受け入れを求めない(SK-007)
2. human-report.md(評価パッケージ)なしで Human Acceptance に進まない(SK-008)
3. Checkpoint(高信頼はマイルストーン)の acceptance.md に ACCEPT がない状態で確定処理をしない(SK-009)。MVPの中間コミット(B-6 PASS後)は可
4. 必須成果物が欠けた状態でFableゲートを呼ばない — 欠落は自分で差し戻して埋める(NFR-05)
5. 実装役(Sonnet)にも codex にもコミットさせない
6. 否定リストに触れる仮説を自律実行しない — エスカレーションまたは人間確認へ
7. 代理ブレストに参加したFableインスタンスにゲート判定(A-6 / B-6)をさせない(自己承認の禁止)(SK-010)
8. **成否は機械判定で決める。** codex は `codex-status.ps1`、実装役は `impl-check.ps1` の `STATUS: OK` 以外を成功として扱わない。プロセスが消えたこと・報告が返ったことは、いずれも単独では完了の証拠にならない。判定を目視や推測で代替しない
9. codexの呼び出しは `bin/` のスクリプト経由でのみ行う。起動コマンドを自分で組み立てない。実装役は Agentツールの `r-super-loop-powers:builder` でのみ起動する
10. codex は助言・レビュー・画像生成の**読み取り専用ロール**である。必ず `-Role techpm | reviewer | grareco` のいずれかで起動し(スクリプトが read-only を強制する)、コード変更・設計承認・要件適合の判定をさせない
11. 実装役は実行者である。設計・計画・選択肢の提示をやり直させない。承認済みの技術アセス(高信頼は人間承認済みの plan)をプロンプトに入れずに委譲しない

## Fableサブエージェント共通契約

- Agentツールで `model: "fable"` を指定して起動する。役割は2種類あり、**インスタンスを分離する**:
  - **代理Fable(MVPのA-1a〜A-4)**: nameを付けて1インスタンスを起動し、SendMessageで往復を継続する(ヒアリング文脈の保持)。入力は goal-seed / goal-frame / hearing-log / retro抜粋 / templates構造のみ。
  - **ゲート・判断Fable(A-6 / B-1 / B-4 / B-6 / B-9)**: 呼び出しごとに新規インスタンス。初回入力は goal-frame.md 全文 + 対象文書(submission / escalation / milestone定義) + assumptions.md の関連部分(未検証仮定) + 必要なら hearing-log.md の関連部分のみ。対象プロジェクトの生コード・全会話履歴を渡さない(PL-009)。追加資料を要求した場合のみ、SendMessageで1往復の追加提供を行う。
- **ロール憲章の貼り付け(必須)**: 起動時の依頼文の冒頭に、このときだけ roles.md を開き、`<skill-dir>\references\roles.md` の「全体図 (overview)」節と該当ロールの節(代理Fable → 「代理Fable (proxy-fable)」、ゲート・判断Fable → 「ゲートFable (gate-fable)」)を**原文のまま**貼り、その後に各工程の依頼文を続ける。要約・言い換えをしない。代理Fableには初回起動時だけ貼る(SendMessage の往復では再送しない)。
- ゲート判定の出力契約: `PASS | REVISE | REPLAN | BLOCKED` のいずれか1つ + 根拠(5行以内) + REVISE/REPLANの場合は戻り先工程と対象の未知・仮定。
- 判定観点(プロンプトに明記する): (1) goal-frame.md の承認基準を満たすか (2) 残存する重要な未知が許容可能か(goal-frameの終了条件と照合) (3) 仮定が事実として扱われていないか (4) 否定リスト違反の仮説がないか。「動くか」ではなくゴール整合を見る。

## 境界リセット(/clear と再開パケット)

長い文脈は精度を落とし、コンパクションは制約を取りこぼす。このハーネスでは**正本はファイル、セッションは使い捨て**にする: 境界で state.md を更新し、印を置き、人間に `/clear` してもらう。`/clear` の直後に SessionStart フック(`hooks/resume-inject.ps1`)が `bin/resume-packet.ps1` で組んだ**再開パケット**(state.md 全文・待ち・否定リスト・goal-frame の制約/承認基準/終了条件・対象マイルストーン・未検証仮定・直近の判定と retro の「次回変えること」・未完了の委譲。要約なし)を会話の先頭に注入する。フックは `/` コマンドを起こせないので、`/clear` は人間が打つ。

**境界**(ここで切る):
- (a) 人間の入力待ちに入るとき(「待ち」を書いた直後)
- (b) **条件付き**: B-6 PASS の中間クローズのあと。PostToolUse フック(`hooks/context-meter.ps1`)が「現在の文脈は約 N 万トークンで、境界リセットの目安(20 万)を超えている」と知らせているときだけ。知らせが無ければ切らずに次の B-1 へ進む
- (c) Checkpoint の ACCEPT を確定処理(B-10)し、Learning を終えて次のマイルストーンへ戻るとき
- (d) A-8 の Goal Plan 承認のあと(ワークフローBに入る前)
- **切らない区間**: 代理Fable が生きている A-1a〜A-4(SendMessage の相手はセッションを跨げない)

**手順(1 ターン)**:
1. `loop-log.ps1 -GoalDir "<goal-dir>" -SetPhase … -SetMilestone … -SetWait … -Mark`(変える欄だけ。`-Mark` が `resume-packet.md` を組んで印 `resume-pending` を置く。`MARKED:` を確認する)
2. ターンを終える。人間への文の末尾に「`/clear` のあと「続けて」と送ってください(文脈を捨てて、ファイルから再開します)」を添える。(a) では待ちの内容(質問・承認依頼)を先に書く
3. `/clear` 後の最初の応答で、起動時チェック 3 の復唱を行う

- 印は 24 時間で無効になる(その場合は従来どおり state.md から再開する)。印は `/clear` か新規起動でだけ使われ、`/compact` や `--resume` では使われない
- パケットは 9,500 文字に収まるよう後方の節(マイルストーン・仮定・判定・retro)だけが切られ、全文は `<goal-dir>/resume-packet.md` にある。制約系の節は切られない(それだけで超えるときは切らずに渡す。`-Mark` の `WARN:` で分かる)
- `/clear` されずに続いた場合もそのまま続行してよい(印は次の `/clear` で使われる)。フックの記録は `hook-log.md` の `RESUME` / `STALE` / `ERROR` / `CTX` 行

## プラグインのフック

プラグインは 3 つのフックを持つ: SessionStart(再開パケットの注入)・PostToolUse(Agent 呼び出し後の文脈メーター)・Stop(人間向け応答チェック)。前 2 つは「境界リセット」のとおり。Stop は、ゴールループ中(phase が done でない state.md がある)にあなたが人間へ返す応答を、日本語か / 結論やお願いが冒頭か / 何をどう答えればよいか明確か / 内部用語を説明なしに使っていないか / 端的か、の5点で検査する。最初からこの基準で書く。`[r-super-loop-powers] 人間向けの応答を書き直してください` で始まる指摘を受けたら、内容は変えずに書き直して返す(1回だけ)。結果は `hook-log.md` に残り、判定役が動かないときは検査なしで通る。

## 読むものと読まないもの(文脈を薄く保つ)

| いつ | 読む | 読まない |
|---|---|---|
| 起動時 | SKILL.md(これ)・policy.md・再開パケット(あれば)・phase に応じた `references/workflow-a.md` **または** `workflow-b.md` | roles.md 全文・両方の workflow |
| Fable を呼ぶ直前 | roles.md の「全体図 (overview)」と該当ロールの節 | roles.md の他の節 |
| codex を呼ぶとき | `references/codex-invocation.md`(初回) | — |
| 実装役の報告 | Agent の最終メッセージ(文脈に 1 回入る)→ `impl-check.ps1 -SaveReport` で保存と判定 | `.report.md` の読み直し |
| 画像(スクショ・グラレコ) | 読まない。確認が要るなら Agent(model: sonnet)に見せて 5 行で返させる。人間に渡すなら SendUserFile かパス | Read ツールで画像を開く |
| シェルの結果 | 失敗分だけ(テストは `… \| grep -E 'FAIL\|ALL PASS'` のように、`FAIL` / `FAILURES` / `ALL PASS` の行だけを出す)。切り詰めてよいが要約はしない | 全出力 |
| 大きな文書(hearing-log・spec・plan・アセス) | 必要な節だけ(Grep / 行範囲)。codex には貼らずパスで渡す | 全文の Read |

## 例外・停止時の扱い

- どのフェーズでも、人間の入力が必要になったら「待ち」を書き、境界リセット(a)を行ってから停止する(代理Fable が生きている A-1a〜A-4 では「待ち」だけを書く)。
- セッションが切れても、次回 `/r-super-loop-powers` 起動時に state.md(または再開パケット)から再開できる(NFR-04)。代理Fableのインスタンスはセッションを跨いで継続できないため、再開後に代理Fableが必要になった場合は、goal-seed / goal-frame / hearing-log を渡して新しい代理Fableを起動する(記録がある限り文脈は復元できる)。
- **codex委譲はセッションを跨いで生き残る。** 再開時に state.md の `codex-run:` にラベルが残っていたら、まず `codex-status.ps1` でそのラベルを判定してから次の行動を決める(`LOST` なら何も完了していない、`OK` なら結果を回収できる)。判定せずに再委譲しない。
- **実装役の委譲はセッションを跨がない。** 再開時に `impl-runs/<ラベル>.prompt.md` があって `.report.md` が無い委譲は、完了していない。`git status` を確認してから、新しいラベルで再委譲する(`-Prepare` を取り直す)。
- このスキルは Superpowers・gstack等の他スキルのファイルを読むことはあっても、**変更してはならない**(SK-001)。
