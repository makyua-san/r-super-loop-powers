# マイルストーンの並行セッション Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1 つのゴールの中で、互いに干渉しない 2 つのマイルストーンを別々の作業ツリー・別々のメインセッションで並行させる仕組み(分割判定・準備・PASS の確定・合流・中止・後片付け・効果の計測)を入れる(v0.13.0)。

**Architecture:** 新しい `bin/parallel.ps1` が git の作業ツリー・ブランチ・合流と、git の共通ディレクトリに置く台帳を 1 本で扱う。子の状態は子の作業ツリーにある普通の `state.md` なので、フック・`resume-packet.ps1` はそのまま動く。変えるのは 3 点だけ: フックのログ行にマイルストーン番号、`loop-log.ps1` の `parallel` フェーズと並行中の記帳、`scout.ps1` の自動ラベル。手順は新しい `references/parallel.md` に集め、workflow-a / workflow-b / SKILL.md からは 1 行で指す。

**Tech Stack:** PowerShell 5.1(`bin/*.ps1`・`hooks/*.ps1`・`tests/*.tests.ps1`)、git 2.31 以上(`worktree`・`rev-parse --path-format=absolute`・`info/attributes`)、Markdown

**Spec:** `docs/superpowers/specs/2026-11-16-parallel-milestone-sessions-design.md`(5 章の改訂 R-a〜R-e が 3 章より優先)

## spec から先に決めたこと(利用者の確認を受ける点)

spec が決めていない、または文面と違う形にした点。実装前に覆してよい。

| # | 決めたこと | 理由 |
|---|---|---|
| P1 | 行の合併(`merge=union`)は、追跡する `.gitattributes` ではなく git の共通ディレクトリの `info/attributes` に書く | 台帳と同じ場所で、対象プロジェクトの履歴にコミットを足さずに済む。全作業ツリーに効くことは実験で確認済み(git 2.47) |
| P2 | 合流のあと、B-7 以降は**ベースのフォルダで開く新しいセッション**が行う。合流担当の子は、マージと全体の検証、ベースの state.md の更新と再開の印までを行う | 合流担当のセッションは子の作業ツリーに居るので、フック(応答チェック・文脈メーター)が子の state.md を見続けてしまう。D2「親セッションを残さない・最後に PASS した子が合流する」は変わらない |
| P3 | PASS の確定コミットと、合流前のベースのゴール記録のコミットは `parallel.ps1` が行う | SHA を台帳に書く手順(R-c)を 1 回の呼び出しで確実にするため。子の `state.md` と再開の印はコミットに入れないので、合流で state.md が衝突しない |
| P4 | 並行は MVP 強度だけ | 高信頼は人間の受け入れがマイルストーンごとなので、D4「同じ Checkpoint の中だけ」に当てはまる組が無い |
| P5 | 実装ファイルが合流で衝突したら、マージ済みの片方だけを残し、もう片方はベースで B-1 から直列でやり直す | 衝突は「触るファイルが重ならない」という見立ての外れ(D5)。進行役は実装方式を決めない |
| P6 | 新しい作業ツリーに要る準備(依存の導入・未追跡ファイルのコピー)は、技術PM に組ごとに書かせ、子が最初に実行する | 作業ツリーには `node_modules` や `.env` が無い。スクリプトはプロジェクトごとの手順を知らない |
| P7 | call-log の行にも、並行の子のときだけ目的の末尾に `[m<n>]` を付ける。スカウトの自動ラベルは並行の子で `m<n>-scout-<k>` | hook-log(R-e)と同じ理由。スカウトは両方の子が `scout-3` を作ると合流で衝突する |

### Q6 の決定: 並行の効果を retro でどう測るか

| 狙い(spec 1 章) | 測るもの | 出所 |
|---|---|---|
| 精度 | 子ごとの最大文脈、子ごとの B-6 差し戻し回数 | hook-log.md の `CTX` 行を `m=` 列で分ける / gate-decision |
| サイクル短縮 | 壁時計(準備〜合流)と直列換算(各子の 準備〜PASS の合計) | `parallel.ps1 -Merge` が計算して `parallel-log.md` に書く |
| 見立ての精度 | 見立て外れの件数(中止・合流の衝突・合流後の検証失敗)/ 並行した組の数 | `parallel-log.md` |
| 認知負荷 | 数値にしない。利用者の所感があれば retro に 1 行 | 受け入れ時のコメント |

壁時計には利用者がセッションを開くまでの時間が入る(それも含めて実際のサイクル)。

### SKILL.md の 24 KB 上限(残り 8 バイト)の扱い

手順は `references/parallel.md` に置き、SKILL.md には 4 か所・計 299 バイトだけ足す。その分、境界リセットの節から説明の 3 文(計 338 バイト)を削る(Task 7 に原文)。差し引き 24,529 バイトの見込み。足りなければ 4 文目(93 バイト)を削る。

## Global Constraints

- 対象は Claude 版 `skills/r-super-loop-powers/`・`hooks/`・`tests/`・`README.md`。`skills-codex/` へはテンプレートのコピー(`scripts/sync-templates.ps1 -Mode Copy`)だけを反映する。
- `SKILL.md` は LF 換算で 24,576 バイト以下(`tests/skill-layout.tests.ps1` の `skill-size`)。着手時点で 24,568 バイト。
- 版: `.claude-plugin/plugin.json` を `0.13.0`、`.codex-plugin/plugin.json` を `0.1.4`。
- 並行は 2 本ちょうど・同じ Checkpoint の中・MVP 強度だけ。
- 台帳の場所: `<git の共通ディレクトリ>\rslp-parallel\<goal-slug>\`。共通ディレクトリは `git -C <dir> rev-parse --path-format=absolute --git-common-dir` で求める。
- 台帳のファイル: `group.json`(準備時に 1 回、合流時に合流担当が更新)、`m<n>.json`(その子だけが書く)、`merger`(排他作成。中身は合流担当の番号)、`halt.json`(排他作成)。JSON は UTF-8 BOM 無し、書き込みは `Write-ExitFile`(一時ファイル → 改名)。
- ブランチ名 `rslp/<goal-slug>/m<n>`。作業ツリー `<WorktreeRoot>\<goal-slug>-m<n>`、`WorktreeRoot` の既定は `<ベースの親>\<ベースのフォルダ名>.rslp`。
- マイルストーン番号 `<n>` は、マイルストーン名(`1-foo`)または state.md の `milestone:` の値の先頭の数字。
- state.md の新しい値: `phase: parallel`(分割中のベース)、`- parallel-base: <ベースの作業ツリーの絶対パス>`(子だけにある行。`- updated:` の直前)。
- 行の合併の対象(`info/attributes` に書く 4 行): `docs/r-super-loop-powers/*/assumptions.md`・`call-log.md`・`hook-log.md`・`scout/index.md`、いずれも `merge=union`。
- PASS の確定コミットに入れないもの: `<goal-dir>/state.md` と `<goal-dir>/resume-*`。
- hook-log.md の行: `YYYY-MM-DD HH:MM | <Result> | <Field3> | <Note> | m=<n>`(番号が取れなければ `m=-`)。
- `parallel.ps1`・`loop-log.ps1` の標準出力は ASCII の KV(`KEY: value`)。`STATUS:` は `OK` / `REFUSED` / `FAILED` / `CONFLICT` / `HALTED`。`OK` 以外は終了コード 1。`REFUSED` と `FAILED` では何も作らない・書かない。
- 日本語を含む `.ps1`(`parallel.ps1`・`loop-log.ps1`・`hook-common.ps1`)は UTF-8 BOM 付き。`codex-common.ps1` は ASCII だけ。
- git の呼び出しは必ず `git -C <dir>`。テストは一時ディレクトリに実リポジトリを作る(`git init -q -b main`、`user.email` / `user.name` を設定)。
- 各タスクの終わりに全テストを実行する: `for t in tests/*.tests.ps1; do powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$t" | grep -E '^FAIL|FAILURES|ALL PASS'; done`
- 着手時点の既知の失敗: なし(全テスト `ALL PASS` を Task 1 の最初に確かめる)。

## Review Focus

1. ベースのパスに空白がある(`C:\work\my app`)。作業ツリーの作成、子の `loop-log.ps1` の起動、台帳のパス照合が通る。Task 3 `prepare-path-with-space`。
2. ベースがブランチに居ない(detached HEAD。v0.12 のスモークで実際にあった)。`-Prepare` は `REFUSED` で、作業ツリーもブランチも台帳も残さない。Task 3 `prepare-refused-detached`。
3. ベースの state.md が CRLF・BOM 付き。子の state.md に足す `parallel-base` の行が改行を混在させず、`loop-log.ps1` がその後も欄を更新できる。Task 3 `prepare-crlf-state`。
4. `-Pass` をやり直す(コミット後に落ちた・印だけ残った)。空のコミットを作らず、同じ SHA のまま選出をやり直す。自分の番号が入った `merger` が残っていれば合流担当になる。Task 4 `pass-rerun-idempotent` / `pass-own-stale-merger`。
5. 対象プロジェクトの pre-commit フックが確定コミットを拒む。`-Pass` は `FAILED` で、台帳の行は `running` のまま。Task 4 `pass-commit-hook-fails`。

---

### Task 1: フックのログ行にマイルストーン番号(R-e)

**Files:**
- Modify: `hooks/hook-common.ps1:41-50`
- Modify: `README.md:75` 付近(フックの表の下に 1 行)
- Test: `tests/context-meter.tests.ps1`

**Interfaces:**
- Produces: `Get-MilestoneNumber([string]$GoalDir) -> string`(`<GoalDir>\state.md` の `- milestone:` の値の先頭の数字。無い・読めないときは `-`)。`Write-HookLogLine` の行末に ` | m=<n>` が付く。

- [ ] **Step 1: 全テストが通る状態を確かめる**

Run: Global Constraints のテストコマンド
Expected: 12 本すべて `ALL PASS`

- [ ] **Step 2: 失敗するテストを書く**

`tests/context-meter.tests.ps1` の `below-logged` の直後に足す:

```powershell
Check 'log-milestone-none' ((Get-Text $log) -match '(?m)\| CTX \| tokens=120000 \| tool=Agent \| m=-$') (Get-Text $log)
W (Join-Path $g 'state.md') "- phase: milestone-implementation`r`n- milestone: 12-orders (CP1)`r`n"
New-Transcript $tr @(130000)
$r = Invoke-Meter (New-Input $proj $tr) $low
Check 'log-milestone-number' ((Get-Text $log) -match '(?m)\| CTX \| tokens=130000 \| tool=Agent \| m=12$') (Get-Text $log)
W (Join-Path $g 'state.md') "- phase: milestone-implementation`n"
```

- [ ] **Step 3: 失敗を確かめる**

Run: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/context-meter.tests.ps1 | grep -E '^FAIL|FAILURES|ALL PASS'`
Expected: `FAIL log-milestone-none` と `FAIL log-milestone-number`

- [ ] **Step 4: `Get-MilestoneNumber` を足し、`Write-HookLogLine` の行を 5 列にする**

`Get-MilestoneNumber` は例外を外へ出さない(フックは失敗しても通す)。`Write-HookLogLine` の引数は変えない。コメントの列の説明を 5 列に直す。

- [ ] **Step 5: 通ることを確かめる**

Run: 全テスト
Expected: すべて `ALL PASS`(`resume-inject` と `human-message-check` の既存の照合は行末を固定していないので通る)

- [ ] **Step 6: README に 1 行足してコミット**

フックの表の直後: `` hook-log.md の各行の末尾には、その時点のマイルストーン番号が `m=<n>` で付く(並行した区間を子ごとに数えるため)。 ``

```bash
git add hooks/hook-common.ps1 tests/context-meter.tests.ps1 README.md
git commit -m "hooks: milestone number on every hook-log line"
```

---

### Task 2: `loop-log.ps1` の `parallel` フェーズ・並行中の記帳、`scout.ps1` の自動ラベル

**Files:**
- Modify: `skills/r-super-loop-powers/bin/codex-common.ps1`(末尾に関数 1 つ。ASCII だけ)
- Modify: `skills/r-super-loop-powers/bin/loop-log.ps1:115`(設計書の関門)、`:155`(call-log の行)
- Modify: `skills/r-super-loop-powers/bin/scout.ps1:222-228`(自動ラベル)
- Test: `tests/loop-log.tests.ps1`、`tests/scout.tests.ps1`

**Interfaces:**
- Produces: `Get-ParallelTag([string]$StateText) -> string`。state.md に `- parallel-base:` の行があり値が空でも `-` でもなく、かつ `- milestone:` の値が数字で始まるとき `m<n>`、それ以外は `''`。Task 3 も使う。
- Produces: `loop-log.ps1` は `learning → parallel` も設計書の行が無ければ `REFUSED` にする。並行の子では call-log の目的の末尾に ` [m<n>]` が付く。
- Produces: `scout.ps1` は `-Label` 省略時、並行の子では `m<n>-scout-<k>`(`k` は同じ接頭辞の `*.meta.json` の最大 + 1)。

- [ ] **Step 1: 失敗するテストを書く**

`tests/loop-log.tests.ps1` の `learning-done-refused` の直後:

```powershell
$r = Invoke-Log $g @('-SetPhase', 'parallel')
Check 'learning-parallel-refused' ($r.Code -ne 0 -and $r.Out -match '(?m)^STATUS: REFUSED\r?$' -and (Get-Text (Join-Path $g 'state.md')) -match '(?m)^- phase: learning$') $r.Out
```

同じファイルの `nothing-to-do-fails` の前:

```powershell
$gp = Join-Path $proj 'docs\r-super-loop-powers\gp'
W (Join-Path $gp 'state.md') ($stateLf -replace '- milestone: 1-one', '- milestone: 2-two' -replace '- updated:', "- parallel-base: C:\base`n- updated:")
$r = Invoke-Log $gp @('-Who', 'fable', '-Purpose', 'B-6 gate')
Check 'parallel-child-tags-call-log' ((Get-Text (Join-Path $gp 'call-log.md')) -match '(?m)\| fable \| milestone-implementation \| B-6 gate \[m2\]$') $r.Out
W (Join-Path $gp 'state.md') ($stateLf -replace '- updated:', "- parallel-base: -`n- updated:")
$r = Invoke-Log $gp @('-Who', 'fable', '-Purpose', 'serial')
Check 'parallel-base-dash-no-tag' ((Get-Text (Join-Path $gp 'call-log.md')) -match '(?m)\| serial$') $r.Out
$r = Invoke-Log $gp @('-SetPhase', 'parallel')
Check 'phase-parallel-accepted' ($r.Code -eq 0 -and (Get-Text (Join-Path $gp 'state.md')) -match '(?m)^- phase: parallel$') $r.Out
```

`tests/scout.tests.ps1` の `-Async` の節(151 行目付近。`$g4` を作っているのと同じ補助関数でゴール `$g6` を作る)の後に足す。state.md は `$stateLf` の `- milestone: 1-one` を `3-three` に変え、`- updated:` の前に `- parallel-base: C:\base` を入れたもの:

```powershell
$r = Invoke-Scout $g6 @('-WorkDir', $t, '-Question', 'q', '-Async')
Check 'parallel-child-auto-label' ((Get-Kv $r.Out 'LABEL') -eq 'm3-scout-1' -and (Test-Path -LiteralPath (Join-Path $g6 'codex-runs\m3-scout-1.prompt.md'))) $r.Out
$r = Invoke-Scout $g6 @('-WorkDir', $t, '-Question', 'q2', '-Async')
Check 'parallel-child-auto-label-next' ((Get-Kv $r.Out 'LABEL') -eq 'm3-scout-2') $r.Out
```

- [ ] **Step 2: 失敗を確かめる**

Run: `loop-log.tests.ps1` と `scout.tests.ps1`
Expected: `learning-parallel-refused`・`parallel-child-tags-call-log`・`parallel-child-auto-label`・`parallel-child-auto-label-next` が `FAIL`(`parallel-base-dash-no-tag` と `phase-parallel-accepted` は今の実装でも通る。変更後も通ることを見る検査)

- [ ] **Step 3: 実装する**

- `codex-common.ps1`: `Get-ParallelTag`。正規表現は ASCII のキーだけを見る。
- `loop-log.ps1:115`: 関門の遷移先を `@('milestone-implementation', 'done', 'parallel')` にする。call-log の行は `$Purpose` に `Get-ParallelTag $stateText` の結果があれば ` [<tag>]` を足す。
- `scout.ps1`: `-Label` 省略時に `<GoalDir>\state.md` を `Read-TextFile` で読み、タグがあれば接頭辞 `<tag>-scout-`、無ければ従来の `scout-`。

- [ ] **Step 4: 通ることを確かめてコミット**

Run: 全テスト → すべて `ALL PASS`

```bash
git add skills/r-super-loop-powers/bin/codex-common.ps1 skills/r-super-loop-powers/bin/loop-log.ps1 skills/r-super-loop-powers/bin/scout.ps1 tests/loop-log.tests.ps1 tests/scout.tests.ps1
git commit -m "loop-log/scout: parallel phase gate, milestone tag on call-log lines and scout labels"
```

---

### Task 3: `bin/parallel.ps1` — 準備(`-Prepare`)と状態(`-Status`)

**Files:**
- Create: `skills/r-super-loop-powers/bin/parallel.ps1`(UTF-8 BOM 付き)
- Create: `tests/parallel.tests.ps1`(UTF-8 BOM 付き)

**Interfaces:**
- Consumes: `Get-ParallelTag`・`Write-Kv`・`Read-TextFile`・`Write-TextFile`・`Write-ExitFile`(`codex-common.ps1`)、`loop-log.ps1`(子プロセスで起動。`loop-log.ps1:165-169` と同じ起動の仕方)
- Produces: スクリプトの引数(Task 4・5 が同じ `param` に足す前提で、ここで全部を宣言する):

```powershell
param(
    [Parameter(Mandatory = $true)][string]$GoalDir,   # 呼び出した側の作業ツリーにある goal-dir
    [switch]$Prepare, [switch]$Status, [switch]$Pass, [switch]$Merge, [switch]$Halt, [switch]$Cleanup,
    [string]$Milestones = '',      # -Prepare: "1-foo,2-bar"(2 つちょうど)
    [string]$WorktreeRoot = '',    # -Prepare: 既定 <ベースの親>\<ベースのフォルダ名>.rslp
    [string]$Reason = '',          # -Halt
    [string]$Keep = '',            # -Halt: 残すマイルストーン番号(既定: 呼び出した子)
    [int]$ElectTries = 5,          # -Pass: 選出の試行回数
    [int]$ElectWaitMs = 1000       # -Pass: 試行の間隔
)
```

- Produces: 共通の関数(Task 4・5 が使う): `Get-Ledger([string]$GoalDir)` は `@{ Dir; Group; Rows; Halt; Merger; Self; Role; Top; GoalRel }` を返す。`Group` は `group.json`(無ければ `$null`)、`Rows` は番号 → `m<n>.json` の内容、`Self` は呼び出し側の作業ツリーが子ならその番号、`Role` は `base` / `child` / `none`、`Top` は `git rev-parse --show-toplevel`、`GoalRel` は `Top` からの goal-dir の相対パス(`/` 区切り)。パスの照合は区切り・末尾の区切り・大文字小文字を無視する。
- Produces: `group.json` = `{ slug, base, baseBranch, baseSha, created, milestones: [{ n, name, branch, worktree }], merged, conflicts: [], redo: [] }`、`m<n>.json` = `{ n, status, started, passed, sha }`(`status` は `running` / `passed`)。時刻は ISO 8601(`(Get-Date).ToString('o')`)。番号(`n`・`by`・`keep`・`redo` の要素・`merger` の中身)はすべて文字列。`Top`・`base`・`worktree` と、state.md の `parallel-base:`・出力の `WORKTREE:` / `BASE:` は `\` 区切りの絶対パス(git が返す `/` 区切りを直す)。

**`-Prepare` の検査(どれかに当たれば `REFUSED`、何も作らない)**

1. `-Milestones` が 2 つちょうどで、どちらも `^\d+-` で始まり、番号が異なる
2. state.md の `強度` が `MVP` で始まる
3. ベースがブランチに居る(`git symbolic-ref --short HEAD` が成功)
4. `git status --porcelain --untracked-files=no` が空
5. goal-dir の下に未追跡ファイルが無い(`resume-pending`・`resume-packet.md`・`resume-pending.failed` は数えない)。`REASON:` に最大 10 件のパス、`NEXT:` は「コミットしてから再実行」
6. 台帳のディレクトリ・2 つのブランチ・2 つの作業ツリーのパスが、どれも存在しない

**`-Prepare` の動作(検査の後、この順)**

1. ベースの state.md を `loop-log.ps1 -SetPhase parallel -SetMilestone "<a> + <b>" -SetWait "並行中: <a> / <b>(合流まで、このフォルダでは作業しない)"` で更新する。`REFUSED`(設計書の関門)ならその `REASON:` / `NEXT:` を中継して終わる
2. `info/attributes` に 4 行を足す(既にある行は足さない。ファイルが無ければ作る)
3. マイルストーンごとに `git worktree add -q -b <branch> <path> HEAD`
4. 子の state.md(作業ツリーにあるコミット済みの写し)に `- parallel-base: <ベース>` を `- updated:` の直前に足す(その行の改行に合わせる)。続けて `loop-log.ps1 -GoalDir <子の goal-dir> -SetPhase milestone-implementation -SetMilestone <名前> -SetOwner opus-main -SetGate impl-gate -Clear '待ち,codex-run' -Mark`
5. `group.json` と `m<n>.json`(`status: running`、`started` = 現在)を書く
6. 3〜5 のどこかで失敗したら、作った作業ツリー・ブランチ・台帳を消し、ベースの state.md を 1 の前の内容に戻して `FAILED`(`ROLLED_BACK: yes`)

出力: `WORKTREE: m<n> | <絶対パス>`(2 行)、`BRANCH: m<n> | <ブランチ>`(2 行)、`LEDGER: <dir>`、`STATUS: OK`、`NEXT: ask the human to open a new session in each WORKTREE folder and send "continue"; close this session`

**`-Status` の出力:** 台帳が無ければ `GROUP: none` と `STATUS: OK`。あれば `GROUP: <a> + <b>`、`ROLE: base|child|none`、`SELF: m<n>`(子だけ)、`BASE: <path>`、`CHILD: m<n> | <status> | <sha または -> | <worktree>`(2 行)、`MERGER: <n または ->`、`HALTED: no` または `HALTED: yes | keep=m<n> | <reason>`、`MERGED: <時刻 または ->`、`STATUS: OK`

- [ ] **Step 1: テストの土台と失敗するテストを書く**

`tests/parallel.tests.ps1`。既存のテストと同じ `Check` / `W` / `Get-Text` / `Get-Kv`(`tests/scout.tests.ps1` の定義を写す)と、次の 2 つ:

```powershell
function Invoke-Par([string]$Goal, [string[]]$Extra) {
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -GoalDir $Goal @Extra 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}
# 一時ディレクトリに「ゴール g1 をコミット済みのリポジトリ」を作り、ベースのパスを返す。
function New-Repo([string]$Dir, [string]$StateText) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    git -C $Dir init -q -b main 2>$null
    git -C $Dir config user.email t@example.com; git -C $Dir config user.name t
    $g = Join-Path $Dir 'docs\r-super-loop-powers\g1'
    W (Join-Path $g 'state.md') $StateText
    W (Join-Path $g 'call-log.md') "# call-log — g1`n`n"
    W (Join-Path $g 'hook-log.md') "2026-11-16 09:00 | PASS | ja-ratio=0.9 |  | m=-`n"
    W (Join-Path $g 'assumptions.md') "| ID | 仮定 | 状態 |`n|---|---|---|`n"
    W (Join-Path $g 'goal-frame.md') "## 制約`n- c`n`n## 承認基準`n1. a`n`n## 終了条件`ne`n"
    W (Join-Path $Dir 'app.txt') "a`n"
    git -C $Dir add -A 2>$null; git -C $Dir commit -q -m init 2>$null
    return $Dir
}
$stateLf = "# state — g1`n- phase: goal-definition`n- 強度: MVP`n- milestone: -`n- 次のCheckpoint: 2-two`n- 担当: opus-main`n- 次のゲート: goal-gate`n- 待ち: -`n- skill-dir: C:\skill`n- codex-env: C:\env.json`n- codex-run: -`n- updated: 2026-11-16 10:00`n"
```

検査(名前と条件):

```powershell
$base = New-Repo (Join-Path $t 'my app') $stateLf          # 空白入りのパス
$g = Join-Path $base 'docs\r-super-loop-powers\g1'
$r = Invoke-Par $g @('-Status')
Check 'status-none' ($r.Code -eq 0 -and (Get-Kv $r.Out 'GROUP') -eq 'none') $r.Out
$r = Invoke-Par $g @('-Prepare', '-Milestones', '1-one,2-two')
$w1 = Join-Path $t 'my app.rslp\g1-m1'; $w2 = Join-Path $t 'my app.rslp\g1-m2'
$c1 = Join-Path $w1 'docs\r-super-loop-powers\g1'
Check 'prepare-path-with-space' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'OK' -and (Test-Path -LiteralPath $c1) -and (Test-Path -LiteralPath (Join-Path $w2 'app.txt'))) $r.Out
$s1 = Get-Text (Join-Path $c1 'state.md')
Check 'prepare-child-state' ($s1 -match '(?m)^- phase: milestone-implementation$' -and $s1 -match '(?m)^- milestone: 1-one$' -and $s1 -match '(?m)^- 次のゲート: impl-gate$' -and $s1.Contains("- parallel-base: $base`n- updated:")) $s1
$sb = Get-Text (Join-Path $g 'state.md')
Check 'prepare-base-state' ($sb -match '(?m)^- phase: parallel$' -and $sb -match '(?m)^- milestone: 1-one \+ 2-two$' -and $sb -match '(?m)^- 待ち: 並行中: 1-one / 2-two') $sb
$mk = Get-Text (Join-Path $c1 'resume-pending')
Check 'prepare-child-marker-cwd' ($mk -match ('(?m)^cwd: ' + [regex]::Escape($w1) + '$')) $mk
$common = (git -C $base rev-parse --path-format=absolute --git-common-dir).Trim()
$led = Join-Path $common 'rslp-parallel\g1'
Check 'prepare-ledger' ((Test-Path (Join-Path $led 'group.json')) -and ((Get-Text (Join-Path $led 'm1.json')) | ConvertFrom-Json).status -eq 'running' -and -not (Test-Path (Join-Path $led 'merger'))) (Get-ChildItem $led | Out-String)
$attr = Get-Text (Join-Path $common 'info\attributes')
Check 'prepare-attributes' ($attr.Contains('docs/r-super-loop-powers/*/call-log.md merge=union') -and $attr.Contains('docs/r-super-loop-powers/*/hook-log.md merge=union') -and $attr.Contains('docs/r-super-loop-powers/*/assumptions.md merge=union') -and $attr.Contains('docs/r-super-loop-powers/*/scout/index.md merge=union')) $attr
Check 'prepare-branches' ((git -C $base branch --list 'rslp/g1/*' | Measure-Object).Count -eq 2) (git -C $base branch | Out-String)
$r = Invoke-Par $c1 @('-Status')
Check 'status-child' ((Get-Kv $r.Out 'ROLE') -eq 'child' -and (Get-Kv $r.Out 'SELF') -eq 'm1' -and $r.Out -match '(?m)^CHILD: m2 \| running \| - \| ' -and (Get-Kv $r.Out 'HALTED') -eq 'no') $r.Out
$r = Invoke-Par $g @('-Status')
Check 'status-base' ((Get-Kv $r.Out 'ROLE') -eq 'base' -and (Get-Kv $r.Out 'GROUP') -eq '1-one + 2-two') $r.Out
$r = Invoke-Par $g @('-Prepare', '-Milestones', '1-one,2-two')
Check 'prepare-twice-refused' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out
```

拒否の検査は、検査ごとに新しいリポジトリを `New-Repo` で作り、拒否の後に「作業ツリー無し(`git worktree list` が 1 行)・`rslp/` のブランチ無し・台帳のディレクトリ無し・state.md が変わっていない」を `Assert-Nothing` という補助関数 1 つで確かめる:

| 検査名 | 仕込み | 期待 |
|---|---|---|
| `prepare-refused-three` | `-Milestones '1-a,2-b,3-c'` | `REFUSED` |
| `prepare-refused-same-number` | `-Milestones '1-a,1-b'` | `REFUSED` |
| `prepare-refused-high` | state.md の `強度: 高信頼` | `REFUSED` |
| `prepare-refused-detached` | `git checkout -q --detach` | `REFUSED`、`REASON:` に `detached` |
| `prepare-refused-dirty` | `app.txt` を書き換え | `REFUSED`、`REASON:` に `app.txt` |
| `prepare-refused-untracked-goal-file` | goal-dir に未追跡の `goal-plan.md` | `REFUSED`、`REASON:` に `goal-plan.md` |
| `prepare-allows-resume-files` | goal-dir に未追跡の `resume-packet.md` | `OK` |
| `prepare-learning-refused-without-design-row` | state.md の `phase: learning`・`milestone: 0-zero`、design.md 無し | `REFUSED`、`REASON:` に `design.md` |
| `prepare-crlf-state` | state.md を CRLF・BOM 付きでコミット | `OK`。子の state.md に `"`r`n- parallel-base: "` があり、`(?<!\r)\n` に一致する箇所が無い |

末尾に `script-has-bom`(`loop-log.tests.ps1` と同じ形)。

- [ ] **Step 2: 失敗を確かめる**

Run: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/parallel.tests.ps1 | grep -E '^FAIL|FAILURES|ALL PASS'`
Expected: スクリプトが無いので全検査が `FAIL`

- [ ] **Step 3: `parallel.ps1` の `-Prepare` と `-Status` を実装する**

モードのスイッチが 1 つちょうどでなければ `FAILED`。`-Pass`・`-Merge`・`-Halt`・`-Cleanup` はこのタスクでは `FAILED`(`REASON: not implemented`)。git の出力は `2>&1 | Out-String` で受け、終了コードで判定する。

- [ ] **Step 4: 通ることを確かめてコミット**

Run: 全テスト → すべて `ALL PASS`

```bash
git add skills/r-super-loop-powers/bin/parallel.ps1 tests/parallel.tests.ps1
git commit -m "parallel.ps1: prepare worktrees, ledger in the git common dir, status"
```

---

### Task 4: `parallel.ps1` — PASS の確定(`-Pass`)と中止(`-Halt`)

**Files:**
- Modify: `skills/r-super-loop-powers/bin/parallel.ps1`
- Modify: `tests/parallel.tests.ps1`

**Interfaces:**
- Consumes: Task 3 の `Get-Ledger` と台帳の形
- Produces: `halt.json` = `{ by, keep, reason, at }`。`-Pass` の出力 `SHA: <40 桁>`・`ROLE: merger|wait`。Task 5 は「`merger` の中身 = 自分の番号」を合流の資格として使う。

**`-Pass`(子の goal-dir で呼ぶ)**

1. 呼び出し側が子でなければ `REFUSED`
2. `halt.json` があり `keep` が自分でなければ `STATUS: HALTED`(終了コード 1、`NEXT: stop; this milestone will be redone serially in the base worktree`)。何もコミットしない
3. `milestones\<自分の名前>\gate-decision.md` が無い、または `\bPASS\b` に一致しなければ `REFUSED`
4. 確定コミット: `git add -A -- . ":(exclude)<GoalRel>/state.md" ":(exclude)<GoalRel>/resume-*"` → ステージに何かあれば `git commit -q -m "rslp: m<n> PASS (<slug>, parallel)"`。コミットが失敗したら `FAILED`(`REASON:` に git の出力の末尾 300 文字)。ステージが空ならコミットしない
5. `m<n>.json` を `status: passed`・`sha: <HEAD>`・`passed: <現在>` にする(既に `passed` なら `passed` の時刻は変えない)
6. 選出(下のアルゴリズム)
7. 出力: `SHA:`、`ROLE:`、`STATUS: OK`。`NEXT:` は `merger` なら `parallel.ps1 -Merge -GoalDir "<GoalDir>"`、`wait` なら `tell the human this milestone passed and the other session will merge; end this session`

選出は、署名とテストだけでは決まらないのでここに書く(各子は**自分の行を `passed` にしてから** `merger` を作りにいく。作った後で相手が未完了なら消し、消した後にもう一度相手を見る。これで「両方が待つ」「両方が担当する」のどちらも起きない):

```powershell
# returns 'merger' or 'wait'
function Select-Merger($Ledger, [string]$Self, [string]$Sibling, [bool]$HaltKeepsSelf) {
    $file = Join-Path $Ledger.Dir 'merger'
    for ($i = 0; $i -lt $ElectTries; $i++) {
        $mine = $false
        try {
            $fs = [IO.File]::Open($file, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $b = [Text.Encoding]::ASCII.GetBytes($Self); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
            $mine = $true
        } catch [IO.IOException] {
            if ((Read-TextFile $file).Trim() -eq $Self) { return 'merger' }   # 自分の印が残っていた(やり直し)
        }
        if ($mine) {
            if ($HaltKeepsSelf -or (Get-RowStatus $Ledger.Dir $Sibling) -eq 'passed') { return 'merger' }
            Remove-Item -LiteralPath $file -Force
            if ((Get-RowStatus $Ledger.Dir $Sibling) -ne 'passed') { return 'wait' }
            continue                                                         # 消した直後に相手が passed になった
        }
        Start-Sleep -Milliseconds $ElectWaitMs                               # 相手が判定中。消えるか、残るかを待つ
    }
    return 'wait'                                                            # 相手の印が残った = 相手が担当
}
```

`Get-RowStatus([string]$Dir, [string]$N) -> string` は `m<n>.json` を読み直して `status` を返す。

**`-Halt -Reason <text> [-Keep <n>]`(子の goal-dir で呼ぶ)**

- 呼び出し側が子でなければ `REFUSED`。`-Reason` が空なら `FAILED`。`-Keep` は 2 つの番号のどちらか(省略時は自分)
- `halt.json` を排他作成で書く。既にあれば書き換えず、その内容を出す
- 出力: `HALTED_BY: m<n>`、`KEEP: m<n>`、`STATUS: OK`、`NEXT: ask the human to tell the other session "parallel is halted"; continue this milestone and run -Pass when B-6 passes`

- [ ] **Step 1: 失敗するテストを書く**

`tests/parallel.tests.ps1` に補助関数を足す:

```powershell
# 準備済みのリポジトリを新しく作る。@{ Base; G; W1; W2; C1; C2; Led } を返す。
function New-Prepared([string]$Name) { <# New-Repo → -Prepare '1-one,2-two' → パスを組む #> }
# 子の作業ツリーで「実装 1 ファイル + PASS の判定 + ログ 1 行ずつ」を作る。
function Add-Work($P, [int]$N, [string]$File, [string]$Body) {
    $w = @($P.W1, $P.W2)[$N - 1]; $c = @($P.C1, $P.C2)[$N - 1]; $name = @('1-one', '2-two')[$N - 1]
    W (Join-Path $w $File) $Body
    W (Join-Path $c "milestones\$name\gate-decision.md") "PASS`n根拠`n"
    [IO.File]::AppendAllText((Join-Path $c 'call-log.md'), "2026-11-16 11:00 | fable | milestone-implementation | B-6 gate [m$N]`n", $utf8)
    [IO.File]::AppendAllText((Join-Path $c 'hook-log.md'), "2026-11-16 11:00 | PASS | ja-ratio=0.9 |  | m=$N`n", $utf8)
}
$fast = @('-ElectTries', '2', '-ElectWaitMs', '50')
```

検査:

```powershell
$p = New-Prepared 'pass'
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-refused-without-gate-decision' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED' -and ((Get-Text (Join-Path $p.Led 'm1.json')) | ConvertFrom-Json).status -eq 'running') $r.Out
Add-Work $p 1 'f1.txt' "one`n"
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
$row1 = (Get-Text (Join-Path $p.Led 'm1.json')) | ConvertFrom-Json
$head1 = (git -C $p.W1 rev-parse HEAD).Trim()
Check 'pass-first-waits' ($r.Code -eq 0 -and (Get-Kv $r.Out 'ROLE') -eq 'wait' -and $row1.status -eq 'passed' -and $row1.sha -eq $head1 -and (Get-Kv $r.Out 'SHA') -eq $head1 -and -not (Test-Path (Join-Path $p.Led 'merger'))) $r.Out
$names = (git -C $p.W1 show --name-only --format= HEAD | Out-String)
Check 'pass-commit-contents' ($names -match 'f1\.txt' -and $names -match 'gate-decision\.md' -and $names -match 'call-log\.md' -and $names -notmatch 'state\.md' -and $names -notmatch 'resume-') $names
Check 'pass-leaves-state-uncommitted' ((git -C $p.W1 status --porcelain | Out-String) -match 'state\.md') (git -C $p.W1 status --porcelain | Out-String)
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-rerun-idempotent' ((Get-Kv $r.Out 'ROLE') -eq 'wait' -and (git -C $p.W1 rev-parse HEAD).Trim() -eq $head1 -and ((Get-Text (Join-Path $p.Led 'm1.json')) | ConvertFrom-Json).passed -eq $row1.passed) $r.Out
Add-Work $p 2 'f2.txt' "two`n"
$r = Invoke-Par $p.C2 (@('-Pass') + $fast)
Check 'pass-last-is-merger' ((Get-Kv $r.Out 'ROLE') -eq 'merger' -and (Get-Text (Join-Path $p.Led 'merger')).Trim() -eq '2' -and $r.Out -match '(?m)^NEXT: .*-Merge') $r.Out
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-sibling-holds-merger' ((Get-Kv $r.Out 'ROLE') -eq 'wait' -and (Get-Text (Join-Path $p.Led 'merger')).Trim() -eq '2') $r.Out
$r = Invoke-Par $p.C2 (@('-Pass') + $fast)
Check 'pass-own-stale-merger' ((Get-Kv $r.Out 'ROLE') -eq 'merger') $r.Out
$r = Invoke-Par $p.G (@('-Pass') + $fast)
Check 'pass-refused-from-base' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out
```

pre-commit フックの検査:

```powershell
$p = New-Prepared 'hook'
$common = (git -C $p.Base rev-parse --path-format=absolute --git-common-dir).Trim()
W (Join-Path $common 'hooks\pre-commit') "#!/bin/sh`necho blocked-by-hook >&2`nexit 1`n"
Add-Work $p 1 'f1.txt' "one`n"
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-commit-hook-fails' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED' -and $r.Out -match 'blocked-by-hook' -and ((Get-Text (Join-Path $p.Led 'm1.json')) | ConvertFrom-Json).status -eq 'running') $r.Out
```

中止の検査:

```powershell
$p = New-Prepared 'halt'
$r = Invoke-Par $p.C1 @('-Halt')
Check 'halt-needs-reason' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'FAILED') $r.Out
$r = Invoke-Par $p.C1 @('-Halt', '-Reason', 'sibling definition changes')
$h = (Get-Text (Join-Path $p.Led 'halt.json')) | ConvertFrom-Json
Check 'halt-written' ($r.Code -eq 0 -and $h.by -eq '1' -and $h.keep -eq '1' -and $h.reason -eq 'sibling definition changes' -and (Get-Kv $r.Out 'KEEP') -eq 'm1') $r.Out
$r = Invoke-Par $p.C2 @('-Halt', '-Reason', 'late')
Check 'halt-first-wins' (((Get-Text (Join-Path $p.Led 'halt.json')) | ConvertFrom-Json).by -eq '1') $r.Out
$r = Invoke-Par $p.C2 @('-Status')
Check 'status-shows-halt' ($r.Out -match '(?m)^HALTED: yes \| keep=m1 \| sibling definition changes') $r.Out
Add-Work $p 2 'f2.txt' "two`n"
$before = (git -C $p.W2 rev-parse HEAD).Trim()
$r = Invoke-Par $p.C2 (@('-Pass') + $fast)
Check 'pass-halted-sibling-stops' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'HALTED' -and (git -C $p.W2 rev-parse HEAD).Trim() -eq $before) $r.Out
Add-Work $p 1 'f1.txt' "one`n"
$r = Invoke-Par $p.C1 (@('-Pass') + $fast)
Check 'pass-halter-is-merger' ((Get-Kv $r.Out 'ROLE') -eq 'merger' -and (Get-Text (Join-Path $p.Led 'merger')).Trim() -eq '1') $r.Out
```

- [ ] **Step 2: 失敗を確かめる**

Run: `tests/parallel.tests.ps1`
Expected: Task 3 の検査は `PASS`、足した検査は `FAIL`

- [ ] **Step 3: `-Pass` と `-Halt` を実装する**

- [ ] **Step 4: 通ることを確かめてコミット**

Run: 全テスト → すべて `ALL PASS`

```bash
git add skills/r-super-loop-powers/bin/parallel.ps1 tests/parallel.tests.ps1
git commit -m "parallel.ps1: pinned PASS commit, merger election by exclusive create, halt"
```

---

### Task 5: `parallel.ps1` — 合流(`-Merge`)と後片付け(`-Cleanup`)

**Files:**
- Modify: `skills/r-super-loop-powers/bin/parallel.ps1`
- Modify: `tests/parallel.tests.ps1`

**Interfaces:**
- Consumes: Task 4 の `merger`・`halt.json`・`m<n>.json` の `sha`
- Produces: `<ベースの goal-dir>\parallel-log.md`(追記。未コミットのまま残す)。`-Merge` の出力 `MERGED: m<n> | <短い SHA>`・`REDO: m<n>`・`BASE_HEAD:`・`WALL_MINUTES:`・`SERIAL_MINUTES:`。

**`-Merge`(合流担当の子の goal-dir で呼ぶ。やり直せる)**

1. `merger` の中身が自分の番号でなければ `REFUSED`。`group.json` の `merged` が既にあれば、何もコミットせず、何も追記せずに、記録から同じ出力(`MERGED:`・`REDO:`・`BASE_HEAD:`・`STATUS: OK`)を出して終わる
2. 合流する集合: `halt.json` があれば `keep` の 1 本だけ、無ければ 2 本。集合の行がどれか `passed` でなければ `REFUSED`
3. ベースの検査(`REFUSED`): 現在のブランチが `baseBranch` でない / `MERGE_HEAD` がある(`NEXT: resolve and commit, or git merge --abort, in <base>`)/ `git status --porcelain --untracked-files=no` に goal-dir の外のパスがある(`REASON:` に最大 10 件)
4. ベースのゴール記録に未コミットの変更があれば `git -C <base> add -- <GoalRel>` → `git commit -q -m "rslp: goal records before merge (<slug>)"`
5. 集合を番号順に: `git merge-base --is-ancestor <sha> HEAD` なら飛ばす。そうでなければ `git -C <base> merge --no-ff --no-edit -m "rslp: merge m<n> (<slug>)" <sha>`
6. マージが失敗したら: `git diff --name-only --diff-filter=U` を取り、`git merge --abort` し、`group.json` の `conflicts` に `{ n, files, at }` を足して、`CONFLICT_FILE: <path>`(各行)・`UNMERGED: m<n>`・`MERGED:`(済んだ分)・`STATUS: CONFLICT` を出して終了コード 1
7. 全部入ったら: `group.json` の `merged` に現在時刻、`redo` に集合に入らなかった番号。`parallel-log.md` に 1 区画を追記する。`WALL_MINUTES` = `merged − created`、`SERIAL_MINUTES` = 合流した子の `passed − created` の合計(分に丸める)
8. 出力の `NEXT:` は `run the integrated verification in <base>, then loop-log.ps1 -GoalDir "<ベースの goal-dir>" ... -Mark (references/parallel.md 4)`

`parallel-log.md` の 1 区画(日本語はこの形で固定):

```markdown
## 2026-11-16 12:40 1-one + 2-two
- 準備 2026-11-16 10:05 / 合流 2026-11-16 12:40 / 壁時計 155 分 / 直列換算 250 分
- 中止: なし
- 合流の衝突: なし

| マイルストーン | 結果 | PASS | コミット |
|---|---|---|---|
| 1-one | merged | 2026-11-16 11:50 | abc1234 |
| 2-two | merged | 2026-11-16 12:35 | def5678 |
```

`中止:` は `halt.json` があれば `m<keep> を残して中止(<reason>)`。`合流の衝突:` は `conflicts` があれば `m<n>: <ファイルを , で連結>`。`結果` は `merged` か `redo`(`redo` の行の PASS とコミットは、あればその値、無ければ `-`)。ファイルが無ければ先頭に `# parallel-log — <slug>` を置く。

**`-Cleanup`(ベースの goal-dir で呼ぶ)**

- 呼び出し側がベースでない、または `group.json` の `merged` が空なら `REFUSED`
- 合流済みの子: `git worktree remove --force <path>` → 成功したら `git branch -d <branch>`。失敗は `WARN: could not remove <path>: <理由>`(止めない)
- `redo` の子: 何も消さず `KEPT_WORKTREE: <path>` と `KEPT_BRANCH: <branch>` を出す
- `WARN:` が 1 つも無ければ台帳のディレクトリを消す。あれば残して `REMAINING: <数>`(再実行できる)
- `WorktreeRoot` のフォルダが空なら消す
- `STATUS: OK`

- [ ] **Step 1: 失敗するテストを書く**

```powershell
# 両方 PASS・m2 が合流担当、まで進めた状態を返す。
function New-Passed([string]$Name, [string]$File1 = 'f1.txt', [string]$File2 = 'f2.txt') { <# New-Prepared → Add-Work 1/2 → -Pass C1 → -Pass C2 #> }

$p = New-Passed 'merge'
$r = Invoke-Par $p.C1 @('-Merge')
Check 'merge-refused-non-merger' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out
[IO.File]::AppendAllText((Join-Path $p.G 'hook-log.md'), "2026-11-16 10:06 | PASS | ja-ratio=0.9 |  | m=1`n", $utf8)   # 準備したセッションの Stop フックの行
W (Join-Path $p.Base 'app.txt') "dirty`n"
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-refused-dirty-base' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED' -and $r.Out -match 'app\.txt') $r.Out
git -C $p.Base checkout -q -- app.txt
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-ok' ($r.Code -eq 0 -and (Get-Kv $r.Out 'STATUS') -eq 'OK' -and (Test-Path (Join-Path $p.Base 'f1.txt')) -and (Test-Path (Join-Path $p.Base 'f2.txt')) -and $r.Out -match '(?m)^MERGED: m1 \| [0-9a-f]{7}' -and $r.Out -match '(?m)^MERGED: m2 \| ' -and $r.Out -match '(?m)^WALL_MINUTES: \d+' -and $r.Out -match '(?m)^SERIAL_MINUTES: \d+') $r.Out
$cl = Get-Text (Join-Path $p.G 'call-log.md'); $hl = Get-Text (Join-Path $p.G 'hook-log.md')
Check 'merge-union-keeps-both' ($cl -match 'B-6 gate \[m1\]' -and $cl -match 'B-6 gate \[m2\]' -and $hl -match '(?m)\| m=1$' -and $hl -match '(?m)\| m=2$' -and $hl -match '10:06' -and $cl -notmatch '<<<<<<<') ($cl + $hl)
Check 'merge-base-state-untouched' ((Get-Text (Join-Path $p.G 'state.md')) -match '(?m)^- phase: parallel$') (Get-Text (Join-Path $p.G 'state.md'))
$pl = Get-Text (Join-Path $p.G 'parallel-log.md')
Check 'merge-writes-parallel-log' ($pl.StartsWith('# parallel-log — g1') -and $pl -match '(?m)^## \d{4}-\d{2}-\d{2} \d{2}:\d{2} 1-one \+ 2-two$' -and $pl -match '壁時計 \d+ 分 / 直列換算 \d+ 分' -and $pl -match '(?m)^- 中止: なし$' -and $pl -match '(?m)^\| 1-one \| merged \| ' -and $pl -match '(?m)^\| 2-two \| merged \| ') $pl
$headB = (git -C $p.Base rev-parse HEAD).Trim()
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-rerun-noop' ($r.Code -eq 0 -and (git -C $p.Base rev-parse HEAD).Trim() -eq $headB -and ([regex]::Matches((Get-Text (Join-Path $p.G 'parallel-log.md')), '(?m)^## ')).Count -eq 1) $r.Out
$r = Invoke-Par $p.C2 @('-Cleanup')
Check 'cleanup-refused-from-child' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out
$r = Invoke-Par $p.G @('-Cleanup')
Check 'cleanup-ok' ($r.Code -eq 0 -and -not (Test-Path $p.W1) -and -not (Test-Path $p.W2) -and -not (Test-Path $p.Led) -and -not (git -C $p.Base branch --list 'rslp/g1/*') -and (Test-Path (Join-Path $p.G 'parallel-log.md'))) $r.Out
$r = Invoke-Par $p.G @('-Status')
Check 'status-none-after-cleanup' ((Get-Kv $r.Out 'GROUP') -eq 'none') $r.Out
```

衝突(同じ実装ファイルを両方が書く)と、その後の中止:

```powershell
$p = New-Passed 'conflict' 'same.txt' 'same.txt'      # Add-Work の本文は m1 と m2 で違う
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-conflict' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'CONFLICT' -and $r.Out -match '(?m)^CONFLICT_FILE: same\.txt' -and $r.Out -match '(?m)^UNMERGED: m2' -and $r.Out -match '(?m)^MERGED: m1 \| ') $r.Out
Check 'merge-conflict-aborted' (-not (git -C $p.Base rev-parse -q --verify MERGE_HEAD 2>$null) -and (Get-Text (Join-Path $p.Base 'same.txt')) -notmatch '<<<<<<<') (git -C $p.Base status | Out-String)
$r = Invoke-Par $p.G @('-Cleanup')
Check 'cleanup-refused-before-merge' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED') $r.Out
$r = Invoke-Par $p.C2 @('-Halt', '-Keep', '1', '-Reason', 'merge conflict: same.txt')
$r = Invoke-Par $p.C2 @('-Merge')
$pl = Get-Text (Join-Path $p.G 'parallel-log.md')
Check 'merge-after-halt-keep' ($r.Code -eq 0 -and $r.Out -match '(?m)^REDO: m2' -and $pl -match '(?m)^- 中止: m1 を残して中止(merge conflict: same\.txt)$' -and $pl -match '(?m)^- 合流の衝突: m2: same\.txt$' -and $pl -match '(?m)^\| 2-two \| redo \| ') ($r.Out + $pl)
$r = Invoke-Par $p.G @('-Cleanup')
Check 'cleanup-keeps-redo' ($r.Code -eq 0 -and -not (Test-Path $p.W1) -and (Test-Path $p.W2) -and $r.Out -match '(?m)^KEPT_BRANCH: rslp/g1/m2' -and $r.Out -match '(?m)^KEPT_WORKTREE: ' -and -not (Test-Path $p.Led)) $r.Out
```

中止した側だけの合流:

```powershell
$p = New-Prepared 'solo'
Invoke-Par $p.C1 @('-Halt', '-Reason', 'coupled') | Out-Null
Add-Work $p 1 'f1.txt' "one`n"
Invoke-Par $p.C1 (@('-Pass') + $fast) | Out-Null
$r = Invoke-Par $p.C1 @('-Merge')
Check 'merge-solo-after-halt' ($r.Code -eq 0 -and (Test-Path (Join-Path $p.Base 'f1.txt')) -and $r.Out -match '(?m)^REDO: m2' -and $r.Out -notmatch '(?m)^MERGED: m2') $r.Out
```

ベースが別のブランチに居る:

```powershell
$p = New-Passed 'branch'
git -C $p.Base checkout -q -b other
$r = Invoke-Par $p.C2 @('-Merge')
Check 'merge-refused-wrong-branch' ($r.Code -ne 0 -and (Get-Kv $r.Out 'STATUS') -eq 'REFUSED' -and $r.Out -match 'main') $r.Out
```

- [ ] **Step 2: 失敗を確かめる**

Run: `tests/parallel.tests.ps1` → 足した検査が `FAIL`

- [ ] **Step 3: `-Merge` と `-Cleanup` を実装する**

- [ ] **Step 4: 通ることを確かめてコミット**

Run: 全テスト → すべて `ALL PASS`

```bash
git add skills/r-super-loop-powers/bin/parallel.ps1 tests/parallel.tests.ps1
git commit -m "parallel.ps1: merge pinned SHAs in the base worktree, parallel-log, cleanup"
```

---

### Task 6: 手順書(`references/parallel.md`・workflow-a・workflow-b・policy・retro テンプレート・README)

**Files:**
- Create: `skills/r-super-loop-powers/references/parallel.md`
- Modify: `skills/r-super-loop-powers/references/workflow-a.md`(技術PM 共通契約の実装アセス、A-2〜A-4 の末尾、A-8)
- Modify: `skills/r-super-loop-powers/references/workflow-b.md`(B-1・B-4・B-6・Learning 1・Learning 3)
- Modify: `skills/r-super-loop-powers/policy.md`(`## Checkpointとマイルストーン粒度` の後に新しい節、`## 観測` に 1 行)
- Modify: `skills/r-super-loop-powers/templates/retrospective-note.md`(観測に 1 行)→ `scripts/sync-templates.ps1 -Mode Copy`
- Modify: `README.md`(使い方・リポジトリ構成・E2E)
- Test: `tests/skill-layout.tests.ps1`

**Interfaces:**
- Consumes: `parallel.ps1` の引数と出力(Task 3〜5)。文書に書くコマンドとキーは、そこで決めた名前と一字一句同じにする。

- [ ] **Step 1: 失敗するテストを書く**

`tests/skill-layout.tests.ps1` の末尾(`if ($script:failures -gt 0)` の前):

```powershell
# v0.13: parallel milestone sessions (references/parallel.md, bin/parallel.ps1).
$par = Get-Text (Join-Path $skillDir 'references\parallel.md')
Check 'parallel-file' ($par -ne '') 'references/parallel.md missing'
Check 'parallel-sections' ($par -match '(?m)^## 1\. 分割の判定' -and $par -match '(?m)^## 2\. 準備' -and $par -match '(?m)^## 3\. 子のセッション' -and $par -match '(?m)^## 4\. 合流' -and $par -match '(?m)^## 5\. 見立てが外れたとき' -and $par -match '(?m)^## 6\. 後片付け') 'parallel.md sections'
Check 'parallel-commands' ($par -match 'parallel\.ps1 -Prepare' -and $par -match '-Milestones' -and $par -match 'parallel\.ps1 -Pass' -and $par -match 'parallel\.ps1 -Merge' -and $par -match 'parallel\.ps1 -Halt' -and $par -match '-Keep' -and $par -match 'parallel\.ps1 -Cleanup' -and $par -match 'parallel\.ps1 -Status') 'parallel.md commands'
Check 'parallel-outputs' ($par -match 'ROLE: wait' -and $par -match 'ROLE: merger' -and $par -match 'STATUS: HALTED' -and $par -match 'STATUS: CONFLICT' -and $par -match 'CONFLICT_FILE:' -and $par -match 'REDO:' -and $par -match 'KEPT_BRANCH:') 'parallel.md output keys'
Check 'parallel-rules' ($par -match '両方が挙げた組だけ' -and $par -match '最大 2 本' -and $par -match '同じ Checkpoint' -and $par -match 'MVP' -and $par -match 'RSLP_HOOK_CHILD' -and $par -match 'COUPLED:' -and $par -match '## PARALLEL' -and $par -match '作業ツリーの準備') 'parallel.md rules'
Check 'a-parallel' ($a -match 'references/parallel\.md' -and $a -match '## PARALLEL' -and $a -match '並行候補') 'workflow-a points to parallel.md'
Check 'b-parallel' ($b -match 'references/parallel\.md' -and $b -match 'parallel-base:' -and $b -match 'parallel-log\.md' -and $b -match '`m=` 列') 'workflow-b points to parallel.md'
Check 'policy-parallel' ($policyText -match '(?m)^## マイルストーンの並行\(MVP のみ\)' -and $policyText -match '見立て外れ' -and $policyText -match 'parallel-log\.md') 'policy.md parallel section'
$rt = Get-Text (Join-Path $tpl 'retrospective-note.md')
Check 'tpl-retro-parallel' ($rt -match '(?m)^- 並行' -and $rt -match '直列換算' -and $rt -match '見立て外れ') 'retro template parallel line'
Check 'readme-parallel' ($readme -match 'parallel\.ps1' -and $readme -match 'マイルストーンの並行') 'README parallel'
```

- [ ] **Step 2: 失敗を確かめる**

Run: `tests/skill-layout.tests.ps1` → 足した 10 検査が `FAIL`

- [ ] **Step 3: `references/parallel.md` を作る(この文面のまま)**

````markdown
# マイルストーンの並行セッション

SKILL.md の起動時チェック 9 から読まれる(state.md の phase が `parallel`、または `parallel-base:` 欄があるとき)。workflow-a の A-4・A-8、workflow-b の B-1・B-4・B-6・Learning 3 からも参照される。**MVP 強度だけ**で使う。

1 つのゴールの中で、互いに干渉しない 2 つのマイルストーンを、別々の作業ツリー・別々のメインセッションで同時に進める。並行は**同じ Checkpoint の中だけ、最大 2 本**。人間の受け入れ(B-8)は従来どおり Checkpoint ごとに 1 回。操作はすべて `<skill-dir>\bin\parallel.ps1` で行う(git の worktree・branch・merge を自分で組み立てない)。`STATUS: OK` 以外は成功として扱わない。

## 1. 分割の判定(A-4 の終わり)

同じ Checkpoint に 2 つ以上のマイルストーンがあるときだけ行う。

- **技術PM**: 実装アセスの依頼文に足す: 「同じ Checkpoint の中で、触るファイルとインターフェースが重ならないマイルストーンの組を `## PARALLEL` 節に出せ。組ごとに、根拠(触るファイルの一覧が重ならないこと)と、新しい作業ツリーで最初に要る準備(依存の導入コマンド・コピーが要る未追跡ファイル)を書け。無ければ `PARALLEL: none`」
- **代理Fable**: 「同じ Checkpoint の中で、要件と受け入れ条件が互いに独立なマイルストーンの組を挙げよ。片方の結果がもう片方の受け入れ条件を変える組は挙げるな。無ければ『なし』」と聞く(`loop-log.ps1 -Who fable`)。
- **両方が挙げた組だけ**を候補にし、goal-plan.md の `## 並行候補` に表で書く: 組 / Fable の根拠 / 技術PM の根拠 / 作業ツリーの準備 / 了承。1 つの Checkpoint に候補が複数あっても、同時に走らせるのは 1 組。
- A-8 の提示に並行候補を含め、利用者の了承を得る(表の「了承」に日付を書く)。了承のない組は並行しない。

## 2. 準備(了承済みの組の先頭に着いたとき)

着く場所は 3 つ: A-8 の承認直後(最初のマイルストーンが組)、B-6 の中間クローズ後(次が組)、Learning 3(次が組)。そこでの `-SetMilestone … -Mark` の代わりに行う。

1. `loop-log.ps1 -SetCheckpoint "<この組の Checkpoint>" -Clear 待ち` で state.md を整え、`docs/r-super-loop-powers/` の未コミット分をコミットする(子の作業ツリーはコミット済みの内容から作られる)。
2. 準備する:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\parallel.ps1" -Prepare `
     -GoalDir "<goal-dir>" -Milestones "<a>,<b>"
   ```
   `WORKTREE:` が 2 行出る。`REFUSED` は `REASON:` / `NEXT:` に従う(未コミットの変更がある・ブランチに居ない・高信頼・設計書の行が無い、など)。
3. 利用者に頼んでターンを終える: 「次の 2 つのフォルダで、それぞれ新しいセッションを開いて『続けて』と送ってください: <WORKTREE 1> / <WORKTREE 2>。このフォルダのセッションは閉じて構いません」。セッションを自動で開く手段は無い。`RSLP_HOOK_CHILD=1` を設定したシェルからは開かない(フックが止まる)。

このフォルダ(ベース)の state.md は phase `parallel` になる。ここで起動されたら作業せず、`parallel.ps1 -Status -GoalDir "<goal-dir>"` の結果(どのフォルダが何をしているか)を利用者に伝える。

## 3. 子のセッション(state.md に `parallel-base:` がある)

- 最初に goal-plan.md「並行候補」の「作業ツリーの準備」を実行する。
- B-1〜B-6 は workflow-b のとおり。`<goal-dir>` と `-WorkDir` は**自分の作業ツリー**のパス。設計書(design.md)は書かない。
- B-1 の依頼文に兄弟のマイルストーン定義も添え、「兄弟の結果がこのマイルストーンの前提を変える、またはその逆なら `COUPLED: <理由>` と書け」を足す。`COUPLED:` が返ったら 5 へ。
- 実装役・codex のラベルは `m<n>-…` にする(スカウトは自動で `m<n>-scout-<k>` になる)。call-log と hook-log にはスクリプトがマイルストーン番号を付ける。
- **B-6 PASS のあと**(中間コミット・`-SetMilestone`・B-7 は行わない): gate-decision.md を保存する。非 Checkpoint のマイルストーンなら中間クローズのグラレコ(grareco-input.md・生成・送り先)まで行う。続けて:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\parallel.ps1" -Pass -GoalDir "<goal-dir>"
  ```
  実装と記録が自分のブランチにコミットされ(state.md と再開の印は入らない)、その SHA が台帳に載る。
  - `ROLE: wait` → 兄弟がまだ。`loop-log.ps1 -SetWait "兄弟 <名前> の完了待ち(合流は相手のセッションが行う)"` を書き、利用者に「このマイルストーンは PASS。もう片方が終わると、そちらのセッションが合流する。このセッションは閉じてよい」と伝えて終わる。
  - `ROLE: merger` → 4 へ。
  - `STATUS: HALTED` → 5 の「止められた側」。
  - `STATUS: FAILED` → コミットできていない。`REASON:` を利用者に示して待つ(境界(a))。

## 4. 合流(合流担当の子)

1. `parallel.ps1 -Merge -GoalDir "<goal-dir>"`。ベースの作業ツリーで、ベースのゴール記録をコミットしてから、PASS 時の SHA を番号順にマージする。
   - `STATUS: REFUSED`(ベースに未コミットの変更がある・別のブランチに居る、など)→ `REASON:` を利用者に伝えて待つ(境界(a))。
   - `STATUS: CONFLICT` → マージは取り消されている。`CONFLICT_FILE:` が全部 `docs/r-super-loop-powers/` の下なら、`git -C "<ベース>" merge <SHA>` をやり直し、両方の内容を残して解消・コミットしてから `-Merge` を再実行する。実装ファイルが含まれるなら見立て外れ: `parallel.ps1 -Halt -GoalDir "<goal-dir>" -Keep <マージ済みの番号> -Reason "merge conflict: <ファイル>"` のあと `-Merge` を再実行する(`REDO:` に出たマイルストーンは直列でやり直す)。1 本目から衝突したら、利用者に報告して待つ。
2. 全体の検証: 合流した各マイルストーンの submission.md の「検証」のコマンドを**ベースの作業ツリー**で実行する(失敗行だけ見る)。失敗したら見立て外れとして、番号の大きい方を直列でやり直す(3 の milestone をそれにする)。
3. ベースの state.md を戻して印を置く(`<ベースの goal-dir>` は `parallel-base:` の下の同じ相対パス):
   - 組に Checkpoint が含まれ、やり直しが無い:
     `loop-log.ps1 -GoalDir "<ベースの goal-dir>" -SetPhase human-acceptance -SetMilestone "<Checkpoint>" -SetGate human-acceptance -SetWait "並行の後片付け(parallel.ps1 -Cleanup)をしてから B-7" -Mark`
   - それ以外:
     `loop-log.ps1 -GoalDir "<ベースの goal-dir>" -SetPhase milestone-implementation -SetMilestone "<次、またはやり直すマイルストーン>" -SetGate impl-gate -SetWait "並行の後片付け(parallel.ps1 -Cleanup)をしてから B-1" -Mark`
4. 利用者に頼んで終わる: 「合流が済んだ。ベースのフォルダ <パス> で新しいセッションを開いて『続けて』と送ってください。並行の 2 つのセッションは閉じてください」。

## 5. 見立てが外れたとき

子の B-1 の `COUPLED:`、B-4 の判断、B-6 の REVISE / REPLAN が、兄弟のマイルストーン定義(goal-plan.md の該当部・tech-assessment.md の兄弟の節)を変える必要を生んだら、並行をやめて直列に戻す。

- **気づいた側**: `parallel.ps1 -Halt -GoalDir "<goal-dir>" -Reason "<理由>"`。利用者に「もう片方のセッションに『並行を中止』と伝えてください」と頼む。自分のマイルストーンはそのまま続け、B-6 PASS で `-Pass`(`ROLE: merger` になる)→ 4。合流されるのは自分だけで、兄弟は `REDO:` になる。
- **止められた側**(`-Status` の `HALTED: yes`、または `-Pass` の `STATUS: HALTED`): 作業を止め、`loop-log.ps1 -SetWait "並行を中止(直列でやり直す)"` を書いて終わる。作業ツリーとブランチは参考として残る。
- **やり直し**: ベースで B-1 から。委譲文の TECHNICAL ASSESSMENT の後に「途中までの変更がブランチ `rslp/<goal-slug>/m<n>` にある。使えるものは取り込め」と書いてよい。
- retro の「無駄だった呼び出し・手戻り」に「疎結合の見立て外れ」として残す。

## 6. 後片付け(合流後、ベースのセッションの最初)

再開パケットの「待ち」に後片付けとあれば、`parallel.ps1 -Cleanup -GoalDir "<goal-dir>"` を実行し、`loop-log.ps1 -Clear 待ち` してから続ける。子の作業ツリー・マージ済みのブランチ・台帳が消える。`WARN:` は、子のセッションが開いたまま等で消せなかったもの(続行は止めない。利用者に閉じてもらって再実行する)。`KEPT_WORKTREE:` / `KEPT_BRANCH:` は、やり直し用に残したもの。区間の記録は `<goal-dir>/parallel-log.md` に残り、retro の観測に使う。
````

- [ ] **Step 4: workflow-a.md に足す**

- 技術PM 共通契約の「実装アセス」の項の末尾(`REVISE / REPLAN で plan が変わった場合…` の前)に 1 文: `同じ Checkpoint に 2 つ以上のマイルストーンがあれば、`references/parallel.md` 1 の `## PARALLEL` 節も出させる。`
- A-2〜A-4 の最後の段落(`完了後、spec/planへの相対リンクと…`)の末尾に 1 文: `同じ Checkpoint に 2 つ以上のマイルストーンがあれば、並行の候補を判定して `## 並行候補` に書く(`references/parallel.md` 1)。`
- A-8 の MVP の項: 提示の列挙に `・並行候補(あれば)` を足す。
- A-8 の最後の段落の末尾に 1 文: `最初のマイルストーンが了承済みの並行の組なら、この `-Mark` の代わりに `references/parallel.md` 2 の準備を行う。`

- [ ] **Step 5: workflow-b.md に足す**

- B-1 の末尾: `並行の子(state.md に `parallel-base:` がある)は、`references/parallel.md` 3 の一文を依頼文に足す。`
- B-4 の末尾: `並行の子で、判断が兄弟のマイルストーン定義を変えるなら `references/parallel.md` 5。`
- B-6 の箇条書きの先頭に 1 項: `- PASS + **並行の子**(state.md に `parallel-base:` がある)→ 中間コミットも B-7 も行わず、`references/parallel.md` 3 の `-Pass` へ`
- B-6 の「PASS + MVPの非Checkpoint」の項の末尾: `次が了承済みの並行の組なら、`-SetMilestone` の代わりに `references/parallel.md` 2。`
- B-6 の「REVISE / REPLAN」の項の括弧に足す: `並行の子で、兄弟の定義に触れる戻りなら `references/parallel.md` 5`
- Learning 1 の観測の列挙(`**境界リセットの回数**(`RESUME` 行の数)` の後)に足す: `・**並行**(並行した区間があるときだけ): 壁時計と直列換算(`parallel-log.md`)、見立て外れの件数(中止・合流の衝突・合流後の検証失敗)、子ごとの最大文脈(hook-log.md の `CTX` 行を `m=` 列で分ける)と B-6 差し戻し回数`
- Learning 3 の `未実装マイルストーンがあれば…` の文の後に 1 文: `次が了承済みの並行の組なら、この呼び出しの代わりに `references/parallel.md` 2(`-SetPhase parallel` も設計書の行が無いと拒否される)。`

- [ ] **Step 6: policy.md に足す**

`## Checkpointとマイルストーン粒度` の節の後に:

```markdown
## マイルストーンの並行(MVP のみ)

- 1 つのゴールの中で、互いに干渉しない 2 つのマイルストーンを、別々のメインセッションで同時に進めてよい。狙いは精度(1 セッション = 1 マイルストーン)と人間の認知負荷への適合で、コストは理由にしない。
- 条件: 同じ Checkpoint の中・最大 2 本・代理Fable(要件と受け入れ条件の独立)と技術PM(触るファイルとインターフェースの非重複)の**両方**が挙げた組・利用者の了承。
- 親セッションは残さない。最後に B-6 PASS した子が合流を担当する。人間の受け入れは Checkpoint ごとに 1 回のまま。
- 片方の差し戻しがもう片方の前提を変えたら、並行をやめて直列に戻し、retro に「疎結合の見立て外れ」として残す。
- 手順は `references/parallel.md`、操作は `bin/parallel.ps1`。
```

`## 観測` の末尾に 1 行: `- 並行した区間は、壁時計と直列換算(parallel-log.md)・見立て外れの件数・子ごとの最大文脈と B-6 差し戻し回数を retro に書く。`

- [ ] **Step 7: retro テンプレートに足して同期する**

`templates/retrospective-note.md` の `- 主要フェーズ所要時間:` の行の後:

```markdown
- 並行(並行した区間があるときだけ): 壁時計 <分> / 直列換算 <分>(parallel-log.md)。見立て外れ <中止・合流の衝突・合流後の検証失敗の件数> / 並行した組 <n>。子ごとの最大文脈 m<a>: <tokens> / m<b>: <tokens>。子ごとの B-6 差し戻し m<a>: <回> / m<b>: <回>。利用者の所感(あれば)
```

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-templates.ps1 -Mode Copy`

- [ ] **Step 8: README.md に足す**

- 「使い方」の箇条書きに 1 項: `- **マイルストーンの並行(v0.13)**: 同じ Checkpoint の中で互いに干渉しない 2 つのマイルストーンは、別々の作業ツリー・別々のセッションで同時に進められる(MVP のみ。代理Fable と技術PM の両方が挙げ、利用者が了承した組だけ)。準備が済むと 2 つのフォルダが示されるので、それぞれでセッションを開いて「続けて」と送る。最後に PASS した側が合流し、続きは元のフォルダで行う。`
- 「リポジトリ構成」の `skills/r-super-loop-powers/` の行に `bin/parallel.ps1`(並行の準備・合流)と `references/parallel.md` を足す。
- 「E2Eテスト」に 4 項:
  - `- [ ] A-8 の提示に並行候補が出て、了承した組だけが準備される(2 つのフォルダが示される)`
  - `- [ ] 子のセッションが「続けて」で自分のマイルストーンから再開し、hook-log.md の行末に `m=<n>` が付く`
  - `- [ ] 先に PASS した子は待ちで終わり、後に PASS した子が合流して、ベースのフォルダでの再開を頼む`
  - `- [ ] ベースで再開すると後片付けが走り、retro の観測に並行の行(壁時計・直列換算・見立て外れ)が入る`

- [ ] **Step 9: 通ることを確かめてコミット**

Run: 全テスト → すべて `ALL PASS`(`templates-in-sync` を含む)

```bash
git add skills/r-super-loop-powers/references skills/r-super-loop-powers/policy.md skills/r-super-loop-powers/templates skills-codex/r-super-loop-powers/templates README.md tests/skill-layout.tests.ps1
git commit -m "docs: parallel milestone sessions (parallel.md, workflow hooks, policy, retro observations)"
```

---

### Task 7: SKILL.md(サイズ内)と版

**Files:**
- Modify: `skills/r-super-loop-powers/SKILL.md`(起動時チェック 9、ディレクトリ契約、state.md フォーマット、境界リセット)
- Modify: `.claude-plugin/plugin.json`(`0.13.0`)、`.codex-plugin/plugin.json`(`0.1.4`)
- Test: `tests/skill-layout.tests.ps1`

- [ ] **Step 1: 失敗するテストを書く**

`tests/skill-layout.tests.ps1`: `version-0.12.0` を `version-0.13.0`(`$ver -eq '0.13.0'`)に、`codex-version-0.1.3` を `codex-version-0.1.4`(`$cver -eq '0.1.4'`)に変え、Task 6 で足した検査の後に:

```powershell
Check 'skill-parallel' ($s -match 'references/parallel\.md' -and $s -match 'parallel-base:' -and $s -match 'parallel-log\.md' -and $s -match 'learning \| parallel \| done') 'SKILL.md parallel pointers'
```

Run: `tests/skill-layout.tests.ps1` → `version-0.13.0`・`codex-version-0.1.4`・`skill-parallel` が `FAIL`

- [ ] **Step 2: SKILL.md から 3 文を削る(境界リセットの節。計 338 バイト)**

1. 冒頭の段落の最後の文: `` フックは `/` コマンドを起こせないので、`/clear` は人間が打つ。 ``
2. 箇条書きの 1 行まるごと: `` - パケットは 9,500 文字に収まるよう後方の節だけが切られる(制約系は切らない)。全文は `<goal-dir>/resume-packet.md` ``
3. その前の行の後半: `` 。印は `/clear` か新規起動でだけ使われ、`/compact` や `--resume` では使われない ``(行は `- 印は 24 時間で無効になる(その場合は従来どおり state.md から再開する)` で終わる)

- [ ] **Step 3: SKILL.md に 4 か所足す(計 299 バイト)**

1. 起動時チェック 9 の末尾: `` state.md の phase が `parallel` か、`parallel-base:` 欄があれば `references/parallel.md` も読む。 ``
2. state.md フォーマットの phase の行: `… | learning | parallel | done`
3. 同じフォーマットの `- codex-run:` の行の後: `` - parallel-base: <ベースの作業ツリー>   # 並行の子だけ(references/parallel.md) ``
4. ディレクトリ契約の `hook-log.md` の行の後: `` ├── parallel-log.md          # 並行区間の記録(parallel.ps1 が書く) ``

- [ ] **Step 4: サイズを確かめる**

Run: `tr -d '\r' < skills/r-super-loop-powers/SKILL.md | wc -c`
Expected: 24,576 以下(見込み 24,529)。超えていたら「プラグインのフック」の節の最後の文 `` 結果は `hook-log.md` に残り、判定役が動かないときは検査なしで通る。 `` を削る。

- [ ] **Step 5: 版を上げる**

`.claude-plugin/plugin.json` の `version` を `0.13.0`、`.codex-plugin/plugin.json` の `version` を `0.1.4` にする。

- [ ] **Step 6: 通ることを確かめてコミット**

Run: 全テスト → 13 本すべて `ALL PASS`

```bash
git add skills/r-super-loop-powers/SKILL.md .claude-plugin/plugin.json .codex-plugin/plugin.json tests/skill-layout.tests.ps1
git commit -m "v0.13.0: parallel milestone sessions (SKILL.md pointers within the 24 KB limit)"
```

---

## 実装後(このプランの外)

1. 全体レビュー(Fable)→ 指摘の反映。
2. main へ merge・push、`claude plugin update`(版が上がっているのでキャッシュは更新される。入れた後、キャッシュの `bin/parallel.ps1` と `SKILL.md` を `cmp` で照合する)。
3. rb-xjw(RB-119)へ報告。
4. 実ゴールでの確認は別の機会(README の E2E の 4 項)。このプランのテストは一時リポジトリでの機械的な検査までで、2 つの実セッションを並べた通し確認は含まない。
