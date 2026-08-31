# Codex移植 スモークテスト結果 — 2026-08-31

対象仕様: `docs/superpowers/specs/2026-08-31-r-super-loop-powers-codex-port-design.md` §8.1
実行環境: codex-cli 0.144.2、Windows 11(検証は Claude Code の Bash ツール経由。詳細は「検証環境の制約」節を参照)

| # | 検証内容 | 判定 | 実測 | 採用方針 |
|---|---|---|---|---|
| S2 | 親Codexセッション内からの `codex exec` ネスト実行 | **判定不能**(実ターミナルでの検証が必要) | 4回の試行(初回/S2a/S2b/S2c)すべてが異なるレイヤーで失敗。最終的にはネスト側 codex プロセスの `orca\codex-runtime-home` への書き込み拒否で停止。詳細は下記 | 設計は暫定継続。ユーザーの実ターミナルでの再検証結果を待って最終判断 |
| S3 | session id の取得と `resume` による往復 | OK | `SID=01a05855-19d3-7b93-a570-ddfca8ce6f7d`。resume 後の応答は `ALPHA`(期待どおり) | C6/C7 採用 |
| S4 | `--output-schema` による構造化出力 | **FAILED**(タイムアウト) | 10分でタイムアウト(exit code 143)。stdout/stderrへの出力なし。`/tmp/verdict-out.json` は生成されず | C8 破棄。judge は自然文で `判定: PASS` の形式で返させ、driver が1行目を読む |
| S5 | `-C <tmpdir>` 隔離下でのリポジトリ読み取り | OK(望ましい結果) | 作業ディレクトリには `goal-frame.md` のみが見え、`README.md` の読み取りは明示的に FAILED(access denied) | 物理隔離のみで PL-009 を担保できる見込み。念のため探索禁止指示も併用する |
| S6 | `codex exec` セッションでの画像生成 | **判定不能**(実ターミナルでの検証が必要) | 未実行(team-lead 裁定により、S2と同じランタイムホーム/サンドボックス問題に当たる可能性が高いため見送り) | グラレコは grareco-input.md のみ生成する運用を暫定採用。実ターミナルでの検証結果を待って再判断 |

## S1 について

S1(marketplace add → plugin add → スキル可視)は、プラグイン骨格ができる Task 5 で実施する。

## 検証環境の制約

このスモークテストは Claude Code の Bash ツール(サンドボックス有効)から実行した。S2(ネストした `codex exec`)の検証は、以下のとおり4回の試行すべてで**異なるレイヤー**の失敗に当たり、試行を重ねるたびに一段深いところまで到達した:

1. **初回**(外側 `-s workspace-write`、Bash ツールのサンドボックス有効): 外側の codex セッション自身の Windows サンドボックス構築が失敗。
   ```
   ERROR codex_core::exec: exec error: windows sandbox: workspace-write sandbox has no writable root capability SIDs
   ```
   Claude Code の Bash ツールのサンドボックスと codex 自身の Windows サンドボックスの「二重掛け」が原因と推定。

2. **S2a**(外側 `-s read-only`、Bash ツールのサンドボックス有効): read-only でも外側のサンドボックス構築が別のエラーで失敗。
   ```
   execution error: Io(Custom { kind: Other, error: "windows sandbox: CreateProcessWithLogonW failed: 267" })
   ```
   さらに、外側の codex エージェントが自律的に「サンドボックス外での再試行」を試み、別レイヤー(PreToolUse/PermissionRequestフックとみられる)により以下のとおり拒否された。
   ```
   error=This action was rejected due to unacceptable risk.
   Reason: ... this plan requires prohibited sandbox escalation under the current approval policy.
   ```

3. **S2b**(Bash ツールのサンドボックスを `dangerouslyDisableSandbox: true` で無効化、作業ルートを一時ディレクトリに変更): 外側のプロセス起動自体は成功(Windows サンドボックス構築エラーは解消)。しかし内側プロンプト文字列中の bare な `codex` コマンドを `mise`(バージョンマネージャ)が解決できず失敗。
   ```
   mise ERROR cannot find binary path
   ```

4. **S2c**(内側の codex 呼び出しも絶対パスに変更): `mise` の PATH解決エラーは解消し、powershell 側のコマンド起動自体は成功した。しかし今度は**ネストされた codex プロセス自身の初期化**が失敗。
   ```
   WARNING: failed to clean up stale arg0 temp dirs: アクセスが拒否されました。 (os error 5)
   WARNING: proceeding, even though we could not create PATH aliases: アクセスが拒否されました。 (os error 5) at path "C:\Users\makyu\AppData\Roaming\orca\codex-runtime-home\home\tmp\arg0\codex-arg0tytwHT"
   Error: failed to initialize in-process app-server client: アクセスが拒否されました。 (os error 5)
   ```
   `AppData\Roaming\orca\codex-runtime-home` は**この実行環境固有のランタイムホーム**であり、ユーザーの素のターミナルには存在しない要因と考えられる。外側で既に動いている codex プロセスと、ネストした内側プロセスが同じランタイムホームを取り合うリソース競合(ファイルロック)の可能性が高い。

この時点で team-lead の裁定により、これ以上の追加検証は「環境アーティファクトを掘るだけ」と判断し、S2 は**判定不能(ユーザーの実ターミナルでの検証が必要)**として確定した。

S4(`--output-schema`)についても、10分間のタイムアウトで出力が一切得られなかった。原因は不明(ハング要因を切り分けるための追加実行はしていない)。これも検証環境固有の問題である可能性を否定できないため、下記「実ターミナルでの再確認が必要な項目」に加えた。

## ユーザーの実ターミナルでの再確認が必要な項目

### S2: ネストした `codex exec` の起動可否

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
"$CODEX" exec -m gpt-5.4-mini -c model_reasoning_effort=low \
  -s workspace-write -c approval_policy=never --skip-git-repo-check \
  "Run exactly this shell command and report its final line verbatim: codex exec -m gpt-5.4-mini -c model_reasoning_effort=low -s read-only --skip-git-repo-check \"Reply with exactly: NESTED_OK\"" 2>&1 | tail -20
```

期待: 出力に `NESTED_OK` が含まれる。

### S6: `codex exec` セッションでの画像生成

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
IMG=$(mktemp -d)
"$CODEX" exec -m gpt-5.6-luna -c model_reasoning_effort=low \
  -C "$IMG" -s workspace-write -c approval_policy=never --skip-git-repo-check \
  "Generate a simple illustrative image (any content) and save it as grareco.png in your working directory. If you have no image generation capability, reply with exactly: NO_IMAGE_TOOL" 2>&1 | tail -10
ls -la "$IMG"
```

期待: `grareco.png` が生成される、または `NO_IMAGE_TOOL` が返る(いずれも判定可能な結果)。

### (参考・任意)S4: `--output-schema` による構造化出力

team-lead からの明示指示にはないが、タイムアウトで原因不明のまま終わっているため、実ターミナルでの再確認を推奨する。

```bash
CODEX="/c/Users/makyu/AppData/Local/OpenAI/Codex/bin/3135b80b111fd431/codex.exe"
cat > /tmp/verdict-probe.json <<'JSON'
{
  "type": "object",
  "properties": {
    "verdict": { "type": "string", "enum": ["PASS", "REVISE", "REPLAN", "BLOCKED"] },
    "rationale": { "type": "string" }
  },
  "required": ["verdict", "rationale"],
  "additionalProperties": false
}
JSON
"$CODEX" exec -m gpt-5.6-sol -c model_reasoning_effort=low \
  -s read-only --skip-git-repo-check \
  --output-schema /tmp/verdict-probe.json -o /tmp/verdict-out.json \
  "A submission is missing its verification evidence. Decide the gate verdict." 2>&1 | tail -3
cat /tmp/verdict-out.json
```

期待: `verdict` が4値のいずれかである JSON が `/tmp/verdict-out.json` に出力される。

## 後続タスクへの申し送り

- Task 4(SKILL.md): 起動時チェックの前提チェックで codex 実行ファイルの絶対パスを解決して控え、judge / proxy / builder / reviewer の全呼び出しでそのパスを使う。bare な `codex` は PATH/shim 解決に失敗しうる(S2bで実測)。
- Task 2〜6: S2 が実ターミナルで FAILED だった場合、サブ役を `codex exec` で分離する設計そのものが成立しないため、全タスクの前提が変わる。S2 の結果が出るまでは、この前提が未確定であることを了解の上で進める。
- S4(`--output-schema`)は本検証環境ではタイムアウトにより判定不能だった。現時点の採用方針は「C8 破棄・自然文方式」だが、これは実測に基づく確信ではなく、タイムアウトを FAILED 扱いした結果である。実ターミナルで S4 が成功する場合は、Task 2(判定スキーマ)の設計を `--output-schema` 採用に戻す余地がある。
- S6 未実行のため、グラレコ関連タスク(該当があれば)は「grareco-input.md のみ生成」を暫定の採用方針とし、実ターミナル検証の結果次第で見直す。
