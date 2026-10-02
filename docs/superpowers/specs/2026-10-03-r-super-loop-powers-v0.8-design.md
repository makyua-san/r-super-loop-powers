# r-super-loop-powers v0.8 設計仕様書 — ロール憲章と人間向け応答チェック(Claude版)

- 作成日: 2026-10-03
- 対象: Claude版 `skills/r-super-loop-powers/`・`agents/`・`hooks/`(新設)・`.claude-plugin/`・`scripts/`・`tests/`・README のClaude版節。Codex版 `skills-codex/` は**変更しない**
- 前提: v0.7.0(merge commit ea02f38)
- ユーザー決定(2026-10-03):
  1. ロール定義は**全ロール**(Opus / 代理Fable / ゲートFable / 技術PM / 技術レビュー / 実装役 / グラレコ)に持たせる
  2. 定義は正本1つ(`references/roles.md`)から各ロールへ配る(案A)
  3. 人間向け応答のチェックは**ゴールループ中の全応答**を対象にする
  4. 判定は機械(日本語比率)+LLM(明瞭・端的さ)。不合格は Stop をブロックして書き直させる(無限ループ防止つき)

## 0. 目的

1. **ロール憲章**: 各担当が「自分はゴールループ全体のどこにいて、何を決め、何を決めないか(誰が評価・レビュー・承認するか)」を知った上で動くようにする。v0.7 の builder.md は「何をするか」の指示はあるが、プロセス全体の地図が無い。全体が分かっていれば、担当外の判断(設計のやり直し・要件適合の自己判定など)をしなくなる。
2. **人間向け応答チェック**: ゴールループ中に Opus が人間へ返す応答(ASK_HUMAN 中継・承認依頼・受け入れテスト依頼・状況報告)が、日本語で、明瞭・端的であることを hooks で機械的に保証する。

工程(A-0〜A-8 / B-1〜B-10)・成果物契約・ゲート規律は変えない。

## 1. 事実確認(2026-10-03、code.claude.com/docs/en/hooks・hooks-guide)

| # | 事実 | 設計への影響 |
|---|---|---|
| F7 | Stop フックの入力 JSON に `last_assistant_message`(最終応答の本文)・`stop_hook_active`・`cwd`・`transcript_path` が含まれる | transcript を解析せずに本文を検査できる |
| F8 | Stop フックが `{"decision":"block","reason":"..."}` を返すと停止が取り消され、Claude は reason を読んで作業を続ける。`stop_hook_active` は、既にストップフックで継続させられている間 true になる | 書き直しを1回だけ要求できる |
| F9 | `type:"prompt"` フックは Stop で使えるが、ファイルシステムを見られない | 「ゴールループ中か」を判定できず全セッションで LLM が動くため**採用しない**。コマンドフックから `claude -p` を呼ぶ |
| F10 | プラグインは `hooks/hooks.json`(settings.json の `hooks` と同形式)を同梱でき、`${CLAUDE_PLUGIN_ROOT}` が使える。Windows ではシェル形式のコマンドは Git Bash(無ければ PowerShell)で実行される | コマンドは `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/hooks/..."` とし、どちらのシェルでも動く形にする |

**未確定(実装計画の最初のスモークで確定する)**: (a) AskUserQuestion ツールで質問するときに Stop が発火するか (b) PreToolUse(matcher `AskUserQuestion`)の `permissionDecision: "deny"` + reason で Claude が質問を書き直すか (c) フック内から `claude -p --model haiku` が起動し、子セッションで同じフックが `RSLP_HOOK_CHILD=1` により素通りするか。(b) が成り立たなければ AskUserQuestion のチェックは入れない(D53)。(c) が成り立たなければユーザーに報告して方式を相談する。

## 2. 設計決定(D46〜D55)

| ID | 決定 | 内容 |
|---|---|---|
| D46 | ロール憲章の正本 | `skills/r-super-loop-powers/references/roles.md` を新設。「プロセス全体図」+7ロールの憲章(§3) |
| D47 | 実装役への配布 | `agents/builder.md` の本文に、roles.md の「全体図」と「実装役」節を `<!-- roles:begin -->` 〜 `<!-- roles:end -->` で囲んで埋め込む。既存の実行契約・ロール・出力契約の節は残す |
| D48 | 同期と検査 | `scripts/sync-roles.ps1`(`-Mode Copy | Verify`)で roles.md → builder.md のマーカー区間を生成・検証する。`tests/roles-sync.tests.ps1` が Verify を呼び、不一致なら失敗する |
| D49 | codex 3ロールへの配布 | `codex-run.ps1` が実行時に `<skill-dir>/references/roles.md` を読み、「全体図」とロール対応節(techpm→技術PM / reviewer→技術レビュー / grareco→グラレコ)を取り出して、実行契約の後・`$RoleBriefs` の前に差し込む。`$RoleBriefs` は残す。roles.md が無い・節が見つからない場合は `WARN: roles section not found` を出して差し込まずに続行する |
| D50 | Fable への配布 | SKILL.md「Fableサブエージェント共通契約」に、起動時の依頼文の冒頭へ roles.md の「全体図」+該当節(代理Fable または ゲートFable)を**原文のまま**貼ることを必須として書く。代理Fableは初回起動時のみ(SendMessage 往復では再送しない) |
| D51 | Opus への配布 | SKILL.md 冒頭と起動時チェック1で、policy.md と一緒に roles.md を読ませる。policy.md「責任分担」表は残し、詳細は roles.md を参照と書く |
| D52 | 人間向け応答チェック = Stop コマンドフック | プラグインに `hooks/hooks.json` を新設し、Stop に `hooks/human-message-check.ps1` を登録する(timeout 90 秒)。処理は §4 |
| D53 | AskUserQuestion のチェック | スモーク(a)(b)の結果次第。Stop が発火せず、かつ PreToolUse の deny で書き直しが起きる場合だけ、同じスクリプトを `-Event PreToolUse` で PreToolUse(matcher `AskUserQuestion`)に登録する。成り立たなければ入れず、その旨を README に書く |
| D54 | フェイルオープン | 判定側の失敗(claude が見つからない・タイムアウト・出力解析不能・予期しない例外)では**ブロックしない**。理由を `hook-log.md` に記録する |
| D55 | 観測 | 判定結果(PASS / BLOCK / SKIP / ERROR と理由)を `<goal-dir>/hook-log.md` に1行ずつ追記する。retro の観測欄でブロック回数を見られるようにする |

## 3. `references/roles.md` の構成

```
# ロール憲章(正本)
## 全体図
  - ゴールループの目的(A. 要件適合性 / B. 未知の低減)
  - フェーズの流れと各段の担当(作る / 決める / 判定する):
    Goal Seed → ヒアリング → Goal Frame → ブレスト → 実装アセス → Goal Gate → 人間承認
    → [マイルストーンごと] 開始確認 → 実装 → 機械判定(impl-check) → 技術レビュー(高信頼のみ)
    → submission → Implementation Gate → Checkpoint受け入れ(人間) → 振り返り・グラレコ
  - 原則: 作る人と判定する人を分ける / 成否は機械判定 / 人間は生成より評価
## Opus(オーケストレーター)
## 代理Fable
## ゲートFable
## 技術PM
## 技術レビュー
## 実装役
## グラレコ
```

各ロール節は同じ5項目を持つ:

1. **あなたの立場** — 全体図のどこにいるか(1〜2行)
2. **受け取るもの / 返すもの** — 入力と、出力が誰に渡り何に使われるか
3. **あなたが決めること**
4. **あなたが決めないこと** — 他の誰が担うかを名指しする(例: 実装役 →「技術方針は技術PMが決定済み」「成否は impl-check.ps1 が機械判定」「技術レビューは codex(高信頼)」「要件適合はゲートFable」「受け入れは人間」)
5. **あなたの出力の判定のされ方** — 誰が・何で合否を決めるか

見出しは `## <ロール名>` で固定する(codex-run.ps1 と sync-roles.ps1 が見出しで節を切り出すため)。内容は policy.md・SKILL.md の既存規定と矛盾させない(新しい規則は足さず、既存規定を担当者目線で並べ直す)。

## 4. `hooks/human-message-check.ps1` の処理

入力: stdin の Stop フック JSON。出力: 合格・対象外は何も出さず exit 0、不合格は `{"decision":"block","reason":"..."}` を stdout に出して exit 0。

1. **対象外判定(SKIP)** — 次のどれかなら即 exit 0:
   - 環境変数 `RSLP_HOOK_CHILD=1`(判定用の子セッション)
   - `stop_hook_active` が true(書き直しは最大1回)
   - `cwd` 配下に `docs/r-super-loop-powers/*/state.md` が無い、またはすべての state.md の `phase:` が `done`
   - `last_assistant_message` が空
   対象のゴールディレクトリは、phase が done でない state.md のうち更新日時が最新のもの。
2. **本文の正規化**: コードフェンス(```…```)・インラインコード(`…`)・URL・Windows/POSIX のパスを除去する。
3. **機械チェック(日本語比率)**: 正規化後の本文で、日本語文字(ひらがな・カタカナ・漢字)の数 J と、英単語(`[A-Za-z]+` の連なり)の数 W を数え、比率 J / (J + W) を計算する。英語は1文字ではなく**1単語を1単位**として数える(1文字ずつ数えると、日本語の文に `STATUS` や `impl-check` が混ざるだけで比率が大きく下がるため)。J + W が 20 未満なら判定しない(通過)。比率が **0.6 未満**なら BLOCK(reason: 日本語で書き直すよう指示)。しきい値はスクリプト冒頭の定数にする。
4. **LLM チェック(明瞭・端的)**: `claude -p --model haiku --output-format text` に、判定基準と本文を渡す(環境変数 `RSLP_HOOK_CHILD=1` を付けて起動、タイムアウト 60 秒)。判定基準:
   - 結論・求める行動(何を答え、何を決めてほしいか)が冒頭にあるか
   - 質問がある場合、ユーザーが何をどう答えればよいか明確か(選択肢や回答の形が示されているか)
   - 内部の工程記号・スクリプト名・ステータス語(A-6、B-2、impl-check、STATUS など)を説明なしに使っていないか
   - 同じことの繰り返し・不要な前置きがなく端的か
   出力は JSON 1行 `{"ok": true}` または `{"ok": false, "reason": "<具体的な直し方>"}`。`ok:false` なら BLOCK(reason をそのまま渡す)。
   - 判定役のコマンドは環境変数 `RSLP_JUDGE_CMD` で差し替え可能にする(テスト用)。
5. **フェイルオープン(D54)**: 4 の起動失敗・タイムアウト・JSON 解析不能・予期しない例外は ERROR として記録し exit 0。
6. **記録(D55)**: SKIP 以外の結果を `<goal-dir>/hook-log.md` に `YYYY-MM-DD HH:MM | PASS|BLOCK|ERROR | ja-ratio=<値> | <理由の要約>` で追記する。

BLOCK の reason の書式(Opus が読む):
`[r-super-loop-powers] 人間向けの応答を書き直してください: <理由>。内容は変えず、日本語で、結論・お願いしたいことを冒頭に、内部用語は言い換えて端的に。`

## 5. 文書の更新

- SKILL.md: 冒頭・起動時チェック1(roles.md を読む)/ Fable共通契約(D50)/ 技術PM共通契約(roles 節は codex-run.ps1 が自動で差し込む旨)/ 記録ルール付近に hook-log.md / ディレクトリ契約に `hook-log.md` を追加
- policy.md: 責任分担表の下に「各ロールの詳細は references/roles.md」1行
- references/codex-invocation.md: 差し込み順(実行契約 → roles 節 → RoleBrief → タスク本文)
- README(Claude版節): ロール憲章・hooks の説明、hooks の動作要件(`claude` CLI が PATH にあること)、AskUserQuestion の扱い(D53の結果)
- `.claude-plugin/plugin.json` / marketplace: version 0.8.0
- Learning(retro)の観測欄に hook-log.md のブロック回数を含める

## 6. テスト

- `tests/roles-sync.tests.ps1`: builder.md のマーカー区間が roles.md と一致(Verify が 0 終了)。一致しない場合に非0終了することも確認する
- `tests/codex-run.tests.ps1` に追加: 正規化後プロンプトに「全体図」と該当ロール節が含まれ、順序が 契約 → roles → RoleBrief → 本文 であること。roles.md が無いときは WARN を出して続行すること
- `tests/human-message-check.tests.ps1`(`RSLP_JUDGE_CMD` で判定役を差し替え):
  - 英語の応答 → BLOCK(LLM を呼ばない)
  - 日本語で明瞭(判定役が ok:true)→ 出力なし
  - 判定役が ok:false → BLOCK、reason に判定役の理由を含む
  - `stop_hook_active: true` → SKIP
  - state.md が無い / phase: done → SKIP
  - `RSLP_HOOK_CHILD=1` → SKIP
  - 判定役が失敗(非0終了・不正出力)→ 出力なし、hook-log.md に ERROR
  - コードブロック主体の応答(J + W が 20 未満)→ 日本語比率で BLOCK しない

## 7. 受け入れ基準(この改訂の完了条件)

1. `references/roles.md` に全体図と7ロールの節があり、各節が §3 の5項目を持つ
2. builder.md に roles の区間があり、`tests/roles-sync.tests.ps1` が通る
3. codex-run.ps1 が roles 節を差し込み、`tests/codex-run.tests.ps1` が通る
4. SKILL.md の Fable 共通契約に roles 節の貼り付けが必須として書かれている
5. `hooks/hooks.json` と `hooks/human-message-check.ps1` があり、`tests/human-message-check.tests.ps1` が通る
6. スモーク: 実際の Claude Code セッションで、ゴールループ中を模した cwd で英語の応答をさせると書き直しが1回起き、2回目は通ること。ループ外の cwd では何も起きないこと
7. 既存テスト(`tests/impl-check.tests.ps1` ほか)がすべて通る
8. version 0.8.0

## 8. 範囲外

- Codex版(`skills-codex/`)へのロール憲章・hooks の移植
- Fable をプラグイン同梱エージェントにすること(案C)
- サブエージェント(実装役・Fable)の出力への言語チェック(人間向けではないため)
- 応答の自動書き換え(書き直しは Opus 自身が行う)
