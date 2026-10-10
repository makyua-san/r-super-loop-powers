# r-super-loop-powers v0.9 設計仕様書 — 境界リセット(/clear + 再開パケット)と記帳の省力化(Claude版)

- 作成日: 2026-10-10
- 対象: Claude版 `skills/r-super-loop-powers/`(SKILL.md・bin/・references/・policy.md)・`agents/builder.md`・`hooks/`・`.claude-plugin/`・`tests/`・README のClaude版節。Codex版 `skills-codex/` と `templates/` は**変更しない**
- 前提: v0.8.1(merge commit 9bbd214)
- 入力: rb-55 の調査ノート `docs/superpowers/notes/2026-10-10-context-survey.md`(人間承認済み)。本仕様はノートの「進め方(修正)」の v0.9 = A′ + B + C + H(+ E・F・I を1行ずつ)を実装可能な粒度に落としたもの
- rb: rb-8rw(RB-59)

## 0. 目的

Opus メインセッションの文脈肥大(1セッション 87 万トークン・平均 49 万 / ターン)と、1 時間超の空白ごとのキャッシュ全額再作成(448 万トークン)と、記帳だけのターン(全体の 2 割強)を、**精度を落とさずに**解消する。

- コンパクションは使わない(制約が平均 17% しか残らない等、調査ノート「追記」の知見)。長文脈も続けない(context rot)。
- 採る形は「**正本はファイル、セッションは使い捨て**」。このハーネスは既にそう設計されている(state.md / goal-frame / goal-plan / assumptions / decisions / call-log、NFR-04)。足りないのは次の 4 つで、v0.9 はこれを足す。
  1. 再開に必要なものを**スクリプトが決定論的に組む**(モデルの要約を挟まない)
  2. `/clear` の後に**自動で注入**する(手で貼らない)
  3. 境界を手順にする(どこで捨てるか)
  4. 再開直後に**復唱で検証**する

工程(A-0〜A-8 / B-1〜B-10)・成果物契約・ゲート規律は変えない。既存のゴールディレクトリと互換(新しいファイルは `resume-pending` / `resume-packet.md` の 2 つだけ)。

## 1. 事実確認(2026-10-10、code.claude.com/docs/en/hooks・hooks-guide)

| # | 事実 | 設計への影響 |
|---|---|---|
| F11 | SessionStart フックの stdin には `source`(`startup` / `resume` / `clear` / `compact` / `fork`)・`cwd`・`session_id`・`transcript_path` が入る。`matcher` は `source` に対して効く | matcher `startup\|clear` で `/clear` と新規起動だけに絞れる(`compact` / `resume` では発火させない) |
| F12 | SessionStart の `hookSpecificOutput.additionalContext`(または素の stdout)は会話の先頭(最初のプロンプトの前)に system reminder として入る | 再開パケットの注入手段。JSON 形で出す(文字コードの事故を避けるため stdout 直書きは使わない) |
| F13 | **`additionalContext` は 1 フィールド 10,000 文字まで**。超えると Claude Code がファイルに退避し、パスと先頭 2,000 文字のプレビューだけを渡す(Claude に読めとは言わない) | パケットは **9,500 文字以内**に収める。制約系(否定リスト・制約・承認基準・終了条件・待ち・state.md)は**先頭に置いて絶対に削らない**(Constraint Pinning)。削るのは後方の節だけ。全文は常に `<goal-dir>/resume-packet.md` に書く |
| F14 | フックは `/` コマンドもツール呼び出しも起こせない(「Command hooks communicate through stdout, stderr, and exit codes only. They can't trigger `/` commands」) | **`/clear` は人間が打つ**。Opus は境界で印を置いてターンを終え、人間に `/clear` → 続行指示を頼む。自律連鎖の途中(B-6 PASS 後)は、文脈が目安を超えたときだけ頼む(F16 の計測で判断) |
| F15 | PostToolUse フックの stdin にも `transcript_path` / `cwd` / `tool_name` が入り、`hookSpecificOutput.additionalContext` をツール結果の横に注入できる。素の stdout は Claude に見えない(debug log のみ) | 文脈サイズの計測と通知に使う。トランスクリプトの最後の assistant 行の `usage`(input + cache_creation + cache_read)が現在の文脈。書き込みは非同期で遅れることがあるが、目安には足りる |
| F16 | `additionalContext` の文面は「命令」ではなく「事実の記述」で書くことが推奨されている(命令口調はプロンプトインジェクション防御に引っかかり、Claude がユーザーに差し出すことがある) | パケットと通知は事実の形で書く(「〜である」「手順は SKILL.md の〜にある」)。何をすべきかは SKILL.md 側に書く |
| F17 | `${CLAUDE_PLUGIN_ROOT}` はプラグイン同梱フックで使え、環境変数としても渡る。Windows では Git Bash(無ければ PowerShell)で実行される | v0.8 の Stop フックと同じ `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/hooks/<名>.ps1"` 形式。スモーク済み |
| F18 | Agent ツールには呼び出し単位でツールを制限する引数が無い(調査ノート追記) | D(ゲート Fable のスクリプト化)は v0.10 へ。v0.9 では扱わない |

## 2. 設計決定(D56〜D70)

| ID | 決定 | 内容 |
|---|---|---|
| D56 | 境界 | (a) 人間待ちに入るとき(state.md の「待ち」を書いた直後) (b) B-6 PASS の中間クローズ後 — **文脈が 20 万トークンを超えているとき**(D61 の通知が出ているとき)だけ (c) Checkpoint ACCEPT の確定処理後 (d) A-8 承認後。代理Fable が生きている A-1a〜A-4 の間は切らない(SendMessage の相手がセッションを跨げない) |
| D57 | 再開パケット | `bin/resume-packet.ps1 -GoalDir <dir> [-OutFile <path>] [-PolicyFile <path>] [-MaxChars 9500]` が §3 の固定順で決定論的に組む。全文(削らない)は常に `<goal-dir>/resume-packet.md` に書く。`-OutFile` を渡すと、制約系の節(ピン留め)は削らず後方の節だけ上限に収めた注入用の本文をそこに書く。stdout には `PACKET:` / `FULL_CHARS:` / `INJECT:` / `CHARS:` / `TRUNCATED:` / `WARN:` の KV 行だけを出す |
| D58 | 印 | `<goal-dir>/resume-pending`(`created: <ISO 8601>` / `cwd: <対象プロジェクト>` の 2 行)。`bin/loop-log.ps1 -Mark` が置く(置く前に D57 を 1 回実行して組めることを確かめる)。有効期限 24 時間。一回限り(注入したら消す) |
| D59 | 注入フック | `hooks/resume-inject.ps1` を SessionStart(matcher `startup\|clear`、timeout 30)に登録。`cwd` 配下の `docs/r-super-loop-powers/*/resume-pending` を探し、有効なら D57 でパケットを**その時点で**組み直して `hookSpecificOutput.additionalContext` に出し、印を消す。印が複数なら `created` が最新のもの 1 つ。期限切れの印は消して `STALE` を記録。組めなかったときは印を `resume-pending.failed` に改名して `ERROR` を記録し、何も出さない(フェイルオープン。従来の起動時チェック 3 で再開できる) |
| D60 | 復唱と再読 | SKILL.md 起動時チェック 3 を強化: パケットが注入されていれば Glob で state.md を探さず、最初の応答で「フェーズ / 強度 / マイルストーン / 次のゲート / 待ち」をパケットの state.md から**そのまま**復唱してから手順に入る。各フェーズの入口(A-5・B-1・B-5・B-7・Learning)で state.md を再読する |
| D61 | 文脈メーター | `hooks/context-meter.ps1` を PostToolUse(matcher `Agent`、timeout 10)に登録。ゴールループ中に、トランスクリプト末尾の assistant 行の `usage` から現在の文脈を求め、`hook-log.md` に `CTX` 行で記録する。**20 万トークン以上**なら `additionalContext` で 1 行通知する(D56 (b) の判断材料)。しきい値は環境変数 `RSLP_CTX_THRESHOLD` で上書き可(テスト用) |
| D62 | 記帳の 1 ターン化 | `bin/loop-log.ps1 -GoalDir <dir> [-Who <役> -Purpose <目的> [-Phase <phase>]] [-SetPhase <v>] [-SetIntensity <v>] [-SetMilestone <v>] [-SetCheckpoint <v>] [-SetOwner <v>] [-SetGate <v>] [-SetWait <v>] [-SetCodexRun <v>] [-Set '<key>=<value>'] [-Mark]`。call-log 追記(`-Who`)と state.md の欄更新(`-Set*`。欄が 1 つでも変わるとき `updated:` も更新)と印(`-Mark`)を 1 回で行う。`-Phase` 省略時は state.md の phase(更新前の値)。存在しない欄を指定されたら何も書かずに失敗する。欄ごとの名前付きパラメータにしたのは、`-File` 起動では配列パラメータに複数の値を渡せない(実測 2026-10-10)ため |
| D63 | impl-check の前後処理 | `impl-check.ps1 -Prepare -Label <l> -GoalDir <dir> -WorkDir <repo>`: `impl-runs/<l>.base.txt`(HEAD)と `<l>.pre.txt`(スナップショット)を 1 回で書く。同じラベルの `.report.md` があれば拒否。`impl-check.ps1 -SaveReport -Label <l> -GoalDir <dir> -WorkDir <repo>`: 実装役の最終メッセージを **stdin** で受けて `<l>.report.md` に保存し、`.base.txt` / `.pre.txt` をラベルから引いてそのまま判定する(従来の `-ReportFile -BaseRef -PreexistingFile` も残す) |
| D64 | 委譲プロンプトの重複排除 | 実装役の禁止領域 `docs/r-super-loop-powers/` に**読み取りだけ**の例外を 2 つ設ける: `impl-runs/*.prompt.md` と `tech-assessment.md`。初回委譲: Opus は `<l>.prompt.md` を書き、Agent の prompt には**そのファイルのパスと 3 行の指示**だけを渡す(本文を二度書かない)。再委譲: `<l>-2.prompt.md` には `## 再委譲の差分`(impl-check の `REASON` / `CRITERION_UNMET` / `WARN` の引用)と初回 prompt のパスだけを書く。M 節の原文貼付は初回の `.prompt.md` の中で現状どおり行う |
| D65 | 積み荷を薄くする | SKILL.md を 3 つに分ける: `SKILL.md`(共通: 起動時チェック・ディレクトリ契約・state.md・フェーズ表・記帳・ゲート保護・Fable 共通契約・境界リセット・例外)/ `references/workflow-a.md`(A-0〜A-8 + 技術PM共通契約)/ `references/workflow-b.md`(B-1〜B-10 + Learning)。state.md の phase が goal-definition なら A、それ以外なら B を読む。起動時に読むのは SKILL.md と policy.md だけ。`references/roles.md` は Fable 依頼文を組むときに該当節だけ読む(Opus 自身の憲章の要点は SKILL.md に 3 行で置く) |
| D66 | 画像を Opus に読ませない(E) | スクショ・グラレコ画像を Opus が Read しない。確認が要るなら `Agent`(model: sonnet)に見せて 5 行で返させる。人間に渡すだけなら SendUserFile か、パスを示す |
| D67 | codex のプロンプト上限と effort(F) | `codex-run.ps1` は本文が **40 KB** を超えると `WARN: prompt is N KB` を出す(止めない)。技術PMには hearing-log / spec / plan を貼らずパスで渡す(codex は read-only で読める)。グラレコの既定 effort を `medium` → **`low`** にし、ロール指示を「imagegen の SKILL.md を読まずに image_gen を直接呼ぶ。読むのはツールが拒んだときだけ」に変える |
| D68 | 出力の切り詰め(I) | シェル結果は「失敗分だけ」を見る手順を SKILL.md に 1 行で書く(テストは `FAIL` / `FAILURES` / `ALL PASS` の行だけを出す)。要約ではなく切り詰め |
| D69 | 観測 | `hook-log.md` に `RESUME` / `STALE` / `CTX` の行が増える。retro の観測欄に「最大文脈(hook-log の CTX 行の最大値)と境界リセットの回数(RESUME 行の数)」を加える(テンプレートは変えず、SKILL.md の Learning の指示で書かせる) |
| D70 | 版 | `0.9.0`。Codex版・テンプレートは変更しない(`scripts/sync-templates.ps1 -Mode Verify` が通り続ける) |

ノートに無く、本仕様で足した決定: D61(文脈メーター。(b) を「目安 20 万」で条件付きにするには Opus が自分の文脈サイズを知る手段が要る)、D64 の「初回委譲もパスで渡す」(ノートは再委譲だけ。同じ読取例外で初回の二重書きも消えるため)、D63 の `-SaveReport` が stdin で受けること(Agent の結果はどのみち文脈に 1 回入るので、保存と判定を 1 ターンに畳むのが実際の効果)。

## 3. `bin/resume-packet.ps1` — 再開パケットの構成(固定順)

出力は Markdown。各節は `## <番号>. <名前>` の見出しで始まる。入力ファイルが無い・節が見つからない場合は、その節に `(見つからない: <ファイル> に「<見出し>」が無い)` と**書く**(黙って落とさない)。

| # | 節 | 出典 | 削る |
|---|---|---|---|
| 0 | 見出し | `# 再開パケット — <goal-slug>`、生成時刻、goal-dir、state.md の `skill-dir:`、全文の所在 `<goal-dir>/resume-packet.md`、「再開手順は SKILL.md の起動時チェック 3 と「境界リセット」にある」 | 不可 |
| 1 | state.md | 全文 | 不可 |
| 2 | 待ち | state.md の `- 待ち:` の値(`-` なら「なし」) | 不可 |
| 3 | 仮説自律の否定リスト | policy.md の `## 仮説自律の否定リスト` 節(原文) | 不可 |
| 4 | 制約・承認基準・終了条件 | goal-frame.md の `## 制約` / `## 承認基準` / `## 終了条件` の 3 節(見出しは前方一致。原文) | 不可 |
| 5 | 対象マイルストーン | goal-plan.md の `## マイルストーン` 節(原文) | 可(上限 2,000 文字) |
| 6 | 未検証の仮定 | assumptions.md の表のうち、最終列(状態)が `未検証` で始まる行。表の見出し 2 行を付ける | 可(上限 2,500 文字) |
| 7 | 直近の判定 | 最新(更新時刻)の `goal-gate-decision.md` / `milestones/*/gate-decision*.md` の先頭 8 行と、最新の `milestones/*/escalation-*.md` の `7.` 行 | 可(上限 1,200 文字) |
| 8 | 直近 retro の「次回変えること」 | `docs/r-super-loop-powers/*/milestones/*/retro.md` のうち最新 1 件の `## 次回変えること` 節(他ゴールの retro も対象。同じプロジェクトの教訓だから) | 可(上限 1,000 文字) |
| 9 | 未完了の委譲 | `impl-runs/<l>.prompt.md` があって `<l>.report.md` が無いラベル / `codex-runs/<l>.prompt.md` があって `<l>.exit` が無いラベル / state.md の `codex-run:` | 不可 |

- 上限超過は末尾を切り、`…(省略 N 文字。全文: <goal-dir>/resume-packet.md)` を付ける。全体が `-MaxChars`(既定 9,500)を超えるときは 8 → 7 → 6 → 5 の順に各 200 文字まで縮める。それでも超えるなら(ピン留めだけで超える)そのまま出して `WARN: packet exceeds <MaxChars> chars` を出す(Claude Code がファイルに退避し、プレビューの先頭には state.md が来る)。
- 文字数は `.Length`(UTF-16 コード単位)。Claude Code の上限も文字数なので揃える。
- 改行は LF。UTF-8(BOM なし)。
- このスクリプトは日本語の見出しを探すので **UTF-8 BOM 付き**で保存する(PS 5.1 の規約。`tests/` で BOM を検査する)。

## 4. `hooks/resume-inject.ps1` — SessionStart フックの処理

入力: stdin の SessionStart JSON(`source` / `cwd` / `session_id`)。出力: 注入するときだけ `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<パケット>"}}`。常に exit 0。

1. `source` が `startup` / `clear` 以外なら何もしない(hooks.json の matcher が一次防御、ここは二次)。stdin が読めない・JSON でないときも何もしない。
2. `cwd` 配下の `docs/r-super-loop-powers/*/resume-pending` を集める。無ければ終了。
3. 各印の `created:` を読む(読めなければファイルの更新時刻)。24 時間より古い印は削除して `hook-log.md` に `STALE` を記録する。残った印のうち `created` が最新の 1 つを採る。
4. `$PSScriptRoot\..\skills\r-super-loop-powers\bin\resume-packet.ps1 -GoalDir <dir> -OutFile <一時ファイル> -MaxChars 9500` を子 PowerShell で実行する(policy.md は同じスキルディレクトリのもの。全文は同時に `<goal-dir>\resume-packet.md` に書かれる)。失敗(非 0 終了・ファイルが空)なら印を `resume-pending.failed` に改名し、`ERROR` を記録して終了。
5. 一時ファイル(注入用に収めたもの)を読み、念のため `MaxChars` を超えていれば先頭 `MaxChars` 文字に切る。JSON にして UTF-8 で stdout に出す。印を削除し、`RESUME` を記録する。

`hook-log.md` の行書式(v0.8 と同じ 4 欄): `YYYY-MM-DD HH:MM | RESUME|STALE|ERROR | source=<source> | <補足: chars=N / 理由>`。

## 5. `hooks/context-meter.ps1` — PostToolUse(Agent)フックの処理

入力: stdin の PostToolUse JSON(`transcript_path` / `cwd` / `tool_name`)。出力: しきい値以上のときだけ `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"..."}}`。常に exit 0。

1. `RSLP_HOOK_CHILD=1` なら終了。ゴールループが active でなければ終了(Stop フックと同じ `Find-GoalDir`)。
2. `transcript_path` の末尾 512 KB を読み、後ろから `"type":"assistant"` かつ `usage` を持つ行を探す。文脈 = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`。見つからなければ終了。
3. `hook-log.md` に `YYYY-MM-DD HH:MM | CTX | tokens=<n> | tool=<tool_name>` を記録する。
4. `n >= しきい値`(既定 200,000。`RSLP_CTX_THRESHOLD` で上書き)なら、事実の形で 1 行通知する: `[r-super-loop-powers] 現在の文脈は約 <n/10000> 万トークンで、境界リセットの目安(20 万)を超えている。次の境界(B-6 PASS の中間クローズ後 / Checkpoint ACCEPT の確定処理後 / A-8 承認後 / 人間待ち)で SKILL.md「境界リセット」の手順を行う。`
5. 例外はすべて握りつぶして exit 0(フェイルオープン)。

`Find-GoalDir` と stdin / stdout の UTF-8 処理は 3 つのフックで同じなので `hooks/hook-common.ps1` に出し、`human-message-check.ps1` もそれを使う(振る舞いは変えない。既存テストで担保)。

## 6. `bin/loop-log.ps1` と `impl-check.ps1` の拡張(B)

### 6-1. loop-log.ps1

```
loop-log.ps1 -GoalDir <dir>
  [-Who fable|codex-techpm|codex-review|codex-grareco|sonnet-builder -Purpose <text> [-Phase <phase>]]
  [-SetPhase <v>] [-SetIntensity <v>] [-SetMilestone <v>] [-SetCheckpoint <v>] [-SetOwner <v>] [-SetGate <v>] [-SetWait <v>] [-SetCodexRun <v>]
  [-Set 'key=value'] [-Clear 'key,key']
  [-Mark]
```

- `-Who` があれば `call-log.md` に `YYYY-MM-DD HH:MM | <who> | <phase> | <purpose>` を追記する(`-Phase` 省略時は state.md の `phase:` の値。同じ呼び出しで `-SetPhase` を渡しても、ログの phase は更新前の値 = その呼び出しが起きたフェーズ)。call-log.md が無ければ見出し付きで作る。
- `-Set*` は state.md の `- <欄>: ...` 行の値を置き換える。対応: `-SetPhase`→`phase` / `-SetIntensity`→`強度` / `-SetMilestone`→`milestone` / `-SetCheckpoint`→`次のCheckpoint` / `-SetOwner`→`担当` / `-SetGate`→`次のゲート` / `-SetWait`→`待ち` / `-SetCodexRun`→`codex-run`。それ以外の欄は `-Set 'key=value'`(1 つ。最初の `=` で分ける)。欄を「なし(`-`)」に戻すときは `-Clear '待ち,codex-run'`(カンマ区切り)を使う(単独の `-` は `powershell -File` の起動引数として渡せず、powershell.exe が黙って終了する。実測 2026-10-10。空文字の値も `-` と扱う)。1 つでも見つからなければ何も書かずに `STATUS: FAILED` / `REASON:` で非 0 終了。欄が 1 つでも変わるとき `updated:` を現在時刻(`YYYY-MM-DD HH:MM`)にする。
- `-Mark` は `resume-packet.ps1 -GoalDir <dir>`(全文を `<goal-dir>\resume-packet.md` に書く)を実行して組めることを確かめてから `resume-pending` を書く。組めなければ印を置かずに非 0 終了。
- `-Who` / `-Set` / `-Mark` のどれも無ければ引数エラー。
- 出力: `LOGGED: <行>` / `SET: <key>` / `UPDATED: <時刻>` / `MARKED: <path>` / `STATUS: OK`。
- 改行は元ファイルに合わせる(CRLF を含めば CRLF、無ければ LF)。UTF-8(BOM なし)で書く。
- 日本語の引数は PowerShell ツール・Bash ツールのどちらから `powershell -File` で渡しても化けないことを実測済み(2026-10-10)。

### 6-2. impl-check.ps1

- `-Prepare -Label <l> -GoalDir <dir> -WorkDir <repo>`: `git rev-parse HEAD` を `<goal-dir>\impl-runs\<l>.base.txt` に、`-Snapshot` と同じ内容を `<l>.pre.txt` に書く。`impl-runs/` が無ければ作る。`<l>.report.md` が既にあれば `STATUS: REFUSED`(ラベルの再利用)で非 0 終了。出力: `BASE_REF:` / `SNAPSHOT:` / `DIRTY_PATHS:` / `STATUS: OK`。git リポジトリでなければ従来どおり throw。
- `-SaveReport -Label <l> -GoalDir <dir> -WorkDir <repo>`: stdin を UTF-8 で読み、空なら `MALFORMED`。`<l>.report.md` に書く(整形しない)。`.base.txt` が無ければ `MALFORMED`(`NEXT:` に `-Prepare` を案内)。`.pre.txt` は無くてもよい(無ければ `-PreexistingFile` なしと同じ)。以後は従来の判定に合流する。
- 従来の `-ReportFile -BaseRef -PreexistingFile` はそのまま使える。

## 7. SKILL.md の分割(H)と手順の追記

### 7-1. 構成

```
skills/r-super-loop-powers/
├── SKILL.md                      # 共通(24 KB 以下。v0.8.1 の 47 KB の半分)
├── references/workflow-a.md      # ワークフローA: A-0〜A-8 + 技術PM(Codex)共通契約
├── references/workflow-b.md      # ワークフローB: B-1〜B-10 + Learning
├── references/roles.md           # 変更なし(読み方だけ変わる)
└── references/codex-invocation.md
```

SKILL.md(共通)の節: frontmatter / 冒頭 / 起動時チェック / ディレクトリ契約と state.md / フェーズと成果物契約 / 仮定台帳の運用 / 記帳(loop-log.ps1)/ ゲート保護ルール / Fable サブエージェント共通契約 / **境界リセット** / 人間向け応答チェック / 例外・停止時の扱い / **どのファイルをいつ読むか**。

### 7-2. 起動時チェックの変更

- 1: 読むのは SKILL.md と policy.md。`roles.md` は Fable 依頼文を組む直前に `(overview)` と該当節だけ読む。自分(Opus)の憲章の要点を 3 行で SKILL.md に置く(ゲートの合否・受け入れ・委譲の成否・実装方式は決めない)。
- 3: 「再開パケットが注入されていればそれを使う(Glob しない)。最初の応答でフェーズ / 強度 / マイルストーン / 次のゲート / 待ちを state.md の文面どおり復唱する。パケットの『未完了の委譲』に codex のラベルがあれば `codex-status.ps1`、実装役のラベルがあれば `git status` を見てから次を決める」。
- 新 9: phase に応じて `references/workflow-a.md` または `workflow-b.md` を読む。両方は読まない。

### 7-3. 境界リセットの手順(共通節)

> 境界 = (a) 人間待ちに入るとき (b) B-6 PASS の中間クローズ後(文脈メーターの通知が出ているときだけ) (c) Checkpoint ACCEPT の確定処理後 (d) A-8 承認後。代理Fable が生きている間(A-1a〜A-4)は切らない。
> 手順(1 ターン): `loop-log.ps1 -GoalDir <dir> -Set 'phase=...' -Set 'milestone=...' -Set '待ち=...' -Mark`(必要な欄だけ)。`MARKED:` を確認したらターンを終え、人間に「`/clear` のあと「続けて」と送ってください(文脈を捨てて再開します)」と伝える。(a) では待ちの内容を伝える文の末尾に添える。
> `/clear` の後は SessionStart フックが再開パケットを注入する。印は 24 時間で無効になる(その場合は従来どおり state.md から再開する)。

### 7-4. 工程への追記

- B-2 (1)(2)(3): `-Prepare` / パスで渡す委譲 / `-SaveReport`(D63・D64)。再委譲の `## 再委譲の差分` の書式。
- B-3: 「シェル結果は失敗分だけ」(D68)。
- B-7 / Learning: 画像の扱い(D66)。Learning のグラレコは effort `low`(D67)。retro の観測欄に最大文脈と境界リセット回数(D69)。
- 技術PM共通契約(workflow-a.md): 「hearing-log / spec / plan は貼らずパスで渡す。本文 40 KB 超は WARN」(D67)。
- 記録ルール: `loop-log.ps1 -Who ... -Purpose ...` で追記する(手で `Add-Content` しない)。

### 7-5. agents/builder.md

実行契約 1 の末尾に加える: 「例外として、`docs/r-super-loop-powers/*/impl-runs/*.prompt.md` と `docs/r-super-loop-powers/*/tech-assessment.md` は**読んでよい**(書かない)。依頼文にパスが示されたら、まずそのファイルを全部読んでから作業する。`## 再委譲の差分` が示されたら、初回の prompt を読んだ上で差分を優先する」。roles.md の builder 節は変えない(規則は SKILL.md / builder.md が正)。

## 8. codex-run.ps1(F)

- 本文(`$rawPrompt`)が 40,960 バイトを超えたら `WARN: prompt is <N> KB (> 40 KB); pass long documents by path and let codex read them.` を出す。止めない。
- `$Effort` の既定: grareco を `low` に。policy.md の責任分担表・README・codex-invocation.md・SKILL.md(Learning)の `medium` を `low` に直す。
- `$RoleBriefs.grareco`: 「imagegen の SKILL.md を読む必要はない。image_gen を直接呼ぶ。ツールが SKILL.md の読取を要求して動かないときだけ、その SKILL.md に限り読んでよい」に置き換える(v0.8.1 の `NO_IMAGE_GENERATED:` の規則は残す)。

## 9. テスト

すべて `powershell -NoProfile -ExecutionPolicy Bypass -File tests\<名>.tests.ps1`、最後に `ALL PASS` / `FAILURES: n`。

- `tests/resume-packet.tests.ps1`(新規): 一時ゴールディレクトリに state.md / goal-frame.md / goal-plan.md / assumptions.md / gate-decision / retro / impl-runs / codex-runs を置き、
  - 節の順序が §3 のとおり / state.md が全文 / 否定リストが policy.md の原文と一致 / 制約・承認基準・終了条件が原文と一致 / 未検証の行だけが入り「検証済み」の行が入らない / 最新の gate-decision が選ばれる / retro の「次回変えること」節だけが入る / 未完了ラベルが列挙され、完了したラベルは出ない
  - goal-frame.md に `## 制約` が無いとき「(見つからない: …)」が入る / goal-plan.md が無くても落ちない
  - 大きな assumptions で `TRUNCATED:` が出て、ピン留め節は削られず、全体が `-MaxChars` 以内 / ピン留めだけで超えるときは `WARN:` が出る
  - `-OutFile` が UTF-8(BOM なし)・LF で書かれる / スクリプト自体が BOM 付き
- `tests/resume-inject.tests.ps1`(新規): stdin JSON で、
  - `source=clear` + 有効な印 → `hookSpecificOutput.additionalContext` にパケット(state.md の phase 行を含む)、印が消える、hook-log に `RESUME`
  - `source=startup` → 同上 / `source=compact` / `resume` → 出力なし・印は残る
  - 印なし → 出力なし / 期限切れ(`created` を 25 時間前に)→ 出力なし・印が消える・`STALE`
  - 印が 2 ゴールにある → `created` が新しい方だけ注入、古い方は残る
  - state.md が無い(組めない)→ 出力なし・`resume-pending.failed` に改名・`ERROR`
  - 不正な stdin → exit 0・出力なし
  - hooks.json に SessionStart(matcher `startup|clear`、`resume-inject.ps1`、`CLAUDE_PLUGIN_ROOT`)と PostToolUse(matcher `Agent`、`context-meter.ps1`)がある
- `tests/context-meter.tests.ps1`(新規): 偽のトランスクリプト(assistant 行の usage)で、
  - しきい値未満 → 出力なし・hook-log に `CTX | tokens=N`
  - しきい値以上(`RSLP_CTX_THRESHOLD` を小さく)→ `additionalContext` に「万トークン」と「境界リセット」を含む
  - usage 行が無い / transcript が無い / ループ外の cwd → 出力なし・exit 0
  - `RSLP_HOOK_CHILD=1` → 出力なし
- `tests/loop-log.tests.ps1`(新規): call-log の行書式 / `-Phase` 省略時に state.md の phase / `-Set` の置換と `updated:` の更新 / 日本語キー(`待ち`)/ 未知のキーで失敗し state.md が変わらない / CRLF の state.md は CRLF のまま / `-Mark` で印が書かれ `created:` が ISO 8601 / state.md が無いと `-Mark` が失敗して印が無い / 引数なしで失敗
- `tests/impl-check.tests.ps1`(追加): `-Prepare` が base/pre を書く / 同ラベルの report があると `REFUSED` / `-SaveReport` が stdin から保存して `OK` / `MALFORMED` でもファイルは保存される / `.base.txt` 無しで `MALFORMED`
- `tests/codex-run.tests.ps1`(変更・追加): `grareco-read-only-low` / 41 KB の本文で `WARN: prompt is` / 短い本文で WARN なし / grareco の brief に `Do not read` 相当と `NO_IMAGE_GENERATED` がある
- `tests/skill-layout.tests.ps1`(新規): SKILL.md が 24 KB 以下 / `references/workflow-a.md` と `workflow-b.md` がある / A-0〜A-8 の見出しが workflow-a にだけ、B-1〜B-10 と Learning が workflow-b にだけある(SKILL.md に無い)/ SKILL.md が両ファイルと `loop-log.ps1` / `resume-packet.ps1` / `境界リセット` に言及する / `scripts/sync-templates.ps1 -Mode Verify` と `tests/roles-sync.tests.ps1` が通る
- `tests/human-message-check.tests.ps1`: 変更なしで通る(hook-common.ps1 への切り出しの回帰)

## 10. スモーク(実セッション)

1. プラグイン更新後、一時プロジェクト(git 初期化済み・state.md あり)で `loop-log.ps1 -Mark` → `claude -p --model haiku "state.md の phase と待ちを答えて"` を実行し、パケットが注入された答え(phase と待ちの文面)が返ること、印が消えて `hook-log.md` に `RESUME` が記録されることを確かめる(`startup` 経路)。
2. 同じ一時プロジェクトで、対話セッションから `/clear` して注入されること(`clear` 経路)。人間の操作が要るので、できなければ README に未確認と書く。
3. 文脈メーター: この作業セッション自身のトランスクリプトを `context-meter.ps1` に食わせ、`CTX` 行が出ることを確かめる。
4. グラレコ effort `low` + 新しい brief で 1 回生成し、画像ができること・`BOUNDARY_HIT` の有無・累計入力を `*.out.jsonl` から読んで記録する(ノート F の「要実測」)。
5. 実タスク 1 周での「平均文脈 20 万未満・空白時のキャッシュ再作成ほぼ 0」は、次の実ゴール(v0.9 で回す最初のゴール)で `scripts/ctx-breakdown.js` により測る。本改訂のスモークでは測れない(測り方は調査ノート末尾)。

## 11. 受け入れ基準(この改訂の完了条件)

1. `bin/resume-packet.ps1` が §3 の固定順でパケットを組み、`tests/resume-packet.tests.ps1` が通る
2. `hooks/resume-inject.ps1` が SessionStart(`startup|clear`)で一回限り注入し、`tests/resume-inject.tests.ps1` が通る。スモーク 1 で実セッションに入る
3. `hooks/context-meter.ps1` が `CTX` を記録し、しきい値超えで通知する。`tests/context-meter.tests.ps1` が通る
4. `bin/loop-log.ps1` と `impl-check.ps1 -Prepare / -SaveReport` があり、各テストが通る
5. SKILL.md が共通 / workflow-a / workflow-b に分かれ、境界リセット・復唱・パスで渡す委譲・再委譲の差分・画像・失敗分だけ・effort low の手順が書かれている。`tests/skill-layout.tests.ps1` が通る
6. `agents/builder.md` に読取例外があり、`tests/roles-sync.tests.ps1` が通る
7. `codex-run.ps1` が 40 KB 超で WARN、grareco が `low`。`tests/codex-run.tests.ps1` が通る
8. 既存テストがすべて通る。`scripts/sync-templates.ps1 -Mode Verify` が通る
9. README(Claude版節)に境界リセット・フック 2 つ・記帳スクリプトの説明と動作要件がある
10. version 0.9.0。main にマージ・push・plugin update 済み

## 12. 範囲外

- D(ゲート Fable のスクリプト化 `bin/gate-run.ps1`)— スパイク後に v0.10
- G(`bin/ctx-report.js` の同梱と retro テンプレートの拡張)— `scripts/ctx-breakdown.js` は残し、計測は次の実ゴールで行う
- J(再開の正確さの計測)— D60 の復唱は手順として入れるが、一致判定の自動化はしない
- Codex版(`skills-codex/`)への移植
- `/clear` の自動化(フックからは起こせない。F14)
