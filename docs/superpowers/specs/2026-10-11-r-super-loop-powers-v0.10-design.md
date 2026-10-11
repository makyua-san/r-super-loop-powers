# r-super-loop-powers v0.10 設計仕様書 — スカウト(codex による調査の肩代わり)(Claude版)

- 作成日: 2026-10-11
- 対象: Claude版 `skills/r-super-loop-powers/`(SKILL.md・bin/・references/・policy.md)・`agents/builder.md`(roles.md の全体図の同期のみ)・`.claude-plugin/plugin.json`・`tests/`・README のClaude版節。Codex版 `skills-codex/` と `templates/` は**変更しない**
- 前提: v0.9.0(main、commit 5982967)
- rb: rb-adawn5(RB-58「codexの使い所を増やす」)

## 0. 目的

Claude 側(Opus メイン)の契約枠が足りず、codex の契約枠が余っている。今の codex は技術PM・技術レビュー(高信頼のみ)・グラレコの 3 ロールで、1 ゴールあたりの呼び出しは数回に留まる。一方で Opus は、ブレスト前の現状把握・plan に書く対象ファイルの特定・委譲文に書く範囲の確認・REJECT 後の原因調査といった「読んで事実を集める」仕事を、自分で Read / Grep を重ねるか Claude のサブエージェント(Explore 等。調査ノート 2026-10-10 で文脈 106K〜135K / 15〜44 ターン)に出して行っている。

v0.10 は、この「調べもの」を codex の 4 つ目の読み取り専用ロール **スカウト(scout)** に移す。目的は Claude の消費を codex へ振り替えることで、精度の向上ではない(精度は落とさない)。

- codex に編集はさせない(v0.7 の決定 D34 を保つ)。読む・検索する・Web を引く・報告を書く、だけ。
- 成果物はファイル(`<goal-dir>/scout/`)で管理し、Opus の文脈には結論の数行だけが入る。
- 呼び出しは **1 回のシェル呼び出し**(`bin/scout.ps1`)で起動から保存・記帳まで終える。記帳だけのターンを増やさない(v0.9 の D62 と同じ方針)。
- 工程(A-0〜A-8 / B-1〜B-10)・成果物契約・ゲート規律は変えない。

ユーザーの判断(2026-10-11): 実装役を codex に戻すかは**別タスク**で扱う(v0.7 で Sonnet にした理由「精度と効率」を覆す根拠がまだ無い)。Opus の筆記(submission 等)の移管・MVP での codex レビュー・ゲート Fable の下調べも本改訂の範囲外(§12)。

## 1. 事実確認(2026-10-11)

| # | 事実 | 設計への影響 |
|---|---|---|
| F19 | `codex-cli 0.160.0` の `codex features list` では `web_search_request` / `web_search_cached` が **deprecated**、`standalone_web_search` が under development。Web 検索は feature フラグではなく設定キー(`web_search = "live" \| "cached" \| "disabled"` 系と見られる。未確認)で制御する版になっている | どのキーが read-only サンドボックスで効くかは**スパイク(§10-1)で確かめてから** `codex-run.ps1` に定数として入れる。確かめずに書かない |
| F20 | `bin/loop-log.ps1` の `-Who` は閉じた語彙(`$Roles = fable / codex-techpm / codex-review / codex-grareco / sonnet-builder`)で、未知の値は失敗する | `codex-scout` を足す(policy.md PL-007・call-log 形式も同時に) |
| F21 | `bin/codex-status.ps1` のロール別の特別扱いは grareco(画像の有無)だけで、他のロールは共通の判定(exit / `turn.completed` / 最終メッセージ)を通る | scout は共通の判定で足りる。`codex-status.ps1` は変更しない |
| F22 | `codex-run.ps1` の実行契約 1 項は `~/.claude/`・`.claude/`・`~/.codex/`・`skills/`・`SKILL.md` を読むことを禁じ、`codex-status.ps1` が `BOUNDARY_HIT` で検出する | scout にもそのまま適用する。調べる相手は対象プロジェクトとゴール文書(`docs/r-super-loop-powers/<goal>/`)だけ |
| F23 | `codex-run.ps1` は `-Model` 未指定なら `codex-env.json` の `model`(`gpt-6.1-sol`)を使い、effort の既定はロール別(techpm / reviewer: max、grareco: low) | scout は `gpt-6.1-sol` / 既定 `medium`(ユーザー判断 2026-10-11)。モデルを 2 本にしない |
| F24 | 調査ノート(2026-10-10)§「サブエージェント」: Opus(Explore 等)の調査は文脈 106K〜135K・15〜44 ターン・出力 16K〜32K。Fable ゲートも「探索したがる」 | 移す対象は Opus 本体と Opus が立てる調査サブエージェント。Fable の探索は v0.10 では扱わない(§12) |

## 2. 設計決定(D71〜D80)

| ID | 決定 | 内容 |
|---|---|---|
| D71 | ロール | `codex-run.ps1 -Role scout` を足す。read-only・`gpt-6.1-sol`・effort 既定 `medium`。ロール指示(brief)の要点: 渡された問いに、対象プロジェクトとゴール文書(指示があれば Web も)を読んで答える / 設計の提案・要件の判断・コードの変更・プロセススキルの起動はしない / 見つからなければ見つからないと書く / §4 の固定の型で報告する / Web が使えなかったら `## 未確認` に `WEB_UNAVAILABLE` と書く。`references/roles.md` に「スカウト (scout)」の節を足し、`codex-run.ps1` が他ロールと同じく差し込む |
| D72 | まとめ役 | `bin/scout.ps1`(§3)が、prompt 生成 → `codex-run.ps1 -Role scout` → `codex-status.ps1` 待ち → 型の検査 → `scout/<label>.md` 保存 → `scout/index.md` 追記 → `loop-log.ps1 -Who codex-scout` を **1 回の呼び出し**で行う。Opus はこの 1 本だけを呼ぶ(`codex-run.ps1 -Role scout` を直接呼ばない) |
| D73 | 成果物の置き場 | `<goal-dir>/scout/`。`<label>.md`(報告。先頭に日時・web・effort・問いのメタ行)と `index.md`(1 行 1 件: `YYYY-MM-DD HH:MM \| <label> \| web:y\|n \| <問い(120 字で切る)>`)。型を満たさない報告は `<label>.raw.md` に残し、index には載せない。ラベルは `scout-<連番>`(`codex-runs/scout-*.meta.json` の最大値 + 1)。実行記録(prompt / out.jsonl / last.txt 等)は従来どおり `codex-runs/` |
| D74 | 報告の型 | `## 問い` / `## 結論`(5 行以内)/ `## 根拠`(主張ごとに `file:line` か URL)/ `## 未確認`。`scout.ps1` は `## 結論` と `## 根拠` の見出しの有無を機械で確かめ、欠ければ `STATUS: INCOMPLETE`(§3)。「結論はあるが根拠が無い」報告を Opus が事実として扱わないための線。行数や根拠の形式までは検査しない(モデルの揺れで止めない) |
| D75 | Opus に入るもの | `scout.ps1` の標準出力は KV 行だけ: `STATUS` / `LABEL` / `REPORT`(パス)/ `CONCLUSION`(`## 結論` の本文、最大 5 行。1 行 1 KV)/ `UNVERIFIED`(`## 未確認` の行数)/ `WEB` / `ELAPSED_MIN`。Opus は報告ファイル全文を読まない(必要な根拠だけ Grep / 行範囲で見る) |
| D76 | 失敗時 | `STATUS: OK` 以外では保存も index も記帳もしない(`codex-status.ps1` の STATUS と `NEXT` をそのまま中継)。Opus は**同じ問いで 1 回だけ再実行**し、再度 OK 以外なら自分で調べ、`loop-log.ps1 -Who codex-scout -Purpose "<label>: FAILED→Opus が代行"` と記帳する。グラレコと同じく、スカウトの失敗でループは止めない(ゲート保護ルール 8 の「OK 以外で止まる」の例外に加える) |
| D77 | Web | `scout.ps1 -Web` → `codex-run.ps1 -Web` → スパイク(§10-1)で確定したキーを `-c` で渡す。`-Web` 無しでは渡さない(既定はリポジトリだけ)。`-Web` は scout 以外のロールでも受け付けるが、SKILL.md では scout にだけ使うと書く。報告の `## 未確認` に `WEB_UNAVAILABLE` があれば `WEB: unavailable` を出す(Opus が Web 調査を自分で行う判断材料) |
| D78 | 非同期 | `-Async` は起動だけして `STATUS: STARTED` / `LABEL:` を返し、`loop-log.ps1 -SetCodexRun <label>` で state.md に置く。`-Collect <label>` が待ち・検査・保存・記帳を行い `-Clear codex-run` する。同期(既定)では `codex-run:` に書かない(待っている間にセッションが切れても、`resume-packet.ps1` が `.exit` の無い `codex-runs/` のラベルを「未完了の委譲」として列挙するので、再開時に `-Collect` で回収できる) |
| D79 | 使う規則 | SKILL.md「読むものと読まないもの」に 1 行: **調べものはまずスカウト**。Opus 本体が自分で読むのは「場所が分かっている 1〜2 ファイル(または 1 回の Grep)」まで。ゴールループ中は調査用の Claude サブエージェント(Explore / general-purpose / Plan)を立てない。投げる前に `scout.ps1 -List` で同じ問いが無いか引く。使い所を workflow-a / b に 1 行ずつ(§6) |
| D80 | 版 | `0.10.0`。Codex版・テンプレートは変更しない(`scripts/sync-templates.ps1 -Mode Verify` が通り続ける)。roles.md の全体図を変えるので `scripts/sync-roles.ps1` で `agents/builder.md` を同期する(`tests/roles-sync.tests.ps1`) |

## 3. `bin/scout.ps1`

### 3-1. 引数

```
scout.ps1 -GoalDir <dir> -WorkDir <repo> (-Question <text> | -QuestionFile <path>)
          [-Web] [-Effort low|medium|high|xhigh|max] [-WaitMinutes 9] [-Label <l>] [-Async]
scout.ps1 -GoalDir <dir> -Collect <label> [-WaitMinutes 9]
scout.ps1 -GoalDir <dir> -List
```

- `-GoalDir`: ゴールディレクトリ。`codex-env.json`(`-EnvFile` で上書き可)・`codex-runs/`・`scout/`・state.md・call-log.md はここから引く
- `-WorkDir`: 対象プロジェクトのルート(codex の作業ディレクトリ。read-only で読む範囲)
- `-Question` / `-QuestionFile`: 問い。どちらか 1 つ。`-File` 起動で改行を含む長文を渡しにくいので、長い問いはファイルで渡す
- `-Effort`: 既定 `medium`(`codex-run.ps1 -Role scout` の既定に委ねる)
- `-WaitMinutes`: 待ちの上限。既定 **9**、上限 9(`codex-status.ps1` が 9 分で切るのと同じ理由: Bash ツールの最長 10 分に収める)。Opus は `scout.ps1` を Bash ツールの `timeout: 600000` で呼ぶ。時間内に終わらなければ `codex-status.ps1` の `RUNNING` / `STALLED` をそのまま中継し `NEXT: scout.ps1 -Collect <label>` を出す(走っている codex は止めない。`-Abort` はしない)
- `-Label`: 省略時 `scout-<連番>`
- `-Async` / `-Collect` / `-List`: D78 / D79

### 3-2. 同期の流れ

1. `scout/` と `codex-runs/` を無ければ作る。ラベルを決める。同じラベルの `meta.json` があれば `REFUSED`(上書きしない)
2. `codex-runs/<label>.prompt.md` を書く(UTF-8 BOM なし・LF):
   ```
   == TASK: SCOUT ==
   ## 問い
   <問い>
   ## 調べる範囲
   - 対象プロジェクト: <WorkDir>(作業ディレクトリ。git grep / rg / 直接読む)
   - ゴール文書: <GoalDir>(state.md・goal-frame.md・goal-plan.md・assumptions.md・decisions.md・scout/ の過去の報告)
   - Web: 使ってよい / 使わない    ← -Web の有無
   ## 報告の型(この 4 節をこの順で。最終メッセージだけが読まれる)
   ## 問い / ## 結論(5 行以内) / ## 根拠(主張ごとに file:line か URL) / ## 未確認
   ```
3. `codex-run.ps1 -EnvFile … -Label <label> -PromptFile … -WorkDir <WorkDir> -RunDir <GoalDir>\codex-runs -Role scout [-Effort …] [-Web]` を起動する。失敗(exit ≠ 0)なら `STATUS: FAILED` とその出力を中継して終わる
4. `-Async` ならここで `loop-log.ps1 -SetCodexRun <label>` を行い、`STATUS: STARTED` / `LABEL:` / `NEXT: scout.ps1 -Collect <label>` を出して終わる
5. `codex-status.ps1 -RunDir … -Label <label> -WaitMinutes <n>` で待つ。`STATUS: OK` 以外は、その `STATUS` と `NEXT` を中継して終わる(exit 1。`RUNNING` / `STALLED` のときの `NEXT` は `scout.ps1 -Collect <label>` に置き換える)
6. `<label>.last.txt` を読み、`## 結論` と `## 根拠` の見出し(`^##\s*\d*\.?\s*(結論|根拠)`)を検査する。欠けていれば `scout/<label>.raw.md` に保存して `STATUS: INCOMPLETE` / `REASON: missing section <名>` / `RAW: <パス>`(exit 1)
7. `scout/<label>.md` に保存する: 先頭にメタ行(`- 日時:` / `- label:` / `- web:` / `- effort:` / `- 問い:`)、空行、本文(last.txt そのまま)。`index.md` に 1 行追記(無ければ見出し行を先に書く)
8. `loop-log.ps1 -GoalDir <GoalDir> -Who codex-scout -Purpose "<label>: <問いの先頭 80 字>"`。state.md の `codex-run:` がこのラベルなら同じ呼び出しで `-Clear codex-run`(同期の実行では置いていないので触らない)
9. 出力: `STATUS: OK` / `LABEL:` / `REPORT:` / `CONCLUSION:`(`## 結論` から次の `## ` 見出しまでの空行でない行を先頭から最大 5 行、1 行 1 KV)/ `UNVERIFIED: <n>`(`## 未確認` の空行でない行数)/ `WEB: used|not-requested|unavailable` / `ELAPSED_MIN:`(exit 0)

`-Collect <label>` は 5 以降を行う。`-List` は `scout/index.md` をそのまま出す(無ければ `INDEX: none`)。

### 3-3. 守ること

- codex の起動は `codex-run.ps1` 経由だけ(規約 `references/codex-invocation.md` を破らない)。`scout.ps1` 自身は codex のコマンドを組み立てない
- 既存の KV 出力の流儀(`Write-Kv`)・UTF-8(BOM なし)・LF・スクリプト自体は BOM 付き、は `codex-common.ps1` のものを使う
- 同じ問いの検出は**しない**(`-List` を Opus が引く。類似判定をスクリプトに持たせない)

## 4. 報告の型と `codex-run.ps1` の変更

### 4-1. `codex-run.ps1`

- `-Role` の `ValidateSet` に `scout`。effort 既定: `scout` → `medium`
- `-Web` スイッチ。付いたとき、スパイクで確定したキー(例: `-c web_search="live"`)を `$codexArgs` に足し、`meta.json` に `web = true` を書く。付かなければ何も足さない(既定の設定に従う)
- `$RoleBriefs.scout`(英文。要点は D71)。実行契約(1〜7 項)はそのまま前置する。契約 1 項(`~/.claude/` 等を読まない)は scout にも有効で、調べる相手は `-WorkDir` と `-GoalDir` 配下だけと明記する
- ヘルプ・コメントの「3 ロール」表記を「4 ロール」に直す

### 4-2. ロール憲章(`references/roles.md`)

全体図の表に 1 行足す: `| 調査(どの段階でも) | スカウト(codex。問いに答える報告) | Opus(報告の採否。根拠の無い結論は事実として扱わない) |`。

「## スカウト (scout)」の節:

- **あなたの立場**: codex(読み取り専用)。Opus から渡された**問い**に、対象プロジェクトとゴール文書(指示があれば Web も)を読んで答える調査役。どの段階でも呼ばれる。設計や判定には関わらない
- **受け取るもの / 返すもの**: 問い・調べる範囲(作業ディレクトリ・ゴール文書のパス)・Web 可否。固定の型(問い / 結論 5 行以内 / 根拠 `file:line` か URL / 未確認)の報告を最終メッセージで返す
- **あなたが決めること**: どこをどう読むか、何を根拠として示すか、何が未確認か
- **あなたが決めないこと**: 実装方式(技術PM)、ユーザー価値(代理Fable / 人間)、要件適合(ゲートFable)、コードの変更(実装役)。問いの外のことを提案しない。見つからないものを推測で埋めない(「見つからない」と書き、探した場所を根拠に書く)
- **あなたの出力の判定のされ方**: 実行の成否は `codex-status.ps1` の `STATUS: OK`、報告の型は `scout.ps1` が機械で確かめる(`結論` と `根拠` の節が無ければ不合格で、index に載らない)。根拠の無い結論は Opus が事実として扱わない

## 5. SKILL.md の変更(共通節)

- **起動時チェック 6**: 「codex は技術PM・技術レビュー(高信頼)・グラレコ・**スカウト**の 4 ロールだけ、すべて `gpt-6.1-sol` の読み取り専用」
- **ディレクトリ契約**: `scout/`(`index.md` と `scout-<n>.md`)を足す
- **記帳**: 呼ぶたびに記帳する一覧に `codex-scout` を足す。成功時は `scout.ps1` が記帳するので Opus は別に `loop-log.ps1` を呼ばない。Opus が手で記帳するのは D76 の「再実行しても OK にならず代行した」ときの 1 行だけ、と明記
- **ゲート保護ルール 8**: 「OK 以外を成功として扱わない」はそのまま。例外の記述を「グラレコとスカウトの失敗はループを止めない(代行して記帳する)」に広げる
- **ゲート保護ルール 10**: `-Role techpm | reviewer | grareco | scout`。「コード変更・設計承認・要件適合の判定をさせない」はそのまま
- **読むものと読まないもの**に 1 行(D79):

  | いつ | 読む | 読まない |
  |---|---|---|
  | 調べもの(場所が分からない・3 ファイル以上・Web) | `bin/scout.ps1` に問いを投げ、`CONCLUSION` 行だけを使う。投げる前に `scout.ps1 -List`。根拠が要るときだけ `REPORT` の該当行を Grep | Opus 本体での Read / Grep の重ね掛け、調査用の Claude サブエージェント(Explore / general-purpose / Plan) |

- **例外・停止時の扱い**: 「codex 委譲はセッションを跨いで生き残る」の段落に、`-Async` のスカウトも `codex-run:` に残る(`scout.ps1 -Collect` で回収)こと、同期のスカウトは `resume-packet.ps1` の「未完了の委譲」に出るので同じく `-Collect` で回収することを足す

SKILL.md は 24 KB 以下を保つ(`tests/skill-layout.tests.ps1`)。超えるなら「読むものと読まないもの」の行を短くし、詳細は `references/codex-invocation.md` に置く。

## 6. workflow-a / workflow-b / policy.md / codex-invocation.md

- `references/workflow-a.md`
  - A-2(ブレスト)の冒頭: 「現状把握(既存の流れ・該当ファイル・使われ方)はスカウトに投げる。技術PMへの問いにスカウトの `REPORT` のパスを添えると、技術PMが同じ探索を繰り返さない」
  - A-4(plan)の末尾: 「plan に書く対象ファイル・関数の特定で場所が分からないものはスカウト」
- `references/workflow-b.md`
  - B-2(委譲文の準備): 「委譲文の『対象範囲』に書くファイルの確認はスカウト(Opus が自分で探索しない)」
  - B-5(MVP のセルフチェック): 「submission の『検証』節に書く事実(テストの所在・設定の既定値など)の確認はスカウト。判断は Opus」
  - B-9(REJECT 後): 「人間の REJECT 理由に対する原因調査はスカウト。戻り先の決定はゲートFable」
- `policy.md`
  - 責任分担表に行: `| スカウト | Codex gpt-6.1-sol / medium / read-only(-Role scout) | Opus の問いに、対象プロジェクト・ゴール文書(指示があれば Web)を読んで固定の型で答える | Opus が調べものを行うとき(どの工程でも)。bin/scout.ps1 経由 | コード変更。設計提案・要件判定。問いの外の助言 |`
  - PL-001 に「スカウト(調査)」を追加。PL-007 と call-log 形式の語彙に `codex-scout`
- `references/codex-invocation.md`: 冒頭の「3ロール」を「4ロール」に、表に `bin/scout.ps1`(起動から記帳までを 1 回で行うまとめ役。scout ロールはこれ経由でだけ呼ぶ)の行を足す。`-Web` の説明(確定したキーと、read-only で効くこと・効かないときの `WEB_UNAVAILABLE`)を 2-x として足す
- `bin/loop-log.ps1`: `$Roles` に `codex-scout`

## 7. `agents/builder.md`・Codex版・README

- `agents/builder.md`: roles.md の全体図を埋め込んでいるので `scripts/sync-roles.ps1` で同期する。実装役の契約は変えない(実装役はスカウトを呼べない。Bash はあるが SKILL.md の規則の対象外で、`codex-env.json` を知らされない)
- `skills-codex/`・`templates/`: 変更なし
- README(Claude版節): スカウトの 1 段落(目的・`scout.ps1` の呼び方・`scout/` の置き場・Web の前提・失敗時は Opus が代行)

## 8. バージョン

`.claude-plugin/plugin.json` を `0.10.0` に。同じ版番号の `plugin update` はキャッシュを更新しないので、版を上げてから入れ替え、`cmp` で確かめる(スモークノート 2026-10-10)。

## 9. テスト

すべて `powershell -NoProfile -ExecutionPolicy Bypass -File tests\<名>.tests.ps1`、最後に `ALL PASS` / `FAILURES: n`。codex は既存の流儀どおり `where.exe` で差し替える(起動系の確認)。

- `tests/scout.tests.ps1`(新規)
  - 偽の `codex-env.json`(`where.exe`)と一時ゴールディレクトリ(state.md・call-log.md)で:
  - 同期: `codex-runs/scout-1.prompt.md` が書かれ、`## 問い` の本文と `Web: 使わない` を含む / `-Web` で `Web: 使ってよい` / 2 回目のラベルが `scout-2`
  - 偽の `last.txt` + `.exit`(0)+ `done.json` を置いて `-Collect`: 4 節そろいなら `STATUS: OK`・`scout/<label>.md` にメタ行と本文・`index.md` に 1 行・call-log に `codex-scout` 行・`CONCLUSION:` が結論の行だけ(最大 5)・`UNVERIFIED:` が未確認の行数
  - `## 根拠` が無い `last.txt` → `STATUS: INCOMPLETE`・`<label>.raw.md` はある・index と call-log は増えない
  - `## 未確認` に `WEB_UNAVAILABLE` → `WEB: unavailable`
  - `.exit` が無い → `STATUS: RUNNING` と `NEXT: … -Collect` / `.exit` が 1 → `STATUS: FAILED`、保存も記帳もされない
  - `-Async` → `STATUS: STARTED`・state.md の `codex-run:` にラベル / `-Collect` 後に `codex-run: -`
  - `-List`: index が無ければ `INDEX: none`、あれば行がそのまま出る
  - `-Question` と `-QuestionFile` の両方 / どちらも無し → 失敗。同じ `-Label` の再実行 → `REFUSED`
  - 出力ファイルが UTF-8(BOM なし)・LF
- `tests/codex-run.tests.ps1`(追加): `scout-read-only-medium`(`-s read-only`・effort `medium`)/ `scout-brief`(brief に `結論` と `根拠` 相当の型と `WEB_UNAVAILABLE` がある)/ `-Web` で確定したキーが `command` に入り `meta.web = true` / `-Web` 無しでは入らない / `-Role` 不正値は従来どおり失敗
- `tests/loop-log.tests.ps1`(追加): `-Who codex-scout` が通る
- `tests/roles-sync.tests.ps1`・`tests/skill-layout.tests.ps1`: 変更なしで通る(全体図の同期・24 KB)。skill-layout に「SKILL.md が `scout.ps1` に言及する」を 1 項足す
- 既存テストはすべて通る。`scripts/sync-templates.ps1 -Mode Verify` が通る

## 10. スパイクとスモーク(実セッション)

1. **Web 検索のキー(実装の最初のタスク)**: `codex exec -s read-only -c windows.sandbox=unelevated -c <候補キー> …` で「<既知のライブラリ>の最新版の番号を公式ページから答えよ」を実行し、`out.jsonl` に Web 検索のイベントが出るか・回答に URL が付くかを見る。候補: `web_search="live"` / `tools.web_search=true` / `features.web_search_request=true`(deprecated)。効いたキーを `codex-run.ps1` の定数にし、`references/codex-invocation.md` に実測として書く。**どれも効かなければ** `-Web` は実装したまま「0.160.0 では未対応」と README とスモークノートに書き、Web 調査は Opus が行うと SKILL.md に 1 行書く
2. **medium の実力**: このリポジトリで実際の問い 2 つ(例: 「`codex-status.ps1` が `BOUNDARY_HIT` を出す条件と、そのパターンの定義場所は?」/「`loop-log.ps1 -Clear` が受け付ける欄名はどこで決まるか?」)を `scout.ps1` で投げ、`ELAPSED_MIN`・`file:line` の正確さ・累計入力トークン(`out.jsonl` の `turn.completed`)を記録する。`file:line` が 1 つでも誤っていれば effort `high` でも同じ問いを測り、既定を決め直す(ユーザーに報告して決める。黙って変えない)
3. **Web ありの 1 問**: 1 で効いた場合、`-Web` で 1 問投げ、URL 付きの根拠が返ることを確かめる
4. 実ゴール 1 周での「Claude 側の消費がどれだけ減ったか」は、次の実ゴールで `scripts/ctx-breakdown.js`(Opus の Read / Grep / Agent の回数とバイト)と `call-log.md` の `codex-scout` 行で測る。本改訂のスモークでは測れない

結果は `docs/superpowers/notes/2026-10-11-v0.10-smoke.md` に書く。

## 11. 受け入れ基準(この改訂の完了条件)

1. `codex-run.ps1 -Role scout` が read-only・`gpt-6.1-sol`・effort `medium` で起動し、`-Web` で確定したキーを渡す。`tests/codex-run.tests.ps1` が通る
2. `bin/scout.ps1` が §3 の流れを 1 回の呼び出しで行い、`tests/scout.tests.ps1` が通る
3. `references/roles.md` にスカウトの節と全体図の行があり、`agents/builder.md` が同期済み(`tests/roles-sync.tests.ps1`)
4. SKILL.md(§5)・workflow-a / b・policy.md・codex-invocation.md(§6)に規則が書かれ、`tests/skill-layout.tests.ps1` が通る
5. `loop-log.ps1 -Who codex-scout` が通る
6. スパイク 1〜3 を実施し、結果(効いたキー、または未対応)がスモークノートと README にある
7. 既存テストがすべて通る。`scripts/sync-templates.ps1 -Mode Verify` が通る
8. version 0.10.0。main にマージ・push・plugin update 済み(`cmp` で確認)

## 12. 範囲外

- 実装役を codex に戻す(別タスクで、v0.7 の判断の根拠と合わせて検討する)
- Opus の筆記(submission・評価パッケージ・振り返り・委譲文)の codex への移管
- MVP 強度での codex 技術レビュー(B-5)
- ゲート Fable の下調べをスカウトに任せる(Fable の探索を減らす。F24)
- ゴールループ外(通常セッション)での `scout.ps1` の利用(`codex-env.json` がゴール単位のため。必要なら次版で `-EnvFile` の既定を `~/.codex` 配下にする)
- 問いの類似判定・報告の自動要約
- Codex版(`skills-codex/`)への移植
