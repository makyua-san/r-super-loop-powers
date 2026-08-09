# r-super-loop-powers

Superpowersの上位に薄く重なる**ゴールループ・オーケストレーション層**。

Goal Loopの目的は **A. 要件適合性**(作りたかったものを正しく作れているか)と **B. 未知の低減**(最初には分からなかった正解を、作りながら発見する)の2つ。品質最大化・速度最大化は目的ではない。AIが未知に仮説を立てて評価可能な具体物まで作り、人間は評価とフィードバックを担う。作業そのものの進め方はSuperpowersに委ね、内部には一切干渉しない。

```
人間  ──(Goal Seed / 強度確定 / 評価)──┐
                                       │
┌──────────────────────────────────────▼───────┐
│ r-super-loop-powers(責任・ゲート層)          │
│  フェーズ / 成果物契約 / Fableゲート / HITL  │
│  ループ強度 / 仮定台帳 / 残存未知の管理      │
├──────────────────────────────────────────────┤
│ Superpowers(実行プロセス層)                  │
│  brainstorming / writing-plans / TDD ...     │
└──────────────────────────────────────────────┘
  実行: Opusメイン  判定: Fableサブ  実装: codex exec
```

## ループ強度

- **MVP(既定)**: E2E価値単位でまとめて実装。独立レビュー省略。検証は受け入れ基準+未知低減に効くもののみ
- **高信頼**: タスク分解・diff確認・独立レビュー・フルテスト
- Goal Frame作成時にFableが提案し、人間が確定する。FableゲートとHuman Acceptanceは両強度で維持される

## 前提

- Claude Code + Superpowersプラグイン(改造不要)
- Codex CLI(`codex login` 済み。モデル等は `~/.codex/config.toml` に従う)
- 対象プロジェクトによっては Codex の `trust_level` 設定(`~/.codex/config.toml` の `[projects]`)が必要になる場合がある
- メインセッションは **`/model opus`** で運用する(Fable消費を承認ゲートに限定するため)

## インストール

```
/plugin marketplace add C:\Users\makyu\Desktop\project\r-super-loop-powers
/plugin install r-super-loop-powers@r-super-loop-powers-marketplace
```

インストール後、Claude Codeを再起動し、スキル一覧に `r-super-loop-powers` が出ることを確認する。

## 使い方

- **新規ゴール**: 対象プロジェクトで `/r-super-loop-powers` を起動し、やりたいこと(Goal Seed)を伝える
- **再開**: 同じコマンドで起動すると `docs/r-super-loop-powers/*/state.md` から現在地を復元する

フェーズの流れ: Goal Frame(Fable・強度提案) → ブレスト/Spec/Plan(Opus+Superpowers、未回答の問いは仮定台帳へ) → Goal Gate(Fable) → 人間承認 → 実装(codex exec) → Submission(残存未知リスト付き) → Implementation Gate(Fable) → Human Review Report(判断の内訳付き) → 人間受け入れ → 確定コミット → 振り返り+グラレコ

## E2Eテスト(導入・改訂時に1周まわす)

小さなプロジェクトで1ゴール1マイルストーンを実行し、以下を確認する:

- [ ] state.md 不在時に新規ゴール開始フローに入る
- [ ] goal-frame.md がFableにより生成され、ループ強度が提案→人間確定される
- [ ] ブレスト中の未回答質問が assumptions.md に記録され、ループが停止しない
- [ ] brainstorming / writing-plans がSuperpowers標準フローのまま動く
- [ ] Goal Gate が PASS するまで人間承認を求められない
- [ ] codex exec がコミットを作らない
- [ ] MVP強度で独立レビュー(opus-sub)とタスク単位のdiff精読が発生しない
- [ ] submission.md に残存未知リストと仮定台帳サマリがある
- [ ] Implementation Gate PASS 前に human-report.md が出てこない
- [ ] human-report.md に判断の内訳(確定/仮説の区別)がある
- [ ] ACCEPT 記録前に確定コミットが行われない
- [ ] 人間フィードバックで発見された未知が assumptions.md に追記される
- [ ] retro.md にループ回数・所要時間・発見された未知が記録される
- [ ] call-log.md に fable / opus-sub / codex の呼び出しが記録されている
- [ ] grareco.png が組み込み image_gen ツールで生成される(スクリプト・APIキー使用なし)
- [ ] セッションを切って再起動 → state.md から現在地が復元される

## リポジトリ構成

- `.claude-plugin/` — プラグインマニフェスト・マーケットプレイス定義
- `skills/r-super-loop-powers/` — SKILL.md(オーケストレーター) / policy.md(運用ポリシー) / templates/(7種)
- `docs/superpowers/specs/` — 設計仕様書
- `docs/superpowers/plans/` — 実装計画
