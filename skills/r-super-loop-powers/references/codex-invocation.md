# codex委譲 実行規約(Claude版)

SKILL.md の起動時チェック・A-2〜A-4(技術PM)・B-5(高信頼の技術レビュー)・Learning(グラレコ)から参照される。**codex を呼ぶときは必ずこの規約に従う。** codex は3ロールすべて**読み取り専用**で、実装はしない(実装役は Sonnet サブエージェント。SKILL.md B-2)。

このディレクトリの `bin/` にある3本のスクリプトが規約の実体である。**PowerShellを自分で組み立てて codex を直接叩かない。** 手書きの起動コマンドは、`< /dev/null` の欠落・POSIXパス・終了確認の省略といった失敗を毎回作り直すからである(下記「実測された失敗」参照)。

| スクリプト | 役割 | 呼ぶ回数 |
|---|---|---|
| `bin/codex-preflight.ps1` | codex実体の解決・バージョン・認証・モデル疎通を確認し `codex-env.json` を書く | ゴールごとに1回 |
| `bin/codex-run.ps1` | 委譲を1件起動して**即座に戻る**(分離プロセスで走り続ける) | 委譲ごとに1回 |
| `bin/codex-status.ps1` | その委譲が**実際にどうなったか**を機械的に判定する | 完了するまで繰り返し |

---

## 1. 実測された失敗と、規約がそれをどう防ぐか

すべて `codex-cli 0.153.4` / Windows 11 での実測。

| 失敗 | 何が起きるか | 防ぎ方 |
|---|---|---|
| **失敗が成功に見える** | 存在しないモデル等でcodexが即死すると、**exit 1 / stdout 0バイト / エラーはstderrだけ**。「プロセスが消えた=完了」で判定すると、3秒で死んだ実行と40分成功した実行が**完全に同一に見える** | `codex-run.ps1` が終了コードを `<label>.exit` に必ず書き、`codex-status.ps1` が `STATUS: FAILED` を返す |
| **完了を確認できない** | `--json` なしだと stdout には**最終回答しか出ない**ため、進捗も完了イベントも無い。ラッパー末尾の `echo` 完了マーカーはプロセス終了に間に合わないことがある | `--json` で `turn.completed` を受け取る。`<label>.exit` は**最後に、リネームで**書かれるので、存在すれば必ず完了 |
| **ハングする** | codexは毎回 `Reading additional input from stdin...` を出す。stdinを閉じないと入力待ちで止まる(既知の deadlock: openai/codex#972) | プロンプトは常にファイルからstdinへリダイレクトする(`exec -`) |
| **`batch file arguments are invalid`** | `codex` を bare で呼ぶと mise 等のシム(`.cmd`)に当たり、バッチ層が複数行引数を壊す | `codex-preflight.ps1` が実体(`node.exe` + `codex.js`、または `codex.exe`)まで解決する |
| **原因不明のハング** | `-o` にPOSIXパスを渡すとWindowsバイナリが解決できない | スクリプトが常にネイティブ絶対パスへ正規化する |
| **codexがプロセス系スキルを始める** | ユーザー設定の superpowers プラグインが委譲先にも読み込まれ、codexが最初に `using-superpowers` → `brainstorming` → `writing-plans` のSKILL.mdを読んで設計・計画をやり直そうとする(過去37委譲中36件で発生) | `codex-run.ps1` が既定で `--disable plugins` を付ける(`-c plugins."superpowers@...".enabled=false` では**消えないことを実測**)。さらに `-Role` のロール指示でプロセス系スキルを起動しないと明示する |
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

- `MODEL_PROBE: FAILED` → `gpt-6.1-sol` がこのアカウントで使えない。**黙って別モデルへ落とさない**。代替はユーザーが指名した場合のみ `-Model` で渡す。

### 2-2. 委譲する

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\codex-run.ps1" `
  -EnvFile   "<goal-dir>\codex-env.json" `
  -Label     "brainstorm-techpm-1" `
  -PromptFile "<goal-dir>\codex-runs\brainstorm-techpm-1.prompt.md" `
  -WorkDir   "<対象プロジェクトのルート>" `
  -RunDir    "<goal-dir>\codex-runs" `
  -Role      techpm `
  -TimeoutMinutes 30
```

すぐに戻る。`RUN: STARTED` と `NEXT:`(そのまま実行できる status コマンド)が出る。

- `-Role` は必須で `techpm`(A-2〜A-4)/ `reviewer`(高信頼のB-5)/ `grareco`(Learning)。**すべて `-s read-only` 固定**で、サンドボックスを選ぶ引数は無い。モデルは codex-env.json の `model`(`gpt-6.1-sol`)。実行契約の後に役割別のロール指示が自動で入る。
- effort の既定は techpm / reviewer = `max`、grareco = `medium`。通常は指定しない。
- プラグインは既定で無効(`--disable plugins`)。組み込みのシステムスキル(imagegen 等)は残る。
- `-Label` は委譲ごとに一意にする(`[A-Za-z0-9._-]+`)。同じラベルで実行中のものがあると起動を拒否する。
- プロンプトの先頭には、**実行契約**(スコープ外禁止・コミット禁止・要件再定義禁止・否定リスト・最終メッセージが唯一の出力・**読み取り専用**)→ **ロール憲章**(`references/roles.md` の全体図+該当ロールの節。見つからなければ `WARN: roles section not found` を出して省く)→ **ロール指示** の順で自動で差し込まれ、その後にタスク本文が続く。

### 2-3. 完了を待つ

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\bin\codex-status.ps1" `
  -RunDir "<goal-dir>\codex-runs" -Label "brainstorm-techpm-1" -WaitMinutes 9
```

`-WaitMinutes 9` は完了まで最大9分ブロックする(ツールのタイムアウトに収まる上限)。`RUNNING` が返ったら同じコマンドを繰り返す。

### 2-4. STATUS の読み方 — これが受け入れ判定そのもの

| STATUS | 意味 | やること |
|---|---|---|
| `OK` | 完了し、報告も整合している | `FINAL_MESSAGE_FILE` を読んで回答として採用する |
| `FAILED` | 非ゼロ終了、または `turn.failed` | **実装済みとして扱わない。** 原因が認証・モデル可用性ならユーザーへ報告して停止 |
| `SUSPECT` | exit 0 だが `turn.completed` が無い / 最終メッセージが空 | 失敗として扱い、再委譲 |
| `TIMEOUT` | タイムアウトで強制終了 | 範囲を分割するかeffortを下げて再委譲。**書きかけのファイルが残っているので先に `git status`** |
| `RUNNING` | 進行中 | もう一度 `-WaitMinutes 9` |
| `STALLED` | 生きているが `-StallMinutes`(既定10分)無音 | 1回待って、まだ無音なら `-Abort` |
| `LOST` | exitファイルを書かずにプロセスが消えた | 何も完了していない。`git status` を見てから再委譲 |

**`OK` 以外を成功として扱わない**(SKILL.md ゲート保護ルール8)。status の終了コードも `OK` のときだけ 0 になる。

補助的に出る行:

- `WARN: codex touched N off-limits path(s)` — codexがスキルファイル等を読みに行った兆候。回答より探索に時間を使った可能性がある。
- `WARN: stderr looks like an auth failure` — `codex login` が必要。
- `THREAD_ID:` — グラレコの画像回収に使う(SKILL.md Learning 2)。

### 2-5. 中断する

```powershell
... \bin\codex-status.ps1 -RunDir "<goal-dir>\codex-runs" -Label "m1-review" -Abort
```

プロセスツリーを落とし、exitファイルを書いて中断を記録する。

---

## 3. 既知の環境問題

### その他

- **`python3` を使わない。** 環境によっては Microsoft Store のスタブが入っており、`Python` とだけ出力して失敗する。JSONLの解析が必要なら `node`(codexの実体と同じもの)を使う。
- **報告ファイルを `Get-Content` の既定エンコーディングで読まない。** Windows PowerShell 5.1 の既定はANSIで、日本語が文字化けする。`Get-Content -Encoding utf8` かReadツールを使う。ファイル自体はUTF-8で正しい。
- **`CODEX_HOME` が端末アプリによって書き換えられていることがある。** preflight が `AUTH:` 行で実際に使われている場所を表示するので、想定と違う場合はそれを疑う。

---

## 4. プロンプトに必ず入れる要素

実行契約・ロール憲章・ロール指示は自動で先頭に付くので、**タスク固有の内容だけ**を書く。

- **techpm**: SKILL.md「技術PM(Codex)共通契約」のプロンプト必須要素
- **reviewer**: SKILL.md B-5(高信頼)に列挙した入力。特に委譲前の HEAD と各委譲の `impl-check.ps1` の `CHANGED_FILES_ACTUAL:` 行を渡し、`git diff <base>` と `git status --porcelain --untracked-files=all` で実際の変更を見させる(未追跡の新規ファイルは `git diff` に出ないので直接読ませる)
- **grareco**: `templates/grareco-prompt.md`

---

## 5. 生成物

`-RunDir` に委譲ごとに残る。`submission.md` の検証証拠として参照できる:

| ファイル | 中身 |
|---|---|
| `<label>.prompt.txt` | 実際に送られたプロンプト(実行契約込み) |
| `<label>.out.jsonl` | イベントストリーム。進捗も完了も全部ここ |
| `<label>.last.txt` | 最終メッセージ = 回答 |
| `<label>.exit` | 終了コード。**存在=完了** |
| `<label>.done.json` | 終了コード・タイムアウト有無・所要時間 |
| `<label>.meta.json` | 起動時のロール・モデル・effort・sandbox(常に read-only)・プラグイン有無・実コマンド |
| `<label>.err.txt` | stderr |

`*.out.jsonl` は長い実行で大きくなる。リポジトリに含めたくない場合は `.gitignore` に `codex-runs/*.jsonl` を足す(`last.txt` は証拠なので残す)。
