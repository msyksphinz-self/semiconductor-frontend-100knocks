# Workflow

## 基本方針

- 1問 = 1 Issue
- 問題を解く場所と、進捗を一覧する場所を分ける
- IssueをCloseしたらその問題は完了
- 新問作成前にREADMEとIssue検索で重複チェックする

## Status

- `Todo`: 未着手
- `Solving`: 回答作成中
- `Review`: 初版回答済み、レビュー・修正中
- `Done`: 合格
- `Blogged`: 合格後に技術記事化済み
- `Replace`: 重複などで差し替え対象

## 重複防止ルール

- 同じ回路名だけでなく、設計上の核心が同じなら重複扱い
- bit幅変更、port数変更、parameterizeだけの派生は原則新問にしない
- 発展版として残す場合は、元問題との差分をIssue冒頭に明記する
- Wakeup/Arbiter/Ready-Valid/FIFO/CDCの近似問題は特に慎重に照合する

## 1問の流れ

1. IssueをOpen
2. 問題文、仕様、制約、Corner Case、提出物を記載
3. `problems/dayXX/solution.sv` に回答を書く
4. ChatGPTレビュー
5. 修正版を反映
6. 合格したらIssueをClose
7. ブログ化したらREADME上のStatusを `Blogged` に更新
