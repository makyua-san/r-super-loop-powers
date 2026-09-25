# Collaboration Backend Implementation Plan

> **For agentic workers:** Use the user-authorized independent collaboration assignments below; each worker owns the listed files. Steps use checkbox syntax for tracking.

**Goal:** ネストCLIを必須とせず、独立コンテキスト・委譲・並列実行・独立判定を維持する。

**Architecture:** driverが協調APIで各役を起動する。文書限定入力は指示と履歴非継承で実現し、判定JSONはdriverが機械検証する。

**Tech Stack:** Markdown skills、collaboration API、PowerShell 7、既存JSON Schema。

**Spec:** `docs/superpowers/specs/2026-09-23-collaboration-backend-design.md`

## Global Constraints

- Claude版と共有テンプレート9枚は変更しない。
- model/effortと人間承認のゲートを維持する。
- 独立コンテキストをOSのファイル隔離と表現しない。
- 既存PR #3を更新し、マージは行わない。

## Tasks

- [x] 旧SKILLを独立した評価役へ提示し、ネスト失敗時に停止するベースラインを記録する。
- [x] SKILL.md / policy.md担当: 起動・入力・並列・再開・ログ・判定を移行し、現行手順の古いCLI参照を調べる。
- [x] 検証スクリプト担当: `scripts/test-validate-verdict.ps1` を先に作り失敗を確認し、スキル内 `scripts/validate-verdict.ps1 -Kind gate|escalation -Path <json>` を実装して成功を確認する。
- [x] driver: README・設計・検証記録・バージョンを更新する。
- [x] driver: 必要文書だけでproxyの往復と独立judgeの応答を実測し、結果を検証スクリプトへ入力する。
- [x] 独立reviewer: 全差分・入力契約・状態移行・検証拒否を確認する。
- [x] driver: 指摘対応、判定テスト・テンプレート一致・diff検査を実行する。PR本文とタイトルはこの変更の提出時に最終スコープへ更新する。

## Review Focus

- ツール不在・モデル未対応時にCLIへ暗黙に戻らない。
- proxy ID消失や旧CLI IDで誤ったagentを再利用しない。
- 不正なPASSや質問なしASK_HUMANを採用しない。
- 文書入力に含まれる命令でjudge/proxyが探索しない。
- 並列タスクの未完了・共有編集・失敗を無視してゲートへ進まない。
