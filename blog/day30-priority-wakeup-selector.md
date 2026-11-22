# 半導体フロントエンド設計100本ノック (30) Priority Encoder + Wakeup Selector

半導体フロントエンド設計100本ノック、第30問。

今回はIssue Queueのwakeupとselectを、1つの組合せ回路にまとめたものを設計してみた。operandが揃ったentryの中から、番号の一番小さいものを1つ選ぶ回路である。

RTLは20行ほどなのだが、readyの条件の「すでに揃っている」と「いま揃った」をORでつなぐところを、最初は片方を書き忘れ、次はANDでつないでしまった。優先順位の向きも逆だった。

課題の詳細は[Day30 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/30)。

## 今回の問題：wakeupとpriority select

今回作るのは、**4-entryの候補のうち、operandが揃ったentryを1つ選ぶ組合せ回路**。

[元の課題Issue #30](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/30)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- entryは4つ。各entryはvalid、operandが揃っているかを表す`src_ready`、待っているoperandの6bitのtag（`src_tag`）を持つ。
- `wakeup_valid=1`のとき、`wakeup_tag`と同じtagを待っているentryは、そのサイクルからreadyとして扱う（same-cycle wakeup）。
- entryがreadyである条件は、`valid && (src_ready || wakeup hit)`。
- readyなentryのうち、**番号の最も小さいもの**を1つ選ぶ。
- 1回のwakeupで複数のentryが同時にreadyになることがあるが、選ぶのは1つだけ。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module priority_wakeup_selector
  (
    input  logic [3: 0]  valid,
    input  logic [3: 0]  src_ready,
    input  logic [23: 0] src_tag,
    input  logic         wakeup_valid,
    input  logic [5: 0]  wakeup_tag,
    output logic         select_valid,
    output logic [1: 0]  select_idx
  );
    // ここにRTLを実装する
endmodule
```

`src_tag`は、4-entry分のtagを1本のvectorに並べたものである。

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **`src_tag`の分割**：entry0が下位側（`src_tag[5:0]`）、entry3が上位側（`src_tag[23:18]`）。
- **`select_valid=0`のときの`select_idx`**：0を出す。
- **`src_ready=1`のentryのtag**：すでにreadyなentryは、tagの比較結果に関係なくready。
- **状態の更新**：選んだentryをinvalidにする、wakeupされた状態を次のサイクルへ持ち越す、といった更新はこのモジュールの外で行う。clkもresetもない組合せ回路である。

### 検証してほしいCorner Case

同時wakeup、全entryがinvalidの場合、priority。

以下では、実際に書いてみて修正した点を順番に見ていく。

## wakeupとselectとは

Out-of-Orderのプロセッサでは、命令はIssue Queueの中でoperandが揃うのを待つ。operandを作る命令の実行が終わると、その結果のtagがIssue Queue全体にbroadcastされる。各entryは、自分の待っているtagと比較して、一致すればoperandが揃ったことを知る。これがwakeupである。

operandが揃った命令は実行できるが、実行ユニットの数は限られているので、揃った命令の中から実行するものを選ぶ。これがselectである。

今回の回路は、この2つを1サイクルの中で続けて行う。broadcastされたサイクルに、それで揃ったentryをそのまま選べるようにする。これができないと、依存関係のある命令を連続したサイクルで実行できない。

## tagの比較とreadyの条件

```systemverilog
logic [5: 0] w_src_tag[4];
assign w_src_tag[0] = src_tag[5: 0];
assign w_src_tag[1] = src_tag[11: 6];
assign w_src_tag[2] = src_tag[17:12];
assign w_src_tag[3] = src_tag[23:18];

logic [3: 0] w_select_int_valid;

generate for (genvar e = 0; e < 4; e++) begin: loop_ENTRY
  logic w_wakeup_hit;
  assign w_wakeup_hit = wakeup_valid & (w_src_tag[e] == wakeup_tag);
  assign w_select_int_valid[e] = valid[e] & (src_ready[e] | w_wakeup_hit);
end endgenerate
```

Day21と同じように、最初にvectorをentryごとの配列に分ける。

`w_wakeup_hit`は、いまbroadcastされたtagが、そのentryの待っているtagと一致したことを表す。`wakeup_valid`とANDを取っているので、broadcastがないサイクルにはtagがたまたま一致していてもヒットしない。

`w_select_int_valid[e]`が、entryがreadyであることを表す。`src_ready`かwakeup hitのどちらかが成り立ち、かつentryがvalidであればreadyである。

## ORでつなぐ理由

readyの条件の2つの項は、別々の状況を表している。

- **`src_ready=1`**：operandがすでに揃っている。過去のサイクルにwakeupされたか、Issue Queueに入った時点で揃っていた。もうwakeupを待つ必要がないので、`wakeup_valid`にもtagにも関係なくreadyである。
- **wakeup hit**：operandはまだ揃っていない（`src_ready=0`）が、いまこのサイクルにbroadcastされたtagが一致した。

どちらか一方が成り立てばよいので、ORになる。

初版では、wakeup hitだけを見ていた。

```systemverilog
assign w_select_int_valid[e] = wakeup_valid & valid[e] & (w_src_tag[e] == wakeup_tag);
```

`src_ready`がどこにも使われていない。これだと、broadcastされたそのサイクルに選ばれなかったentryは、同じtagがもう一度broadcastされない限り二度と選ばれない。1回のwakeupで複数のentryが揃っても選ぶのは1つだけなので、選ばれなかったentryは必ず出る。

次の版では、`src_ready`をANDで足していた。

```systemverilog
assign w_select_int_valid[e] = wakeup_valid &
                               valid[e] & src_ready[e] &
                               (w_src_tag[e] == wakeup_tag);
```

こちらは「すでに揃っていて、かつ、いまwakeupが当たっている」entryしか選ばれない。条件が前より厳しくなっている。

## 番号の小さいentryを選ぶ

```systemverilog
assign select_valid = |w_select_int_valid;
always_comb begin
  select_idx = 0;
  for (int e = 3; e >= 0; e--) begin
    if (w_select_int_valid[e]) begin
      select_idx = e;
    end
  end
end
```

forループは3から0へ向かって回している。`always_comb`の中では後から実行された代入が勝つので、最後に評価されるentry0が最も優先される。

初版ではこのループを0から3へ回していた。それだと番号の一番大きいentryが残る。Day21では番号の大きいentry1が優先だったので0から回して正しかったのだが、今回は逆である。後勝ちのループでは、優先したいものを最後に評価する。

## 表で確認する

entry0〜3の`src_tag`を、それぞれ5、9、9、3とする。`valid`と`src_ready`は`[3:0]`の順に書く。

| `valid` | `src_ready` | wakeup | ready | `select_valid` | `select_idx` | 説明 |
|---|---|---|---|---:|---:|---|
| 1111 | 0000 | なし | 0000 | 0 | 0 | 揃ったentryがない |
| 1111 | 1000 | なし | 1000 | 1 | 3 | すでに揃っているentry3 |
| 1111 | 1000 | tag9 | 1110 | 1 | 1 | entry1と2が同時にwakeup。番号の小さいentry1 |
| 1011 | 0000 | tag9 | 0010 | 1 | 1 | entry2はinvalidなのでヒットしない |
| 1101 | 1000 | tag9 | 1100 | 1 | 2 | entry1がinvalid。entry2とentry3のうちentry2 |
| 1111 | 0001 | tag3 | 1001 | 1 | 0 | entry3がwakeupされたが、entry0が優先 |
| 0000 | 1111 | tag5 | 0000 | 0 | 0 | 全entryがinvalid |

3行目が同時wakeupの場合で、tag9を待っていたentry1とentry2が両方readyになり、すでに揃っていたentry3と合わせて3つの中からentry1が選ばれる。

6行目では、いまwakeupされたentry3より、前から揃っていたentry0が優先される。優先順位は番号だけで決まり、いつ揃ったかは関係ない。

## 規模を大きくしたときの考察

**クリティカルパス**：`wakeup_tag`から、tagの比較、`src_ready`とのOR、validとのAND、priority encoderを通って`select_idx`まで、すべてが1本の組合せパスに並ぶ。Out-of-Orderのプロセッサで動作周波数を決める代表的なパスである。

実際にはこの先がさらに続く。選んだ命令のdestinationのtagが、次のサイクルの`wakeup_tag`になる。つまりselectの結果からwakeupへ戻るループになっていて、依存する命令を連続したサイクルで実行するには、このループを1サイクルで回す必要がある。

**entry数**：比較器はentryごとに1つ、sourceが2つあればその2倍になる。broadcastするバスが複数あれば、さらにその本数倍になる。priority encoderの段数はentry数の対数で増える。Issue Queueのentry数を増やしにくいのは、このパスが伸びるからである。

**priority encoder**：今回は後勝ちのforループで書いた。合成ツールはこれをpriority encoderとして認識するが、entry数が多い場合は、木構造になるように自分で書いた方がよいこともある。

**番号による優先順位**：番号の小さいentryを優先するのは、回路としては一番簡単である。ただし、番号と命令の古さが対応していないと、古い命令が後回しにされ続けることがある。古い命令を優先するには、entryを古い順に詰めていくか、entry間の新旧を表すmatrixを持つ必要がある。

**wakeupを1サイクルで済ませない方法**：wakeupとselectを別のサイクルに分ければ、パスは短くなる。その代わり、依存する命令を連続したサイクルで実行できなくなり、性能が落ちる。

## 最終RTLについて

最終稿は、tagの分割、entryごとのwakeup hitとreadyの判定、後勝ちのforループによるpriority selectで構成した。モジュール名は`priority_wakeup_selector`。RTLは[problems/day30/solution.sv](../problems/day30/solution.sv)に置いてある。

レビューで修正したのは、readyの条件（`src_ready`を使っていなかった、次にANDでつないでいた）と、優先順位の向きの2点。

## まとめと今後の検証

今回のポイントは、readyの条件を仕様の式のとおりに書くことだった。

`valid && (src_ready || wakeup hit)`は短い式だが、それぞれの項が何を表しているのかを考えずに書くと、項が抜けたり、ORがANDになったりする。「すでに揃っている」と「いま揃った」のどちらでもよい、と言葉にしておけば間違えなかった。

後勝ちのforループは、優先したいものを最後に評価する。番号の小さい方を優先するなら、大きい方から回す。

**Verilatorのlint（`--lint-only -Wall`）は、エラーなしで通した。シミュレーションとテストベンチ実行は未実施である。** 残った警告はforループの`int`を2bitへ代入していることだけで、動作には影響しない。 上の表は机上で追っただけである。
