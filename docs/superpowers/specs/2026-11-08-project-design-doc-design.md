# プロジェクト設計書の必須化(RB-106)

作成日: 2026-11-08
対象: r-super-loop-powers Claude 版(`skills/r-super-loop-powers/`)
タスク: RB-106「プロジェクトごとの設計書をループで必須にする(Codex が作成・更新)」
想定版: v0.12.0(Codex 版プラグインは 0.1.3。テンプレートのコピーのみ)
前提: RB-99 の spec 6 章(`2026-11-06-fable-direct-hearing-design.md`)で別タスクにしたもの

以下で「利用者」は、このハーネスを使う人間を指す。各判断の出所を「利用者の決定」「作成者の判断」で区別する。作成者の判断は実装前に覆してよい。

## 1. 意図と背景

利用者が次の要求を出す前に、対象プロジェクトの現状(何ができていて、何が足りず、なぜ止まっているか)を手元で読めるようにする。読み手は主に利用者で、「この要求は既存 X の拡張か」「前に試して足りなかった件か(頼み直しでは解決しない)」を判断するために使う。

### きっかけの場面(利用者の原文: 2026-11-05、agent-alert)

> エージェントの本体はどこにいますか? 以下の目的のために把握したいです。(略)あとは、エージェントの記憶や感覚とか

このとき Opus がその場でコードを読み、「部位 / 場所 / 今の状態」の表(人格は固定値、頭は状態なし、長期記憶は入口だけ、3D の部屋はブラウザにしか無い、など)を作って答えた。利用者は「よい整理と思います」と受け、それを元に 4 層に分けて 4 件起票した。この表が、聞く前から手元にあり、ゴールが終わるたびに更新され続ける状態を作る。

### 今うまくいっていないこと

- 現状の地図が無く、問われるたびにその場でコードを読む。ヒアリング前の照合(workflow-a A-0)もスカウトが毎回コードから探す。
- 「取り組んだが足りない」件が、ゴールごとの `retro.md`(発見された未知)・`acceptance.md`(新たな未知・要望、スキップ)・`assumptions.md`(未検証)に散らばる。次の要求では同じ件を頼み直しやすい。
- 到達度はゴール単位の `state.md` にしか無く、機能の軸では見えない。agent-alert では `avatar-motion-generation` が `phase: finalization` のまま 2 か月止まっている(2026-09-09 以降)。
- 被りが見えない。例: モーション目録の UI の要望(avatar-motion-generation の A26)は後のゴール motion-catalog-manager で実現したが、台帳の上では未着手のままである。

### 実運用の記録から分かったこと(agent-alert、12 ゴール)

- retro・acceptance・台帳に「次回」「未検証のままスキップ」「follow-up」「新たな要望」として残る項目が、ゴールあたり 3〜8 件、合計 60 件超ある。
- 既存の文書(`docs/overview.md` の構成要素と 2 台のトポロジ、`docs/architecture.md`、`server/DESIGN.md`)は開発者向けで、到達度や「足りない理由」は書いていない。設計書はこれらを置き換えず、指す。
- 並行ゴールが 2 本(worktree `agent-alert-memory` と `dev/agent-alert`)走ることがある。

## 2. ゴール・非ゴール・避けたいこと

### ゴール

1. 対象プロジェクトに 1 つの設計書があり、全体概要・主要な機能の流れ・機能の地図(到達度)・足りない理由を持つ。
2. Codex(読み取り専用)が本文を書き、Opus がそのまま保存する。ゴールの最初と、Checkpoint の振り返りのたびに更新する。
3. 更新せずにループを進められない。記帳スクリプトが遷移を拒否し、Stop フックが網を張る。
4. ヒアリング前の照合が設計書を読み、Fable が「既存 X の拡張で足りるか」「前に試して足りなかった件か」を問える。

### 非ゴール

- 既存のアーキテクチャ文書(overview / architecture / DESIGN.md)の置き換えや再編。
- Codex 版(`skills-codex/`)への工程の反映。テンプレートのコピーだけ行う(作成者の判断。RB-99 と同じ)。
- 過去ゴールの記録(retro・acceptance・台帳)の書き換え。設計書は読むだけで、元の記録は触らない。
- ゲート判定(A-6 / B-6)への設計書の投入。ゲートの入力は変えない。
- 設計書の内容を人間向け評価パッケージ(human-report)に転記すること。

### 避けたいこと

- 設計書が 2 つ目のアーキテクチャ文書になり、二重管理になる。細部は既存文書を指す。
- 毎ゴールの最初に長い待ちが増える。2 回目以降は差分更新にする。
- Codex の失敗でループが止まる。失敗時は Opus が最小限を代筆して記録に残す(スカウトと同じ扱い)。
- 設計書が長くなり、ヒアリング Fable の文脈を食う。章ごとの書き方を決め、Fable は照合が指した行だけ読む。
- Opus や Fable が設計書を手で書き足す習慣がつく。書くのは Codex。例外は代筆だけ。

## 3. 全体の流れ

```text
A-0  Opus: Goal Seed 保存
     → design-doc.ps1(設計書が無ければ作成、あれば差分更新。同期で待つ)
     → 照合スカウト(設計書の 1〜3 章を先に読ませる)
     → retro 抜粋・他の作業の一覧
     → loop-log -SetOwner hearing-fable(設計書に今回の A-0 の行が無ければ拒否)
     → 利用者に /model fable を案内
A-1a Fable: 照合結果と設計書の該当行を読み、「拡張で足りるか」「前に足りなかった件か」を問う
A-1b〜B-10: 変更なし
Learning: retro → design-doc.ps1(Checkpoint の更新)→ グラレコ
     → loop-log -SetPhase milestone-implementation | done(行が無ければ拒否)
```

利用者の決定: 設計書は Codex が作成・更新し、ループの最初と最後で必須にする。必ず通るように仕組み(フック)で担保する。
作成者の判断: 「最後」は Checkpoint ごとの Learning とする(ゴールの途中で止まっても、そこまでの到達度が残る)。「やらない / 後回し」で閉じたゴールは更新しない(hearing-log の結論が残り、次の A-0 で Codex が「要望はあるが未着手」に拾う)。

## 4. 設計

### 4.1 設計書の置き場所と形

- 置き場所: 対象プロジェクトの `docs/r-super-loop-powers/design.md`(ゴールディレクトリの外、プロジェクトに 1 つ)。作成者の判断。
- コミット: A-0 の更新分は、そのゴールの最初のコミット(B-6 の中間コミットか B-10 の確定コミット)に含まれる。Learning の更新分は、Learning の末尾(3「次へ」)で Opus が `docs/r-super-loop-powers/` の未コミット分(設計書・retro・grareco・ゴール記録)をコミットする工程を足して残す。「やらない」で閉じるときも同じコミットを行う。Opus のコミットは既存の中間・確定コミットと同じ扱いで、実装役・codex はコミットしない(ゲート保護ルール 5 は変えない)。作成者の判断(builder check で決めた)。
- 言語: 日本語。読み手は利用者。
- テンプレート: `templates/design-doc.md`(Codex 版へコピー)。章立ては固定で、次の順:

| 章 | 中身 | 書き方の決まり |
|---|---|---|
| 冒頭コメント | 読み手・書き手・到達度の語彙 | テンプレートのまま |
| 更新履歴 | `日時 / ゴール / 節目 / 見たコミット / 書き手` の表 | 行はスクリプトが足す(4.3)。Codex は書かない |
| このプロジェクトは何か | 3 行以内 | — |
| 0. 構成 | 0.1 全体概要: どの機械・プロセスで何が動き、何と話すか(1 画面)。0.2 主要な機能の流れ: 機能ごとに「入口 → 使うコンポーネントの順 → 出口」を 1 行 | 細部は既存文書を指す(「詳しい資料」に列挙)。繰り返さない |
| 1. 機能の地図(到達度) | 表: `機能 / 何をする / どこにある(拡張の入口) / つながり / 到達度` | 1 行 1 機能。到達度は `できている / 一部 / 取り組んだが足りない / 進行中 / 未着手` の 5 語。「一部」「取り組んだが足りない」は 2 章へ `→ 2 章` と書く |
| 2. 取り組んだが足りない | 機能ごとに `試したこと / 足りないこと / 止まっている理由 / 出典` の 4 項目 | 出典はゴール名とファイル(例 `long-term-memory/milestones/5-…/retro.md`、`assumptions.md H5`)。推測には「(推測)」を付ける |
| 3. 要望はあるが未着手 | 受け入れで「次回」になったもの、やらない・後回しで閉じた要求 | 1 行 1 件、出典付き |
| 4. 運用で見る懸念 | goal-frame の「運用で見る懸念」と、未検証のまま受け入れた項目 | 1 行 1 件、出典付き |

- 「主要な機能」の選び方は Codex に任せる(利用者が名指しする機能、ゴールの単位になった機能、1 章の行になる機能)。
- 大きさの目安: 全体で 40 KB を超えたら `design-doc.ps1` が `WARN:` を出す(止めない)。

### 4.2 設計書役(Codex の第 5 ロール)

- `codex-run.ps1 -Role surveyor`(日本語名: 設計書役)。既存 4 ロールと同じく **読み取り専用**、モデルは `gpt-6.1-sol`。
- effort の既定: 作成(設計書が無い)は `high`、更新は `medium`。`-Effort` で上書きできる。作成者の判断。
- ロール指示(`$RoleBriefs.surveyor`): 「あなたは記録係。対象プロジェクトのコードと既存文書、ゴールの記録を読み、テンプレートの章立てで設計書の全文を書く。設計・判定・提案はしない。推測は(推測)と書き、出典を付ける。更新のときは前回の設計書を土台にし、前回のコミット以降の変更と、今回のゴールの記録だけを読んで差分を反映する。最終メッセージが設計書の全文であり、唯一の出力」。
- `roles.md` に「設計書役 (surveyor)」の節を足し、全体図の表に「設計書(ゴールの最初と Checkpoint 後) | 設計書役 | Opus(保存。型は design-doc.ps1 が機械で確かめる)」の行を足す。`policy.md` 責任分担にも行を足す。
- Web 検索は使わない(scout 以外のロールと同じく既定のまま。`-Web` は渡さない)。

### 4.3 ラッパー `bin/design-doc.ps1`

`scout.ps1` と同じ形の 1 回呼びのまとめ役。Opus は手で codex を起動しない(ゲート保護ルール 9)。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\design-doc.ps1" `
  -GoalDir "<goal-dir>" -WorkDir "<対象プロジェクトのルート>" -Milestone A-0 [-WaitMinutes 9] [-Effort …]
# 続き: -Collect <label>    代筆: -Fallback -Milestone … -Reason "<理由>"
```

- `-Milestone` は節目。`A-0` か `CP:<milestone>`(state.md の `milestone:` の値。例 `CP:3-conversation-quiz`)。
- 動き: 設計書の有無でモードを決める → プロンプトを組む(4.4)→ `codex-run.ps1 -Role surveyor` → `codex-status.ps1` で待つ(1 回最大 9 分。`RUNNING` なら `-Collect` で続ける。scout と同じ)→ 型の検査 → 保存 → 記帳。
- 型の検査: 必須見出し(`更新履歴`・`構成`・`機能の地図`・`取り組んだが足りない`・`要望はあるが未着手`・`運用で見る懸念`)が無ければ `STATUS: INCOMPLETE`、本文は `<goal-dir>/codex-runs/<label>.raw.md` に残す。同じ依頼で 1 回だけ再実行する。
- 保存: 前の設計書を `<goal-dir>/codex-runs/<label>.design-prev.md` に写してから `design.md` を上書きする。更新履歴の行はスクリプトが足す: `| YYYY-MM-DD HH:MM | <goal-slug> | <節目> | <HEAD の短い SHA> | codex |`。Codex が履歴行を書いていたら捨てる(スクリプトの行が正)。
- 記帳: `loop-log.ps1 -Who codex-surveyor -Purpose "<節目>: <作成|更新>"`。`loop-log.ps1` の役一覧に `codex-surveyor` を足す。
- 標準出力(KV): `STATUS: OK` のとき `LABEL` / `DESIGN_DOC`(パス)/ `MODE`(create | update | unchanged | fallback)/ `FEATURES`(1 章の行数)/ `INSUFFICIENT`(2 章の機能数)/ `HISTORY`(足した行)/ `ELAPSED_MIN`。失敗は `STATUS` / `REASON` / `NEXT`。40 KB 超は `WARN:`。
- 変更が無いとき(A-0 だけ): 更新履歴の中で書き手が `codex` の最新の行を基準にする(`unchanged` や `opus(代行…)` の行は基準にしない。無ければ常に更新)。その行の SHA から HEAD までの差分が、その行のゴールのディレクトリ(`docs/r-super-loop-powers/<行のゴール>/`)と `design.md` 自身の中にしか無く、かつ今回のゴールディレクトリと `design.md` 以外に未コミットの変更が無ければ、Codex を呼ばずに履歴行だけ足す(`MODE: unchanged`、書き手 `unchanged`)。Learning(`CP:`)では常に更新する(そのゴールの記録が新しい材料になるため)。理由: Learning の末尾で Opus が `docs/r-super-loop-powers/` をコミットするので HEAD は必ず動く。前のゴールの記録はその Learning の更新で取り込み済みなので、差分として数えない。A-0 で続けてゴールを始めたときに待ちを作らないため。作成者の判断(builder check と Task 3 の実装で決めた)。
- 再実行の方針(Opus が呼び直す。1 回の待ちは 9 分までなのでスクリプトの中では完結しない): `INCOMPLETE` / `FAILED` / `SUSPECT` / `LOST` は同じ依頼で 1 回だけ再実行。`TIMEOUT` は effort を 1 段下げて(作成 `high` → `medium`、更新 `medium` → `low`)1 回だけ再実行。2 回目も `OK` でなければ `-Fallback`。`NEXT:` 行にそのまま実行できる再実行コマンドを出す。作成者の判断(builder check で決めた)。
- `-Fallback`: Codex が 2 回失敗したときの代筆。設計書が無ければテンプレートから作り(各章は「(未作成: Codex 失敗のため)」の 1 行)、あれば本文はそのままで、更新履歴に `| … | <goal-slug> | <節目> | <SHA> | opus(代行: <理由>) |` を足す。`loop-log.ps1 -Who codex-surveyor -Purpose "<節目>: FAILED→Opus が代行"` で記帳する。Opus はこれ以外の方法で設計書を書かない。
- ラベルは `design-<節目を [A-Za-z0-9._-] に寄せたもの>-<連番>`(例 `design-A-0-1`、`design-CP.3-conversation-quiz-1`)。`-Async` は付けない(A-0 も Learning も、終わるまで次に進めないため)。

### 4.4 作成と差分更新の材料(プロンプトの中身)

スクリプトが組む。実行契約・ロール憲章・ロール指示は `codex-run.ps1` が先頭に付けるので、ここはタスク固有の部分だけ。

- 共通: 目的と読み手(1 段落)、テンプレート全文(貼る)、書き方の決まり(4.1 の表)、出力は設計書の全文のみ、履歴行は書かない。
- 作成(設計書が無い):
  - 対象プロジェクトのルート(コードを読む。README・`docs/*.md`・`*/DESIGN.md` など既存文書を先に読み、「詳しい資料」に列挙する)
  - `docs/r-super-loop-powers/*/` の全ゴール: `goal-seed.md`、`goal-frame.md`(承認基準・運用で見る懸念)、`state.md`(phase・milestone)、`milestones/*/acceptance.md`(判定・新たな未知・要望・スキップ)、`milestones/*/retro.md`(発見された未知・次回変えること)、`assumptions.md`(未検証・棄却・未対応の行)、`hearing-log.md` の `## 結論`(やらない・後回し)
  - 読む順: 文書 → ゴール記録 → コード(足りないところだけ)
- 更新(設計書がある):
  - 前回の設計書のパス(土台にする。章立てと既存の行を保ち、変わったところだけ直す)
  - 前回の履歴行の SHA。`git log --oneline <SHA>..HEAD` と `git diff --stat <SHA>..HEAD` を自分で実行して、変わったファイルに関係する行だけ見直す(読み取り専用で実行できる。reviewer ロールと同じ)
  - 今回のゴールのディレクトリ(作成と同じファイル群)。A-0 のときは `goal-seed.md` だけがあるので、コードの差分が中心になる
  - 他のゴールディレクトリで前回以降に `acceptance.md` / `retro.md` / `hearing-log.md` の結論が増えたもの(並行ゴールの分)
- 「取り組んだが足りない」の判定材料を明示する: acceptance の REJECT 理由とスキップ、retro の発見された未知、台帳の未検証・棄却、phase が `done` でないゴール(finalization のまま等)、goal-frame の運用で見る懸念。
- タイムアウト: 作成 30 分、更新 15 分(`-TimeoutMinutes`。再実行を含めた最悪の待ちは作成で約 60 分。作成者の判断。builder が実測で直してよい)。codex 基準行が無い更新(履歴が代筆だけ)は、作成と同じ effort `high`・30 分で走り、プロンプトは全体に読み直しになる(`MODE` は update のまま。final review の指摘で追加)。

### 4.5 必ず通るための仕組み

利用者の決定: 仕組みで担保する(文書の指示だけに頼らない)。作成者の判断で 2 段にする。

**主: `loop-log.ps1` の遷移拒否。** 次の 3 つの遷移は、設計書の更新履歴に該当行が無いと `STATUS: REFUSED` で何も書かない。

| 遷移 | 必要な行 |
|---|---|
| `-SetOwner hearing-fable`(A-0 の終わり) | ゴール = このゴールの slug、節目 = `A-0` |
| 現在の phase が `learning` で `-SetPhase milestone-implementation` | 節目 = `CP:<state.md の milestone の値>` |
| 現在の phase が `learning` で `-SetPhase done` | 同上 |

- 設計書の場所は `<GoalDir の 3 つ上>/docs/r-super-loop-powers/design.md`(`-Mark` の projectRoot と同じ求め方)。
- 行の照合は `| <slug> | <節目> |` の完全一致(前後の空白は無視)。書き手が `codex` / `unchanged` / `opus(代行…)` のどれでも通る。
- `REASON` には「design.md に <slug> の <節目> の行が無い」、`NEXT` には `design-doc.ps1` の呼び方を出す。
- `goal-definition` → `done`(やらないで閉じる)は拒否しない。REJECT で実装に戻る遷移も対象外。

**副: Stop フックの機械検査。** `human-message-check.ps1` の日本語比率の検査の前に、判定役を呼ばない検査を 1 つ足す。
- 条件: 活動中のゴールの state.md が `担当: hearing-fable` で、設計書が無いか、`| <slug> | A-0 |` の行が無い。
- 動き: `{"decision":"block"}` で差し戻す。理由は固定文「[r-super-loop-powers] 設計書が未更新です: docs/r-super-loop-powers/design.md に <slug> の A-0 の行がありません。bin/design-doc.ps1 を実行してから返答してください」。`hook-log.md` に `BLOCK | design-doc | …` を残す。
- `stop_hook_active` のときは今までどおり検査しない(1 回だけ)。
- Learning 側は Stop フックでは見ない(フックは `phase: done` のゴールを対象にしないため。主の拒否で足りる)。

**代筆。** Codex が 2 回失敗したら `design-doc.ps1 -Fallback` で履歴行だけ足し、遷移を通す(4.3)。失敗の理由は履歴行と call-log に残る。ゲート保護ルール 8 の「グラレコとスカウトの失敗だけはループを止めない」に設計書役を加える。

### 4.6 ヒアリングとの接続

- A-0 の照合スカウトの問いに、設計書を先に読むことを書く: 「`docs/r-super-loop-powers/design.md` の 1〜3 章を先に読み、goal-seed に関係する機能の行(到達度)・『取り組んだが足りない』の該当・『要望はあるが未着手』の該当を挙げよ。見つからなければコードから探せ」。報告の結論に設計書の行を引かせる。
- `references/hearing.md` の「始め方 2」で読む材料に、設計書のうち照合が指した行(1 章の該当行と 2 章の該当節)を足す。設計書は文書なので PL-009(対象コードを読まない)には触れない。`policy.md` PL-009 に「設計書は読んでよい」を足す。
- 「問いの目的 4 メタ調整」に足す: 「設計書で『取り組んだが足りない』に当たるなら、頼み直しでは解決しない。何を変えるか(やり方・要件・確かめ方)を問う。『一部』や『進行中』に当たるなら、そのゴールの続きとして扱うかを問う」。
- `templates/goal-frame.md` の「ヒアリングで表面化した既知」に 1 行の例を足す: `- 既存機能との関係: <設計書 1 章の行名> の拡張 | 新規 | 前に足りなかった件(2 章)`。新しい章は作らない(作成者の判断。goal-frame の章立てを増やさない)。

### 4.7 工程の変更点

**workflow-a A-0**(Opus):
1. Goal Seed 保存、ディレクトリ作成(今までどおり)。
2. **設計書**: `design-doc.ps1 -Milestone A-0` を実行し、終わるまで待つ(`RUNNING` なら `-Collect`。待つ間に 4 を進めてよい。3 は設計書を読むので待つ)。初回作成は時間がかかるので、利用者に「設計書を作っています(初回は十数分、長いと 1 時間)」と一言伝える。再実行は 4.3 の方針、2 回失敗なら `-Fallback`。
3. 照合スカウト(設計書を先に読ませる)。設計書の完了後に起動する(直列)。
4. retro 抜粋、他の作業の一覧(今までどおり)。
5. `loop-log.ps1 -SetOwner hearing-fable -SetWait …`(設計書の行が無ければ拒否される)。

**workflow-a「やらないと決まったとき」**: `-SetPhase done` の後に、`docs/r-super-loop-powers/` の未コミット分(ゴール記録と A-0 の設計書)を Opus がコミットする 1 文を足す。設計書の更新は行わない。

**workflow-b Learning**: 1(retro)の後、2(グラレコ)の前に「1.5 設計書の更新」を足す: `design-doc.ps1 -Milestone "CP:<milestone>"`。MVP は Checkpoint 単位、高信頼はマイルストーン単位(retro と同じ)。3(次へ)は、`-SetPhase` の前に `docs/r-super-loop-powers/` の未コミット分(設計書・retro・grareco)を Opus がコミットする。`-SetPhase` は行が無ければ拒否される。

**境界リセット・再開パケット**: 変更なし。`design-doc.ps1` は `-Async` を持たないので `codex-run:` には乗らない。ただし `codex-run.ps1` の run は残るので、セッションが切れたときは `codex-status.ps1` で判定してから `-Collect` する(既存の「codex 委譲はセッションを跨いで生き残る」のとおり)。

### 4.8 規則と文書の変更

- `SKILL.md`: ディレクトリ契約に `docs/r-super-loop-powers/design.md`(ゴールの外)を 1 行、記帳の役一覧に `codex-surveyor`、ゲート保護ルール 8・10 に設計書役、起動時チェック 6 の「4 ロール」を「5 ロール」、「読むものと読まないもの」に「設計書: 照合が指した行だけ」。**24 KB(24,576 バイト、LF 換算)の上限**は変えない。着手時点で残り約 12 バイトなので、足す分は削って作る。削る候補(作成者の判断。builder が選ぶ): ディレクトリ契約の木のコメントの短縮、「プラグインのフック」節の圧縮(詳細は `references/` へ)、「例外・停止時の扱い」の重複する文。
- `references/codex-invocation.md`: 4 ロール → 5 ロールの表、2-7 に `design-doc.ps1` の使い方、4 章にプロンプト要素。
- `references/roles.md`、`policy.md`(責任分担・PL-009・「技術PMを呼ぶ場面」と同じ形で「設計書役を呼ぶ場面」)。
- `README.md`: 役とモデルの表、リポジトリ構成。
- 版: `.claude-plugin/plugin.json` 0.12.0、`.codex-plugin/plugin.json` 0.1.3。`tests/skill-layout.tests.ps1` の版の検査を合わせる。
- `skills-codex/`: `scripts/sync-templates.ps1 -Mode Copy` でテンプレートを写すだけ。

### 4.9 並行ゴールと衝突

worktree で 2 本のゴールが走ると、両方が `design.md` を更新し、ブランチ合流で衝突しうる。作成者の判断: 設計書は次のゴールの A-0 で Codex が作り直すので、衝突したらどちらかを採って合流してよい(4.1 のとおり Learning の末尾でコミットされているので、合流の対象になる)。workflow-a の A-0 にその一文を書く。構造を分ける(機能ごとに 1 ファイル等)ことはしない。

## 5. 確認方法

テスト(`tests/*.tests.ps1`。全部 `ALL PASS`):

- `design-doc.tests.ps1`(新規): プロンプトの組み立て(作成 / 更新で材料が変わる、テンプレートが貼られる、履歴行を書かない指示)、型の検査(見出し欠落で `INCOMPLETE`、raw 保存)、保存(履歴行の形、前の設計書の写し、Codex が書いた履歴行の除去)、`-Fallback`(無い時の作成、ある時の行追加)、記帳(`codex-surveyor`)、40 KB の `WARN`。codex は scout のテストと同じく手作りの完了 run で代える。
- `loop-log.tests.ps1`: 3 つの遷移の拒否と通過(行あり / 行なし / 代行の行 / `goal-definition` → `done` は通る / REJECT の戻りは通る)、`codex-surveyor` の役。
- `human-message-check.tests.ps1`: `担当: hearing-fable` で行なし → 固定文で `block`、行あり → 既存の検査へ進む、`stop_hook_active` では検査しない。
- `codex-run.tests.ps1`: `-Role surveyor` の受理、effort の既定、ロール指示の差し込み、`-Web` 無し。
- `roles-sync.tests.ps1`: `roles.md` に `(surveyor)` の節がある。
- `skill-layout.tests.ps1`: サイズ上限、版、テンプレートの同期。

スモーク(利用者の確認。plan の外で 1 回):

- agent-alert の dev チェックアウトで `design-doc.ps1 -Milestone A-0` を 1 回実行し、できた `design.md` を利用者が読む。確認の問い: 「11/5 の『本体はどこにいるか、記憶はあるか』に、この文書だけで答えられるか」「0.2 の流れが主要な機能を押さえているか」「2 章の『止まっている理由』が頼み直すかどうかの判断に使えるか」。所要時間と文書の大きさを記録する。
- 次の実ゴール 1 本で、A-0 の更新と Learning の更新が拒否なしに通り、ヒアリングで設計書の行が引かれることを見る。

## 6. 利用者の決定(2026-11-08、builder check 後の確認)

1. スモーク(初回作成)は agent-alert で行う。`dev/agent-alert` に `docs/r-super-loop-powers/design.md` ができ、利用者が読んで「11/5 の問いに答えられるか」を判断する。これで agent-alert の次のゴールの A-0 は更新(数分)になる。
2. 「最後」= Checkpoint ごとの Learning(ゴール完了時だけにしない)。
3. 他のプロジェクトで初めて使うときは、A-0 が初回作成を待つ(十数分、再実行を含む最悪で約 1 時間)。非同期にしてヒアリングを先に始める案は、照合に設計書を使えないので採らない。
4. 見本の形(0.1 全体概要 / 0.2 主要な機能ごとに使うコンポーネントの流れ / 1〜4 章)でよい。「アーキテクチャ(全体概要と、主要な機能が使われるときにどのコンポーネントをどんな流れで使うか)」は利用者の要望で足した。
5. 必ず通るように仕組み(フック)で担保する(利用者の要望)。

builder check で作成者が決めたこと(利用者が覆してよい): Learning 末尾と「やらない」で閉じるときに Opus が `docs/r-super-loop-powers/` をコミットする(4.1)/ A-0 の照合スカウトは設計書の完了を待つ(4.7)/ 再実行は 1 回、TIMEOUT は effort を 1 段下げる(4.3)/ 変更が無ければ Codex を呼ばず履歴行だけ足す(4.3)。

## 7. builder に任せること

- `design-doc.ps1` の内部構造(scout.ps1 の関数の共有・複製のどちらでもよい)、ラベルの連番、KV の細部。
- ロール指示(英文)・テンプレートの文言・各 reference の文言。
- SKILL.md のどこを削るか(4.8 の候補から。上限のテストが正)。
- タイムアウトと effort の実測による調整。
- 実装の分割順とテストの追加方法。
