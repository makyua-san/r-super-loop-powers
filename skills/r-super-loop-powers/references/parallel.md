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
   `WORKTREE:` が 2 行出る。`REFUSED` は `REASON:` / `NEXT:` に従う(未コミットの変更がある・ブランチに居ない・高信頼・設計書の行が無い、など)。`FAILED` で `ROLLED_BACK: yes` が出たら、途中で失敗して元に戻してある(多くは設計書など `docs/r-super-loop-powers/` の未コミットが原因。コミットして再実行する)。
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
   - `STATUS: CONFLICT` → マージは取り消されている。`CONFLICT_FILE:` が全部 `docs/r-super-loop-powers/` の下なら、`git -C "<ベース>" merge <SHA>` をやり直し、両方の内容を残して解消・コミットしてから `-Merge` を再実行する。実装ファイルが含まれるなら見立て外れ: `parallel.ps1 -Halt -GoalDir "<goal-dir>" -Keep <マージ済みの番号> -Reason "merge conflict: <ファイル>"` のあと `-Merge` を再実行する(`REDO:` に出たマイルストーンは直列でやり直す)。残せるのはマージ済みの方だけで、`-Keep` に未マージの番号を渡すと拒否される(`NEXT:` に正しいコマンドが出る)。1 本目から衝突したら、利用者に報告して待つ。
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
