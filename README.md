# r-super-loop-powers

Superpowersの上位に薄く重なる**ゴールループ・オーケストレーション層**。
目的は (1) ゴールループの管理 (2) 適切なヒューマン・イン・ザ・ループの配置 (3) 適切なモデルの使用 — による効率化・安定化・精度向上。作業そのものの進め方はSuperpowersに委ね、内部には一切干渉しない。

```
人間  ──(Goal Seed / 受け入れ)──┐
                                │
┌───────────────────────────────▼──────────────┐
│ r-super-loop-powers(責任・ゲート層)          │
│  フェーズ / 成果物契約 / Fableゲート / HITL  │
├──────────────────────────────────────────────┤
│ Superpowers(実行プロセス層)                  │
│  brainstorming / writing-plans / TDD ...     │
└──────────────────────────────────────────────┘
  実行: Opusメイン  判定: Fableサブ  実装: codex exec
```

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

フェーズの流れ: Goal Frame(Fable) → ブレスト/Spec/Plan(Opus+Superpowers) → Goal Gate(Fable) → 人間承認 → タスク実装(codex exec) → 独立レビュー(Opus) → Implementation Gate(Fable) → Human Review Report → 人間受け入れ → 確定コミット → 振り返り+グラレコ

## E2Eテスト(初回導入時に1周まわす)

小さなダミープロジェクトで1ゴール1マイルストーンを実行し、以下を確認する:

- [ ] state.md 不在時に新規ゴール開始フローに入る
- [ ] goal-frame.md がFableサブエージェントにより生成される
- [ ] brainstorming / writing-plans がSuperpowers標準フローのまま動く
- [ ] Goal Gate が PASS するまで人間承認を求められない
- [ ] codex exec がコミットを作らない
- [ ] 独立レビュー(opus-sub)が submission.md に反映される
- [ ] Implementation Gate PASS 前に human-report.md が出てこない
- [ ] ACCEPT 記録前に確定コミットが行われない
- [ ] retro.md と grareco-input.md(+ grareco.png)が生成される
- [ ] call-log.md に fable / opus-sub / codex の呼び出しが記録されている
- [ ] セッションを切って再起動 → state.md から現在地が復元される

## リポジトリ構成

- `.claude-plugin/` — プラグインマニフェスト・マーケットプレイス定義
- `skills/r-super-loop-powers/` — SKILL.md(オーケストレーター) / policy.md(運用ポリシー) / templates/(6種)
- `docs/superpowers/specs/` — 設計仕様書
- `docs/superpowers/plans/` — 実装計画
