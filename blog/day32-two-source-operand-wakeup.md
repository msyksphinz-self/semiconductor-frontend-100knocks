# 半導体フロントエンド設計100本ノック (32) 2-source Operand Wakeup

半導体フロントエンド設計100本ノック、第32問。

今回はIssue Queueの1 entry分について、2つのsource operandが揃ったかどうかを判定する回路を設計してみた。Day30のwakeupの続きである。

RTLは`assign`が3本だけなのだが、最初は入出力の信号が何を表しているのかがよく分からなかった。分かったつもりで書いたら、2つのsourceをORでつないでいた。

課題の詳細は[Day32 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/32)。

## 今回の問題：2-sourceのoperand wakeup

今回作るのは、**Issue Queueの1 entryについて、2つのsource operandがそれぞれ揃っているか、命令を発行できるかを判定する組合せ回路**。

[元の課題Issue #32](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/32)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- Issue Queueの1 entryに、source operandが2つある。
- wakeup portは1本（`wakeup_valid`、`wakeup_tag`）。broadcastされたtagと一致したsourceは、そのサイクルからreadyとして扱う（same-cycle wakeup）。
- `issue_ready = valid && src0_ready_now && src1_ready_now`。
- 2つのsourceが同じtagを待っている場合は、1回のbroadcastで両方readyになる。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module two_source_operand_wakeup
  (
    input  logic        entry_valid,
    input  logic        src0_ready,
    input  logic        src1_ready,
    input  logic [5: 0] src0_tag,
    input  logic [5: 0] src1_tag,
    input  logic        wakeup_valid,
    input  logic [5: 0] wakeup_tag,
    output logic        src0_ready_now,
    output logic        src1_ready_now,
    output logic        issue_ready
  );
    // ここにRTLを実装する
endmodule
```

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **`srcN_ready_now`に`entry_valid`を含めるか**：含める。entryがinvalidなら、3つの出力はすべて0になる。
- **すでにreadyなsourceのtag**：`srcN_ready=1`なら、tagの比較結果に関係なくready。
- **使わないsource**：sourceが1つしかない命令では、使わない側を外側で`srcN_ready=1`にして入力する前提。

### 検証してほしいCorner Case

2つのsourceが同じtagを待っている場合、片方だけhitする場合、entryがinvalidの場合。

以下では、実際に書いてみて考えた点を順番に見ていく。

## 信号は何を表しているか

入力のうち、`entry_valid`、`src0_ready`、`src1_ready`、`src0_tag`、`src1_tag`は、Issue Queueの1 entryがFFに持っている内容である。

- `entry_valid`：このentryに命令が入っている。
- `srcN_ready`：そのoperandが、前のサイクルまでに揃っている。
- `srcN_tag`：そのoperandを作る命令のtag。

`wakeup_valid`と`wakeup_tag`だけが別で、これは実行側からIssue Queueの全entryへ配られるbroadcastである。このサイクルに結果が出る命令のtagを表す。

出力の`srcN_ready_now`は、「このサイクルの時点で、そのoperandが揃っているか」を表す。FFの`srcN_ready`は前のサイクルまでの情報なので、それに今のbroadcastの分を足したものである。

`issue_ready`は、「このentryの命令を、このサイクルに発行できる」ことを表す。Issue Queueから実行ユニットへ命令を送り出すことをissueと呼ぶ。

Day30との関係でいうと、Day30でpriority encoderに入れていたentryごとのreadyのbitが、今回の`issue_ready`に当たる。今回のモジュールをentryの数だけ並べ、その`issue_ready`を集めてpriority encoderに入れれば、Day30の回路の2-source版になる。

## sourceごとのready

```systemverilog
assign src0_ready_now = entry_valid &
                        (src0_ready |
                         (wakeup_valid & (src0_tag == wakeup_tag)));
assign src1_ready_now = entry_valid &
                        (src1_ready |
                         (wakeup_valid & (src1_tag == wakeup_tag)));
```

Day30と同じ形である。「すでに揃っている」か「いま揃った」かのどちらかが成り立てばよいので、この2つはORでつなぐ。

`wakeup_valid`とANDを取っているので、broadcastのないサイクルにtagがたまたま一致してもヒットしない。

2つのsourceはそれぞれ独立に`wakeup_tag`と比較している。`src0_tag`と`src1_tag`が同じ値なら、1回のbroadcastで両方の比較が一致し、両方が同時にreadyになる。`add x3, x1, x1`のように同じレジスタを2回使う命令がこれに当たる。特別な処理は要らない。

## 両方揃ったら発行できる

```systemverilog
assign issue_ready = entry_valid & (src0_ready_now & src1_ready_now);
```

operandが2つとも揃ったときに、命令を発行できる。sourceごとのreadyをANDでつなぐ。

初版では、ここをORで書いていた。

```systemverilog
assign issue_ready = entry_valid & (src0_ready_now | src1_ready_now);
```

これだと、片方のoperandが揃っただけで`issue_ready`が立つ。もう片方はまだ値が決まっていないのに、命令が実行ユニットへ送られてしまう。

Day30でORを書き忘れてANDにした直後だったので、今度はORを書きすぎた。ORでつなぐのは、1つのsourceについての「すでに揃っている」と「いま揃った」である。source同士は、両方必要なのでANDになる。

## 表で確認する

`add x3, x1, x2`がentryに入っていて、x1を作る命令のtagが5、x2を作る命令のtagが9だとする。

| cycle | `src0_ready` | `src1_ready` | wakeup | `src0_ready_now` | `src1_ready_now` | `issue_ready` |
|---:|---:|---:|---|---:|---:|---:|
| 1 | 0 | 0 | なし | 0 | 0 | 0 |
| 2 | 0 | 0 | tag5 | 1 | 0 | 0 |
| 3 | 1 | 0 | なし | 1 | 0 | 0 |
| 4 | 1 | 0 | tag9 | 1 | 1 | 1 |

cycle 2でx1が揃う。`src0_ready_now`は外側でFFに書き戻されるので、cycle 3では`src0_ready`が1になっている。cycle 4でx2のbroadcastが来ると、`src1_ready`のFFはまだ0だが、`src1_ready_now`が1になるので、そのサイクルに`issue_ready`が立つ。FFへの書き戻しを待たずに発行できる。

初版のORでは、cycle 2とcycle 3でも`issue_ready`が1になっていた。

corner caseは次のとおり。

| `entry_valid` | src0 | src1 | `src0_ready_now` | `src1_ready_now` | `issue_ready` |
|---:|---|---|---:|---:|---:|
| 1 | hit | 未 | 1 | 0 | 0 |
| 1 | hit | hit（同じtag） | 1 | 1 | 1 |
| 1 | ready済み | ready済み | 1 | 1 | 1 |
| 0 | ready済み | hit | 0 | 0 | 0 |

## 規模を大きくしたときの考察

**比較器**：1 entryあたり、tag幅の比較器が2つ必要になる。Issue QueueがN-entryなら2N個。broadcastするportが複数あれば、さらにその本数倍になる。sourceを2つ持つことで、wakeupの回路はDay30の2倍になる。

**クリティカルパス**：`wakeup_tag`から、tagの比較、`srcN_ready`とのOR、2つのsourceのAND、`entry_valid`とのANDを通って`issue_ready`に至る。Day30と比べると、ANDが1段増える。この先にentry間のpriority encoderが続く。

**`entry_valid`の入れ方**：今回は`srcN_ready_now`にも`entry_valid`を入れたので、`issue_ready`の式の`entry_valid`は冗長になっている。Issueの式のとおり`issue_ready`にだけ入れる書き方もある。その場合、invalidなentryでも`srcN_ready_now`が立つことがあるが、entryに新しい命令が入るときにready bitは上書きされるので、普通は問題にならない。

**状態の更新**：今回のモジュールは組合せ回路だけである。実際のIssue Queueでは、`srcN_ready_now`を次のサイクルの`srcN_ready`としてFFに書き戻す。発行されなかったentryは、wakeupされたことをFFで覚えておかないと、次のサイクルには忘れてしまう。

**source数**：3つのsourceを持つ命令（積和演算など）に対応するには、比較器とORをもう1組足し、ANDを3入力にする。sourceの数だけ同じ形が並ぶ。

## 最終RTLについて

最終稿は、sourceごとのreadyの判定2本と、その2つのANDによる`issue_ready`の、`assign` 3本で構成した。モジュール名は`two_source_operand_wakeup`。RTLは[problems/day32/solution.sv](../problems/day32/solution.sv)に置いてある。

レビューで修正したのは、`issue_ready`のORをANDにした1点。

## まとめと今後の検証

今回のポイントは、ORでつなぐものとANDでつなぐものを区別することだった。

1つのsourceについて、「すでに揃っている」と「いま揃った」はどちらでもよいのでOR。2つのsourceは、両方揃う必要があるのでAND。信号が何を表しているのかを先に言葉にしておけば、式はそのまま決まる。

**Verilatorのlint（`--lint-only -Wall`）は、エラーも警告もなく通した（ファイル名に関する警告を除く）。シミュレーションとテストベンチ実行は未実施である。** 上の表は机上で追っただけである。
