# ゴールループのコンテキストの扱い — 調査と改善案(2026-10-10, rb-55)

対象: v0.8.1 のゴールループ(Claude 版)。設計資料(SKILL.md / policy.md / roles.md / bin/)と、実際に回した 24 ゴールの記録(`docs/r-super-loop-powers/*`)、および Claude Code のセッション記録(`~/.claude/projects/.../*.jsonl`)から実測した。

## 結論

1. **雪だるまはオーケストレーター(Opus メイン)に起きている。** 1 セッションで 843 ターン、文脈は 70K → **87 万トークン**まで単調増加(圧縮 0 回)、累計キャッシュ読みは **4.1 億トークン**。サブエージェント(Fable / Sonnet / codex)は毎回使い捨てで、構造は正しい。
2. 文脈を増やしているのは、サブエージェントの回答ではなく **Opus 自身が書いたもの**(依頼文・文書・シェル引数で約 790KB)と、**バックグラウンド完了通知の再掲**(272KB)。サブエージェントの最終回答は 36 回で 41KB しかない。
3. コストはおおよそ **Σ(各ターンの文脈サイズ)** で決まる。ターンの 2 割強が記帳だけ(call-log 追記 126 回・impl-check 39 回・報告の転記 19 回…)で、これが文脈 50 万のときに走る。
4. 同じプロジェクトで圧縮が 3 回入ったセッションは、ターン数がほぼ同じで**平均文脈が半分以下**(49 万 → 23 万)。state.md からの再開は設計どおり動いている。つまり「フェーズ境界で文脈を捨てる」だけで費用は半減する。
5. 「最小コンテキスト」のはずのゲート Fable が、依頼文 5〜6KB でパスだけ受け取り、**自分で 20〜50 ターン探索**している(Read 16〜25 回 + Bash/Grep)。文脈 10〜13 万トークン。PL-009 の意図と逆で、判定の精度にも効く。
6. 精度への影響は仮説の域だが、圧縮なしで 80 万を超えたセッションの retro に「前回の教訓を書いたのに守らなかった」「同種のプロンプト不備で再委譲 7 回」が記録されている。長文脈で注意が薄まる典型と整合する。

> **追記(同日)**: 改善案 A は「/compact」ではなく「**/clear + スクリプトが組む再開パケット**」に差し替えた。コンパクションは制約を平均 17% しか残さない等の知見があり、精度の面で採らない。末尾の「追記: コンパクションを使わない根拠と方針の修正」を参照。

## 現状の仕組み(設計上の扱い)

| 担当 | 文脈の与え方 | 文脈の寿命 |
|---|---|---|
| Opus メイン | SKILL.md(47KB)+ policy.md(18KB)+ roles.md(13KB)を起動時に読む。以後、全文書の執筆・転記・記帳・依頼文の作成を自分で行う | セッション全体に残る。圧縮は手順にない |
| 代理 Fable | goal-seed / goal-frame / hearing-log + SendMessage 往復 | ヒアリング〜計画(A-1a〜A-4)の間、1 インスタンス |
| ゲート Fable | goal-frame + 対象文書 + 未検証仮定(PL-009) | 呼び出しごとに新規 |
| 実装役 Sonnet | `## TECHNICAL ASSESSMENT`(アセスの M 節を原文貼付)+ 受入条件 + SCOPE + 検証 | 委譲ごとに新規。最終メッセージ(JSON)だけ読まれる |
| codex(技術PM / レビュー / グラレコ) | 実行契約 + 憲章 + タスク本文(ファイルから stdin) | 呼び出しごとに新規。`last.txt` だけ読まれる |

正本はファイル(`docs/r-super-loop-powers/<goal>/`)にあり、NFR-04 で state.md から再開できる。設計としては「捨てられる文脈」になっているが、Opus メインについては捨てる手順がない。

## 実測

### Opus メインセッション(dev-agent-alert)

| セッション | 期間 | ターン | 最大文脈 | 圧縮 | 累計キャッシュ読み | 平均文脈/ターン | 出力 |
|---|---|---|---|---|---|---|---|
| canvas-generalization | 10-04〜10-06 | 843 | 871,656 | 0 | 4.13 億 | ≈ 49 万 | 101 万 |
| jarvis-daily-hub | 10-08〜10-10 | 884 | 429,890 | 3 | 2.00 億 | ≈ 23 万 | 76 万 |

同じ作業量で、圧縮の有無だけで累計入力が半分になっている。他のセッションも最大文脈 39 万・55 万・59 万と、圧縮なしでは 40〜90 万に達する。

### 文脈に入ったバイト数の内訳(canvas-generalization)

| 向き | 内訳 |
|---|---|
| 入る側(ツール結果) | Read 1,320KB(うち画像 13 枚 ≈ 1,200KB、アセス 51KB、技術PM回答 39KB)/ Bash 226KB(276 回)/ **Agent 41KB(36 回)** / TaskStop 33KB |
| Opus が書いた側(ツール引数) | **Bash 413KB / Write 220KB / Agent 依頼文 100KB** / PowerShell 34KB / SendMessage 21KB |
| ユーザー側テキスト | **タスク通知 272KB**(バックグラウンド完了通知が結果本文を再掲)/ 人間 105KB / エージェント間 55KB / Stop フック差し戻し 2.5KB |

画像はトークン換算では小さい(1 枚 ≈ 1.5K)が、1 枚 54〜640KB のバイトが毎回キャッシュ作成に乗る。

### ターンの内訳(canvas-generalization, 843 ターン)

| 種類 | 回数 |
|---|---|
| ツール呼び出しなしの応答(人間への説明・地の文) | 370 |
| **call-log 追記** | **126** |
| その他のシェル | 99 |
| 文書・プロンプト・報告をシェルで書く | 45 |
| impl-check(スナップショット / 判定) | 39 |
| Agent 起動 | 36 |
| **実装役の報告を report.md に転記** | **19** |
| TaskStop | 16 |
| codex-status 待ち / codex-run | 11 / 8 |
| SendMessage | 11 |
| state.md 更新 | 5 |

### サブエージェント(同プロジェクト 10-03〜10-06、60 件)

| 種類 | 文脈 | ターン | 出力 | 備考 |
|---|---|---|---|---|
| Fable(ゲート・開始確認・REJECT 戻り先) | 46K〜131K | 6〜52 | 5K〜97K | 30 ターン超が 6 件。Read 16〜25 回・Bash 最大 10 回・Grep 最大 12 回 |
| Sonnet 実装役 | 25K〜290K | 8〜182 | ≤ 276K | 隔離されており問題は小さい。20 分超の委譲が 29 万 |
| Opus(Explore 等) | 106K〜135K | 15〜44 | 16K〜32K | |

### codex(`*.out.jsonl` の `turn.completed` usage)

| ロール | 累計入力 | うちキャッシュ | 出力 | プロンプト |
|---|---|---|---|---|
| 技術PM(max) | 140 万〜240 万 | 約 9 割 | 3 万〜4.6 万(推論 1.8〜2.8 万) | 10KB〜**328KB**(hearing-log・spec・plan・前ラウンド Q&A を全文貼ると肥大) |
| グラレコ(medium) | 11 万〜17.5 万 | 約 8 割 | 1.5K〜2.5K | 7KB。imagegen の SKILL.md を読む等で 15 往復前後。ゴールあたり 5〜8 回 |
| (旧 v0.6 の codex 実装役) | 最大 1,290 万 | | | 参考。v0.7 で Sonnet に置換済み |

### 再貼り付けされる文書のサイズ(24 ゴール)

| 文書 | サイズ | どこへ貼られるか |
|---|---|---|
| goal-frame.md | 10〜53KB(典型 12〜18KB) | 全 Fable 呼び出し・技術PM |
| tech-assessment.md | 29〜220KB(M 節は 4〜36KB) | 実装役の各委譲に M 節を原文貼付。再委譲でも毎回 |
| assumptions.md | 3〜139KB | Fable(関連部分)・実装役(OPEN ASSUMPTIONS) |
| hearing-log.md | 8〜61KB | 代理 Fable・技術PM |
| 実装役プロンプト | 平均 14〜36KB(M4 系は 34〜36KB × 4 回) | Opus が毎回書く。`m1-impl` と `m1-impl-2` がバイト一致の例あり |
| 実装役の報告 | 3〜15KB | Agent 結果として入り、さらに Write で転記(2 重) |

## 問題の構造

- **コスト ≈ Σ(文脈サイズ × ターン)**。文脈を減らす(圧縮)とターンを減らす(記帳の一括化)が独立した 2 つのレバーで、どちらも設計変更なしに手順とスクリプトで効く。
- Opus は「責任・ゲート層」のはずが、実態は**全文書の筆記係**。書いたものが全部文脈に残り、しかも再委譲のたびに同じ内容を書き直す。
- ゲート Fable は「最小コンテキスト」の設計意図に反して探索している。codex 版のスモーク(2026-08-31)で「判定役は探索したがる」と実測した事実が、Claude 版でも再現している。
- 計測の仕組みが call-log(回数と時刻)しかなく、文脈サイズとターン数が見えていない(D18 で「トークンは計測不能」と置いたが、セッション記録から後計算できる)。

## 改善案(優先順)

### A. フェーズ境界で文脈を捨てる — 効果大・変更小(推奨、最初に)

- SKILL.md の手順に「**B-6 PASS の中間クローズ後 / Checkpoint ACCEPT の確定処理後 / A-8 承認後**に state.md を更新してから `/compact`(または新セッションで `/r-super-loop-powers` 再開)」を入れる。再開手順は起動時チェック 3 として既にある。
- 目安: 文脈が 20 万を超えたら次のマイルストーン境界で必ず切る。
- 制約: 代理 Fable(SendMessage 継続)はセッションを跨げないので、A-4 完了後が最初の切れ目。
- 期待: 平均文脈 49 万 → 15〜20 万。ターン数は変わらずに累計入力 1/2〜1/3(jarvis の実測が裏付け)。精度面でも、retro の「教訓の再発」に対する最も安い対策。

### B. 記帳を 1 ターンに畳む — ターン数 -20%

- `bin/loop-log.ps1`: call-log 追記 + state.md の欄更新(`codex-run:` / `milestone:` / `updated:`)を 1 回で。
- `impl-check.ps1 -Prepare -Label`: `.base.txt` と `.pre.txt` を 1 回で書く(今は 2 ターン)。
- `impl-check.ps1 -SaveReport`: 実装役の最終メッセージをファイルから受けて `.report.md` に保存し、そのまま判定(転記の Write と判定の 2 ターン → 1 ターン。文脈への 2 重載せも消える)。
- 期待: 126 + 39 + 19 + 5 ≈ 190 ターン → 60 程度。

### C. 委譲プロンプトの重複排除 — Opus の書き出し -30%

- 再委譲(`m1-impl-2` …)は全文を書き直さず、初回 prompt のパス + `## 再委譲の差分`(impl-check の `REASON` / `CRITERION_UNMET` の引用)だけにする。builder の禁止領域 `docs/r-super-loop-powers/` に `impl-runs/*.prompt.md` と `tech-assessment.md` の**読取だけ**例外を設ける。
- M 節の原文貼付は「実装役が迷わない」ための設計意図なので、初回委譲は現状維持。

### D. ゲート Fable の探索を封じる — 精度と費用(スパイク後)

- 現状: 依頼文でパスを渡し、Fable がプロジェクトを 20〜50 ターン探索。
- 案 D1: `agents/gate-fable.md`(model: fable、tools: Read のみ)を同梱し、必要文書は依頼文に貼る。
- 案 D2: Stop フックの判定役と同じ `claude -p --model fable --tools ''` を `bin/gate-run.ps1` にする。文脈を完全に制御でき、結果を gate-decision.md に直接保存、Opus の文脈には判定行だけ入る。バックグラウンド通知の重複も消える。
- 推奨 D2(codex-run と同じ型)。先に `-p --model fable` の可否と所要・費用をスパイクで確認する(v0.8 の判定役は haiku で確認済み)。

### E. 画像を Opus に読ませない

- スクショ・グラレコを Read すると 1 枚 54〜640KB が文脈に乗る(canvas で 13 枚 1.2MB)。確認が要るなら Sonnet サブエージェントに見せて 5 行で返させる。人間に渡すだけなら SendUserFile のみ。

### F. codex のプロンプト上限と effort

- 技術PM: 全文貼りの上限(例 40KB)。hearing-log・spec・plan は「読むもの」としてパスを渡し、codex 自身に読ませる(read-only で読める。328KB の例は全文貼り)。
- グラレコ: effort `low`、imagegen の SKILL.md を読まず image_gen を直接呼ぶ指示に変える(累計入力 1/3 程度の見込み。要実測)。

### G. 計測の常設(PL-007 の拡張)

- 今回使った集計(セッション記録から「最大文脈・ターン数・記帳ターン比・ツール結果の内訳」)を `bin/ctx-report.js` として同梱し、retro の観測欄に 3 項目を追加する。

## 進め方の案

1. **v0.9**: A + B + C(SKILL.md と bin/ の変更のみ。既存ゴールと互換)
2. D のスパイク → D2 を v0.10
3. E・F は手順の 1 行追加で、v0.9 に同梱可

## 追記: コンパクションを使わない根拠と方針の修正(2026-10-10)

人間からの指摘「精度が落ちるのが気になる。特にコンパクション」を受けて、Lydia Hallie のウェビナー記事(@ery_treasure の解説)と同種の知見を調べた。結論: **コンパクションもしない、長文脈も続けない。ファイルから決定論的に再水和できる状態を保ってから /clear する。**

### 調べた知見

| 出典 | 要点 |
|---|---|
| Anthropic「Effective context engineering for AI agents」 | 長期タスクの 3 技法 = compaction / 構造化メモ(ノート)/ サブエージェント。compaction は「何を残すかの選択が芸で、やりすぎると微妙だが重要な文脈を失う」。軽量で有効なのは tool result clearing(古いツール結果を消す)。必要時にパスから読む JIT 読込 |
| Anthropic「Effective harnesses for long-running agents」 | 「compaction isn't sufficient」「compaction doesn't always pass perfectly clear instructions to the next agent」。解は、毎セッション新規開始 + progress ファイル + feature list + git log を最初に読む + 1 セッション 1 機能 |
| 「Lost in Compaction」(arXiv 2608.11242) | 「確認するまで削除しない」のようなセッション制約は、現行のコンパクタで**平均 17% しか残らない**。制約抽出を別モジュールにすると 90% 超 |
| 「Governance Decay」(arXiv 2606.22528) | 制約が見えている間は違反 0%、コンパクションで消えると 30〜59%。**Constraint Pinning**(制約を要約の外に隔離)で 0% に戻る |
| 「Slipstream」(arXiv 2605.08580) | 要約者は「後で何が要るか」を知らない構造的欠陥。要約をエージェントの実際の次手と突き合わせて検証すると精度 +8.8pt |
| Louis Bouchard「Why we stopped compacting」(2026) | 要約プリセットは記憶再現 38%(全保持 92%)で、cache が壊れて費用は 2 倍。総合採点では 97〜99% に見える=**静かに事実を落とす**。出力の安定した上限(cap)は 38% 削減で再現率低下なし。「shrink, don't rewrite」 |
| Manus「Context Engineering lessons」 | ファイルシステム=**復元可能な圧縮**(パスが残れば本文は捨ててよい)。todo の**復唱**で目標を文脈末尾に置き直し lost-in-the-middle を避ける。append-only で KV cache を守る |
| cc-clear-handoff / dumb-compact(Claude Code プラグイン) | /compact の代わりに「引き継ぎ文書を書いて /clear、SessionStart フックが一回限り注入」 |
| Context rot(arXiv 2606.29718 ほか) | 情報が全部あっても長さで精度が 13.9〜85% 低下。長いほど途中で諦める(premature termination) |
| Lydia Hallie ウェビナー(記事) | 作業単位で /clear、席を立つ前に /compact(cache 期限)、積み荷(CLAUDE.md・スキル・MCP)を薄く、結果は失敗分だけ、長い調査は別室、モデル・effort は最初に決める、/usage の「>150k context」行を見る |

### 追加の実測: 空白時間でのキャッシュ再作成

canvas-generalization のセッション(圧縮 0 回)では、人間待ち等で 75〜1538 分の空白が 6 回あり、そのたびに 47〜83 万トークンを**全額で**キャッシュ再作成していた(合計 448 万トークン。セッション全体のキャッシュ作成 712 万の 6 割)。このアカウントの cache 期限は 1 時間なので、「待ち」に入る時点で文脈を捨てていれば、この分はゼロになり、再開も軽い。

### 方針の修正

- 長文脈(context rot)もコンパクション(制約の取りこぼし)も精度を落とす。両方を避ける唯一の形が「**正本はファイル、セッションは使い捨て**」で、このハーネスは既にその設計(state.md / goal-frame / goal-plan / assumptions / decisions / call-log、NFR-04)。足りないのは次の 4 つ。
  1. 再開に必要なものを**スクリプトが**組む(モデルの要約を挟まない = 取りこぼしが構造的に起きない)
  2. /clear の後に**自動で注入**する(手で貼らない)
  3. 境界を手順にする(どこで捨てるか)
  4. 再開直後に**復唱で検証**する
- 否定リスト・承認基準・制約・「待ち」の内容は、再開パケットに**原文で必ず**入れる(Constraint Pinning)。

### 改善案 A の差し替え: A′ 境界リセット(/clear + 再開パケット)

- **境界**: (a) 人間待ちに入るとき(state.md の「待ち」を書いた直後)(b) B-6 PASS の中間クローズ後 (c) Checkpoint ACCEPT の確定処理後 (d) A-8 承認後。代理 Fable が生きている A-1a〜A-4 の間は切らない。
- **`bin/resume-packet.ps1 -GoalDir`**: 固定順・決定論的に次を連結して出す(目安 10〜20KB)。
  state.md 全文 / goal-frame.md の「制約」「承認基準」「終了条件」節(原文)/ 否定リスト(policy.md から原文)/ 対象マイルストーン定義(goal-plan.md の該当節)/ assumptions.md の未検証行 / 直近の gate-decision・escalation の判定行 / 直近 retro の「次回変えること」/ 「待ち」の内容 / impl-runs・codex-runs の未完了ラベル(`.prompt` があって `.report` / `.exit` が無いもの)
- **SessionStart フック**(plugin の hooks.json に追加): cwd のゴールループが active で `<goal-dir>/resume-pending` の印があれば、パケットを additionalContext として注入して印を消す(一回限り)。印は Opus が「state.md 更新 → 印 → /clear」の手順で置く。
- **復唱**: 再開した Opus は最初の応答で「フェーズ / マイルストーン / 次のゲート / 待ち」をパケットから復唱する(起動時チェック 3 を強化)。各フェーズの入口でも state.md を再読する(Manus の recitation)。不一致は hook-log に記録(G に含める)。
- **期待**: 平均文脈 49 万 → 10〜15 万。空白時のキャッシュ再作成 448 万 → ほぼ 0。精度は「残すものをスクリプトが決める」ので要約の取りこぼしが起きない。retro の「次回変えること」が毎回目に入るので、教訓の再発にも効く。

### 追加の改善案

- **H. 積み荷を薄くする**: Opus が毎セッション読む SKILL.md 47KB + policy.md 18KB + roles.md 13KB(約 78KB)。SKILL.md を「共通」「ワークフロー A」「ワークフロー B + Learning」に分け、state.md の phase に応じて該当分だけ読む(JIT)。roles.md は Fable 依頼文に貼る節だけ読む。見込み 78KB → 30〜40KB。
- **I. 出力の上限(切り詰め、要約しない)**: テスト実行などのシェル結果は「失敗分だけ」。`codex-status` / `impl-check` は既に短い KV 形式なので対象外。切り詰めは要約と違って cache を壊さない。
- **J. 計測に「再開の正確さ」を足す**: 復唱と state.md の不一致、再開直後の最初のゲート判定の結果を hook-log / retro に残す。

### 進め方(修正)

1. **v0.9**: A′(resume-packet + SessionStart フック + 手順)+ B(記帳スクリプト)+ C(再委譲差分)+ H(SKILL.md 分割)。E・F・I は 1 行追加で同梱。
2. D(ゲート Fable のスクリプト化)はスパイク後に v0.10。
3. 記事の対応表: #10 作業単位で /clear → A′ / #14 席を立つ前に /compact → A′(/clear の方が安く正確)/ #5〜7 積み荷 → H / #8 失敗分だけ → I / #9 別室 → E / #4 @ は 1 回 → C / #12 最初に決める → 起動時チェック 2 で済んでいる / #15 /usage → G。

## 測り方のメモ

- Opus メイン: `~/.claude/projects/<project>/<session>.jsonl` の assistant 行 `usage`(input + cache_creation + cache_read = その時点の文脈)。
- サブエージェント: 同ディレクトリの `<session>/subagents/agent-*.jsonl`。
- codex: `codex-runs/<label>.out.jsonl` 末尾の `turn.completed` の `usage`(スレッド累計)。
- 集計スクリプト(`scripts/` に保存。G でスキルの `bin/` へ移す予定): `node scripts/ctx-breakdown.js <session.jsonl>`(文脈の内訳・軌跡・大きなツール結果)/ `node scripts/turn-kinds.js <session.jsonl>`(ターン種別とユーザー側テキストの内訳)。
