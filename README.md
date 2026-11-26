# 半導体フロントエンド設計・100本ノック

SystemVerilog RTL / マイクロアーキテクチャ設計の100本ノックを管理するRepositoryです。

## 運用

- **1問 = 1 GitHub Issue**
- **Day番号 = Issue番号** とする（Day01 = Issue #1）
- Open IssueがBacklog。解答・レビュー完了後にCloseする
- 状態は `Todo / Solving / Review / Done / Blogged / Replace` を使う
- 解答RTLは `problems/dayXX/solution.sv`
- 問題メモ・最終解説は `problems/dayXX/README.md`
- 新問を作る前にこのIndexと既存Issueを検索し、重複を避ける
- 単なるbit幅変更、port数変更、parameterizeだけの派生は原則として新問に数えない

## 現在の進捗

- Closed / Completed: 39問
- Closed / Duplicate (`Replace`): 4問
- Open / Review: 0問
- Open / Todo: 17問
- Open Issue合計: 17問

未消化問題は [Open Issues](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues?q=is%3Aissue%20state%3Aopen) だけ見れば確認できます。

## 問題台帳

| No. | Issue | Problem | Status | Note |
|---:|---:|---|---|---|
| 01 | [#1](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/1) | Ready/Valid 1-entry FIFO | Blogged | canonical |
| 02 | [#2](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/2) | Power-of-two Synchronous FIFO | Blogged | canonical |
| 03 | [#3](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/3) | 3-requester Round-Robin Arbiter | Done | canonical |
| 04 | [#4](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/4) | 2-stage Elastic Pipeline | Blogged | canonical |
| 05 | [#5](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/5) | Pulse CDC — Toggle Synchronizer | Blogged | canonical |
| 06 | [#6](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/6) | Async Input + Debounce | Done | canonical |
| 07 | [#7](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/7) | Fixed-latency Operation Wrapper | Blogged | [blog](blog/day07-fixed-latency-operation-wrapper.md) |
| 08 | [#8](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/8) | W1C Interrupt Status | Blogged | [blog](blog/day08-w1c-interrupt-status.md) |
| 09 | [#9](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/9) | LSB Priority Encoder | Done | canonical |
| 10 | [#10](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/10) | Scoreboard Issue Control | Done | canonical |
| 11 | [#11](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/11) | Arbitrary-depth FIFO | Blogged | [blog](blog/day11-arbitrary-depth-fifo.md) |
| 12 | [#12](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/12) | 2-master→1-slave Ready/Valid Fixed-priority Arbiter | Done | canonical |
| 13 | [#13](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/13) | 2FF Synchronizer + Edge Detect | Done | canonical |
| 14 | [#14](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/14) | Skid Buffer | Done | canonical |
| 15 | [#15](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/15) | 4-requester Round-Robin Arbiter | Done | canonical |
| 16 | [#16](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/16) | Ready/Valid Fork | Done | canonical |
| 17 | [#17](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/17) | Ready/Valid Join | Done | canonical |
| 18 | [#18](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/18) | Credit-based Flow Control | Done | canonical |
| 19 | [#19](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/19) | In-order Completion Queue | Blogged | [blog](blog/day19-in-order-completion-queue.md) |
| 20 | [#20](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/20) | Banked Register File | Blogged | [blog](blog/day20-banked-register-file.md) |
| 21 | [#21](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/21) | Store-to-Load Forwarding | Blogged | [blog](blog/day21-store-to-load-forwarding.md) |
| 22 | [#22](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/22) | Killable Pipeline | Blogged | [blog](blog/day22-killable-pipeline.md) |
| 23 | [#23](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/23) | 2-master→1-slave RR Ready/Valid Arbiter | Blogged | [blog](blog/day23-rr-ready-valid-arbiter.md) |
| 24 | [#24](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/24) | Tree-PLRU Replacement Controller | Blogged | [blog](blog/day24-tree-plru.md) |
| 25 | [#25](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/25) | SEC-DED ECC for 32-bit Data | Done | canonical |
| 26 | [#26](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/26) | Ready/Valid Join variant | Replace | duplicate of #17 |
| 27 | [#27](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/27) | 2-bit Saturating Counter BHT Branch Predictor | Blogged | canonical |
| 28 | [#28](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/28) | Load Aligner | Blogged | canonical |
| 29 | [#29](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/29) | Store Aligner / Byte Enable Generator | Blogged | canonical |
| 30 | [#30](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/30) | Priority Encoder + Wakeup Selector | Blogged | [blog](blog/day30-priority-wakeup-selector.md) |
| 31 | [#31](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/31) | Leading Zero Counter | Blogged | canonical |
| 32 | [#32](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/32) | 2-source Operand Wakeup | Blogged | [blog](blog/day32-two-source-operand-wakeup.md) |
| 33 | [#33](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/33) | 2-way Cache Tag Lookup + Multi-hit Detection | Blogged | [blog](blog/day33-cache-tag-lookup.md) |
| 34 | [#34](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/34) | Reset Synchronizer — Async Assert / Sync Deassert | Done | canonical |
| 35 | [#35](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/35) | Pulse Synchronizer | Replace | duplicate of #5 |
| 36 | [#36](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/36) | 2-bit Saturating Counter | Replace | subset/duplicate of #27 |
| 37 | [#37](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/37) | Byte-granular Store-to-Load Forwarding | Blogged | [blog](blog/day37-byte-store-load-forward.md) |
| 38 | [#38](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/38) | Load Queue Memory Ordering Violation Detection | Blogged | [blog](blog/day38-load-queue-violation.md) |
| 39 | [#39](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/39) | SECDED ECC Encoder / Decoder | Replace | duplicate of #25 |
| 40 | [#40](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/40) | AXI Burst Address Generator | Blogged | [blog](blog/day40-axi-burst-addr-gen.md) |
| 41 | [#41](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/41) | Gray Code Counter | Blogged | [blog](blog/day41-gray-counter.md) |
| 42 | [#42](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/42) | Multi-bit CDC Handshake (4-phase req/ack) | Blogged | [blog](blog/day42-cdc-handshake.md) |
| 43 | [#43](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/43) | Asynchronous FIFO | Blogged | [blog](blog/day43-async-fifo.md) |
| 44 | [#44](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/44) | UART Transmitter (8N1) | Todo | canonical |
| 45 | [#45](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/45) | UART Receiver (8N1, 16x Oversampling) | Todo | canonical |
| 46 | [#46](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/46) | SPI Master (mode 0 / mode 3) | Todo | canonical |
| 47 | [#47](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/47) | Ready/Valid Width Converter (32→8, 8→32) | Todo | canonical |
| 48 | [#48](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/48) | Barrel Shifter | Todo | canonical |
| 49 | [#49](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/49) | Saturating Adder / Subtractor | Todo | canonical |
| 50 | [#50](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/50) | Sequential Multiplier (shift-add) | Todo | canonical |
| 51 | [#51](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/51) | Sequential Divider (restoring, RISC-V rules) | Todo | canonical |
| 52 | [#52](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/52) | CRC-32 (8-bit parallel) | Todo | canonical |
| 53 | [#53](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/53) | PWM + Prescaler (shadow register) | Todo | canonical |
| 54 | [#54](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/54) | FIFO on a Synchronous-read SRAM | Todo | canonical |
| 55 | [#55](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/55) | SRAM Read-During-Write Bypass | Todo | canonical |
| 56 | [#56](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/56) | AXI4-Lite Slave Register Block | Todo | canonical |
| 57 | [#57](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/57) | Blocking Direct-mapped Cache (read-only) | Todo | canonical |
| 58 | [#58](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/58) | Physical Register Free List | Todo | canonical |
| 59 | [#59](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/59) | RISC-V CSR Bank + Illegal Access Check | Todo | canonical |
| 60 | [#60](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/60) | Age Matrix Oldest-first Select | Todo | canonical |

## Statusの意味

- `Todo`: 未着手
- `Solving`: 回答作成中
- `Review`: 初版回答済み、レビュー・修正中
- `Done`: 合格
- `Blogged`: 合格後に技術記事化済み
- `Replace`: 重複等のため、新規テーマへ差し替える番号

GitHub上では `Done / Blogged` は **Closed (completed)**、`Replace` は **Closed (duplicate)**、`Todo / Solving / Review` は **Open** として管理します。

## 今後の流れ

1. Open Issueから1問選ぶ
2. Issue本文の仕様・制約・Corner Case・提出物を確認する
3. `problems/dayXX/solution.sv` を作成する
4. ChatGPTでレビューする
5. 必要な修正を行う
6. 合格したらIssueをCloseする
7. 必要ならブログ化し、Issue/READMEへURLを追記する

## 重複防止

新問を追加する前に、READMEと既存Issueを検索する。同じ回路名だけでなく**設計上の核心が同じか**で判定し、単なるport数・bit幅・parameterize変更は原則として別問題にしない。
