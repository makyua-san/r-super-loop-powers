# r-super-loop-powers 設計仕様書

- 日付: 2026-08-09
- ステータス: Approved (ブレインストーミング承認済み)
- 上位文書: `goal_engineering_ai_skill_policy_requirements.docx` (要件定義 Draft v0.1)
- 対象: 新規プラグイン `r-super-loop-powers`(オーバーレイスキル + モデル運用ポリシー + テンプレート)
- 命名: 要件定義の候補名 `goal-loop-orchestrator`(仮)は標準スキル群との区別がつきにくいため、`r-super-loop-powers` に確定(ユーザー指定)。プラグイン名・スキル名・対象プロジェクトの成果物ディレクトリ名をこの名称で統一する

## 1. 概要

Superpowersを改造せず、その上位に薄い「ゴールループ・オーケストレーション層」をプラグインとして追加する。
Fableは承認ゲート・入口の基準設定・エスカレーション処理に限定して呼び出し、日常のブレスト・仕様化・計画・レビュー・レポートはOpusが、実装はCodex(`codex exec`)が担当する。人間はAI側の承認ループが完了した後に、Human Review Reportを入口として最終受け入れを行う。

### 1.1 Superpowersとの位置づけ(レイヤーモデル)

本プラグインの目的は **(1) ゴールループの管理、(2) 適切なヒューマン・イン・ザ・ループの配置、(3) 適切なモデルの使用** であり、それによって **効率化(Fable消費の最適配分)・安定化(ゲート順序と成果物契約の固定、再開性)・精度向上(独立レビューとゴール整合ゲートを人間より前に置く)** を実現する。作業そのものの進め方には介入しない。

| レイヤー | 担うもの | 担わないもの |
|---|---|---|
| **Superpowers**(実行プロセス層 = HOW) | ブレスト、仕様化、計画、TDD、subagent-driven development、デバッグ、検証など「作業をどう進めるか」の技法。各スキル内部の手順・品質基準 | フェーズ間の責任境界、モデル選定、ゴール整合の承認、人間ゲートの配置 |
| **r-super-loop-powers**(責任・ゲート層 = WHO / WHEN / WHETHER) | いまどのフェーズか、次に必要なArtifactは何か、誰(どのモデル)が実行し誰が判定するか、人間へ返すタイミング、差し戻し先の決定 | Superpowersスキルの内部手順の変更・複製・上書き |

**接続規約**:

- 本プラグインはSuperpowersスキルを**スキル名で呼び出し、標準の成果物(spec / plan等)をそのまま消費する**だけとする。内部にパッチせず、出力形式にも追加要求をしない(ゴールループ用の情報はオーバーレイ側Artifactに別途保存する)。これによりSuperpowers更新時の追従コストを最小化する(NFR-01)。
- ゲートは**Superpowersスキルの境界(入口・出口)にのみ**挿入する。スキル実行中には割り込まない。例: Goal Gate(A-6)はbrainstorming→writing-plans完了後に置かれ、brainstorming内部のHARD-GATEや質問フローには一切干渉しない。
- スキル内部の指示と本プラグインが競合した場合、**スキル実行中はスキル側が優先**、**フェーズ遷移・ゲート順序・モデル割り当てはプラグイン側が優先**する。
- Codex(`codex exec`)はSuperpowersスキルを直接利用できないため、subagent-driven developmentの**プロセス構造**(タスク分解→実装→レビューのループ)をOpusメインが駆動し、TDD等の品質要求はタスクプロンプトの受け入れ条件として伝達する。

**フェーズとSuperpowersスキルの対応**:

| フェーズ | 利用するSuperpowersスキル | 本プラグインが足すもの |
|---|---|---|
| Goal Definition | brainstorming, writing-plans | 前: Fable Goal Frame(A-1) / 後: Goal Gate(A-6)+Human承認(A-8) |
| Milestone Implementation | subagent-driven developmentのプロセス構造(実行はcodex exec)、verification-before-completion(証拠確認) | 独立レビュー(B-5)、Implementation Gate(B-6) |
| Human Acceptance | — | Human Review Report(B-7)、受け入れ記録(B-8/B-9) |
| Finalization | finishing-a-development-branch(必要に応じて) | ACCEPT前のコミット禁止(SK-009)、確定処理(B-10) |
| Learning | — | Retrospective Note、グラレコ生成(§12) |

## 2. 確定した設計決定

| ID | 論点 | 決定 | 根拠 |
|---|---|---|---|
| D1 | 配置形態 | プラグイン形式。本リポジトリがローカルマーケットプレイス兼プラグイン本体 | ユーザー選択。バージョン管理・配布に強い |
| D2 | 実行構造 | **Opus主駆動**。メインセッションは `/model opus` で運用し、FableはAgentツール(`model: fable`)のサブエージェントとしてのみ起動 | Fable消費最小化(要件11.2章)、人間との対話がOpusセッションで自然に成立 |
| D3 | Fable同一性 | 入口Fableが **Goal Frame**(方向・制約・承認基準)を生成して保存し、ゲートFableには Goal Frame + Approval Submission のみを渡す。同一性は文書で担保 | 「入口で基準を決めるFableと出口で承認するFableは同一であるべき」というユーザー要求を、要件5章の「Fable常駐不要」原則と両立させる。PL-009(コンテキスト最小化)準拠 |
| D4 | Codex呼び出し | Opusメインが subagent-driven-development のプロセス(タスク分解→実装→レビューのループ)を駆動し、各タスクの実装+自己検証を `codex exec` に委譲 | 要件の役割分担(Codex=実装)に忠実。途中検知・エスカレーション粒度を確保 |
| D5 | グラレコ | `codex exec` 経由でgpt-image-1により生成。単位は**マイルストーンごと**、Human ACCEPT後 | ユーザー確認済み(Codex側で画像生成可能)。OpenAI APIキー不要 |
| D6 | ゲート・状態管理 | 純Markdown契約(案A)。SKILL.mdの手順が「フェーズ遷移前に state.md と必須Artifactの存在を確認し、欠落なら進まない」を規定。スクリプト・hooksなし | SK-012(軽量性)、要件18章「痛点が出てから自動化」 |
| D7 | 保存場所 | 対象プロジェクトの `docs/r-super-loop-powers/<goal-slug>/` 配下(§5参照) | 要件17章の未決事項を確定 |
| D9 | 名称 | プラグイン名・スキル名・成果物ディレクトリ名を `r-super-loop-powers` に統一 | 標準スキル群(superpowers等)との区別を明確にするため(ユーザー指定) |
| D8 | コミット責任 | Human ACCEPT後にOpusメインセッションが確定コミット。`codex exec` にはコミットさせない | 要件17章原案を採用。確定制御(SK-009)を単一主体に集約 |

### 要件17章の未決事項の確定

- **マイルストーン粒度**: 1マイルストーン = 人間が5〜15分の受け入れテスト1回で確認できる振る舞い変化(実装タスク2〜8個目安)。policy.mdにガイドラインとして記載。
- **Sonnetの位置付け**: MVPでは未使用。policy.mdに将来枠としてのみ記載。
- **学習メモ注入**: Goal Frame作成時とマイルストーン開始時に、最新のRetrospective Note最大3件を自動参照する(SKILL.md手順)。
- **グラレコ生成単位**: マイルストーンごと(D5)。

## 3. スコープ / 非目的

**スコープ(MVP)**: オーバーレイスキル1個、運用ポリシー1個、テンプレート6個、README(インストール・運用手順)。

**非目的**(要件3章の再確認):
- 複雑度スコアリングによる動的モデルルーティングは作らない。
- Superpowers本体(スキルファイル・hooks)には一切触れない。
- Fableの排除は目的でない。5:1比率はハード制限にしない。
- 人間の最終受け入れ責任をAIへ移譲しない。

## 4. リポジトリ構成(本リポジトリ)

```
r-super-loop-powers/
├── .claude-plugin/
│   ├── plugin.json          # name: r-super-loop-powers
│   └── marketplace.json     # ローカルマーケットプレイス定義
├── skills/
│   └── r-super-loop-powers/
│       ├── SKILL.md         # オーケストレーター本体 (SK-001〜012を実装)
│       ├── policy.md        # モデル運用ポリシー (PL-001〜010)
│       └── templates/
│           ├── goal-frame.md
│           ├── approval-submission.md
│           ├── human-review-report.md
│           ├── retrospective-note.md
│           ├── escalation.md        # 6点フォーマット
│           └── grareco-prompt.md    # codex exec用画像生成指示
├── docs/superpowers/specs/  # 本仕様書
├── goal_engineering_ai_skill_policy_requirements.docx  # 上位要件
└── README.md
```

- スキル呼び出し名: `/r-super-loop-powers`(= `r-super-loop-powers:r-super-loop-powers`)。
- インストール: `/plugin marketplace add C:\Users\makyu\Desktop\project\r-super-loop-powers` → `/plugin install r-super-loop-powers`。

## 5. 対象プロジェクト側の成果物レイアウト

```
<対象プロジェクト>/docs/r-super-loop-powers/<goal-slug>/
├── state.md             # 現在フェーズ / 担当 / 次ゲート / 更新日時
├── goal-seed.md         # A1 人間の意図(原文のまま保存)
├── goal-frame.md        # Fable入口出力 = 方向・制約・承認基準の原本
├── goal-plan.md         # A2 (superpowers specs/plansへの相対リンクを含む)
├── call-log.md          # PL-007観測: 1呼び出し1行 (日時 / モデル / 目的)
└── milestones/<n>-<名前>/
    ├── submission.md    # A5 Opus作成のApproval Submission
    ├── gate-decision.md # A6 Fable判定 + 短い根拠
    ├── human-report.md  # A7 Human Review Report + 受け入れテスト手順
    ├── acceptance.md    # A8 ACCEPT / REJECT + コメント
    ├── retro.md         # A9 Retrospective Note
    ├── grareco-input.md # A10生成用入力(レポート要約 + 画像プロンプト)
    └── grareco.png      # A10 グラフィックレコード
```

- `<goal-slug>` はGoal Seedから生成する短いkebab-case。
- Superpowersが生成するspec/planは従来の場所(`docs/superpowers/`)に置き、goal-plan.mdからリンクする(SK-001: 非侵襲)。

## 6. フェーズ状態機械 (SK-002)

```
Goal Definition → Milestone Implementation → Human Acceptance → Finalization → Learning
      ↑                    ↑ (差し戻し)            │ (REJECT)
      └────── REPLAN ──────┴──────── Fable判断で戻り先決定
```

`state.md` は常に次を保持する: 現在フェーズ、対象マイルストーン、担当(次に動くモデル)、次のゲート、必須Artifactのチェックリスト。**全フェーズで「state.md更新 → 作業」の順**とし、セッション中断後は `/r-super-loop-powers` 起動時にstate.mdから現在地を復元する(NFR-04)。

## 7. ワークフローA: Goal Plan作成(Claude Code具体化)

| 手順 | 担当 | Claude Code上の実装 |
|---|---|---|
| A-1 入口の責任設定 | Fable | `Agent(model: fable)` にGoal Seed + 直近Retro最大3件を渡し、**Goal Frame**(方向・制約・今回確定すべきこと・承認基準)を生成 → `goal-frame.md` 保存 |
| A-2 ブレスト | Opusメイン | `superpowers:brainstorming` をそのまま起動(人間と対話) |
| A-3 Spec作成 | Opusメイン | brainstormingの標準フローで `docs/superpowers/specs/` へ |
| A-4 Plan作成 | Opusメイン | `superpowers:writing-plans` で実装計画+マイルストーン分割 → `goal-plan.md` に集約 |
| A-5 承認提出パッケージ | Opusメイン | `templates/approval-submission.md` に従い作成 |
| A-6 Goal Gate | Fable | `Agent(model: fable)` に **goal-frame.md + submission.md のみ**を渡し、PASS/REVISE/REPLAN/BLOCKED + 根拠 → `gate-decision.md` |
| A-7 差し戻し | Opusメイン | REVISE→該当工程へ、REPLAN→A-4から、BLOCKED→人間へ質問して停止 |
| A-8 Human Goal Acceptance | 人間 | Goal Planの確認と実装進行の承認 |

## 8. ワークフローB: マイルストーン実装ループ

| 手順 | 担当 | Claude Code上の実装 |
|---|---|---|
| B-1 開始確認 | Fable | `Agent(model: fable)` にgoal-frame + 対象マイルストーン定義を渡し、注意点のみ取得(軽量呼び出し) |
| B-2 実装 | Codex | Opusメインがsubagent-driven-development流にタスク分解し、各タスクを `codex exec`(cwd=対象プロジェクト)へ。タスクプロンプトには目的・対象ファイル・受け入れ条件・**コミット禁止**を明記 |
| B-3 自己検証 | Codex | 各 `codex exec` にテスト・lint・型検査の実行と証拠出力を要求 |
| B-4 エスカレーション | Codex/Opus | 検出時、Opusが6点フォーマット作成 → `Agent(model: fable)` へ(§10) |
| B-5 独立レビュー | Opusサブ | `Agent(model: opus)` で実装非関与の独立レビュー(goal-plan/milestone/diff/テスト証拠の突き合わせ)→ Opusメインがsubmission.mdに反映 |
| B-6 Implementation Goal Gate | Fable | A-6と同形式。入力 = goal-frame + milestone定義 + submission |
| B-7 Human Review Report | Opusメイン | PASS後に `templates/human-review-report.md` に従い生成 |
| B-8 Human Acceptance | 人間 | レポートを入口に受け入れテスト → `acceptance.md` |
| B-9 Human NG処理 | Fable | REJECT理由を `Agent(model: fable)` へ渡し、戻り先(修正/再計画/ゴール修正)を決定 |
| B-10 確定処理 | Opusメイン | ACCEPT後に確定コミット、state.md更新、マイルストーン完了 |

## 9. Fableサブエージェント契約

- **入力**(常にこれだけ): goal-frame.md全文 + 当該submission.md全文(+エスカレーション時は6点フォーマット)。対象プロジェクトの生コード・全会話履歴は渡さない(PL-009)。ただしFable側が必要と判断した場合は追加資料を1往復で要求できる(SendMessageで継続)。
- **出力契約**: `PASS / REVISE / REPLAN / BLOCKED` のいずれか1つ + 根拠(5行以内) + REVISE/REPLANの場合は戻り先工程の指定。
- **判定観点**: 「コードが動くか」ではなく「Goal Frameの承認基準を満たすか」。証拠不足・曖昧性・重大リスク時は無理にPASSしない(NFR-05)。

## 10. エスカレーション (SK-011)

発火条件は要件12章の6条件をpolicy.mdへ転記。フォーマット(`templates/escalation.md`):
「何をしようとしたか / 何が判断不能か / 選択肢 / 影響 / 推奨案 / いま必要な判断」の6点。
経路: 検出者(Codex出力またはOpusレビュー)→ Opusメインが6点に整形 → `Agent(model: fable)` に goal-frame + 6点のみを渡す → 判断を state.md と call-log.md に記録。

## 11. codex exec 契約

- 呼び出し形式: `codex exec`(Bashツール、cwd=対象プロジェクト)。モデル・reasoning effortはユーザーの `~/.codex/config.toml`(gpt-5.6-sol / xhigh)に従い、上書きしない。
- タスクプロンプト構成: 目的 / 対象ファイル・範囲 / 受け入れ条件 / 検証コマンド / 禁止事項(コミット禁止、要件の再定義禁止、`~/.claude/`・`.claude/`配下への接触禁止)。
- 出力の受け取り: 変更ファイル一覧・テスト結果・未解決事項をテキストで返させ、Opusメインがdiffを確認して受け入れ/差し戻し。
- 対象プロジェクトはcodexの`trust_level`設定が必要な場合がある(README記載)。

## 12. グラフィックレコード生成 (A10)

- タイミング: Human ACCEPT + 確定コミット後(未承認状態を確定として描かない)。
- 入力: human-report.md、gate-decision.md、retro.md から `grareco-input.md` を生成(Opus)。
- 生成: `codex exec` に `templates/grareco-prompt.md` ベースの指示を渡し、gpt-image-1で「目的→実装→検証→判断→結果」が一枚で追える画像を `grareco.png` として保存させる。
- 失敗時のフォールバック: `grareco-input.md` が残るため後から手動生成可能。生成失敗はループ完了をブロックしない。

## 13. 観測 (PL-007)

`call-log.md` に1呼び出し1行で追記: `日時 | モデル(fable/opus-sub/codex) | フェーズ | 目的`。
Opusメイン自身の消費は記録対象外(常駐のため)。Retrospective作成時にOpusサブ+メイン主要作業 : Fable の比率を概算し、5:1目安から大きく外れた場合はretro.mdに記載する。比率はハード制限にしない(PL-008)。

## 14. 失敗安全 (NFR-05)

- 必須Artifact欠落時はFableゲートを**呼ばずに**Opusが差し戻す(Fable消費節約 + PL-004証拠ファースト)。
- BLOCKED時は人間へ質問を返して停止し、state.mdに「人間待ち」を記録。
- ゲート順序の保護: Fable PASS前にHuman Acceptanceへ進まない(SK-007)。Human ACCEPT前に確定コミットしない(SK-009)。

## 15. 受け入れ基準

要件16章の10項目をそのまま採用する。加えてハーネス固有の確認として:

1. `/plugin install` 後、`/r-super-loop-powers` が起動しstate.md不在時に新規ゴール開始フローに入る。
2. セッションを切って再開しても、state.mdから現在フェーズを復元できる。
3. Fableサブエージェント呼び出しの**初回入力**にgoal-frame + submission(+エスカレーション6点)以外の生コンテキストが含まれない(Fable自身が追加要求した資料は除く)。
4. `codex exec` がコミットを作らない。

## 16. テスト計画

ダミープロジェクト(小さなCLIツール等)で1ゴール1マイルストーンを1周させる:
Goal Seed → Goal Frame → Brainstorm/Spec/Plan → Goal Gate → Human承認 → タスク分解 → codex exec実装 → 独立レビュー → Implementation Gate → Human Report → ACCEPT → 確定コミット → Retro → グラレコ。
各ステップでArtifactの生成・ゲート順序・call-log記録を要件16章チェックリストと照合する。その後、実案件1〜3件で5:1比率と手戻りを観測する(要件18章)。
