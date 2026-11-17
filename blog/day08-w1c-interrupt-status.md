# 半導体フロントエンド設計100本ノック (8) W1C Interrupt Status

半導体フロントエンド設計100本ノック、第8問。

今回はW1C（Write-1-to-Clear）の割り込みステータスレジスタを設計してみた。ハードウェアがbitを立て、ソフトウェアがそのbitに1を書いて落とす、というよくあるレジスタである。

回路としては数行で終わる。ただ、setとclearが同じサイクルに来たらどちらを勝たせるのか、なぜそうするのか、というところは一度きちんと考えておく価値があった。あとはSystemVerilogの文法で2か所つまずいた。

課題の詳細は[Day08 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/8)。

## 今回の問題：W1Cの割り込みステータスレジスタ

今回作るのは、**ハードウェアからのsetで1になり、ソフトウェアからのW1Cで0になるステータスレジスタ**。

[元の課題Issue #8](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/8)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- `status`は`WIDTH`bitのレジスタ。デフォルトは`WIDTH=8`。各bitが1つの割り込み要因に対応する。
- `hw_set[i]=1`のサイクルの次に、`status[i]`は1になる。
- `sw_clear[i]=1`のサイクルの次に、`status[i]`は0になる。
- **同じbitにsetとclearが同時に来たら、set優先**。`status[i]`は1になる。
- setもclearもなければ値を保持する。
- reset値は0。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module w1c_interrupt_status #(
    parameter int WIDTH = 8
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] hw_set,
    input  logic [WIDTH-1:0] sw_clear,
    output logic [WIDTH-1:0] status
);
    // ここにRTLを実装する
endmodule
```

### 動作例

ある1bitに注目した場合。

| サイクル | `hw_set` | `sw_clear` | `status` | 説明 |
|---:|---:|---:|---:|---|
| 1 | 0 | 0 | 0 | reset後 |
| 2 | 1 | 0 | 0 | 割り込み発生 |
| 3 | 0 | 0 | 1 | statusが立つ |
| 4 | 1 | 1 | 1 | clearと同時に次の割り込み |
| 5 | 0 | 1 | 1 | set優先なので1のまま。もう一度clear |
| 6 | 0 | 0 | 0 | 今度は落ちる |

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **resetの方式**：非同期reset（`negedge rst_n`）にした。
- **`sw_clear`の意味**：bitごとのクリア要求として扱う。このモジュールにはwrite enableもwrite dataもないので、バスのアドレスデコードと「そのbitに1が書かれたか」の判定は、外側で済んでいるものとする。
- **`hw_set`の形**：レベルかパルスかは区別しない。1になっているサイクルにsetする。

### 検証してほしいCorner Case

set/clearの同時発生、別bitの同時操作、連続set、reset。

以下では、実際に書いてみて考えた点を順番に見ていく。

## なぜW1Cなのか

割り込みステータスを普通のread/writeレジスタにすると、ソフトウェアは「読んで、落としたいbitを0にして、書き戻す」ことになる。読んでから書き戻すまでの間に別のbitが立つと、そのbitは読んだ時点では0だったので、0が書き戻されて消えてしまう。

W1Cなら、ソフトウェアは読んだ値をそのまま書き戻せばよい。読んだときに1だったbitだけが落ち、0だったbitには0を書くことになるので何も起きない。読んだ後に立ったbitは、そのまま残る。

## なぜset優先なのか

同じbitにsetとclearが同時に来た場合を考える。

clearは、ソフトウェアが**それ以前に**読んだ割り込みに対するものである。同じサイクルに来たsetは、それとは別の**新しい**割り込みだ。

ここでclearを勝たせると、新しい割り込みはstatusに残らず、誰にも気づかれないまま消える。

setを勝たせておけば、statusは1のまま残る。ソフトウェアは次にstatusを読んだときにもう一度割り込みを処理することになるが、取りこぼしは起きない。割り込みを余分に1回処理するのは無害で、取りこぼすのは有害なので、set優先にする。

## bitごとのFFを並べる

各bitは独立に動くので、1bit分の回路をgenerateで`WIDTH`個並べた。

```systemverilog
logic [WIDTH-1: 0] r_status;

generate for (genvar i = 0; i < WIDTH; i++) begin: loop_STATUS
  always_ff @ (posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      r_status[i] <= 1'b0;
    end else begin
      if (hw_set[i]) begin
        r_status[i] <= 1'b1;
      end else if (sw_clear[i]) begin
        r_status[i] <= 1'b0;
      end
    end
  end
end endgenerate

assign status = r_status;
```

`hw_set[i]`を先に判定しているので、同時に`sw_clear[i]`が来ていても1になる。if / else ifの順番が、そのまま優先順位になっている。

どちらも来ていなければどの代入も実行されないので、値は保持される。

bitごとに別々のFFなので、あるbitをclearしながら別のbitをsetしても互いに干渉しない。すでに1のbitにsetが来ても1のままである。

## 文法でつまずいたところ

初版には文法上誤っている記述が2か所あった。

1つ目は、ポートリストの最後に余分なカンマを付けていたこと。

```systemverilog
    output logic [WIDTH-1: 0] status,
  );
```

これは単純な打ち間違い。

2つ目は、generateのforで`int i`を使っていたこと。

```systemverilog
generate for (int i = 0; i < WIDTH; i++) begin: loop_STATUS
```

generateのforループの変数は`genvar`でなければならない。

前回のDay07では`always_ff`の中でfor文を使っていて、そちらは`int i`で正しかった。同じforでも、`always_ff`の中のforは実行時に回る手続き的なループ、generateのforはエラボレーション時に回路を複製するためのループで、変数の種類が違う。前回の書き方をそのまま持ってきてしまった。

## 別の書き方

bitごとに同じ式なので、generateを使わずにベクタ演算でも書ける。

```systemverilog
always_ff @ (posedge clk, negedge rst_n) begin
  if (!rst_n) begin
    r_status <= '0;
  end else begin
    r_status <= (r_status & ~sw_clear) | hw_set;
  end
end
```

先にclearを適用し、最後に`hw_set`をORしている。ORが最後にあることがset優先を表している。

こちらの方が短いが、今回はif / else ifの形のままにした。優先順位が読んですぐ分かるからである。

## hw_setが立ちっぱなしの場合

`hw_set`がレベル信号で、割り込み要因が解消されるまで1のままだとする。

set優先なので、その間はソフトウェアが何度clearしてもstatusは落ちない。ソフトウェアは先に割り込み要因の側を解消してから、statusをclearする必要がある。

これは不具合ではなく、レベル割り込みとして正しい動作である。要因が残っているのにstatusだけ落ちてしまう方が困る。

## 規模を大きくしたときの考察

**面積**：FFは`WIDTH`個。各bitの組合せ論理は、次の値を決める小さな論理が1つだけ。`WIDTH`に比例して増える。

**クリティカルパス**：各bitの次の値は、そのbit自身の`hw_set`、`sw_clear`、現在の値だけで決まる。bit間に依存がないので、`WIDTH`を増やしてもこのモジュールの中のクリティカルパスは変わらない。

**モジュールの外側**：`WIDTH`が増えたときに効いてくるのは、むしろ外側の論理である。`sw_clear`を作るためのバスのアドレスデコードと、statusとenableのANDを全bitでORして1本の割り込み信号にまとめる論理は、要因の数とともに深くなる。

## 最終RTLについて

最終稿は、bitごとの非同期reset付きFFをgenerateで並べた構成。モジュール名は`w1c_interrupt_status`。RTLは[problems/day08/solution.sv](../problems/day08/solution.sv)に置いてある。

レビューで修正したのは、ポートリスト末尾のカンマと、generate forの`genvar`の2点。論理そのものは初版から変わっていない。

## まとめと今後の検証

今回のポイントは、setとclearが同時に来たときの優先順位だった。

clearは過去の割り込みに対するもの、同時に来たsetは新しい割り込みなので、setを勝たせて取りこぼしを防ぐ。RTLではif / else ifの順番1つで決まることだが、理由を説明できるようにしておきたい。

文法の面では、generateのforには`genvar`を使う、という基本を確認した。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** set/clearの同時発生、別bitの同時操作、連続set、resetは机上で確認しただけである。
