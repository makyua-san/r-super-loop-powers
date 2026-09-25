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
  実行: Opus 5.5メイン  判定・代理: Fableサブ  技術PM・実装: codex exec
```

## ループ強度

- **MVP(既定)**: Fableヒアリング → HOW委任(代理ブレスト: Fable=ユーザー目線 / 技術PM=Codex astra・effort maxによるHOW回答+実装アセス) → マイルストーン自律進行(実装はCodex solがアセスに従って実行)(Fableゲート+中間コミット) → Checkpointでのみ評価パッケージ+Human Acceptance。人間の関与は「ヒアリング回答 / Goal Frame確定 / Goal Plan承認(WHATレベル) / ASK_HUMAN応答 / Checkpoint受け入れ」の5点
- **高信頼**: 人間参加のブレスト・タスク分解・diff確認・独立レビュー・フルテスト・マイルストーン毎Acceptance
- Goal Frame作成時にFableが提案し、人間が確定する。FableゲートとHuman Acceptanceは両強度で維持される

## 前提

- Claude Code + Superpowersプラグイン(改造不要)
- Codex CLI **0.153.0 以上**(`codex login` 済み)。モデル・サンドボックス・effort はスキル側が明示的に渡すため `~/.codex/config.toml` には依存しない
- Windows PowerShell 5.1(委譲ヘルパーの実行環境)
- 対象プロジェクトによっては Codex の `trust_level` 設定(`~/.codex/config.toml` の `[projects]`)が必要になる場合がある
- ゴール開始時にプリフライト(`bin/codex-preflight.ps1`)が走り、codex実体・バージョン・認証・モデル疎通・**書き込み可否**を確認する。ここで止まった場合は表示された `REASON:` に従う
- メインセッションは **Opus 5.5**(`/model opus`。aliasは最新Opus=5.5に解決される)で運用する(Fable消費をヒアリング・代理回答・承認ゲートに限定するため)

## インストール

```
/plugin marketplace add C:\Users\makyu\Desktop\project\r-super-loop-powers
/plugin install r-super-loop-powers@r-super-loop-powers-marketplace
```

インストール後、Claude Codeを再起動し、スキル一覧に `r-super-loop-powers` が出ることを確認する。

## 使い方

- **新規ゴール**: 対象プロジェクトで `/r-super-loop-powers` を起動し、やりたいこと(Goal Seed)を伝える
- **再開**: 同じコマンドで起動すると `docs/r-super-loop-powers/*/state.md` から現在地を復元する

フェーズの流れ(MVP): ヒアリング(Fable往復・無自覚の既知の表面化) → Goal Frame(強度確定) → ブレスト/Spec/Plan(Fable代理回答+技術PM回答・Checkpoint配置) → Goal Gate(Fable) → 人間承認(WHATレベル) → マイルストーン自律実装(codex exec → Fableゲート → 判断記録+グラレコ+中間コミット) → Checkpoint: 評価パッケージ → 人間受け入れ → 確定 → 振り返り

### 役とモデル(Claude版)

| 役 | モデル / effort | 担当 |
|---|---|---|
| メイン | Opus 5.5(`/model opus`) | 進行管理・成果物作成・代理ブレストでの問いの振り分け |
| 代理Fable | Fable(`Agent model: fable`) | ヒアリング駆動・Goal Frame・代理ブレストの**ユーザー目線**の回答と設計承認 |
| ゲート・判断Fable | Fable(`Agent model: fable`、呼び出し毎に新規) | 承認ゲート・マイルストーン開始確認・エスカレーション判定・REJECT後の戻り先決定 |
| 技術PM | codex `gpt-6-astra` / max / read-only | 代理ブレストで**HOWに係る問い**に実装責任者として回答し、A-4末にマイルストーン別の実装アセスを出す |
| 実装 | codex `gpt-6-sol` / B-1でFableが選択(low〜max。スクリプト既定 low) | 技術PMのアセスに従う実行者として実装と自己検証(プラグイン無効・ブレスト/計画はしない) |
| 独立レビュー(高信頼のみ) | Opus 5.5(`Agent model: opus`) | B-5の独立レビュー |

## E2Eテスト(導入・改訂時に1周まわす)

小さなプロジェクトで1ゴール(中間マイルストーン1つ以上+Checkpoint1つ以上)を実行し、以下を確認する:

- [ ] state.md 不在時に新規ゴール開始フローに入る
- [ ] MVP選択時、A-1aでFable駆動のヒアリング往復が行われ、hearing-log.md に記録される
- [ ] ヒアリングの質問にHOW質問(UI形式・実装方式の選択)が含まれない
- [ ] goal-frame.md に「ヒアリングで表面化した既知」があり、ループ強度が提案→人間確定される
- [ ] MVPのブレスト(A-2〜A-4)でユーザー目線の質問・設計承認が代理Fableに、HOWの質問が技術PMに向かい、人間にはASK_HUMAN該当のみ届く
- [ ] 技術PMが `codex-run.ps1 -Sandbox read-only -Effort max` で起動され、`STATUS: OK` の回答だけが採用される(コードを変更していない)
- [ ] goal-plan.md の主要設計判断に、Fable代理回答 / 技術PM回答のどちらを根拠にしたかが記録されている
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
- [ ] call-log.md に fable往復 / opus-sub / codex-techpm / codex の呼び出しが記録されている
- [ ] grareco.png が組み込み image_gen ツールで生成される(スクリプト・APIキー使用なし)
- [ ] セッションを切って再起動 → state.md から現在地が復元される
- [ ] 高信頼強度ではv0.2のフロー(人間参加ブレスト・マイルストーン毎Acceptance)が維持される

## リポジトリ構成

- `.claude-plugin/` — Claude版プラグインマニフェスト・マーケットプレイス定義
- `skills/r-super-loop-powers/` — Claude版 SKILL.md(オーケストレーター) / policy.md(運用ポリシー) / templates/(9種、Codex版の原本) / `bin/`(codex委譲ヘルパー) / `schemas/`(実装報告スキーマ) / `references/`(codex呼び出し規約)
- `.codex-plugin/` — Codex版プラグインマニフェスト(`plugin.json`)
- `.agents/plugins/` — Codex版マーケットプレイス定義(`marketplace.json`)
- `skills-codex/r-super-loop-powers/` — Codex版 SKILL.md / policy.md / schemas/(ゲート判定・エスカレーション判定の構造化出力スキーマ) / templates/(9種、`skills/` からの複写)
- `scripts/` — `sync-templates.ps1`(templatesの複写・一致検証)
- `docs/superpowers/specs/` — 設計仕様書
- `docs/superpowers/plans/` — 実装計画

---

## Codex版(協調サブエージェント対応環境)

Claude Code 版と同じゴールループを、Codexの協調サブエージェントで回すための移植版です。工程(A-0〜A-8 / B-1〜B-10)・成果物契約・ゲート規律は維持し、各役をdriverから直接委譲します。実行環境に `collaboration.spawn_agent` / `followup_task` / `send_message` / `list_agents` / `wait_agent` / `interrupt_agent` と独立コンテキスト指定(`fork_turns: "none"`)が必要です。CLIをインストールしただけではこの実行条件を満たすとは限りません。判定検証用にPowerShell 7の `pwsh` も必要です。

初期移植設計: `docs/superpowers/specs/2026-08-31-r-super-loop-powers-codex-port-design.md`。現在の実行方式は[協調サブエージェント移行設計](docs/superpowers/specs/2026-09-23-collaboration-backend-design.md)を優先します。

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

### 実行方式と検証範囲

`codex exec` のネスト起動とその事前プローブを必須条件から外しました。旧方式のS2では内側プロセスを起動するWindowsサンドボックスが失敗しましたが、直接の `codex exec` や通常のエージェント委譲全体が不能という結果ではありません([当時の検証記録](docs/superpowers/notes/2026-09-23-codex-github-install-smoke.md))。

新方式はdriverが各役を `fork_turns: "none"` で作成し、役ごとの必要資料を明示的に渡します。これは会話履歴と役割の分離です。共有ファイルシステムへのアクセスをOSが遮断するものではなく、judge/proxyにはファイル探索・ツール利用を禁止する指示を付けます。OSレベルのアクセス隔離が必要な用途では別の実行基盤が必要です。

導入(S1)の実測はv0.1.0に対する結果です。協調方式の検証範囲は[移行検証記録](docs/superpowers/notes/2026-09-23-collaboration-backend-smoke.md)を参照してください。以下のE2Eチェックリストは完走時に別途確認します。

### 役とモデル

| 役 | モデル / effort | 担当 |
|---|---|---|
| driver | gpt-5.6-sol / medium | メインセッション。進行管理と成果物作成 |
| proxy | gpt-5.6-sol / max | ヒアリング駆動・Goal Frame・MVPの代理ブレスト回答 |
| judge | gpt-5.6-sol / ultra | 承認ゲート・エスカレーション判定・REJECT後の戻り先決定 |
| builder | gpt-5.6-luna / max | 実装と自己検証 |
| reviewer | gpt-5.6-sol / max | 高信頼強度の独立レビュー(B-5) |

サブ役はすべてdriverが協調サブエージェントとして直接作成します。proxyのみ同じagentへ `followup_task` で往復し、judgeは判定ごとに新規作成します。judge/proxyには必要文書の本文だけを渡し、builder/reviewerには対象spec・planと作業に必要なソース範囲を指定します。独立した作業は同時委譲できますが、同じファイルの変更や依存する工程は直列化し、ゲートは必要な結果が揃ってから実行します。

### Claude版との差分

- 役名: Opus / Fable / Codex → driver / judge / proxy / builder / reviewer
- ゲート判定はJSONで返させ、`schemas/gate-verdict.json` と同梱の `scripts/validate-verdict.ps1` で形式・意味条件を検証(PASS / REVISE / REPLAN / BLOCKED)。検証失敗をPASSとして扱わない
- 代理役のIDは `state.md` の `proxy-agent:` に記録する。同一実行環境で存在確認できる場合だけ再利用し、セッションを跨ぐ場合・消失時は保存文書から新規proxyへ文脈を復元する。旧 `proxy-session:` はCLIセッションIDなので流用しない
- テンプレート9枚は Claude 版と同一。原本は `skills/r-super-loop-powers/templates/` で、`scripts/sync-templates.ps1` が `skills-codex/` 側へ複写する

### E2Eチェックリスト(Codex版)

新規の小規模プロジェクトで MVP 強度・中間マイルストーン1つ以上・Checkpoint1つ以上を完走して確認する。

- [ ] 1. `$r-super-loop-powers` で起動し、起動時チェック5項目が実行される
- [ ] 2. driver が `gpt-5.6-sol` / medium でない場合に `/model` 切替提案が出て、承諾か明示的続行までフェーズ作業が始まらない
- [ ] 3. `docs/r-super-loop-powers/<goal-slug>/` 一式が作成される(state.md / goal-seed.md / hearing-log.md / assumptions.md / call-log.md)
- [ ] 4. A-1a で独立コンテキストのproxyが起動し、返されたagent IDが `state.md` の `proxy-agent:` に記録される
- [ ] 5. A-1a の質問がそのまま人間へ提示され、回答が hearing-log.md に記録され、`followup_task` で往復する
- [ ] 6. proxy が HOW を質問せず、無自覚の既知(暗黙の前提・避けたい体験・優先順位)を掘る質問を返す
- [ ] 7. A-1b で goal-frame.md が生成され、人間がループ強度を確定する
- [ ] 8. A-2〜A-4 で `$superpowers:brainstorming` が起動し、質問の相手が proxy になる
- [ ] 9. proxy がユーザー固有判断の問いに `ASK_HUMAN:` を返し、それだけが人間へ提示される
- [ ] 10. goal-plan.md にマイルストーン一覧と Checkpoint 印、「主要設計判断(proxy代理回答による)」欄がある
- [ ] 11. A-6 で新規judgeが `fork_turns: "none"` で起動し、返したJSONが検証スクリプトを通過する。不正JSON・不整合なPASSでは進まない
- [ ] 12. judge/proxyに全会話や生コードを渡さず、ツール利用・担当外探索がないことを実行履歴で確認する(ファイルアクセス権の隔離を意味しない)
- [ ] 13. A-8 の承認提示が WHAT レベル(spec/plan は参照リンクのみ)である
- [ ] 14. B-2 で builder が `gpt-5.6-luna` / max で起動し、`builder-report.md` に自己検証報告を残す
- [ ] 15. builder が git コミットをしていない
- [ ] 16. decisions.md が4区分で作成される
- [ ] 17. B-6 の PASS 後、非Checkpointマイルストーンは人間承認なしで次のB-1へ進む
- [ ] 18. Checkpoint到達時のみ human-report.md が作られ、受け入れテストが依頼される
- [ ] 19. judgeのagent IDがproxy/builder/reviewerと異なり、判定ごとに新規作成されている(call-log.md と実行履歴で確認)
- [ ] 20. call-log.mdの役欄が `judge|proxy|builder|reviewer` の4語のみで、agent ID・model/effort・入力・出力・失敗も記録される
- [ ] 21. Checkpoint の ACCEPT 後に確定コミットが行われ、retro.md が作成される
- [ ] 22. 依存しない作業だけが並列委譲され、全必須結果の確認前にゲートへ進まない
- [ ] 23. 旧CLI状態・消失したproxy IDから、必要文書だけで新規proxyを復元できる
- [ ] 24. 協調ツール不在・起動失敗は明示して停止し、ネストCLIやdriverによる自己判定へ暗黙に切り替えない
