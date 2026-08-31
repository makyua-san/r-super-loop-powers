# r-super-loop-powers Codex版 設計仕様書 — Codex CLIへの移植(Codex v0.1 / Claude版 v0.3.0 相当)

- 作成日: 2026-08-31
- 対象: `skills-codex/r-super-loop-powers/`(新規)。Claude版 `skills/r-super-loop-powers/` は v0.3.0 のまま凍結する
- 前提調査: 2026-08-30の実現可能性調査 + 2026-08-31の実測(本書 §1)
- ユーザー決定: (1) Codex単体で完結 (2) 役割別モデル分担 (3) 別ディレクトリに翻訳版 (4) 1:1移植+Codex固有機能 (5) 実行環境は Codex CLI(ターミナル)

## 0. 目的

Claude Code 上で動く r-super-loop-powers v0.3.0 と**同じ工程・同じ成果物契約・同じゲート規律**を、Codex CLI 単体で完結して回せるようにする。ゴールループの設計思想(A. 要件適合性 / B. 未知の低減)は一切変更しない。書き換えるのは**モデル運用層**、すなわち「誰がどのモデルで起動され、どう往復し、どう判定を返すか」だけである。

## 1. プラットフォーム実測結果(2026-08-31、codex-cli 0.144.2 / models_cache client 0.147.0)

前回調査からの**訂正2件を含む**。

| # | 事実 | 根拠 | 設計への影響 |
|---|---|---|---|
| F1 | Codexプラグインは `.codex-plugin/plugin.json` + `skills: "./<dir>/"` ポインタ + `skills/<名>/SKILL.md`。frontmatter は Claude版と同一形式 | superpowers Codex版 6.3.0 の実物 | プラグイン骨格はほぼ無変更で移植可 |
| F2 | **訂正**: Codexプラグインに agents レジストリは無い。superpowers 6.3.0 の Codex 版に `agents/` は存在せず、`skills/using-superpowers/references/codex-tools.md` が「named agent は .md を読んで `spawn_agent` に流す」回避策を指示している | 実ディレクトリ確認 + codex-tools.md | `agents/*.md` によるサブエージェント定義は使えない |
| F3 | `spawn_agent` / `wait` / `close_agent` は `[features] multi_agent = true` が必要。ユーザーの config.toml には未設定。役割は `default` / `explorer` / `worker` の3種のみで、**モデル・effort の個別指定は確認できない** | config.toml 実物 + `codex exec --enable multi_agent` での実測(spawn_agent は露出せず) | 役割別モデル分担の手段として spawn_agent は採用しない |
| F4 | `codex exec -m <model> -c model_reasoning_effort=<effort>` で**呼び出しごとにモデルとeffortを指定できる** | `codex exec --help` | 役割別モデル分担の実装手段はこれ |
| F5 | `codex exec resume <SESSION_ID> "<prompt>"` でセッションを継続できる | `codex exec resume --help` | Claude版 SendMessage の代替。代理役の往復が成立する |
| F6 | `codex exec --output-schema <JSON Schema file>` で最終応答の構造を強制できる。`--json` で JSONL イベント出力、`-o <file>` で最終メッセージをファイル出力 | `codex exec --help` | ゲート判定の構造化出力に使う |
| F7 | `codex exec -C <dir>` で作業ルートを指定でき、`-s read-only` でサンドボックスを絞れる | `codex exec --help` | judge / proxy を対象リポジトリから物理的に隔離できる |
| F8 | Codexはスキルを `plugin:skill` 形式で認識し、ユーザーは `$plugin:skill` で明示起動、description 一致でも自動起動する | `codex exec` での実測(利用可能スキル一覧に `superpowers:brainstorming` 等が列挙された) | 入口は `$r-super-loop-powers:r-super-loop-powers` |
| F9 | Codex版 superpowers は **6.3.0**(Claude側と同版)。`brainstorming` / `writing-plans` / `subagent-driven-development` 等すべて同名で存在 | 実ディレクトリ確認 | 委譲先スキル名の読み替えは不要 |
| F10 | 利用可能モデルと effort: `gpt-5.6-sol`(low/medium/high/xhigh/max/**ultra**)、`gpt-5.6-terra`(同左)、`gpt-5.6-luna`(low〜**max**、**ultraなし**) | `~/.codex/models_cache.json` | **訂正**: luna に ultra は無い。実装役の上限は max |
| F11 | 配布は `codex plugin marketplace add <local path | owner/repo[@ref] | Git URL>` → `codex plugin add <plugin>@<marketplace>`。マーケットプレイス定義は `.agents/plugins/marketplace.json` | `codex plugin marketplace add --help` + バンドル実物 | 同一GitHubリポジトリからCodexへ配布できる |

**未確定(実装時のスモークテストで確定する)**: (a) `.agents/plugins/marketplace.json` の Git ソース用スキーマ(実物は local 形式のみ確認済み) (b) 親Codexセッション内から `codex exec` を起動できるか(ネスト実行とサンドボックスの相互作用) (c) `codex exec` セッションで画像生成が可能か(グラレコ)。

## 2. 設計決定(C1〜C14)

| ID | 決定 | 内容 | 根拠 |
|---|---|---|---|
| C1 | 二重ホスティング | 同一リポジトリに `.codex-plugin/plugin.json` と `.agents/plugins/marketplace.json` を追加し、Codex版スキル本体を `skills-codex/r-super-loop-powers/` に置く。Claude版 `skills/` と `.claude-plugin/` は**一切変更しない** | ユーザー決定。Claude版v0.3.0はE2E未実施のため、凍結して比較基準として残す |
| C2 | templates の単一原本 | `skills/r-super-loop-powers/templates/` を正とし、`skills-codex/.../templates/` はその複写。`scripts/sync-templates.ps1` が複写と差分検証を行う。テンプレ9枚はプラットフォーム中立なので内容は同一。複写先のパスが同じ(`templates/<名>.md`)なので、SKILL.md 内のテンプレート参照は Claude版の記述をそのまま使える | 二重管理の破綻防止 |
| C3 | 四役モデル分担 | driver = `gpt-5.6-sol` / medium(メインセッション)、judge = `gpt-5.6-sol` / **ultra**、proxy = `gpt-5.6-sol` / **max**、builder = `gpt-5.6-luna` / **max**。高信頼モードの独立レビューア reviewer = `gpt-5.6-sol` / max | ユーザー決定(C3の前4つ)。reviewer は PL-003「実装非関与の独立レビュー」を満たす自然な帰結として本設計で確定 |
| C4 | 役名の中立化 | Claude版の Opus / Fable / Codex を、Codex版では `driver / judge / proxy / builder / reviewer / human` に置換する。**工程記号(A-0〜A-8, B-1〜B-10)・成果物名・ディレクトリ契約・ゲート保護ルールの内容は完全に同一**に保つ | Opus/Fable は Codex に存在しないモデル名であり、そのまま残すと誤解を生む |
| C5 | サブ役の起動手段 | すべて `codex exec` サブプロセス。spawn_agent は使わない | F3/F4。feature flag 非依存で、役ごとのモデル・effort 指定が確実 |
| C6 | 代理役の往復 | proxy は初回 `codex exec --json` で session id を取得し、以後 `codex exec resume <id> "<入力>"` で往復する。session id は state.md の `proxy-session:` に記録する | F5。Claude版 SendMessage の代替 |
| C7 | セッション跨ぎの文脈復元 | `proxy-session:` が state.md に残っていれば、セッション再開後も同じ proxy を `resume` で継続できる。resume が失敗した場合のみ、goal-seed / goal-frame / hearing-log を渡して新しい proxy を起動する(Claude版の挙動にフォールバック) | Codex固有機能。Claude版で妥協していた制約の解消 |
| C8 | ゲート判定の構造化出力 | judge の呼び出しに `--output-schema schemas/gate-verdict.json` を付け、`verdict`(PASS/REVISE/REPLAN/BLOCKED)・`根拠`・`戻り先工程`・`対象の未知` を構造化して受け取る。エスカレーション判定は `schemas/escalation-verdict.json`(`decision`: DECIDE/ASK_HUMAN)を使う | F6。自然文からの判定読み取りミスの構造的排除 |
| C9 | judge / proxy の物理隔離 | judge と proxy は、必要文書だけをコピーした一時ディレクトリで `codex exec -C <tmpdir> -s read-only --skip-git-repo-check` として起動する | **Claude版にない新規リスクへの対策**。Claude版のAgentツールは明示的に渡した情報しか持たないが、`codex exec` は起動先のファイルシステムを読めるため、PL-009(生コード・全会話を渡さない)が素通りする。物理隔離により Claude版より強く担保される |
| C10 | 自己承認の禁止(SK-010) | judge は毎回新規セッション。**proxy の session id を judge に `resume` することを禁止**する | 代理ブレストに参加したインスタンスによるゲート判定の防止。Codex版では「resume しない」が実装上の担保になる |
| C11 | builder のサンドボックス | builder のみ `-s workspace-write -c approval_policy=never` で起動する。非対話実行で承認要求が発生すると停止するため | `codex exec` は非対話。承認ポリシー `on-request` のままでは詰まりうる |
| C12 | プロンプトの受け渡し | 長文プロンプトは引数ではなく stdin(`codex exec -` へヒアドキュメント)で渡す | Windows の引数長・エスケープ問題の回避 |
| C13 | 起動時チェックの拡張 | Claude版の4項目に「前提チェック(`codex` CLI が呼べること、`gpt-5.6-sol` / `gpt-5.6-luna` が利用可能なこと)」を初回のみ追加。モデル確認は「`/model` で `gpt-5.6-sol` / effort medium への切替提案」に翻訳 | PL-002 の翻訳 + Codex固有の前提 |
| C14 | グラレコ | 従来通り `codex exec` へ委譲する(実行環境が Codex CLI のため)。生成に失敗した場合は `grareco-input.md` を残して先へ進む(非ブロック)。この非ブロック規定は Claude版から不変 | ユーザー決定(実行環境=CLI)。CLI セッションでの画像生成可否は未確定(§1未確定c) |

## 3. リポジトリ構成

```
r-super-loop-powers/
├── .claude-plugin/                       # 既存・無変更
│   ├── plugin.json                       # version 0.3.0 のまま
│   └── marketplace.json
├── .codex-plugin/
│   └── plugin.json                       # 新規
├── .agents/plugins/
│   └── marketplace.json                  # 新規(Codex側マーケットプレイス)
├── skills/r-super-loop-powers/           # 既存・無変更(templates の原本)
│   ├── SKILL.md / policy.md
│   └── templates/*.md                    # 9枚
├── skills-codex/r-super-loop-powers/
│   ├── SKILL.md                          # 新規(Codex版)
│   ├── policy.md                         # 新規(Codex版)
│   ├── schemas/
│   │   ├── gate-verdict.json             # 新規
│   │   └── escalation-verdict.json       # 新規
│   └── templates/*.md                    # skills/ からの複写(9枚)
├── scripts/
│   └── sync-templates.ps1                # 新規(複写 + 差分検証)
├── docs/superpowers/specs/               # 本書を含む
└── README.md                             # Codex版セクションを追記
```

### 3.1 `.codex-plugin/plugin.json`

```json
{
  "name": "r-super-loop-powers",
  "version": "0.1.0",
  "description": "Superpowersの上位に薄く重なるゴールループ・オーケストレーション層(Codex版)。フェーズ管理、承認ゲート、ヒューマン・イン・ザ・ループ配置、役割別モデル分担(sol進行/sol判定/sol代理/luna実装)を制御する。",
  "author": { "name": "rnakayama", "email": "rnakayama831@gmail.com" },
  "homepage": "https://github.com/makyua-san/r-super-loop-powers",
  "repository": "https://github.com/makyua-san/r-super-loop-powers",
  "license": "MIT",
  "keywords": ["goal-engineering", "orchestration", "superpowers-overlay", "human-in-the-loop", "model-routing"],
  "skills": "./skills-codex/",
  "interface": {
    "displayName": "R Super Loop Powers",
    "shortDescription": "ゴールループ・オーケストレーション(要件適合性と未知低減)",
    "developerName": "rnakayama",
    "category": "Developer Tools",
    "capabilities": ["Interactive", "Read", "Write"]
  }
}
```

バージョンは Claude版と独立に採番する(Codex版 0.1.0 = Claude版 0.3.0 相当)。

### 3.2 `.agents/plugins/marketplace.json`

```json
{
  "name": "r-super-loop-powers-marketplace",
  "interface": { "displayName": "R Super Loop Powers" },
  "plugins": [
    {
      "name": "r-super-loop-powers",
      "source": { "source": "local", "path": "./" },
      "category": "Developer Tools"
    }
  ]
}
```

Git ソース用のスキーマが local 形式と異なる場合はスモークテスト1で判明するため、そこで確定する。

### 3.2.1 `scripts/sync-templates.ps1`

2モードを持つ。

- `-Mode Copy`(既定): `skills/r-super-loop-powers/templates/*.md` を `skills-codex/r-super-loop-powers/templates/` へ複写する
- `-Mode Verify`: 両者を比較し、内容差分・ファイル数の不一致があれば差分を表示して**非ゼロで終了**する

Codex版のテンプレートを編集したくなった場合は、原本(`skills/` 側)を編集して Copy を実行する。Codex版だけに固有のテンプレートが必要になったら、その時点で C2 を見直す。

### 3.3 導入手順(README に記載する)

```bash
codex plugin marketplace add makyua-san/r-super-loop-powers
codex plugin add r-super-loop-powers@r-super-loop-powers-marketplace
```

起動: セッション内で `$r-super-loop-powers:r-super-loop-powers`

## 4. モデル運用層(Claude版からの唯一の実質的差分)

### 4.1 役の一覧

| 役 | モデル / effort | 起動 | サンドボックス | 対応するClaude版 |
|---|---|---|---|---|
| **driver** | gpt-5.6-sol / medium | ユーザーのメインセッション | 通常 | Opusメイン |
| **judge** | gpt-5.6-sol / ultra | `codex exec` 新規セッション(毎回) | `-C <tmpdir> -s read-only` | ゲート・判断Fable |
| **proxy** | gpt-5.6-sol / max | `codex exec --json` で開始 → `codex exec resume` で往復 | `-C <tmpdir> -s read-only` | 代理Fable |
| **builder** | gpt-5.6-luna / max | `codex exec` 新規セッション | `-s workspace-write -c approval_policy=never` | Codex実装 |
| **reviewer** | gpt-5.6-sol / max | `codex exec` 新規セッション(高信頼のB-5のみ) | 対象リポジトリの read-only | Opusサブ(opus-sub) |
| **human** | — | — | — | 人間 |

### 4.2 呼び出しコマンドの規定形

judge(ゲート判定):

```bash
codex exec -m gpt-5.6-sol -c model_reasoning_effort=ultra \
  -C "<tmpdir>" -s read-only --skip-git-repo-check \
  --output-schema "<skill_dir>/schemas/gate-verdict.json" \
  -o "<tmpdir>/verdict.json" -
```

proxy(初回 → 往復):

```bash
# 初回(session id 取得のため --json を使う)
codex exec -m gpt-5.6-sol -c model_reasoning_effort=max \
  -C "<tmpdir>" -s read-only --skip-git-repo-check --json - | tee "<tmpdir>/first.jsonl"
# 往復
codex exec resume "<session-id>" -m gpt-5.6-sol -c model_reasoning_effort=max \
  -o "<tmpdir>/reply.md" "<次の入力>"
```

builder(実装):

```bash
codex exec -m gpt-5.6-luna -c model_reasoning_effort=max \
  -s workspace-write -c approval_policy=never \
  -o "<milestone_dir>/builder-report.md" -
```

共通規定:
- プロンプトは stdin(`-`)で渡す(C12)
- Bash実行の timeout は最長(600000ms)。長時間になる委譲はバックグラウンド実行
- 出力は `-o` でファイルに落とし、driver がそれを読む
- session id は `--json` の JSONL から拾う。取得できない場合は `codex exec resume --last` を使わず、新規 proxy 起動へフォールバックする(誤ったセッションへの接続防止)

### 4.3 judge / proxy 一時ディレクトリの内容(C9)

場所は `<OSのTEMP>/r-slp/<goal-slug>/<役>-<工程>-<連番>/`。呼び出しごとに作成し、以下**だけ**をコピーする。judge は呼び出し完了後に削除する。proxy は `resume` で往復するため往復の途中では削除せず、その工程(A-1a〜A-4)の完了時にまとめて削除する。削除に失敗しても処理はブロックしない。

| 呼び出し | コピーする文書 |
|---|---|
| A-1a/A-1b/A-2〜A-4(proxy) | goal-seed.md、hearing-log.md、goal-frame.md(あれば)、retro抜粋(あれば)、対象テンプレートの構造 |
| A-6(judge) | goal-frame.md 全文、goal-plan-submission.md 全文、assumptions.md の未検証仮定 |
| B-1(judge) | goal-frame.md、対象マイルストーン定義(goal-plan.md の該当部分)、retro抜粋 |
| B-4(judge) | goal-frame.md、escalation-<n>.md の1〜6、関連する未検証仮定、hearing-log.md の関連部分 |
| B-6(judge) | goal-frame.md、マイルストーン定義、submission.md、assumptions.md の未検証仮定 |
| B-9(judge) | goal-frame.md、human-report.md、REJECT理由 |

プロンプトにも「与えられた文書のみで判定し、他のファイルを探索しない」と明記する(ultra の自動タスク委譲による余計な探索の抑制)。

### 4.4 構造化出力スキーマ

`schemas/gate-verdict.json`:

```json
{
  "type": "object",
  "properties": {
    "verdict": { "type": "string", "enum": ["PASS", "REVISE", "REPLAN", "BLOCKED"] },
    "rationale": { "type": "string", "description": "根拠。5行以内" },
    "return_to": { "type": "string", "description": "REVISE/REPLANの場合の戻り先工程。該当なしは空文字" },
    "target_unknowns": { "type": "array", "items": { "type": "string" }, "description": "対象の未知・仮定" },
    "blocking_questions": { "type": "array", "items": { "type": "string" }, "description": "BLOCKEDの場合の人間向け質問" }
  },
  "required": ["verdict", "rationale", "return_to", "target_unknowns", "blocking_questions"],
  "additionalProperties": false
}
```

`schemas/escalation-verdict.json`:

```json
{
  "type": "object",
  "properties": {
    "decision": { "type": "string", "enum": ["DECIDE", "ASK_HUMAN"] },
    "judgement": { "type": "string", "description": "DECIDEの場合の判断内容。ASK_HUMANでは空文字" },
    "rationale": { "type": "string" },
    "question_for_human": { "type": "string", "description": "ASK_HUMANの場合の人間向け質問文。DECIDEでは空文字" }
  },
  "required": ["decision", "judgement", "rationale", "question_for_human"],
  "additionalProperties": false
}
```

判定の出力契約(PASS/REVISE/REPLAN/BLOCKED + 根拠5行以内 + 戻り先 + 対象の未知)は Claude版と同一であり、表現がJSONになるだけである。

## 5. SKILL.md の翻訳仕様(工程別の差分)

以下に挙げた箇所**以外**は Claude版 SKILL.md の文言をそのまま使う。

### 5.1 frontmatter

```yaml
name: r-super-loop-powers
description: Use when starting or resuming a goal-engineering loop (ゴールループ / goal loop / ゴールエンジニアリング開発). Superpowersの上位で、要件適合性と未知低減を目的に、フェーズ管理・成果物契約・承認ゲート・ヒューマン・イン・ザ・ループ配置・役割別モデル分担(sol進行 / sol判定 / sol代理 / luna実装)をオーケストレーションする。MVPモードでは代理役のヒアリングでゴールと文脈を掘り、HOWは代理ブレストでAgentへ委任し、Checkpoint単位でHuman Acceptanceを行う。
```

### 5.2 起動時チェック(4項目 → 5項目)

1. policy.md 読込 — 不変
2. **モデル確認**: driver が `gpt-5.6-sol` / effort `medium` でない場合、`/model` での切替をユーザーに提案し、切替またはユーザーの明示的な続行指示があるまでフェーズ作業を開始しない(PL-002)
3. 状態復元 — 「Globツール」→「ネイティブのファイル検索」に読み替え。それ以外不変
4. 強度確認 — 不変
5. **新規: 前提チェック(初回のみ)** — `codex` CLI が呼べること、`gpt-5.6-sol` と `gpt-5.6-luna` が利用可能であることを確認する。満たされない場合はユーザーに報告して停止する

### 5.3 ディレクトリ契約 / state.md

ディレクトリ構造は完全に同一。state.md のフォーマットのみ2箇所変更:

```markdown
# state — <goal-slug>
- phase: goal-definition | milestone-implementation | human-acceptance | finalization | learning | done
- 強度: MVP | 高信頼 | 未確定
- milestone: <n>-<名前> または -
- 次のCheckpoint: <n>-<名前> または -
- 担当: driver | judge | proxy | builder | reviewer | human      # ← 値を変更
- 次のゲート: goal-gate | impl-gate | human-acceptance | none
- proxy-session: <uuid> または -                                  # ← 新規1行(C6/C7)
- 待ち: <人間待ちの場合はその内容。なければ ->
- updated: YYYY-MM-DD HH:MM
```

### 5.4 記録ルール(PL-007)

`call-log.md` 形式: `YYYY-MM-DD HH:MM | judge|proxy|builder|reviewer | フェーズ | 目的`
proxy の resume 往復も1往復1行。driver 自身の消費は記録対象外。

### 5.5 ゲート保護ルール(7項目)

内容は不変。文言のみ以下2箇所:
- 1・3・7 の「Fable」→「judge」/「代理Fable」→「proxy」
- 5「`codex exec` にコミットさせない」→「**builder にコミットさせない**」(Codex版では全役が `codex exec` のため、対象を役で特定する)
- 7 に実装上の担保を追記: 「proxy の session id を judge に `resume` しない」

### 5.6 「Fableサブエージェント共通契約」→「役の共通契約」

- judge / proxy / builder / reviewer は `codex exec` で起動する(§4.2の規定形)
- proxy: 1インスタンスを `resume` で継続。入力は goal-seed / goal-frame / hearing-log / retro抜粋 / templates構造のみ
- judge: 呼び出しごとに新規セッション。入力は §4.3 の表のとおり。対象プロジェクトの生コード・全会話履歴を渡さない(PL-009 は §4.3 の一時ディレクトリ隔離で担保)。追加資料を要求された場合のみ 1 往復だけ `resume` で追加提供する
- 判定の出力契約: §4.4 のスキーマ
- 判定観点(プロンプトに明記): Claude版と同一の4点 + 「与えられた文書のみで判定し他を探索しない」

### 5.7 ワークフローA

| 工程 | 変更点 |
|---|---|
| A-0 | 不変(driver が実行) |
| A-1a | 「Agentツール(model: fable、nameを付けて起動)」→「proxy を `codex exec --json` で起動し session id を state.md に記録」。ヒアリング指示文は一字一句そのまま。往復は `codex exec resume` |
| A-1b | MVP: proxy へ `resume` で goal-frame.md の構造を渡す / 高信頼: **proxy と同設定(sol / max、一時ディレクトリ隔離)の新規セッションを1回だけ使い捨てで起動**する(役割は「ゴールの全体責任者」であって判定ではないため judge は使わない。session id は記録せず往復もしない)。指示文は不変 |
| A-2〜A-4 | `superpowers:brainstorming` の起動が `$superpowers:brainstorming` になる。MVP代理ブレストの相手は proxy(`resume` 往復)。ASK_HUMAN の扱いは不変 |
| A-5 | 不変(driver が実行) |
| A-6 | judge を新規セッションで起動、`--output-schema gate-verdict.json`。判定観点(Checkpoint配置の妥当性を含む)は不変。結果を `goal-gate-decision.md` に保存する際は、JSONを Claude版と同じ見出し構造の Markdown に整形して保存する |
| A-7 | 不変 |
| A-8 | 不変 |

### 5.8 ワークフローB

| 工程 | 変更点 |
|---|---|
| B-1 | judge を軽量起動(`--output-schema` は使わない。10行以内のテキスト応答) |
| B-2〜B-3 | 委譲先が builder(`gpt-5.6-luna` / max)。§4.2 の規定形。プロンプト必須6要素は不変。ただし禁止事項に `~/.codex/` `.codex/` 配下への接触禁止を追加(既存の `~/.claude/` `.claude/` はそのまま残す)。「モデル・reasoning effort・sandbox はユーザーの config.toml に従う(上書きしない)」の一文は、**本設計では役割別に明示指定するため削除**し、代わりに §4.2 の規定形を参照する |
| B-4 | judge に `--output-schema escalation-verdict.json`。DECIDE / ASK_HUMAN の扱いは不変。`escalation-<n>.md` の7欄には整形した内容を書く |
| B-5 | MVP: driver のセルフチェック(不変)。高信頼: reviewer を `codex exec` で起動(実装非関与=builder とは別セッション・別モデル。PL-003) |
| B-6 | judge + `--output-schema`。PASS後の分岐(中間クローズ / human-acceptance / 差し戻し)は不変 |
| B-7 | 不変 |
| B-8 | 不変 |
| B-9 | judge を新規セッションで起動。戻り先決定。出力は自由記述で可 |
| B-10 | 不変 |

### 5.9 Learning フェーズ

- Retrospective: 不変(driver が作成)。`record_lesson`(orca-meta MCP)は「導入されていない環境では省略してよい」の既存規定でカバーされる
- グラレコ: `codex exec` へ委譲(C14)。使用モデルは builder と同じ `gpt-5.6-luna` / max とする。失敗時は非ブロックで先へ進む(不変)
- 次へ: 不変

### 5.10 例外・停止時の扱い

- 人間待ちの扱い: 不変
- セッション再開: 「代理Fableはセッションを跨げない」という制約が**解消される**。state.md の `proxy-session:` があれば `resume` で継続し、失敗時のみ新規 proxy を goal-seed / goal-frame / hearing-log から起動する(C7)
- 他スキルのファイルを変更しない(SK-001): 不変

## 6. policy.md の翻訳仕様

構造・ID・条件はすべて維持し、以下のみ翻訳する。

| 箇所 | 変更 |
|---|---|
| 責任分担テーブル | 行の主語を Fable→judge/proxy、Opus→driver/reviewer、Codex→builder に置換。モデル名列を追加(sol ultra / sol max / sol medium / luna max) |
| 「Fableを呼ぶ場面」7項目 | 「judge / proxy を呼ぶ場面」に改題。内容不変 |
| 「Fableを原則呼ばない場面」 | 「judge / proxy を原則呼ばない場面」に改題。内容不変 |
| PL-001 | 「judge=判定、proxy=代理、driver=整理/仕様/レビュー/報告、builder=実装をデフォルトとする」 |
| PL-002 | 「『高性能だから』という理由だけで effort を上げない。driver は `gpt-5.6-sol` / medium で運用する」 |
| PL-003 | 「高信頼強度では、judge 提出前に実装非関与の reviewer(`gpt-5.6-sol` / max)が独立レビューする」 |
| PL-007 | call-log 形式を `judge|proxy|builder|reviewer` に。5:1目安は driver:judge+proxy として読む。適用範囲(ワークフローB以降)は不変 |
| PL-009 | 「judge / proxy へは goal-frame + 対象文書 + 仮定台帳の関連部分のみを渡す」に加え、**「一時ディレクトリ隔離で物理的に担保する」**を追記(C9) |
| 画像生成の行 | 「Codex組み込み image_gen ツール」→「builder セッション(`codex exec`)経由の画像生成」 |
| Sonnet 将来枠の行 | 「`gpt-5.4-mini` / `gpt-5.3-codex-spark` 将来枠(未使用)。軽量探索・補助実装の候補」 |
| 強度別工程表 | 「codex exec に委譲」→「builder に委譲」等、役名のみ置換。工程内容は不変 |

上位原則・MVPモードの原則・Checkpoint規定・否定リスト6項目・エスカレーション発火条件10項目は**一字一句変更しない**。

## 7. 受け入れ基準

1. Codex CLI セッションで `$r-super-loop-powers:r-super-loop-powers` が起動し、起動時チェック5項目が実行される
2. driver が `gpt-5.6-sol` / medium でない場合に `/model` 切替提案が出て、承諾か明示的続行までフェーズ作業が始まらない
3. proxy が `codex exec --json` で起動され、session id が state.md の `proxy-session:` に記録され、`resume` で往復できる
4. A-1a のヒアリング質問が人間へそのまま提示され、回答が hearing-log.md に記録される
5. judge が一時ディレクトリで起動され、**対象リポジトリのファイルを読めない**
6. judge の判定が `gate-verdict.json` スキーマに適合したJSONで返り、`goal-gate-decision.md` / `gate-decision.md` に Claude版と同じ見出し構造で保存される
7. builder が `gpt-5.6-luna` / max で起動され、コミットせずに実装と自己検証報告を返す
8. proxy の session id が judge に `resume` されない(SK-010)
9. Claude版と同じディレクトリ契約(state.md / goal-frame.md / assumptions.md / call-log.md / milestones/…)が生成される
10. `scripts/sync-templates.ps1` が templates 9枚の一致を検証し、差分があれば非ゼロ終了する
11. Claude版 `skills/` と `.claude-plugin/` に変更が入っていない(`git diff` で確認)
12. MVP強度で Checkpoint 1つ以上を完走し、Human Acceptance が Checkpoint でのみ発生する

## 8. 検証計画

### 8.1 スモークテスト(実装中に必ず通す。失敗したら設計に戻る)

| # | 検証内容 | 失敗時の対応 |
|---|---|---|
| S1 | ローカルパスで `codex plugin marketplace add` → `codex plugin add` → スキルが `$r-super-loop-powers:r-super-loop-powers` で見える | marketplace.json のスキーマを実物に合わせて修正(§1未確定a) |
| S2 | **親Codexセッションの中から `codex exec` を起動できる**(ネスト実行がサンドボックス・承認で詰まらない) | 詰まる場合は driver 自身が builder を兼ねる案へ設計変更。**この検証を最優先で行う** |
| S3 | `codex exec --json` から session id を拾い、`resume` で往復できる | 拾えない場合は C6/C7 を破棄し、Claude版と同じ「記録から再構築」方式へ戻す |
| S4 | `--output-schema` で PASS/REVISE の構造化出力が返る | 返らない場合は C8 を破棄し、自然文+パースへ戻す |
| S5 | `-C <tmpdir>` 隔離下の judge が対象リポジトリを読めない | 読めてしまう場合は、プロンプトでの禁止指示のみに後退し、その旨を policy.md に明記 |
| S6 | `codex exec` セッションで画像生成ができる(グラレコ) | できない場合は grareco-input.md のみ生成する運用に確定(非ブロック規定は既存) |

### 8.2 E2Eテスト

新規の小規模プロジェクトで、Codex CLI から MVP 強度のゴールループを、中間マイルストーン1つ以上 + Checkpoint 1つ以上で完走する。README に Codex版E2Eチェックリスト(受け入れ基準§7の12項目 + Claude版20項目のうち工程共通の項目)を置き、これを確認する。

要観察点(Claude版と同じ): proxy が過剰に代答せず ASK_HUMAN を正しく返すか、ヒアリングで無自覚の既知が実際に表面化するか。Codex版固有: judge の ultra が余計な探索や過剰な差し戻しをしないか、builder(luna max)の自己検証報告が受け入れ判断に足りるか。

## 9. スコープ外

- Claude版 v0.3.0 の改修(凍結)
- Claude版とCodex版の共通化リファクタリング(将来、両方を育てる判断をした時点で再検討)
- `spawn_agent`(multi_agent feature)の利用
- Codex デスクトップアプリでの動作保証(実行環境は CLI に確定)
- Codex版での orca-meta `record_lesson` 導線の新規整備(既存の「未導入環境では省略」規定に従う)
