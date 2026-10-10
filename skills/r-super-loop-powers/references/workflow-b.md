# ワークフローB: Milestone Implementation(B-1〜B-10)と Learning

SKILL.md(共通)の起動時チェック 9 から読まれる。state.md の phase が `milestone-implementation` / `human-acceptance` / `finalization` / `learning` のときに使う。共通の規則(起動時チェック・ディレクトリ契約・記帳・ゲート保護・Fable 共通契約・境界リセット・読むもの)は SKILL.md にある。各工程の入口(B-1・B-5・B-7・Learning)で state.md を読み直す。

## 工程(マイルストーンごとに繰り返す)

**B-1 開始確認(Fable・軽量)**
state.md を読み直す。直近の retro.md 最大3件の要点を抜粋し、Agentツール(model: fable、新規インスタンス)に goal-frame.md + 対象マイルストーン定義(goal-plan.mdの該当部分) + retro抜粋(あれば)を渡し、「このマイルストーンが上位ゴールのどの成果を満たすか確認し、実装上の注意点があれば10行以内で示せ。実装方式は技術PMのアセスで決まっており、実装役(Sonnet 5.5)はそれを実行するだけである点を考慮せよ」と指示する。呼び出しは `loop-log.ps1 -Who fable -Purpose "B-1 <n>"` で記録する。

**B-2〜B-3 実装と自己検証(Sonnet 実装役)**
強度により委譲単位を変える(policy.md工程表):
- **MVP**: **マイルストーン単位でまとめて**1〜数回、実装役に委譲する。タスク細分化しない。
- **高信頼**: subagent-driven developmentと同じプロセス構造でタスク分解し、個別に委譲する。

実装役は Agentツールの `subagent_type: "r-super-loop-powers:builder"`(`claude-sonnet-5-5`。Skill / Agent ツールを持たないので、プロセス系スキルを起動できない)で起動する。実行契約(スコープ・コミット禁止・要件再定義禁止・否定リスト)・ロール指示・出力契約・ロール憲章(roles.md の全体図+実装役の節。`scripts/sync-roles.ps1` で同期)はエージェント定義に入っているので、プロンプトに書かなくてよい。

**(1) 委譲前の基準を記録する(1 回の呼び出し)**
ラベルは `m<n>-impl`(再委譲は `m<n>-impl-2` …。高信頼でタスクごとに委譲する場合は `m<n>-t<k>-impl`)。
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" -Prepare `
  -Label "<ラベル>" -GoalDir "<goal-dir>" -WorkDir "<対象プロジェクトのルート>"
```
`BASE_REF:`(HEAD)と `SNAPSHOT:`(未コミット変更の指紋)が `impl-runs/<ラベル>.base.txt` / `.pre.txt` に書かれる。B-3 はこのスナップショットと比べて**今回の委譲で変わったものだけ**を判定に使うので、未コミット変更があっても判定は混ざらない。同じマイルストーンの未コミット変更(以前の委譲・再委譲・高信頼の先行タスクの分)は**そのまま残して**委譲する。`DIRTY_PATHS:` が 0 でないとき、`docs/r-super-loop-powers/` 以外で**このマイルストーンと無関係な**未コミット変更(このマイルストーンの過去の `impl-runs/*.report.md` の `changed_files` に無いもの)がある場合だけ、委譲前にそれをユーザーに提示し、扱い(コミット / そのまま残す等)の指示を受けてから委譲する。`STATUS: REFUSED` はラベルの再利用(同じラベルの `.report.md` がある)なので、新しいラベルにする。

**(2) プロンプトを書く**
`<goal-dir>/impl-runs/<ラベル>.prompt.md` に保存する。実装役は**実行者**であり、設計・計画は済んでいる。プロンプトは「何を・どの方針で・何をもって完了とするか」を**決め切った状態**で渡す。必須要素は次の6つで、この見出しの順に書く:
  1. `## TECHNICAL ASSESSMENT` — **MVP**: `tech-assessment.md` の該当 `## M<n>` 節を**原文のまま**貼る(要約・言い換えしない) / **高信頼**: 人間が承認した plan の該当タスク本文。エージェント定義がこの見出しを参照するので名前を変えない
  2. `## ACCEPTANCE CRITERIA` — 受け入れ条件(実装役が `acceptance_criteria` へ原文のまま写すので、検証可能な文で書く)
  3. `## SCOPE` — 対象ファイル・変更範囲(触ってよい範囲と、触らない範囲)
  4. `## VERIFICATION` — **MVP**: 受け入れ基準に直結する検証+未知低減に効く検証のみ / **高信頼**: テストファースト+単体・結合・lint・型検査。実行すべきコマンドを具体的に書く
  5. `## OPEN ASSUMPTIONS` — 関連する未検証仮定(assumptions.mdから)
  6. `## OUTPUT` — 「最終メッセージは impl-report 形式の JSON を ```json フェンス1つで返すこと」

plan から転記するときは、`REQUIRED SUB-SKILL` / `superpowers:` / チェックボックス付きの手順指示など**エージェント向けの進め方の指示行を含めない**。コードや手順の中身だけを写す。

**(2′) 再委譲のプロンプト**
`impl-check.ps1` が `OK` 以外を返して再委譲するときは、全文を書き直さない。`<goal-dir>/impl-runs/<ラベル>-2.prompt.md`(以後 `-3` …)に次の 2 節だけを書く:
  1. `## 再委譲の差分` — impl-check の `STATUS` / `REASON` / `CRITERION_UNMET` / `WARN` の行をそのまま引用し、今回直すべき点を箇条書きにする(受け入れ条件・スコープは変えない)
  2. `## 初回の依頼` — `初回の依頼文: <goal-dir>/impl-runs/<初回ラベル>.prompt.md(先に全部読むこと。TECHNICAL ASSESSMENT・受け入れ条件・SCOPE・検証・仮定・出力契約はそこにある)`

**(3) 起動し、報告を保存して判定する**
Agentツール: `subagent_type: "r-super-loop-powers:builder"`、description `B-2 <ラベル>`。prompt には**ファイルのパスだけ**を渡す(本文を Agent の引数に二度書かない。実装役は `impl-runs/*.prompt.md` と `tech-assessment.md` を読める):
```
依頼文は <goal-dir>/impl-runs/<ラベル>.prompt.md にある。まずそのファイルを全部読み、そこに書かれた TECHNICAL ASSESSMENT・受け入れ条件・SCOPE・検証に従って作業せよ。最終メッセージは impl-report 形式の JSON を ```json フェンス 1 つで返すこと。
```
返ってきた最終メッセージを**そのまま** stdin で渡して保存し、同じ呼び出しで判定する(B-3。転記の Write と判定を 1 ターンにまとめる。整形・補完しない):
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" -SaveReport -Label "<ラベル>" -GoalDir "<goal-dir>" -WorkDir "<対象プロジェクトのルート>" <<'EOF'
<実装役の最終メッセージをそのまま貼る>
EOF
```
(PowerShell ツールから呼ぶ場合は `@'…'@ | powershell … -SaveReport …`。)`SAVED:` に `impl-runs/<ラベル>.report.md` が出る。同じシェル呼び出しの末尾で `loop-log.ps1 -Who sonnet-builder -Purpose "B-2 <ラベル>"` を続けて実行する(記帳を別ターンにしない)。

**B-3 受け入れ判定は `impl-check.ps1` の `STATUS` で行う**
判定は (3) の `-SaveReport` の出力に含まれている。保存済みの報告を判定し直すときは:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\impl-check.ps1" `
  -ReportFile "<goal-dir>\impl-runs\<ラベル>.report.md" `
  -WorkDir "<対象プロジェクトのルート>" `
  -BaseRef (Get-Content "<goal-dir>\impl-runs\<ラベル>.base.txt") `
  -PreexistingFile "<goal-dir>\impl-runs\<ラベル>.pre.txt"
```
報告JSONと git の実状態(HEAD の移動・`docs/r-super-loop-powers/` 以外で**今回の委譲による**実際の変更)を突き合わせる。委譲前から未コミットで今回変わっていないパスは `PREEXISTING_UNCHANGED:` に出るだけで、判定には使われない。出力は KV 形式で短い。実装役が実行したテストの生ログは読まない(報告の `verification` の要点で足りる。自分でテストを再実行するときは失敗行だけを見る: `… | Select-String -Pattern 'FAIL|ALL PASS'`)。

| STATUS | 扱い |
|---|---|
| `OK` | 合格。**MVP**: 報告(`.report.md`)を確認する(diff精読はしない)。**高信頼**: B-5 の技術レビューへ |
| `MALFORMED` | 報告が読めない。同じプロンプトで1回だけ再委譲し、再度なら B-4。ただし `REASON` が `BaseRef` / `PreexistingFile` / `base ref` に触れている場合は報告ではなく記録側の誤りなので、再委譲せず `-Prepare` をやり直す(か `.base.txt` / `.pre.txt` を直す)。報告は保存済みなので、`-ReportFile` 形式で B-3 をやり直せる |
| `BLOCKED` / `INCOMPLETE` | **不合格。実装済みとして扱わない。** 不足点(`REASON` / `CRITERION_UNMET`)を引用して再委譲する((2′))。`BLOCKED` の原因が否定リストやユーザー固有判断ならB-4へ |
| `CONTRACT_VIOLATION` | 実装役がコミットした。`git log` / `git status` を確認してから判断する |

`STATUS: OK` 以外で B-5 へ進まない。`NEW_ASSUMPTION:` は assumptions.md に、`UNRESOLVED:` は残存未知として submission に転記する。`WARN: unreported change:` が出たら、その変更がスコープ内かを確認し、submission の「残存未知」に含めるか対処する。`WARN: reported but unchanged:` は報告と実態のずれなので、報告の該当箇所を割り引いて読み、submission の「残存未知」に記載する。

- 実装・設計上の主要判断は随時 `milestones/<n>-<名前>/decisions.md`(`templates/decisions.md` の形式)に追記する(要件由来とAgent仮説を区別する)。

**B-4 エスカレーション(必要時のみ)**
policy.md の発火条件(否定リスト該当・ユーザー固有判断・Solution分岐・低確信を含む10件)を検出したら、`templates/escalation.md` の1〜6を整形し、Agentツール(model: fable、新規インスタンス)に goal-frame.md + 1〜6 + 関連する未検証仮定(assumptions.mdの該当行、あれば) + hearing-log.md の関連部分(あれば)を渡す。Fableは7(判定)に **DECIDE**(判断+根拠)または **ASK_HUMAN**(人間向け質問文)を記入する。ASK_HUMANの場合はOpusが人間へ提示し(境界(a): `loop-log.ps1 -SetWait "…" -Mark` の後にターンを終える)、回答を hearing-log.md に追記してから続行する。文書を milestone ディレクトリに `escalation-<連番>.md` として保存し、`loop-log.ps1 -Who fable` で記録する。

**B-5 レビューとSubmission作成(Opus)**
state.md を読み直す。
- **MVP**: Opusメインが**セルフチェック**(goal-frame承認基準との対応・残存未知の列挙・未検証仮定の確認)を行い、`decisions.md` の4区分(要件由来 / Agent仮説HOW / 低確信 / 発見された未知)を確定させ、`templates/approval-submission.md` に従い `milestones/<n>-<名前>/submission.md` を作成する(判断記録欄から decisions.md を参照)。
- **高信頼**: **技術レビュー**を codex `gpt-6.1-sol`(`-Role reviewer`、read-only・effort max)で、**マイルストーンごとに1回**、その全タスクが `STATUS: OK` になった後に行う(PL-003)。ラベルは `m<n>-review`(CONCERNS 後の再レビューは `m<n>-review-2` …)。プロンプト(`<goal-dir>/codex-runs/<ラベル>.prompt.md`)には、goal-plan.md 該当部・マイルストーン定義・各タスクの plan 本文・受け入れ条件・委譲前の HEAD(このマイルストーン最初の委譲の `impl-runs/<ラベル>.base.txt` の値)・各委譲の `impl-check.ps1` の出力(`CHANGED_FILES_ACTUAL:` 行を含む)・実装役の報告を入れ、「`git diff <base>` と `git status --porcelain --untracked-files=all` で実際の変更を見よ。未追跡(新規)ファイルは `git diff` に出ないので直接読め」と書く。起動・完了判定は `references/codex-invocation.md`(`codex-run.ps1 -Role reviewer` → `codex-status.ps1`、`STATUS: OK` の `FINAL_MESSAGE_FILE` だけを採用)。最終行が `TECH_REVIEW: CONCERNS` なら、HIGH の指摘を引用して実装役へ再委譲し(B-2 に戻る)、解消してから submission を作る。MEDIUM / LOW は submission に記載する。**要件に合っているかはここでは見ない** — それは B-6 のゲートFableが判定する。`loop-log.ps1 -Who codex-review` で記録する。
- どちらの場合も**残存未知リスト・仮定台帳サマリ・decisions.mdの確定**を必須とする(欠けたままB-6へ進まない)。

**B-6 Implementation Gate(ゲートFable・新規インスタンス)**
前提確認: submission.md が存在し、検証証拠と残存未知リストが含まれること。
共通契約に従い goal-frame.md + マイルストーン定義 + submission.md + assumptions.md の未検証仮定を渡し、判定観点で「このマイルストーンのゴールを満たし、残存未知が許容可能か」を判定させる。結果を `gate-decision.md` に保存し、`loop-log.ps1 -Who fable` で記録する。
- PASS + **MVPの非Checkpointマイルストーン** → **中間クローズ**: grareco-input.md作成(gate-decision.md / decisions.md の要点)+グラレコ生成(失敗は非ブロック)→ 中間コミット → `loop-log.ps1 -SetMilestone "<次>" -SetGate impl-gate`。文脈メーターの通知「境界リセットの目安を超えている」が出ていれば `-Mark` も付けて**境界リセット**(境界(b))し、人間に `/clear` と「続けて」を頼んでターンを終える。出ていなければ**人間承認なしで次のB-1へ**
- PASS + Checkpointマイルストーン(MVP)または高信頼 → `loop-log.ps1 -SetPhase human-acceptance -SetGate human-acceptance` の後、B-7へ
- REVISE / REPLAN → 指定された工程へ差し戻す(対象の未知・仮定が指定される。人間へは出さない)
- BLOCKED → 人間へ質問して停止(境界(a))

**B-7 Human Review Report=評価パッケージ(Opus)**
state.md を読み直す。`templates/human-review-report.md` に従い `human-report.md` を作成する。
- **MVP**: 対象は**前回Checkpoint以降の全マイルストーン**。各マイルストーンの decisions.md を「3.5 判断の内訳」に集約する(Agent仮説HOW・低確信・実装対象外・新しく発見された未知を含む)。
- **高信頼**: 従来通り対象マイルストーン単体。
受け入れテスト手順は人間が1回のテストで確認できる具体性で書く。受け入れテストの証拠にスクショや画像を含める場合、Opus は画像を Read せず、パスを human-report.md に書く(人間に見せるなら SendUserFile)。

**B-8 Human Acceptance(人間)**
human-report.md を人間に提示し、受け入れテストを依頼する(MVPはCheckpoint単位)。提示してターンを終える前に**境界(a)**: `loop-log.ps1 -SetWait "Checkpoint <n> の受け入れテスト結果(ACCEPT / REJECT とコメント)" -Mark` を行い、依頼文の末尾に `/clear` と「続けて」を添える。結果を `acceptance.md` に記録する(ACCEPT / REJECT + コメント)。**フィードバックから新たに発見された未知・要望は assumptions.md に追記する**(次ループの入力)。ACCEPT の場合は `loop-log.ps1 -SetPhase finalization -Clear 待ち` にする。

**B-9 REJECT処理(Fable)**
REJECTの場合、Agentツール(model: fable、新規インスタンス)に goal-frame.md + human-report.md + REJECT理由を渡し、戻り先(タスク修正 / **Checkpoint配下の任意マイルストーン** / マイルストーン再計画 / ゴール再確認)を決定させる。REJECT理由から発見された未知は assumptions.md に追記する。決定に従い該当フェーズへ戻り、戻り先に応じて state.md を更新する(`loop-log.ps1 -SetPhase … -SetMilestone …`)。`loop-log.ps1 -Who fable` で記録する。

**B-10 確定処理(Opus)**
acceptance.md に ACCEPT があることを確認してから、Checkpoint範囲(前回Checkpoint以降の中間コミットを含む)を確定として扱い、未コミット分を確定コミットする。`loop-log.ps1 -SetPhase learning` にする。

## Learning フェーズ

state.md を読み直してから始める。

1. **Retrospective(Opus)**: `templates/retrospective-note.md` に従い `retro.md` を作成する(**MVP: Checkpoint単位** — 対象は前回Checkpoint以降の全マイルストーン / **高信頼**: マイルストーン単位)。観測欄に、ループ回数(REVISE/REPLAN差し戻し数)・呼び出し数(call-log.mdから)・主要フェーズ所要時間(call-logの時刻から概算)・**発見された未知**・人間向け応答の書き直し回数(hook-log.md の BLOCK 行の数と、主な理由)・**最大文脈**(hook-log.md の `CTX` 行の tokens の最大値)・**境界リセットの回数**(`RESUME` 行の数)を記載する(5:1目安はワークフローB以降、ハード制限ではない)。「再利用できる知見・テンプレート候補」に「なし」以外を書いた場合、**このプロジェクトの外でも効くもの**は orca-meta の MCP tool `record_lesson` で送る(軸は person / agent / method。orca-meta プラグインが導入されていない環境では省略してよい)。
2. **グラレコ(Codex経由・読み取り専用)**: human-report.md / gate-decision.md / retro.md の要点を `grareco-input.md` にまとめ、`templates/grareco-prompt.md` の指示文を埋めて codex に渡す(MVPの非Checkpoint分はB-6中間クローズで生成済みのため、ここではCheckpointマイルストーン分を生成する)。`codex-run.ps1 -Role grareco`(effort `low` が既定)→ `codex-status.ps1` で待つ。codex は read-only なので画像を自分では保存しない。grareco の成否は**画像ファイルがあるかどうか**で決まる(codex の「生成しました」という最終メッセージは根拠にしない)。`codex-status.ps1` が `generated_images\<THREAD_ID>\*.png` を探し、
   - `STATUS: OK` なら `IMAGE:` 行に画像のパスが出る。Opus がそれをコピーする: `Copy-Item -LiteralPath "<IMAGE: の値>" -Destination "<milestone-dir>\grareco.png"`
   - `STATUS: NO_IMAGE` は、実行は終わったが画像が無い状態。call-log に「画像なし」と記録して先へ進む
   v0.9 からは imagegen の SKILL.md を読まずに image_gen を直接呼ばせる(ツールが拒んだときだけ読む)。読んだ場合は `BOUNDARY_HIT` の `WARN:` が出るが想定内。生成・回収のどちらで失敗しても grareco-input.md を残したまま先へ進む(ループ完了をブロックしない) — ここは `STATUS: OK` 以外でも停止しない唯一の例外である。`loop-log.ps1 -Who codex-grareco` で記録する。生成した画像を Opus が Read しない(人間に見せるならパスを示す)。
3. **次へ**: 未実装マイルストーンがあれば `loop-log.ps1 -SetPhase milestone-implementation -SetMilestone "<次>" -SetCheckpoint "<次のCheckpoint>" -SetGate impl-gate -Mark` で戻し(境界(c))、人間に `/clear` と「続けて」を頼む。再開後に B-1 から繰り返す。全マイルストーン完了なら `loop-log.ps1 -SetPhase done -SetGate none -Clear milestone,次のCheckpoint,待ち` にし、ゴール全体の完了を人間に報告する。
