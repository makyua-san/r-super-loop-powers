# r-super-loop-powers v0.3 設計仕様書 — MVPモードのHOW委任とHuman Feedbackのエスカレーション化

- 日付: 2026-08-18
- ステータス: Approved (ブレインストーミング承認済み)
- 前版: `2026-08-10-r-super-loop-powers-v0.2-design.md`(v0.2。本書に書かれていない事項はv0.2以前の決定が引き続き有効)
- 入力: `20260818_ハーネス改善-2.md`(2回目の実地テストから得た課題整理)

## 0. 上位原則への追記(v0.2 §0 に追加)

v0.2の2目的(A. 要件適合性 / B. 未知の低減)は変更しない。以下をMVPモードの原則として追加する:

> MVPモードでは、人間にHOWの詳細確定を原則として求めない。その代わり、開発開始前のヒアリングでGoal・Requirements・Constraints・利用文脈・暗黙の期待を十分に探索し、ユーザーの「無自覚の既知」を可能な限り表面化する。Agentはその情報を根拠として、まだ正解の存在しないHOWを仮説として具体化し、自律的に実装・評価・改善する。Human Feedbackは各マイルストーンの必須ゲートではなく、重大な不確実性・不可逆性・低確信度の判断に対するエスカレーションとして用いる。通常はユーザー価値がEnd-to-Endで成立した段階(Checkpoint)でHuman Acceptanceを行う。

「HOWを聞かない」ことと「ヒアリングを減らす」ことを混同しない。質問の対象をHOWからGoal / Context / Preferenceへ移す。

## 1. v0.2からの問題認識(fbの課題1〜9)

- 開発特性に関係なく均一なフローが適用され、MVPには承認粒度が細かすぎた(課題1)
- ユーザーが答えを持たないHOW(UI・導線・実装方式)の判断を人間に求め、Human-in-the-loopがボトルネック化(課題2)
- HOW委任の前提となる初期ヒアリングが工程として存在しなかった(課題3)
- 詳細仕様の事前確定フローがMVPの「触らないと分からない」領域に合わない(課題4・5)
- マイルストーン毎のHuman Feedback必須ゲートで、人間の応答速度が開発速度の上限になる。中間マイルストーンはユーザー価値未完成で評価しにくい(課題6)
- 一方で途中確認ゼロは重大誤判断リスク(課題7)
- 人間が途中の意思決定に参加しなくなる分、判断履歴と評価パッケージが必要(課題8・9)

## 2. 設計決定(D21〜D33。v0.2のD10〜D20に追加)

| ID | 論点 | 決定 | 根拠 |
|---|---|---|---|
| D21 | MVPの人間関与点 | MVPモードの人間関与を5点に限定: (1) ヒアリング回答 (2) Goal Frame確定(強度含む) (3) A-8 WHATレベル承認 (4) ASK_HUMANエスカレ応答 (5) CheckpointでのAcceptance | fb課題2・6。ユーザー決定(2026-08-18) |
| D22 | Checkpoint分離 | **Checkpoint = ユーザー価値をEnd-to-Endで評価できる点**。goal-plan.mdのマイルストーン一覧に印として配置し、A-8で人間が配置を承認。MVPではマイルストーンを内部作業単位に格下げし(E2E価値の完成を要求しない)、Human Report/AcceptanceはCheckpoint到達時のみ実施。最終マイルストーンは必ずCheckpoint。v0.2 D14の粒度基準「E2E価値単位」は「1Checkpoint」に移る(高信頼は従来通りマイルストーン=E2E価値単位) | fb課題6。ユーザー決定(Checkpoint分離方式) |
| D23 | Fableヒアリング(A-1a新設) | Fableサブエージェントが質問を駆動し、Opusが人間へ中継する往復ループ。初回に開発タイプ確認(MVPか仕様重視か)を含む質問セット(3〜7問)+理解サマリを出させ、回答を hearing-log.md に記録してSendMessageで返す。Fableが「十分」と判断するまで(目安2〜4往復)。質問方針: **HOWを聞かない**。WHO/利用状況/最速で達成したいこと/現状の不満/絶対避けたい操作・体験/成功条件/優先順位を「感情・体験 → 嗜好・制約 → 検証」の順で聞く。「わからない/決めていない」は仮説化して台帳へ(D19踏襲)。高信頼確定時は深掘りを打ち切りv0.2相当の軽いA-1へ | fb課題3。ユーザー決定(Fableヒアリングフェーズ)。質問順序はClaude-Code-Game-Studiosのbrainstormスキルを参考 |
| D24 | Fable代理ブレスト | MVPではsuperpowers:brainstormingを通常通り起動するが、「人間パートナー」役を**ヒアリングを担当した同一Fableインスタンス**(SendMessage継続、文脈保持)が務める。Fableはgoal-frame + hearing-logを根拠に質問へ回答し設計を承認する。Fable自身が「ユーザー固有判断・否定リスト・エスカレ条件に該当」と判断した問いのみOpusが人間へ中継(ASK_HUMAN) | fb課題2・4。ユーザー決定(Fable代理ブレスト) |
| D25 | Fableインスタンス分離 | **代理Fable**(A-1aヒアリング〜A-4代理ブレスト。文脈保持のためSendMessage継続)と**ゲートFable**(A-6/B-6。新規インスタンス+最小コンテキスト=PL-009)を分離する。代理ブレストに参加したFableが自分の決定をゲート判定する自己承認を防ぐ | 設計上の独立性要件 |
| D26 | A-8のWHATレベル化 | MVPのA-8承認対象を「ゴール解釈・要件・制約・Checkpoint配置・仮定台帳サマリ」に限定。spec/planは参照リンク添付のみ(閲覧は自由、承認対象にしない) | fb課題4。ユーザー決定(WHATレベルで維持) |
| D27 | エスカレ条件拡張と出口2値化 | 発火条件に3件追加(§5)。Fableのエスカレ判定出力を `DECIDE`(判断を返し自律続行)/ `ASK_HUMAN`(人間向けに質問を整形して停止)の2値に明文化 | fb課題7 |
| D28 | decisions.md新設 | マイルストーン毎に `decisions.md` を作成し、B-2〜B-5の間に随時追記、B-5セルフチェック時に確定。区分: (1) 要件由来の決定 (2) Agentが仮説として決めたHOW(根拠付き) (3) 低確信の判断 (4) 発見された未知(台帳参照) | fb課題8 |
| D29 | 評価パッケージ | human-review-report.md をCheckpoint用評価パッケージに拡張。対象は**前回Checkpoint以降の全マイルストーン**で、各decisions.mdを集約。fb課題9の項目(Goal/主要Requirements/実装された価値/要件対応/Agent決定HOW/Assumptions/低確信/新発見の未知/制約/対象外/確認ポイント/グラレコ)を網羅 | fb課題9 |
| D30 | コミット規律 | MVPでは各マイルストーンのFable PASS後に**中間コミット可**(自律進行区間の作業保全)。「確定」(ゴール成果としての完了扱い)はCheckpointのACCEPT後のみ。SK-009は「Checkpoint ACCEPTなしで確定扱いしない」に再定義。高信頼は従来通りACCEPT後のみコミット | 自律進行の長期化への対応 |
| D31 | Learning再配置 | MVPではグラレコ+decisions.md確定=**マイルストーン毎**(B-6 PASS後の中間記録)、retro.md=**Checkpoint毎**(人間フィードバックが入る単位)。orca-meta導線(record_lesson)はretroに残す。高信頼は従来通り | fb改善案13 |
| D32 | A段階の判断記録 | 代理ブレスト中のFableの主要決定は goal-plan.md の「主要設計判断(Fable代理回答による)」欄に記録。人間へ中継した質問と回答は hearing-log.md に追記。SendMessage往復もcall-logに1行ずつ記録(fable) | fb課題8のA段階適用 |
| D33 | 5:1目安の適用範囲 | MVPのヒアリング・代理ブレスト期はfable往復が構造的に増えるため、PL-007の5:1目安は**ワークフローB以降**に適用と注記(観測指標のまま、PL-008維持) | D23・D24の帰結 |

## 3. MVPモードのフロー全体図

```
Goal Seed(人間)
→ A-1a Fableヒアリング      ← 新設。Fable駆動・Opus中継・hearing-log記録
→ A-1b Goal Frame確定       ← 人間が強度と方向を確定(従来A-1後半)
→ A-2〜A-4 ブレスト→Spec→Plan ← Fable代理ブレスト。人間はASK_HUMAN時のみ
→ A-5〜A-6 Goal Gate(ゲートFable・新規インスタンス)
→ A-8 Human Goal Plan承認    ← WHATレベル(ゴール解釈・要件・制約・Checkpoint配置・主要仮定)
→ ワークフローB: M1 → M2 → M3 …
   各M: B-1〜B-6(Fableゲートまで)を自律進行
   非Checkpoint M: B-6 PASS → decisions.md確定+グラレコ+中間コミット → 次MのB-1へ
→ Checkpoint到達: B-7 評価パッケージ → B-8 Human Acceptance → retro
→ 全マイルストーン完了 → done
```

高信頼モードのフローはv0.2から変更しない(ただしD28のdecisions.mdは両強度に適用する)。

## 4. 強度別工程表(v0.2 §3の改訂。変更行のみ記載、無印行は従来通り)

| 工程 | MVP(既定) | 高信頼 |
|---|---|---|
| ヒアリング(A-1a) | **Fable駆動の往復ヒアリング**(無自覚の既知の表面化。目安2〜4往復) | 軽量(v0.2相当のA-1のみ) |
| ブレスト〜Plan(A-2〜A-4) | **Fable代理回答**(人間はASK_HUMAN時のみ) | 人間参加のsuperpowers:brainstorming |
| Human Goal Plan承認(A-8) | **WHATレベル**(ゴール・要件・制約・Checkpoint配置・主要仮定) | 従来(spec/planレビュー含む) |
| B-7 Human Report / B-8 Acceptance | **Checkpoint到達時のみ** | マイルストーン毎 |
| コミット | マイルストーン毎に中間コミット可、Checkpoint ACCEPTで確定 | ACCEPT後のみ |
| Learning | グラレコ+decisions.md=マイルストーン毎 / retro=Checkpoint毎 | 従来通り(マイルストーン毎) |

## 5. エスカレーション(v0.2の7条件に追加)

発火条件に追加:

8. **ユーザー固有の判断**(好み・業務文脈・優先順位)が必要で、hearing-log / goal-frame から答えを導けない
9. **複数の合理的Solutionが存在し、選択でユーザー体験が大きく変わる**
10. **低確信かつ影響が大きい判断**(後から変更すると高コストな構造選択を含む)

出口の2値化(D27): Fableのエスカレ判定は `DECIDE | ASK_HUMAN` のいずれかを必ず返す。DECIDEは判断根拠付きで自律続行、ASK_HUMANは人間向けに整形した質問を返してOpusが人間へ提示・停止する。代理ブレスト中の人間中継もこの仕組みに乗る。

## 6. アーティファクト変更

### 6.1 hearing-log.md(新規テンプレート)

goal直下に配置。往復ごとに記録:
`ラウンド / Fableの質問 / 人間の回答 / 表面化した既知 / 仮説化して台帳へ送った未知(ID参照)`
代理ブレスト中にASK_HUMANで人間へ中継した質問・回答もここに追記する。

### 6.2 decisions.md(新規テンプレート)

`milestones/<n>-<名前>/decisions.md`。4区分で記録:
- **要件由来の決定**: Requirements → 実装の対応
- **Agentが仮説として決めたHOW**: 内容+根拠(なぜ受け入れられる可能性が高いと判断したか)
- **低確信の判断**: 特に評価パッケージで人間に見てほしい点
- **発見された未知**: assumptions.mdへの追記と対応(ID参照)

### 6.3 goal-frame.md(改訂)

「ゴールの方向」の後に **「ヒアリングで表面化した既知」** 欄を追加(hearing-logの要点サマリ。暗黙の前提・避けたい体験・成功条件など)。

### 6.4 human-review-report.md(改訂)

Checkpoint用評価パッケージへ拡張(D29)。既存の1〜6章の骨格は維持しつつ:
- 対象を「前回Checkpoint以降の全マイルストーン」とし、各decisions.mdを集約する章を追加
- 「3.5 判断の内訳」に「実装対象外としたもの」「開発中に新しく発見された未知」を追加
- グラレコへの参照を追加

### 6.5 escalation.md(改訂)

末尾に **「7. Fableの判定」** を追加: `DECIDE(判断+根拠) | ASK_HUMAN(人間向け質問文)`。

### 6.6 approval-submission.md(改訂)

Goal Plan対象時に **「Checkpoint配置」** 欄(マイルストーン一覧とCheckpoint印+配置理由)を追加。Milestone対象時に decisions.md への参照を追加。

### 6.7 retrospective-note.md(改訂)

MVPではCheckpoint単位で作成する旨を注記(観測欄・orca-meta導線は変更なし)。

### 6.8 goal-plan.md(規定の改訂)

- マイルストーン一覧にCheckpoint印を必須化(最終マイルストーンは必ずCheckpoint)
- 「主要設計判断(Fable代理回答による)」欄を追加(D32)

### 6.9 state.md(改訂)

`次のCheckpoint: <n>-<名前> または -` の行を追加。

### 6.10 policy.md(改訂)

- 上位原則にMVPモード原則(§0)を追記
- 強度別工程表を§4の内容に更新
- エスカレ発火条件8〜10と出口2値化(§5)を追加
- 責任分担表を更新: 人間(D21の5関与点)/ Fable(ヒアリング駆動・代理ブレスト回答・インスタンス分離)/ Opus(Solution仮説設計の責任を明記)
- 「Fableを呼ぶ場面」にヒアリング往復・代理ブレスト応答を追加。「原則呼ばない場面」の「ブレスト本文作成」は維持(Fableは回答者、本文はOpus)
- PL-007に5:1目安の適用範囲注記(D33)

### 6.11 SKILL.md(改訂)

- ワークフローAをA-1a/A-1bに分割、MVP時のA-2〜A-4代理ブレスト手順、A-8のWHATレベル化
- ワークフローBにB-6 PASS後の分岐(非Checkpoint→中間記録+中間コミット+次MのB-1へ / Checkpoint→B-7)
- Fable共通契約に代理Fable/ゲートFableの分離(D25)を追記
- ディレクトリ契約に hearing-log.md / decisions.md を追加
- ゲート保護ルールのSK-009をD30の定義に更新
- Learning章をD31の配置に更新

### 6.12 その他

- plugin.json / marketplace.json: version 0.3.0
- README: MVPモードのフロー図・人間関与5点・Checkpoint概念の説明、E2Eチェックリスト更新(§7の項目を反映)

## 7. 受け入れ基準(v0.3固有)

1. MVP確定時、A-1aでFable駆動のヒアリング往復が行われ、hearing-log.mdに記録される
2. ヒアリングの質問にHOW質問(UI形式・実装方式の選択)が含まれない
3. MVPのA-2〜A-4で設計質問・設計承認がFableに向かい、人間にはASK_HUMAN該当のみ届く
4. ゲート判定(A-6/B-6)が代理Fableとは別の新規Fableインスタンスで行われる
5. A-8で人間に提示されるのがWHATレベル(ゴール・要件・制約・Checkpoint配置・主要仮定)である
6. goal-plan.mdにCheckpoint印があり、最終マイルストーンがCheckpointである
7. 非CheckpointマイルストーンでB-6 PASS後、人間承認なしで次マイルストーンへ進む(decisions.md・グラレコ・中間コミットが残る)
8. Checkpoint到達時のみB-7評価パッケージ(全マイルストーンのdecisions.md集約)とB-8 Human Acceptanceが行われる
9. エスカレ判定がDECIDE / ASK_HUMANの2値で返り、ASK_HUMANのみ人間へ届く
10. 高信頼強度ではv0.2のフロー(人間参加ブレスト・マイルストーン毎Acceptance)が維持される

## 8. 検証計画

v0.3適用(コミット→plugin update→再起動)後、新規の小規模プロジェクトを**MVP強度**で開始し、ヒアリング→代理ブレスト→複数マイルストーン(中間1・Checkpoint1以上)を完走させ、§7の10項目を照合する。人間の主観評価: ヒアリングで「無自覚の既知」が実際に表面化したか、評価パッケージだけでCheckpoint判断ができたか、途中の認知負荷。
