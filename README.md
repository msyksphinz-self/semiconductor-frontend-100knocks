# 半導体フロントエンド設計・100本ノック

SystemVerilog RTL / マイクロアーキテクチャ設計の100本ノックを管理するRepositoryです。

## 運用

- 1問 = 1 GitHub Issue
- Issueが未解決なら未消化、Closeしたら完了
- 状態は `Todo / Solving / Review / Done / Blogged / Replace` を使う
- 解答RTLは `problems/dayXX/solution.sv`
- 問題メモ・最終解説は `problems/dayXX/README.md`
- 新問を作る前にこのIndexと既存Issueを検索し、重複を避ける
- 単なるbit幅変更、port数変更、parameterizeだけの派生は原則として新問に数えない

## 問題台帳

| No. | Problem | Status | Note |
|---:|---|---|---|
| 01 | Ready/Valid 1-entry FIFO | Blogged | canonical |
| 02 | Power-of-two Synchronous FIFO | Blogged | canonical |
| 03 | 3-requester Round-Robin Arbiter | Done | canonical |
| 04 | 2-stage Elastic Pipeline | Blogged | canonical |
| 05 | Pulse CDC — Toggle Synchronizer | Blogged | canonical |
| 06 | Async Input + Debounce | Todo | canonical |
| 07 | Fixed-latency Operation Wrapper | Todo | canonical |
| 08 | W1C Interrupt Status | Todo | canonical |
| 09 | LSB Priority Encoder | Done | canonical |
| 10 | Scoreboard Issue Control | Done | canonical |
| 11 | Arbitrary-depth FIFO | Todo | canonical |
| 12 | 2-master→1-slave Ready/Valid Fixed-priority Arbiter | Done | canonical |
| 13 | 2FF Synchronizer + Edge Detect | Done | canonical |
| 14 | Skid Buffer | Done | canonical |
| 15 | 4-requester Round-Robin Arbiter | Done | canonical |
| 16 | Ready/Valid Fork | Done | canonical |
| 17 | Ready/Valid Join | Done | canonical |
| 18 | Credit-based Flow Control | Done | canonical |
| 19 | In-order Completion Queue | Review | canonical |
| 20 | Banked Register File | Review | canonical |
| 21 | Store-to-Load Forwarding | Todo | canonical |
| 22 | Killable Pipeline | Todo | canonical |
| 23 | 2-master→1-slave RR Ready/Valid Arbiter | Todo | close to #12/#15 |
| 24 | Tree-PLRU Replacement Controller | Todo | canonical |
| 25 | SEC-DED ECC for 32-bit Data | Done | canonical |
| 26 | Ready/Valid Join variant | Replace | duplicate of #17 |
| 27 | 2-bit Saturating Counter BHT Branch Predictor | Blogged | canonical |
| 28 | Load Aligner | Blogged | canonical |
| 29 | Store Aligner / Byte Enable Generator | Blogged | canonical |
| 30 | Priority Encoder + Wakeup Selector | Todo | canonical |
| 31 | Leading Zero Counter | Blogged | canonical |
| 32 | 2-source Operand Wakeup | Todo | close to #30/#10; no further similar variants |
| 33 | 2-way Cache Tag Lookup + Multi-hit Detection | Todo | canonical |
| 34 | Reset Synchronizer — Async Assert / Sync Deassert | Done | canonical |
| 35 | Pulse Synchronizer | Replace | duplicate of #5 |
| 36 | 2-bit Saturating Counter | Replace | subset/duplicate of #27 |
| 37 | Byte-granular Store-to-Load Forwarding | Todo | advanced variant of #21; uniqueness review |
| 38 | Load Queue Memory Ordering Violation Detection | Todo | canonical |
| 39 | SECDED ECC Encoder / Decoder | Replace | duplicate of #25 |
| 40 | AXI Burst Address Generator | Todo | canonical |

## Statusの意味

- `Todo`: 未着手
- `Solving`: 回答作成中
- `Review`: 初版回答済み、レビュー・修正中
- `Done`: 合格
- `Blogged`: 合格後に技術記事化済み
- `Replace`: 重複等のため、新規テーマへ差し替える番号

## 今後の流れ

1. Backlogから1問選ぶ、または新問を追加する
2. Issue本文に仕様・制約・Corner Case・提出物を書く
3. `solution.sv`を作成する
4. ChatGPTでレビューする
5. 修正完了後にIssueをCloseする
6. 必要ならブログ化してURLを追記する
