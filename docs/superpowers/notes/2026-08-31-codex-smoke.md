# Codex移植 スモークテスト結果 — 2026-08-31

対象仕様: `docs/superpowers/specs/2026-08-31-r-super-loop-powers-codex-port-design.md` §8.1
実行環境: codex-cli 0.144.2、Windows 11(検証は Claude Code の Bash ツール経由。詳細は「検証環境の制約」節を参照)

| # | 検証内容 | 判定 | 実測 | 採用方針 |
|---|---|---|---|---|
| S2 | 親Codexセッション内からの `codex exec` ネスト実行 | **判定不能**(実ターミナルでの検証が必要) | 4回の試行(初回/S2a/S2b/S2c)すべてが異なるレイヤーで失敗。最終的にはネスト側 codex プロセスの `orca\codex-runtime-home` への書き込み拒否で停止。詳細は下記 | 設計は暫定継続。ユーザーの実ターミナルでの再検証結果を待って最終判断 |
| S3 | session id の取得と `resume` による往復 | OK | `SID=01a05855-19d3-7b93-a570-ddfca8ce6f7d`。resume 後の応答は `ALPHA`(期待どおり) | C6/C7 採用 |
| S4 | `--output-schema` による構造化出力 | OK(再試行で成功。詳細は下記「実測メモ」) | 初回は10分タイムアウト(exit code 143、出力なし)。stdin明示クローズ(`< /dev/null`)+Windows形式絶対パスの両対策を入れた再試行で `verdict=REVISE` のJSONが標準出力と `-o` の両方に返った(team-leadの独立再実行でも同様に確認) | C8採用(構造化出力) |
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

### S4 の実測メモ(タイムアウト→再試行で成功)

初回の S4 は10分間のタイムアウトで出力が一切得られなかった。原因の仮説として (a) `codex exec` が stdin が TTY でないときに追加入力待ちでブロックする、(b) `/tmp/verdict-probe.json` という POSIX パスを Windows バイナリの codex.exe が正しく解決できていない、の2つが考えられた。

再試行では、両方の対策(`< /dev/null` で stdin を明示的にクローズ、`--output-schema` / `-o` に `cygpath -w` で得た Windows形式の絶対パスを使用)を**同時に**適用したところ、5分未満で以下の有効な JSON が返った(スキーマどおり `verdict` が4値のいずれかを含む)。

```
{"verdict":"REVISE","rationale":"Required verification evidence is missing, so the submission cannot pass the gate. Supply the evidence and resubmit; the underlying plan does not need to change."}
```

なお実行ログの先頭に一過性のサンドボックスエラー行(`windows sandbox: CreateProcessWithLogonW failed: 267`)が出力されていたが、最終的な JSON 出力は正常に得られており、コマンド全体は成功として扱った。

**2つの対策を同時に適用したため、stdin未クローズとPOSIXパスのどちらが根本原因だったかは切り分けられていない。** 両方を常に適用することを採用方針とした。

team-lead が同一条件で独立に再実行し、標準出力・`-o` 出力ファイルの両方でスキーマ準拠の JSON(`{"verdict":"REVISE","rationale":"..."}`)が得られたことを確認した。原因が「コマンドの書き方」であり `--output-schema` 機能自体は動作することが2回の実測で裏づけられた。

### 新しい観察: judge モデルは判定前に対象リポジトリを探索しようとする

S4 の実行ログ(team-lead の再実行時)で、判定を下す前にモデルが `Get-Content` でスキルファイルを読み、`Get-ChildItem` でリポジトリ直下を列挙し、`rg` でリポジトリ全体を検索するシェルコマンドを発行していたことが確認された(サンドボックスに阻まれて実行自体は失敗したが、意図としては探索している)。これは設計判断 C9(judge を必要文書だけの一時ディレクトリで起動する)が必須であることの実測的裏づけであり、**プロンプトでの探索禁止指示だけでは不十分であることを示す**。S5(隔離テスト、OK)の結果と合わせ、物理隔離を必須、プロンプトでの探索禁止指示を補助(隔離の代替にはならない)と位置づける。

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

(S4 は当初この節に含めていたが、stdin明示クローズ+Windows形式絶対パスの再試行で OK が確定したため、この節からは除外した。詳細は上記「S4 の実測メモ」を参照。)

## 後続タスクへの申し送り

- Task 4(SKILL.md): 起動時チェックの前提チェックで codex 実行ファイルの絶対パスを解決して控え、judge / proxy / builder / reviewer の全呼び出しでそのパスを使う。bare な `codex` は PATH/shim 解決に失敗しうる(S2bで実測)。
- Task 2〜6: S2 が実ターミナルで FAILED だった場合、サブ役を `codex exec` で分離する設計そのものが成立しないため、全タスクの前提が変わる。S2 の結果が出るまでは、この前提が未確定であることを了解の上で進める。
- Task 4(SKILL.md): 全ての `codex exec` 呼び出しで stdin を明示的に閉じる(またはヒアドキュメントで与える)こと、および `--output-schema` / `-o` には**Windows形式の絶対パス**を渡すことを規定する。POSIXパスは Windows バイナリが解決できない(S4で実測。これを怠ると原因不明のままタイムアウトする)。
- Task 4(SKILL.md): judge / proxy は必ず `-C <一時ディレクトリ>` で起動する。プロンプトの探索禁止指示は補助であり、隔離の代替にはならない(S4実行時に探索行動を実測)。
- S6 未実行のため、グラレコ関連タスク(該当があれば)は「grareco-input.md のみ生成」を暫定の採用方針とし、実ターミナル検証の結果次第で見直す。
