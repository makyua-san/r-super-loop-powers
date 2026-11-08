# ワークフローA: Goal Definition(A-0〜A-8)

SKILL.md(共通)の起動時チェック 9 から読まれる。state.md の phase が `goal-definition` の間(新規ゴールを含む)だけ使う。共通の規則(起動時チェック・ディレクトリ契約・記帳・ゲート保護・Fable 共通契約・境界リセット・読むもの)は SKILL.md にある。A-1a〜A-1b はメインセッションの Fable が利用者と直接話す(`/model` の切り替えは利用者が行う)。A-0 の終わりから A-1b の確定まで(ヒアリング中)は境界リセットの印を置かず、「待ち」を書くだけにする。A-2〜A-4 は代理Fable(SendMessage 継続)が生きているので、A-8 の承認まで境界リセットをしない(人間待ちでも「待ち」を書くだけで印は置かない)。設計書(`docs/r-super-loop-powers/design.md`)は A-0 で Codex が作成・更新し、行が無いと `loop-log.ps1 -SetOwner hearing-fable` が拒否される。

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
  2. goal-frame.md 全文(貼る)。hearing-log.md・spec・plan は**貼らずにパスで渡し**(codex は read-only で読める)、関連する節名を示す。(2ラウンド目以降)前ラウンドの回答は `codex-runs/<前ラベル>.last.txt` のパスで渡す。本文が 40 KB を超えると `codex-run.ps1` が `WARN: prompt is N KB` を出す(全文貼りで 300 KB に達した実測がある)。スカウトの報告(`scout/<label>.md`)があれば `REPORT:` のパスを添え、同じ探索を技術PMに繰り返させない
  3. 質問リスト(番号付き。アプローチ比較の問いは候補案を併記)
  4. 出力要求: 質問ごとに「回答 / 根拠(既存コードの該当箇所があれば引用) / 前提・リスク / 確信度(高・中・低)」。ユーザー判断が要る問いは `NEEDS_USER_VIEW:` 行で返す
- **往復**: codexはセッションを継続しないため、**1ラウンド=1呼び出し**。effort `max` は1回が重いので、brainstormingの進行を止めない範囲でHOWの問いを束ねる(例: アプローチ提示の段階でそれまでのHOW論点をまとめて1回)。
- **実装アセス(MVP・A-4末に1回。ラベル `techpm-assessment`)**: writing-plans が plan を書き終えたら、goal-frame.md を貼り、spec・plan・goal-plan.md(主要設計判断)はパスで渡し、**マイルストーンごと**に次を出させる — 採用する実装方式(1つに決め切る) / 触るファイル・関数 / 作業順 / 既知のリスクと回避策 / 完了を示す検証コマンド / 実装役が迷いそうな点への指示。出力は `## M<n>` 見出しで区切らせる。検証コマンドには、1 回 10 分を超える実測を入れさせない(超えるものは「運用で見る懸念」として書かせる。goal-frame.md の承認基準に利用者が入れたものと、否定リストに触れる確認は除く)。`STATUS: OK` の `FINAL_MESSAGE_FILE` を `tech-assessment.md`(goal直下)に保存し、goal-plan.md からリンクする。Goal Gate(A-6)の submission にも添付する(ゲートFableが実装方針を確認できるように)。
  - REVISE / REPLAN で plan が変わった場合は、変わったマイルストーンについてのみ再アセスする。
- **高信頼強度**: HOWは人間が決めるため必須ではない。人間が技術的見解を求めた場合のみ同じ契約で呼ぶ。
- 呼び出しごとに `loop-log.ps1 -Who codex-techpm` で記録する。

## 工程

**A-0 Goal Seed保存(Opus)**
ユーザーの「やりたいこと」を原文のまま `goal-seed.md` に保存する。要約・整形しない。`<goal-slug>` を決め、ディレクトリと state.md(phase: goal-definition, 強度: 未確定)、空の call-log.md(`loop-log.ps1` が初回の記録時に作るので省略可)、`templates/assumptions.md` の形式で空の仮定台帳、`templates/hearing-log.md` の形式で空のヒアリング記録を作成する。

続けて、ヒアリング Fable に渡す材料を揃える(Fable の消費を増やさないため、ここは Opus が行う):
1. **Goal Seed 保存**: 上の保存(原文のまま `goal-seed.md`、ディレクトリ・state.md・仮定台帳・ヒアリング記録)を先に済ませる。2 以降はこの後に行う。
2. **設計書(Codex 設計書役)**: プロジェクトの設計書 `docs/r-super-loop-powers/design.md` を作成・更新する。利用者に「設計書を作っています(初回は十数分、長いと 1 時間)」と一言伝えてから呼ぶ。Bash ツールの `timeout` を 600000 にする:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\design-doc.ps1" `
     -GoalDir "<goal-dir>" -WorkDir "<対象プロジェクトのルート>" -Milestone A-0
   ```
   `STATUS: OK` なら先へ進む(`MODE: unchanged` は、前回の Codex の行以降に変わったのがゴール記録と設計書だけだった印。変更が無ければ Codex を呼ばず履歴行だけ足される)。`STATUS: RUNNING` / `STALLED` は 9 分で終わらなかったので、`NEXT:` の `-Collect <label>` で回収する。待つ間に 4 を進めてよい。3 は設計書を読むので直列で待つ。
   `INCOMPLETE / FAILED / SUSPECT / LOST` は同じ依頼で 1 回だけ再実行する。`TIMEOUT` は `NEXT:` のとおり effort を 1 段下げて 1 回だけ再実行する。2 回目も `OK` でなければ `-Fallback -Reason "<理由>"` で Opus が履歴行だけ代筆する(設計書が既にあれば本文は書き換えず、無ければ雛形から作る)。並行ゴールで `design.md` が衝突したら、どちらかを採って合流してよい(次の A-0 で作り直す)。
3. **照合**: `bin/scout.ps1` に「`docs/r-super-loop-powers/design.md` の 1〜3 章を先に読み、goal-seed に関係する機能の行(到達度)・『取り組んだが足りない』の該当・『要望はあるが未着手』の該当を挙げよ。見つからなければコードから探せ。被り・拡張か新規かの候補も挙げよ」を問う。失敗してもループを止めない。
4. **retro 抜粋 + 他の作業の一覧**: 直近の `docs/r-super-loop-powers/*/milestones/*/retro.md` を新しい順に最大3件読み、要点を `hearing-log.md` の冒頭(ラウンドの前)に書く。続けて Linear の接続があれば、利用者の進行中の課題を読み取りで一覧にして同じ場所に書く。接続が無い・失敗したときはその旨を書く。
5. **ヒアリングへの引き渡し**: `loop-log.ps1 -SetOwner hearing-fable -SetWait "/model fable への切り替え"` を実行し、利用者に「次はヒアリングです。`/model fable` に切り替えて『続けて』と送ってください」と案内して止まる。設計書の行(`| <goal-slug> | A-0 |`)が無ければ `STATUS: REFUSED` で拒否されるので、2 に戻る。Fable が使えない(利用上限など)と利用者が明示したときだけ、Opus が `references/hearing.md` に従って代わりに行い、hearing-log.md にその旨を書く。

**A-1a ヒアリング(ヒアリング Fable・直接会話)**
メインセッションの Fable が `references/hearing.md` に従い、利用者と直接話す。Opus は中継しない。終わりに hearing-log.md の `## 結論` を書く。

**やらないと決まったとき**: `## 結論` が「やらない / 後回し / 合流」なら Goal Frame を作らずに閉じる。`loop-log.ps1 -SetPhase done -SetOwner opus-main -Clear 待ち` を実行し(state.md は `phase: done` になり、フックと再開の対象から外れる)。続けて `docs/r-super-loop-powers/` の未コミット分(ゴール記録と A-0 の設計書)を Opus がコミットする。設計書は更新しない。その後、利用者に `/model opus` への切り替えを案内する。retro は作らない。rb のタスクから始まったゴールなら、結論を rb に報告する。

**A-1b Goal Frame(ヒアリング Fable)**
- **MVP**: ヒアリング Fable がそのまま `templates/goal-frame.md` で作る。
- **高信頼**: 新規Fableインスタンスに `templates/goal-frame.md` の構造 + goal-seed.md 全文 + retro抜粋(あれば)を渡す(呼ぶのはメインセッションのモデルのどちらでもよい)。
指示: 「あなたはこのゴールの全体責任者。ゴールの方向・ヒアリングで表面化した既知・制約・今回確定すべきこと・未知マップ(既知の未知と無自覚の未知の探索方針)・承認基準・運用で見る懸念・終了条件(残存未知の許容基準)を定義し、ループ強度(MVP | 高信頼)を理由付きで提案せよ。既定はMVP(品質最大化は目的ではない)。承認基準と終了条件は後でゲート判定の基準として使われる。検証可能な形で書け。MVPでは、承認基準を稼働テストと短時間の要件確認にし、1 回 10 分を超える実測は利用者が選んだもの以外を運用で見る懸念に置け(`references/hearing.md`「受け入れ条件と運用で見る懸念」)。」
出力を `goal-frame.md` に保存し、`loop-log.ps1 -Who fable` で記録する。内容をユーザーに提示し、**ループ強度を確定**してもらい、方向のズレがないか確認する。A-1aで高信頼と答えた後にここでMVPへ確定が変わった場合は、A-1aの深掘りヒアリングを再開してからA-2へ進む。確定した強度を goal-frame.md の「人間の確定」欄と state.md に記録する(`loop-log.ps1 -SetIntensity MVP|高信頼`)。
確定したら `loop-log.ps1 -SetOwner opus-main -SetWait "/model opus への切り替え"` を実行し、利用者に「ヒアリングは終わりです。`/model opus` に切り替えて『続けて』と送ってください」と案内して止まる。

**A-2〜A-4 ブレスト → Spec → Plan(Opus + Superpowers)**
開始時(Opus に戻った後)、MVP では**新しい代理Fable**を名前付きで起動する。依頼文はロール憲章(全体図+代理Fable節)、goal-seed.md・goal-frame.md・hearing-log.md の全文の順。代理Fableはヒアリングの会話を見ていないので、記録だけが根拠になる。`loop-log.ps1 -Clear 待ち` で待ちを消す。
現状把握(既存の流れ・該当ファイル・使われ方)は Opus が自分で探索せず `bin/scout.ps1` に投げる(SKILL.md「読むものと読まないもの」)。`superpowers:brainstorming` を起動し、その標準フロー(spec作成 → writing-plans)に完全に従う。スキル内部の手順・ゲートには干渉しない。強度により質問・承認の相手を変える:
- **高信頼**: 従来通り人間が相手(人間が技術的見解を求めた場合のみ技術PMを呼ぶ)。
- **MVP(代理ブレスト: Fable + 技術PM)**: 質問・設計承認の相手を人間ではなく**代理Fable**(SendMessage)と**技術PM**(「技術PM(Codex)共通契約」)にする。Opusはbrainstormingが出す問いを次のように振り分ける:
  - ユーザー価値・体験・優先順位・好み・受け入れ観点(WHAT) → **代理Fable**
  - 実装方式・技術選択・構成と分割・技術リスク・実現性(HOW) → **技術PM**
  - 両方に係る問い(アプローチ選択・設計承認など) → 先に技術PMの技術評価を取り、それを添えて代理Fableへ渡す。**最終の回答・設計承認は代理Fable**が行う(ユーザーの代理であるため)
  - 技術PMが `NEEDS_USER_VIEW:` を返した問い → 代理Fableへ回す

  代理Fableへの依頼文に必ず含める: 「あなたはユーザーの代理として**ユーザー目線で**回答する。根拠は goal-frame.md と hearing-log.md。技術PMの見解が添付されている場合、技術的な実現性・リスクの評価はそれを前提とし、ユーザー価値の観点で選べ。技術PMの評価とユーザー価値が衝突し、選択でユーザー体験が大きく変わる場合は回答せず `ASK_HUMAN:` を返せ。**ユーザー固有の判断(好み・業務文脈・優先順位)が必要でヒアリング記録から導けない問い、否定リスト該当、エスカレーション発火条件該当の問いには、回答せず `ASK_HUMAN: <人間向けの質問文>` と返せ**。新しい懸念が出たら、1 回 10 分を超える実測は運用で見る懸念に置け。それを承認基準にしたいときは `ASK_HUMAN:` で利用者に確かめよ。」 ASK_HUMANが返った質問のみ人間へ提示し、回答を hearing-log.md に追記して代理Fableへ共有する。主要決定(採用アプローチ・設計承認・主要な技術選択)は goal-plan.md の「主要設計判断(Fable代理回答 / 技術PM回答による)」欄に、**どちらの回答を根拠にしたか**を付けて記録する。往復ごとに `loop-log.ps1 -Who fable|codex-techpm` で記録する。
**未知の振り分け**: ヒアリング・ブレスト中に人間または代理Fableが「決めていない / わからない」と答えた問いは、その場で追及せず**仮説化して assumptions.md に記録し、続行する**。goal-frame.md の未知マップと突き合わせる。plan に書く対象ファイル・関数で場所が分からないものはスカウト(`bin/scout.ps1`)に投げる。
**MVPでは plan 完成後に技術PMの実装アセスを取る**(「技術PM(Codex)共通契約」の実装アセス)。これが無いまま A-5 へ進まない。
完了後、spec/planへの相対リンクとマイルストーン一覧を `goal-plan.md` に集約し、**Checkpoint印を付ける**(policy.md「Checkpointとマイルストーン粒度」: Checkpoint = ユーザー価値をE2Eで評価できる点。最終マイルストーンは必ずCheckpoint)。「主要設計判断(Fable代理回答 / 技術PM回答による)」欄もここに置く。

**A-5 Approval Submission(Opus)**
state.md を読み直してから、`templates/approval-submission.md` に従い、Goal Plan承認用の submission を作成する(対象: Goal Plan全体。**Checkpoint配置**・残存未知リスト・仮定台帳サマリを含める)。保存先: `goal-plan-submission.md`(goal直下)。

**A-6 Goal Gate(ゲートFable・新規インスタンス)**
前提確認: goal-frame.md と submission が存在すること。
共通契約に従い goal-frame.md 全文 + submission 全文 + assumptions.md の未検証仮定を渡し、判定観点(適合性・残存未知の許容性・仮定の事実扱い・否定リスト)に加えて「**Checkpoint配置が『人間の受け入れテスト1回でE2E価値を評価できる』単位か**」、MVPでは「**1 回 10 分を超える実測が、利用者の確認なしに承認基準や検証コマンドに入っていないか**」で「この計画で元の目的を達成できるか」を判定させる。品質の細部ではなくゴール整合性を中心に見る。
結果を `goal-gate-decision.md`(goal直下)に保存し、`loop-log.ps1 -Who fable` で記録する。

**A-7 差し戻し処理(Opus)**
- REVISE → 指定された工程(ブレスト/spec/plan)へ戻り、修正後 A-5 から再提出
- REPLAN → A-4(計画)から作り直し
- BLOCKED → 根拠に含まれる質問を人間へ提示し、`loop-log.ps1 -SetWait "<質問の要旨>"` で「待ち」を書いて停止(代理Fableが生きているので印は置かない)

**A-8 Human Goal Plan承認(人間)**
Fable PASS後、人間に提示して実装へ進む承認を得る。
- **MVP(WHATレベル)**: 提示は「ゴール解釈(goal-frameの方向)・要件・制約・マイルストーン一覧とCheckpoint配置・仮定台帳サマリ」に限定し、spec/planは参照リンクとして添付する(HOW詳細は承認対象にしない)。
- **高信頼**: 従来通り Goal Plan(と goal-frame)を提示する。
承認されたら **境界リセット**(SKILL.md)を行う: `loop-log.ps1 -GoalDir "<goal-dir>" -SetPhase milestone-implementation -SetMilestone "1-<名前>" -SetCheckpoint "<n>-<名前>" -SetGate impl-gate -Clear 待ち -Mark` の 1 回で state.md を更新して印を置き、人間に `/clear` と「続けて」を頼んでターンを終える。再開後に `references/workflow-b.md` を読んで B-1 へ。
