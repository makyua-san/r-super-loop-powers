# codex委譲 実行規約(Claude版)

SKILL.md の起動時チェック・B-2・Learning から参照される。**codex を呼ぶときは必ずこの規約に従う。**

このディレクトリの `bin/` にある3本のスクリプトが規約の実体である。**PowerShellを自分で組み立てて codex を直接叩かない。** 手書きの起動コマンドは、`< /dev/null` の欠落・POSIXパス・終了確認の省略といった失敗を毎回作り直すからである(下記「実測された失敗」参照)。

| スクリプト | 役割 | 呼ぶ回数 |
|---|---|---|
| `bin/codex-preflight.ps1` | codex実体の解決・バージョン・認証・モデル疎通・**書き込み可否**を確認し `codex-env.json` を書く | ゴールごとに1回 |
| `bin/codex-run.ps1` | 委譲を1件起動して**即座に戻る**(分離プロセスで走り続ける) | 委譲ごとに1回 |
| `bin/codex-status.ps1` | その委譲が**実際にどうなったか**を機械的に判定する | 完了するまで繰り返し |

---

## 1. 実測された失敗と、規約がそれをどう防ぐか

すべて `codex-cli 0.153.4` / Windows 11 での実測。

| 失敗 | 何が起きるか | 防ぎ方 |
|---|---|---|
| **失敗が成功に見える** | 存在しないモデル等でcodexが即死すると、**exit 1 / stdout 0バイト / エラーはstderrだけ**。「プロセスが消えた=完了」で判定すると、3秒で死んだ実行と40分成功した実行が**完全に同一に見える** | `codex-run.ps1` が終了コードを `<label>.exit` に必ず書き、`codex-status.ps1` が `STATUS: FAILED` を返す |
| **空回りを成功として扱う** | codexが「サンドボックスを作れず何もできませんでした」と丁寧に報告して **exit 0** で終わる。自己検証報告は返るが中身は「未実施」 | `--output-schema` で報告を構造化し、`codex-status.ps1` が `blocked` / `changed_files` / `verification` / `acceptance_criteria` を読んで `STATUS: BLOCKED` / `INCOMPLETE` に落とす |
| **完了を確認できない** | `--json` なしだと stdout には**最終回答しか出ない**ため、進捗も完了イベントも無い。ラッパー末尾の `echo` 完了マーカーはプロセス終了に間に合わないことがある | `--json` で `turn.completed` を受け取る。`<label>.exit` は**最後に、リネームで**書かれるので、存在すれば必ず完了 |
| **ハングする** | codexは毎回 `Reading additional input from stdin...` を出す。stdinを閉じないと入力待ちで止まる(既知の deadlock: openai/codex#972) | プロンプトは常にファイルからstdinへリダイレクトする(`exec -`) |
| **`batch file arguments are invalid`** | `codex` を bare で呼ぶと mise 等のシム(`.cmd`)に当たり、バッチ層が複数行引数を壊す | `codex-preflight.ps1` が実体(`node.exe` + `codex.js`、または `codex.exe`)まで解決する |
| **原因不明のハング** | `--output-schema` / `-o` にPOSIXパスを渡すとWindowsバイナリが解決できない | スクリプトが常にネイティブ絶対パスへ正規化する |
| **委譲が途中で消える** | ターン境界でセッションのプロセスツリーがkillされ、TDDのred段階で止まったまま気づけない | ワーカーを `Win32_Process.Create` で起動し、このシェルのジョブ外に出す。それでも消えた場合は `STATUS: LOST` として**成功と区別する** |

**最重要**: 「プロセスが消えた」は完了条件ではない。**唯一の完了条件は `<label>.exit` が存在すること**であり、成否は `codex-status.ps1` の `STATUS` が決める。

---

## 2. 使い方

### 2-1. 起動時(ゴールごとに1回)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\codex-preflight.ps1" `
  -EnvOut "<goal-dir>\codex-env.json"
```

`PREFLIGHT: OK` で終われば、以後の全呼び出しは `-EnvFile "<goal-dir>\codex-env.json"` だけを渡せばよい。
`PREFLIGHT: FAILED` の場合は `REASON:` 行をそのままユーザーに伝えて**停止する**。特に:

- `MODEL_PROBE: FAILED` → 実装役のモデルがこのアカウントで使えない。**黙って別モデルへ落とさない**。
- `SANDBOX_WRITE: FAILED` → 下記「3. 既知の環境問題」を参照。

### 2-2. 委譲する

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\codex-run.ps1" `
  -EnvFile   "<goal-dir>\codex-env.json" `
  -Label     "m1-impl" `
  -PromptFile "<goal-dir>\codex-runs\m1-impl.prompt.md" `
  -WorkDir   "<対象プロジェクトのルート>" `
  -RunDir    "<goal-dir>\codex-runs" `
  -Effort    "<B-1でFableが選んだ値>" `
  -OutputSchema "<skill-dir>\schemas\impl-report.json" `
  -TimeoutMinutes 60
```

すぐに戻る。`RUN: STARTED` と `NEXT:`(そのまま実行できる status コマンド)が出る。

- `-Label` は委譲ごとに一意にする(`[A-Za-z0-9._-]+`)。同じラベルで実行中のものがあると起動を拒否する。
- `-Effort` は `low | medium | high | xhigh | max | ultra`。**`xhigh` 以上は `high` の桁違いのトークンを使い、長時間ハングの報告がある**。B-1でFableが選んだ値を使い、迷ったら `high`。
- `-OutputSchema` を付けると最終メッセージが `schemas/impl-report.json` に従うJSONになり、status が中身まで検査できる。**B-2では必ず付ける。**
- **`-Sandbox` は通常指定しない。** プリフライトがこの環境で実際に書き込めると確認したモードが `codex-env.json` から自動で使われる。明示指定は、そのマイルストーンだけ読み取り専用にしたい場合(`read-only`)など例外的な用途に限る。
- プロンプトの先頭には**実行契約**(スコープ外禁止・コミット禁止・要件再定義禁止・否定リスト・最終メッセージが唯一の出力)が自動で差し込まれる。自分で書かなくてよい。

### 2-3. 完了を待つ

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\codex-status.ps1" `
  -RunDir "<goal-dir>\codex-runs" -Label "m1-impl" -WaitMinutes 9
```

`-WaitMinutes 9` は完了まで最大9分ブロックする(ツールのタイムアウトに収まる上限)。`RUNNING` が返ったら同じコマンドを繰り返す。

### 2-4. STATUS の読み方 — これが受け入れ判定そのもの

| STATUS | 意味 | やること |
|---|---|---|
| `OK` | 完了し、報告も整合している | `FINAL_MESSAGE_FILE` を読んでB-3の受け入れへ進む |
| `FAILED` | 非ゼロ終了、または `turn.failed` | **実装済みとして扱わない。** 原因が認証・モデル可用性ならユーザーへ報告して停止 |
| `BLOCKED` | 完了したが報告が `blocked: true` | **実装済みとして扱わない。** 阻害要因を解消するかB-4エスカレーション |
| `INCOMPLETE` | 完了したが受け入れ条件が未達 / 検証が失敗 / 変更ファイルが0 / 検証が1件も実行されていない | **submission.mdを書かない。** 不足点を引用して再委譲 |
| `CONTRACT_VIOLATION` | 報告が `committed: true`(コミット禁止違反) | 先に `git log` / `git status` を確認してから判断 |
| `SUSPECT` | exit 0 だが `turn.completed` が無い / 最終メッセージが空 | 失敗として扱い、再委譲 |
| `TIMEOUT` | タイムアウトで強制終了 | 範囲を分割するかeffortを下げて再委譲。**書きかけのファイルが残っているので先に `git status`** |
| `RUNNING` | 進行中 | もう一度 `-WaitMinutes 9` |
| `STALLED` | 生きているが `-StallMinutes`(既定10分)無音 | 1回待って、まだ無音なら `-Abort` |
| `LOST` | exitファイルを書かずにプロセスが消えた | 何も完了していない。`git status` を見てから再委譲 |

**`OK` 以外を成功として扱わない**(SKILL.md ゲート保護ルール8)。status の終了コードも `OK` のときだけ 0 になる。

補助的に出る行:

- `WARN: codex touched N off-limits path(s)` — codexがスキルファイル等を読みに行った兆候。実装より探索に時間を使った可能性がある。
- `WARN: stderr looks like an auth failure` — `codex login` が必要。
- `WARN: codex could not build its Windows sandbox` — 下記参照。
- `NEW_ASSUMPTION:` / `UNRESOLVED:` — そのまま `assumptions.md` へ転記する。
- `THREAD_ID:` — 同じセッションを続けたい場合に使える(通常は不要)。

### 2-5. 中断する

```powershell
... \bin\codex-status.ps1 -RunDir "<goal-dir>\codex-runs" -Label "m1-impl" -Abort
```

プロセスツリーを落とし、exitファイルを書いて中断を記録する。

---

## 3. 既知の環境問題

### `-s workspace-write` が使えない環境がある(実測)

Windows で `workspace-write sandbox has no writable root capability SIDs` が出ると、codexは**シェルコマンドを1つも実行できない**まま、丁寧な最終報告を返して exit 0 で終わる。放置すると全マイルストーンが空回りする。

`codex-preflight.ps1` は実際に1ファイル書かせて確認し、失敗すれば `SANDBOX_WRITE: FAILED` で停止する。回避策はcodexのサンドボックスを外すことだが、これは **policy.md 否定リスト4(セキュリティの扱いの変更)** に該当する。

したがって:

1. ユーザーに「この環境では codex の workspace-write サンドボックスが機能しないこと」「回避にはサンドボックスを外す必要があること」を提示して**判断を仰ぐ**。
2. 承認された場合のみ、プリフライトを `-AllowUnsandboxed` 付きで再実行する。プリフライトは**まず workspace-write を試し**(最小権限優先)、駄目なときだけ `danger-full-access` に落ちて**それが実際に書けることを確認**してから `codex-env.json` に記録する。以後の委譲は `-Sandbox` を書かなくてもそのモードで走る。
3. **`assumptions.md` と `decisions.md` に「codexをサンドボックスなしで実行している(ユーザー承認済み・日付)」を記録する。**
4. 承認されない場合は委譲を行わない。**モデルの判断で `-AllowUnsandboxed` を付けない。**

`codex-run.ps1` は preflight が不可と判定した状態で `workspace-write` を指定すると**起動を拒否する**(何もしない委譲でトークンを捨てないため)。

**サンドボックスなしで動かしているときに何が変わるか**: codexは作業ディレクトリの外を含め任意のコマンドを実行できる。スコープを守らせているのは `codex-run.ps1` が注入する実行契約(プロンプト)だけであり、強制力はない。したがって (a) B-2のプロンプトで対象範囲を具体的に書く、(b) `codex-status.ps1` の `BOUNDARY_HIT:` / `WARN:` 行を毎回確認する、(c) `CONTRACT_VIOLATION`(コミット実行)が出たら必ず `git log` を見る、の3点の重要度が上がる。

### その他

- **`python3` を使わない。** 環境によっては Microsoft Store のスタブが入っており、`Python` とだけ出力して失敗する。JSONLの解析が必要なら `node`(codexの実体と同じもの)を使う。
- **報告ファイルを `Get-Content` の既定エンコーディングで読まない。** Windows PowerShell 5.1 の既定はANSIで、日本語が文字化けする。`Get-Content -Encoding utf8` かReadツールを使う。ファイル自体はUTF-8で正しい。
- **`CODEX_HOME` が端末アプリによって書き換えられていることがある。** preflight が `AUTH:` 行で実際に使われている場所を表示するので、想定と違う場合はそれを疑う。

---

## 4. プロンプトに必ず入れる要素(B-2)

実行契約は自動で先頭に付くので、**タスク固有の内容だけ**を書く:

1. 目的 — このマイルストーンが満たす受け入れ条件(`acceptance_criteria` にそのまま写させるので、検証可能な文にする)
2. 対象ファイル・変更範囲
3. 検証要求 — MVP: 受け入れ基準に直結する検証+未知低減に効く検証のみ / 高信頼: テストファースト+単体・結合・lint・型検査
4. 関連する未検証仮定(`assumptions.md` から)
5. 出力要求 — 「最終メッセージは指定されたJSONスキーマに従うこと」

禁止事項(コミット・要件再定義・否定リスト・`~/.claude/` 等への接触)は**書かなくてよい**。実行契約に含まれている。

---

## 5. 生成物

`-RunDir` に委譲ごとに残る。`submission.md` の検証証拠として参照できる:

| ファイル | 中身 |
|---|---|
| `<label>.prompt.txt` | 実際に送られたプロンプト(実行契約込み) |
| `<label>.out.jsonl` | イベントストリーム。進捗も完了も全部ここ |
| `<label>.last.txt` | 最終メッセージ = 自己検証報告 |
| `<label>.exit` | 終了コード。**存在=完了** |
| `<label>.done.json` | 終了コード・タイムアウト有無・所要時間 |
| `<label>.meta.json` | 起動時のモデル・effort・sandbox・実コマンド |
| `<label>.err.txt` | stderr |

`*.out.jsonl` は長い実行で大きくなる。リポジトリに含めたくない場合は `.gitignore` に `codex-runs/*.jsonl` を足す(`last.txt` は証拠なので残す)。
