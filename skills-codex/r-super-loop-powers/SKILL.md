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
5. **前提チェック(このゴールで初回のみ)**: 次の5点を確認し、満たされない場合はユーザーに報告して停止する。
   - **codex 実行ファイルの絶対パスを解決して控える**。以後の judge / proxy / builder / reviewer の**全呼び出しでこの絶対パスを使う**。`codex` をそのまま(bare で)呼ぶと、バージョンマネージャの shim 解決に失敗して `cannot find binary path` になる環境がある(実測)。解決したパスは state.md の直下に `codex-path: <絶対パス>` として記録する。
   - `<codexパス> --version` が応答すること。
   - **このスキル自身のディレクトリの絶対パスを解決して控える**。設置場所は `CODEX_HOME` に依存し環境ごとに異なるため、起動時チェックで都度解決する。以後 judge の `--output-schema` の指定にこの絶対パスを使う。解決したパスは state.md の直下に `skill-dir: <絶対パス>` として記録する。**解決したパスに `schemas/gate-verdict.json` が実在することを確認する**(存在しない場合、`--output-schema` に渡すと原因不明のハングになる)。存在しなければユーザーに報告して停止する。
   - `gpt-5.6-sol` と `gpt-5.6-luna` が利用可能であること。
   - **ネスト実行の確認**: driver 自身が `<codexパス> exec -s workspace-write -c approval_policy=never --skip-git-repo-check` で1回起動し、「次のシェルコマンドを一字一句そのまま実行し、その最終行を一字一句そのまま報告せよ: `<codexパス> exec -s read-only --skip-git-repo-check "Reply with exactly: NESTED_OK"`」を指示する(内側の呼び出しも bare ではなく `<codexパス>` の絶対パスを使う。軽量モデル・低effortでよい)。応答に `NESTED_OK` が含まれることを確認する。含まれない場合は「このプラグインの設計はサブ役の分離(codex execのネスト実行)に依存しているため続行できない」旨をユーザーに報告して停止する。このチェックはゴールごとに初回1回、codex呼び出しを2回消費する(ユーザーの有料クォータを使う)。

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
- codex-path: <codex実行ファイルの絶対パス>
- skill-dir: <このスキルのディレクトリの絶対パス>
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

サブ役はすべて `codex exec` で起動する。以下の4点は**実測に基づく必須の作法**であり、守らないと原因の分かりにくい失敗をする(起動時チェック5とあわせて参照):

1. **codex は前提チェックで解決した絶対パスで呼ぶ。** bare な `codex` は shim 解決に失敗しうる。以下の規定形の `<codexパス>` はこの絶対パスに置き換える。
2. **プロンプトは引数ではなく stdin(`-`)で渡す。** Windows の引数長・エスケープ問題を避けられる。プロンプトを引数で渡す場合は、**stdin を明示的に閉じる**(`< /dev/null`)。閉じないと codex が標準入力を読みに行き、応答を返さないまま止まることがある。
3. **`--output-schema` と `-o` にはネイティブの絶対パス**(Windowsなら `C:\...` 形式)を渡す。POSIX形式のパスは Windows バイナリが解決できず、これも原因不明のハングになる。
4. 実行の timeout は最長(600000ms)を指定し、長そうな委譲はバックグラウンドで実行する。出力は `-o` でファイルに落とし、driverがそれを読む。

**judge(ゲート・判断。呼び出しごとに新規セッション)**

```bash
<codexパス> exec -m gpt-5.6-sol -c model_reasoning_effort=ultra \
  -C "<tmpdir>" -s read-only --skip-git-repo-check \
  --output-schema "<このスキルのディレクトリの絶対パス>/schemas/gate-verdict.json" \
  -o "<tmpdirの絶対パス>/verdict.json" -
```

`--output-schema` と `-o` のパスは、OSネイティブ形式の絶対パスにする(Windowsなら `C:\...`)。

**proxy(代理。1インスタンスを継続)**

```bash
# 初回
<codexパス> exec -m gpt-5.6-sol -c model_reasoning_effort=max \
  -C "<tmpdir>" -s read-only --skip-git-repo-check \
  -o "<tmpdir>/reply-1.md" - | tee "<tmpdir>/session.log"
# session id は tee したログに現れる最初のUUIDを正規表現で拾う
SID=$(grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "<tmpdir>/session.log" | head -1)
# 往復
<codexパス> exec resume "$SID" -m gpt-5.6-sol -c model_reasoning_effort=max \
  -o "<tmpdir>/reply-<n>.md" "<次の入力>"
```

session id は `state.md` の `proxy-session:` に記録する。UUIDが拾えなかった場合、`--last` は**使わない**(誤ったセッションへ接続するため)。新しい proxy を起動し直し、goal-seed / goal-frame / hearing-log を渡して文脈を再構築する。

**builder(実装)**

```bash
<codexパス> exec -m gpt-5.6-luna -c model_reasoning_effort=max \
  -s workspace-write -c approval_policy=never \
  -o "<milestoneディレクトリ>/builder-report.md" -
```

**reviewer(高信頼のB-5のみ)**

```bash
<codexパス> exec -m gpt-5.6-sol -c model_reasoning_effort=max \
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
共通契約に従い、一時ディレクトリに goal-frame.md 全文 + submission 全文 + assumptions.md の未検証仮定をコピーして judge を `--output-schema`(規定形のとおり `<スキルのディレクトリの絶対パス>/schemas/gate-verdict.json`)付きで起動する。判定観点(適合性・残存未知の許容性・仮定の事実扱い・否定リスト)に加えて「**Checkpoint配置が『人間の受け入れテスト1回でE2E価値を評価できる』単位か**」で「この計画で元の目的を達成できるか」を判定させる。品質の細部ではなくゴール整合性を中心に見る。
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
<codexパス> exec -m gpt-5.6-luna -c model_reasoning_effort=max \
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
policy.md の発火条件(否定リスト該当・ユーザー固有判断・Solution分岐・低確信を含む10件)を検出したら、`templates/escalation.md` の1〜6を整形し、一時ディレクトリに goal-frame.md + 1〜6 + 関連する未検証仮定(assumptions.mdの該当行、あれば) + hearing-log.md の関連部分(あれば)をコピーして judge を `--output-schema`(規定形のとおり `<スキルのディレクトリの絶対パス>/schemas/escalation-verdict.json`)付きで起動する。judgeは **DECIDE**(判断+根拠)または **ASK_HUMAN**(人間向け質問文)を返す。返った内容を7(判定)欄へ整形して記入する。ASK_HUMANの場合はdriverが人間へ提示し、回答を hearing-log.md に追記してから続行する。文書を milestone ディレクトリに `escalation-<連番>.md` として保存し、call-logに記録。

**B-5 レビューとSubmission作成(driver)**
- **MVP**: driverが**セルフチェック**(goal-frame承認基準との対応・残存未知の列挙・未検証仮定の確認)を行い、`decisions.md` の4区分(要件由来 / Agent仮説HOW / 低確信 / 発見された未知)を確定させ、`templates/approval-submission.md` に従い `milestones/<n>-<名前>/submission.md` を作成する(判断記録欄から decisions.md を参照)。
- **高信頼**: reviewer(`gpt-5.6-sol` / max、**実装に関与していない新規セッション**。PL-003)を起動し、goal-plan.md該当部・マイルストーン定義・diff・検証証拠を渡してレビューさせ、結果を反映してsubmissionを作成する。call-logに記録(reviewer)。
- どちらの場合も**残存未知リスト・仮定台帳サマリ・decisions.mdの確定**を必須とする(欠けたままB-6へ進まない)。

**B-6 Implementation Gate(judge・新規セッション)**
前提確認: submission.md が存在し、検証証拠と残存未知リストが含まれること。
共通契約に従い、一時ディレクトリに goal-frame.md + マイルストーン定義 + submission.md + assumptions.md の未検証仮定をコピーして judge を `--output-schema`(規定形のとおり `<スキルのディレクトリの絶対パス>/schemas/gate-verdict.json`)付きで起動し、判定観点で「このマイルストーンのゴールを満たし、残存未知が許容可能か」を判定させる。返ったJSONを `gate-decision.md` へ整形保存、call-logに記録。
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
- セッションが切れても、次回 `$r-super-loop-powers`(環境によっては `$r-super-loop-powers:r-super-loop-powers`)起動時に state.md から再開できる(NFR-04)。`proxy-session:` に session id が残っていれば `codex exec resume` で同じ proxy を継続する。resume が失敗した場合のみ、goal-seed / goal-frame / hearing-log を渡して新しい proxy を起動する(記録がある限り文脈は復元できる)。
- このスキルは Superpowers・gstack等の他スキルのファイルを読むことはあっても、**変更してはならない**(SK-001)。
