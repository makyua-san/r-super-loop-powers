# grareco-spec — グラレコの構造データ(v1)

<!-- 作成者: Opus。プロジェクトに送り先(docs/r-super-loop-powers/grareco-sink.md)があるときだけ、grareco-input.md の直後に同じ文脈で書く。送り先(例: r-beads ハブ)が手描き風の図(PNG)にして、issue や記事に載せる。 -->

## 形式

```json
{"version": 1,
 "title": "<節目の見出し(32字以内)>",
 "stages": [
  {"label": "目的", "items": ["<24字以内>", "..."]},
  {"label": "実装", "items": []},
  {"label": "検証", "items": []},
  {"label": "判断", "items": []},
  {"label": "結果", "items": []}],
 "result": "<PASS / ACCEPT / 保留 など 12字以内>"}
```

- stages は「目的→実装→検証→判断→結果」の5段固定(この順・このラベル)。1段3項目以内、1項目24字以内、全体400字以内(超えるとハブが切り詰める)。
- 中身は grareco-input.md の要点から書く。未確定のことを確定として書かない(仮説は「仮説:」と書く)。
- **書かない語**: 個人名・URL・クライアント名・勤務先名・issue 番号(ABC-123 など)・bd id(rb-xxx)・ブランチ名・ファイルパス・秘密情報。見出しにも issue 番号を入れない。プロジェクト名は書いてよい。
- 送り先でも伏字処理をかける場合があるが、二重の安全のためにここで書かないこと。

## 送り方

送り方はプロジェクトの `docs/r-super-loop-powers/grareco-sink.md` に従う(このテンプレートには書かない)。
