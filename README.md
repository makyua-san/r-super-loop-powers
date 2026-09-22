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

- `.claude-plugin/` — Claude版プラグインマニフェスト・マーケットプレイス定義
- `skills/r-super-loop-powers/` — Claude版 SKILL.md(オーケストレーター) / policy.md(運用ポリシー) / templates/(9種、Codex版の原本)
- `.codex-plugin/` — Codex版プラグインマニフェスト(`plugin.json`)
- `.agents/plugins/` — Codex版マーケットプレイス定義(`marketplace.json`)
- `skills-codex/r-super-loop-powers/` — Codex版 SKILL.md / policy.md / schemas/(ゲート判定・エスカレーション判定の構造化出力スキーマ) / templates/(9種、`skills/` からの複写)
- `scripts/` — `sync-templates.ps1`(templatesの複写・一致検証)
- `docs/superpowers/specs/` — 設計仕様書
- `docs/superpowers/plans/` — 実装計画

---

## Codex版(Codex CLI)

Claude Code 版と同じゴールループを Codex CLI 単体で回すための移植版です。工程(A-0〜A-8 / B-1〜B-10)・成果物契約・ゲート規律は Claude 版と同一で、モデル運用層だけが異なります。

設計仕様: `docs/superpowers/specs/2026-08-31-r-super-loop-powers-codex-port-design.md`

### 導入時の注意(導入コマンドを実行する前にお読みください)

- **インストール先は `CODEX_HOME` に従います。** 環境変数 `CODEX_HOME` が設定されている場合、`~/.codex/config.toml` ではなくそちらの config.toml に登録されます。普段 Codex を起動している環境で導入コマンドを実行してください。
- `codex plugin marketplace add` にローカルパスを渡すと、そのパスに対して `trust_level = "trusted"` が config.toml へ自動追加されることがあります(実測)。
- 取り消しは `codex plugin remove r-super-loop-powers@r-super-loop-powers-marketplace` と `codex plugin marketplace remove r-super-loop-powers-marketplace` です。`trust_level` のエントリはこれらでは消えない可能性があります。誤った `CODEX_HOME` に導入した場合、きれいには戻せない可能性があります。

### 導入

```bash
codex plugin marketplace add makyua-san/r-super-loop-powers
codex plugin add r-super-loop-powers@r-super-loop-powers-marketplace
```

**この GitHub 形式の導入コマンドは検証済みです。** 2026-09-23、Windows 11 / codex-cli 0.146.0 で、マーケットプレイス登録・プラグイン導入・新規 `codex exec` セッションからのスキル認識を確認しました。検証範囲と再現手順は[導入検証記録](docs/superpowers/notes/2026-09-23-codex-github-install-smoke.md)を参照してください。これは導入(S1)の確認であり、ネスト実行(S2)やゴールループ全体のE2E完走を意味しません。GitHub形式で失敗する場合は、リポジトリをクローンしてローカルパスで登録してください(ローカルパス形式もスモークテストS1で実測済み)。

```bash
codex plugin marketplace add "<クローンしたリポジトリの絶対パス>"
codex plugin add r-super-loop-powers@r-super-loop-powers-marketplace
```

起動: Codex セッション内で `$r-super-loop-powers`

スキル名は `$` を入力すると補完候補に出ます。環境によっては `r-super-loop-powers:r-super-loop-powers` の形(プラグイン名:スキル名)で表示されることがあるので、実際に表示された名前を選んでください。

### 未検証事項: ネスト実行(S2)

このプラグインの設計は、親Codexセッションの中からサブ役(judge / proxy / builder / reviewer)を `codex exec` でネスト実行できることに全面的に依存していますが、この動作(S2)は検証環境の固有事情により**判定不能**のままです。2026-09-23の再試行もWindowsサンドボックスのシェル起動エラーで停止しました([検証記録](docs/superpowers/notes/2026-09-23-codex-github-install-smoke.md))。導入後、実ターミナルで一度確認することを推奨します。プローブコマンドは `docs/superpowers/notes/2026-08-31-codex-smoke.md` の「ユーザーの実ターミナルでの再確認が必要な項目」にあります(SKILL.mdの起動時チェックでも毎ゴール初回に自動確認されます)。

### 役とモデル

| 役 | モデル / effort | 担当 |
|---|---|---|
| driver | gpt-5.6-sol / medium | メインセッション。進行管理と成果物作成 |
| proxy | gpt-5.6-sol / max | ヒアリング駆動・Goal Frame・MVPの代理ブレスト回答 |
| judge | gpt-5.6-sol / ultra | 承認ゲート・エスカレーション判定・REJECT後の戻り先決定 |
| builder | gpt-5.6-luna / max | 実装と自己検証 |
| reviewer | gpt-5.6-sol / max | 高信頼強度の独立レビュー(B-5) |

サブ役はすべて `codex exec` サブプロセスとして起動され、proxy のみ `codex exec resume` で往復します。judge と proxy は必要文書だけをコピーした一時ディレクトリで起動し、対象プロジェクトの生コードを渡しません(PL-009)。

### Claude版との差分

- 役名: Opus / Fable / Codex → driver / judge / proxy / builder / reviewer
- ゲート判定は `schemas/gate-verdict.json` による構造化出力(PASS / REVISE / REPLAN / BLOCKED)
- 代理役の文脈は `state.md` の `proxy-session:` に記録され、**セッションを跨いで復元できる**(Claude版にはない)
- テンプレート9枚は Claude 版と同一。原本は `skills/r-super-loop-powers/templates/` で、`scripts/sync-templates.ps1` が `skills-codex/` 側へ複写する

### E2Eチェックリスト(Codex版)

新規の小規模プロジェクトで MVP 強度・中間マイルストーン1つ以上・Checkpoint1つ以上を完走して確認する。

- [ ] 1. `$r-super-loop-powers` で起動し、起動時チェック5項目が実行される
- [ ] 2. driver が `gpt-5.6-sol` / medium でない場合に `/model` 切替提案が出て、承諾か明示的続行までフェーズ作業が始まらない
- [ ] 3. `docs/r-super-loop-powers/<goal-slug>/` 一式が作成される(state.md / goal-seed.md / hearing-log.md / assumptions.md / call-log.md)
- [ ] 4. A-1a で proxy が起動し、session id が `state.md` の `proxy-session:` に記録される
- [ ] 5. A-1a の質問がそのまま人間へ提示され、回答が hearing-log.md に記録され、`codex exec resume` で往復する
- [ ] 6. proxy が HOW を質問せず、無自覚の既知(暗黙の前提・避けたい体験・優先順位)を掘る質問を返す
- [ ] 7. A-1b で goal-frame.md が生成され、人間がループ強度を確定する
- [ ] 8. A-2〜A-4 で `$superpowers:brainstorming` が起動し、質問の相手が proxy になる
- [ ] 9. proxy がユーザー固有判断の問いに `ASK_HUMAN:` を返し、それだけが人間へ提示される
- [ ] 10. goal-plan.md にマイルストーン一覧と Checkpoint 印、「主要設計判断(proxy代理回答による)」欄がある
- [ ] 11. A-6 で judge が一時ディレクトリで起動し、`gate-verdict.json` 準拠のJSONを返す
- [ ] 12. judge が一時ディレクトリ外の対象リポジトリのファイルを読めない(例: README.md 等の読み取りが FAILED になる。C9 の隔離効果の確認)
- [ ] 13. A-8 の承認提示が WHAT レベル(spec/plan は参照リンクのみ)である
- [ ] 14. B-2 で builder が `gpt-5.6-luna` / max で起動し、`builder-report.md` に自己検証報告を残す
- [ ] 15. builder が git コミットをしていない
- [ ] 16. decisions.md が4区分で作成される
- [ ] 17. B-6 の PASS 後、非Checkpointマイルストーンは人間承認なしで次のB-1へ進む
- [ ] 18. Checkpoint到達時のみ human-report.md が作られ、受け入れテストが依頼される
- [ ] 19. proxy の session id が judge に `resume` されていない(call-log.md と実行履歴で確認)
- [ ] 20. call-log.md が `judge|proxy|builder|reviewer` の4語のみで記録されている
- [ ] 21. Checkpoint の ACCEPT 後に確定コミットが行われ、retro.md が作成される
