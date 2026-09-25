# Codex GitHub形式の導入検証 — 2026-09-23

## 環境と対象

- Windows 11 Home (`10.0.26200`)、PowerShell、Codex desktop のシェルツールから実行
- `codex-cli 0.146.0`、ChatGPTでログイン済み
- `CODEX_HOME` は未設定。既定の `~/.codex` に導入
- リポジトリ: `makyua-san/r-super-loop-powers`
- 検証対象コミット: `08dbdec6555d4d83eb0ccf2f9cddf267e3f35b5a`
- プラグインバージョン: `0.1.0`

## S1: GitHub形式の導入 — OK

READMEどおり、ローカルパスへのフォールバックなしで順に実行した。

```powershell
codex plugin marketplace add makyua-san/r-super-loop-powers
codex plugin add r-super-loop-powers@r-super-loop-powers-marketplace
codex plugin list
```

両方の追加コマンドの終了コードは0。主要出力:

```text
Added marketplace `r-super-loop-powers-marketplace` from https://github.com/makyua-san/r-super-loop-powers.git.
Added plugin `r-super-loop-powers` from marketplace `r-super-loop-powers-marketplace`.
r-super-loop-powers@r-super-loop-powers-marketplace  installed, enabled  0.1.0
```

マーケットプレイスの取得先は `~/.codex/.tmp/marketplaces/r-super-loop-powers-marketplace`、導入先は `~/.codex/plugins/cache/r-super-loop-powers-marketplace/r-super-loop-powers/0.1.0`。取得先のHEADは上記コミットと一致した。

新規プロセスの初期スキル一覧を確認するため、空の一時ディレクトリで次のプローブを実行した。`$probeDir` は作成済みの一時ディレクトリの絶対パス、`$codexPath` は `Get-Command codex` で取得した実行ファイルの絶対パス。

```powershell
$prompt = 'This is an installation visibility probe, not a goal workflow. From the available skills catalog in your initial context only, list the exact name and SKILL.md path of every skill whose name contains r-super-loop-powers, and whether superpowers:brainstorming is available. Do not invoke skills, call tools, inspect files, or start a goal. If the requested skill is absent, say NONE.'
'' | & $codexPath exec -m gpt-5.6-sol -c model_reasoning_effort=medium `
  -s read-only -c approval_policy=never --skip-git-repo-check --ephemeral `
  -C $probeDir --json -o (Join-Path $probeDir 'skill-visibility-sol.txt') $prompt
```

終了コード0で、初期スキル一覧から次の回答が返った。スキルのワークフロー自体は起動していない。

- `r-super-loop-powers:r-super-loop-powers` と、上記導入先配下の `skills-codex/r-super-loop-powers/SKILL.md` の絶対パス
- `superpowers:brainstorming` available: **Yes**

追加確認:

- 導入先の `skills-codex/` 全13ファイルをクローン元とSHA-256で比較: 不一致0
- `./scripts/sync-templates.ps1 -Mode Verify`: `Verify OK (9 templates)`、終了コード0

### CLIと既定モデルの互換性

最初の可視性プローブはモデル指定なしで実行し、既定の `gpt-6-astra` が次のエラーで拒否された(終了コード1)。

```text
The 'gpt-6-astra' model requires a newer version of Codex. Please upgrade to the latest app or CLI and try again.
```

そのため、プラグインがdriverとして指定する `gpt-5.6-sol` / medium をコマンド単位で指定して再試行し、上記の成功を確認した。既定モデルの設定は変更していない。導入の成功と、CLI・モデルの互換性は区別する必要がある。

## S2: ネスト実行 — 判定不能を維持

起動時チェックに沿って、外側を `gpt-5.6-sol` / medium / `workspace-write`、内側を `gpt-5.6-luna` / low / `read-only` とした。両方で実行ファイルの絶対パス、`approval_policy=never`、`--skip-git-repo-check`、`--ephemeral` を指定し、内側にはツールを使わず `NESTED_OK` とだけ回答するよう指示した。

外側セッションは開始したが、内側コマンドを実行するシェルの起動が以下で失敗した。

```text
windows sandbox: CreateProcessWithLogonW failed: 2
```

JSONLの `command_execution` は `status=failed` / `exit_code=-1`。外側Codex自体は失敗を報告して終了コード0で完了したが、内側Codexの応答は得られていないため、S2成功とは判定しない。サンドボックス設定を緩めての再試行はしていない。

## 今回の検証範囲外

- S3〜S6の再検証、各サブ役の実運用、ゴールループのE2E完走
- Codex desktop の再起動後の補完表示・スキル起動
- 他のOS・CLIバージョン・新規アカウントでの導入

2026-08-31の記録は当時の結果として保持する。本記録により更新するのはGitHub形式の導入(S1)の検証状況のみ。
