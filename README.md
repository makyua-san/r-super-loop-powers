# r-super-loop-powers

Superpowersの上位に薄く重なる**ゴールループ・オーケストレーション層**。

Goal Loopの目的は **A. 要件適合性**(作りたかったものを正しく作れているか)と **B. 未知の低減**(最初には分からなかった正解を、作りながら発見する)の2つ。品質最大化・速度最大化は目的ではない。AIが未知に仮説を立てて評価可能な具体物まで作り、人間は評価とフィードバックを担う。作業そのものの進め方はSuperpowersに委ね、内部には一切干渉しない。

MVPモード(v0.3)では、人間にHOW(UI・機能構成・実装方式)の確定を求めない。開始前のFableヒアリングでゴール・文脈・暗黙の期待(無自覚の既知)を表面化し、HOWはAgentが仮説化して自律的に実装・評価する。Human Feedbackは定期ゲートではなくエスカレーション(ASK_HUMAN)であり、人間の受け入れは**Checkpoint**(ユーザー価値がEnd-to-Endで成立した点)でのみ行う。

```
人間  ──(Goal Seed / ヒアリング回答 / 強度確定 / ASK_HUMAN応答 / Checkpoint評価)──┐
                                                                                │
┌───────────────────────────────────────────────────────────────────────────────▼┐
│ r-super-loop-powers(責任・ゲート層)                                            │
│  フェーズ / 成果物契約 / Fableゲート / HITL                                    │
│  ヒアリング / 代理ブレスト / Checkpoint / 仮定台帳 / 判断記録                  │
├────────────────────────────────────────────────────────────────────────────────┤
│ Superpowers(実行プロセス層)                                                    │
│  brainstorming / writing-plans / TDD ...                                       │
└────────────────────────────────────────────────────────────────────────────────┘
  実行: Opusメイン  判定・代理: Fableサブ  実装: codex exec
```

## ループ強度

- **MVP(既定)**: Fableヒアリング → HOW委任(Fable代理ブレスト) → マイルストーン自律進行(Fableゲート+中間コミット) → Checkpointでのみ評価パッケージ+Human Acceptance。人間の関与は「ヒアリング回答 / Goal Frame確定 / Goal Plan承認(WHATレベル) / ASK_HUMAN応答 / Checkpoint受け入れ」の5点
- **高信頼**: 人間参加のブレスト・タスク分解・diff確認・独立レビュー・フルテスト・マイルストーン毎Acceptance
- Goal Frame作成時にFableが提案し、人間が確定する。FableゲートとHuman Acceptanceは両強度で維持される

## 前提

- Claude Code + Superpowersプラグイン(改造不要)
- Codex CLI(`codex login` 済み。モデル等は `~/.codex/config.toml` に従う)
- 対象プロジェクトによっては Codex の `trust_level` 設定(`~/.codex/config.toml` の `[projects]`)が必要になる場合がある
- メインセッションは **`/model opus`** で運用する(Fable消費をヒアリング・代理回答・承認ゲートに限定するため)

## インストール

```
/plugin marketplace add C:\Users\makyu\Desktop\project\r-super-loop-powers
/plugin install r-super-loop-powers@r-super-loop-powers-marketplace
```

インストール後、Claude Codeを再起動し、スキル一覧に `r-super-loop-powers` が出ることを確認する。

## 使い方

- **新規ゴール**: 対象プロジェクトで `/r-super-loop-powers` を起動し、やりたいこと(Goal Seed)を伝える
- **再開**: 同じコマンドで起動すると `docs/r-super-loop-powers/*/state.md` から現在地を復元する

フェーズの流れ(MVP): ヒアリング(Fable往復・無自覚の既知の表面化) → Goal Frame(強度確定) → ブレスト/Spec/Plan(Fable代理回答・Checkpoint配置) → Goal Gate(Fable) → 人間承認(WHATレベル) → マイルストーン自律実装(codex exec → Fableゲート → 判断記録+グラレコ+中間コミット) → Checkpoint: 評価パッケージ → 人間受け入れ → 確定 → 振り返り

## E2Eテスト(導入・改訂時に1周まわす)

小さなプロジェクトで1ゴール(中間マイルストーン1つ以上+Checkpoint1つ以上)を実行し、以下を確認する:

- [ ] state.md 不在時に新規ゴール開始フローに入る
- [ ] MVP選択時、A-1aでFable駆動のヒアリング往復が行われ、hearing-log.md に記録される
- [ ] ヒアリングの質問にHOW質問(UI形式・実装方式の選択)が含まれない
- [ ] goal-frame.md に「ヒアリングで表面化した既知」があり、ループ強度が提案→人間確定される
- [ ] MVPのブレスト(A-2〜A-4)で設計質問・設計承認が代理Fableに向かい、人間にはASK_HUMAN該当のみ届く
- [ ] goal-plan.md にCheckpoint印と主要設計判断欄があり、最終マイルストーンがCheckpointである
- [ ] Goal Gate が代理Fableとは別の新規Fableインスタンスで行われ、PASSするまで人間承認を求められない
- [ ] A-8で人間に提示されるのがWHATレベル(ゴール・要件・制約・Checkpoint配置・主要仮定)である
- [ ] codex exec がコミットを作らない
- [ ] 非Checkpointマイルストーンで B-6 PASS後、人間承認なしで次マイルストーンへ進む(decisions.md・グラレコ・中間コミットが残る)
- [ ] Checkpoint到達時のみ評価パッケージ(human-report.md)とHuman Acceptanceが行われる
- [ ] 評価パッケージに各マイルストーンの decisions.md 集約(Agent仮説HOW / 低確信 / 実装対象外 / 新発見の未知)がある
- [ ] エスカレ判定が DECIDE / ASK_HUMAN の2値で返り、ASK_HUMANのみ人間へ届く
- [ ] Checkpoint の ACCEPT 記録前に確定処理が行われない(中間コミットは可)
- [ ] 人間フィードバックで発見された未知が assumptions.md に追記される
- [ ] retro.md がCheckpoint単位で作成され、ループ回数・所要時間・発見された未知が記録される
- [ ] call-log.md に fable往復 / opus-sub / codex の呼び出しが記録されている
- [ ] grareco.png が組み込み image_gen ツールで生成される(スクリプト・APIキー使用なし)
- [ ] セッションを切って再起動 → state.md から現在地が復元される
- [ ] 高信頼強度ではv0.2のフロー(人間参加ブレスト・マイルストーン毎Acceptance)が維持される

## リポジトリ構成

- `.claude-plugin/` — プラグインマニフェスト・マーケットプレイス定義
- `skills/r-super-loop-powers/` — SKILL.md(オーケストレーター) / policy.md(運用ポリシー) / templates/(9種)
- `docs/superpowers/specs/` — 設計仕様書
- `docs/superpowers/plans/` — 実装計画
