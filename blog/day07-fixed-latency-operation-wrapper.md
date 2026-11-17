# 半導体フロントエンド設計100本ノック (7) Fixed-latency Operation Wrapper

半導体フロントエンド設計100本ノック、第7問。

今回はFixed-latency Operation Wrapperを設計してみた。入力を受け取ってから、決まったサイクル数だけ後に結果とvalidを出力する回路である。

やることはシフトレジスタを並べるだけなので、これまでの問題と比べるとかなり単純。ただ、dataのFFにresetを付けるかどうか、付けないならどう書くべきか、というところで一つ学びがあった。

課題の詳細は[Day07 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/7)。

## 今回の問題：固定レイテンシのvalid付きパイプライン

今回作るのは、**各サイクルの入力を受理し、ちょうど`LATENCY`サイクル後に演算結果とvalidを出力する回路**。

[元の課題Issue #7](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/7)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- 入力は`in_valid`と32bitの`in_data`。出力は`out_valid`と32bitの`out_data`。
- 演算は例として**入力+1**。`out_data = in_data + 1`を出力する。
- `in_valid=1`で入力したデータは、**ちょうど`LATENCY`サイクル後**に`out_valid=1`とともに出力される。
- `LATENCY`はパラメータで、`LATENCY >= 1`。デフォルトは3。
- **毎サイクル受理可能**。readyはなく、入力側を止める手段は持たない。
- `in_valid=0`のサイクル（bubble）は、`LATENCY`サイクル後の`out_valid=0`としてそのまま出てくる。
- `rst_n`はactive-low。reset中にパイプライン内にあったデータは破棄する。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module fixed_latency_wrapper #(
    parameter int LATENCY = 3
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [31:0] in_data,
    output logic        out_valid,
    output logic [31:0] out_data
);
    // ここにRTLを実装する
endmodule
```

### 動作例

`LATENCY=3`の場合。サイクルtに入力したデータは、サイクルt+3に出力される。

| サイクル | `in_valid` | `in_data` | `out_valid` | `out_data` |
|---:|---:|---:|---:|---:|
| 1 | 1 | 10 | 0 | - |
| 2 | 1 | 20 | 0 | - |
| 3 | 0 | - | 0 | - |
| 4 | 1 | 30 | 1 | 11 |
| 5 | 0 | - | 1 | 21 |
| 6 | 0 | - | 0 | - |
| 7 | 0 | - | 1 | 31 |

サイクル3のbubbleは、サイクル6の`out_valid=0`として出てくる。bubbleが挟まっても前後のデータのレイテンシは変わらない。

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **resetの方式**：非同期reset（`negedge rst_n`）にした。
- **`out_valid=0`のときの`out_data`**：不定扱い。パイプラインに残っている古い値がそのまま見える。

### 検証してほしいCorner Case

連続投入、bubble、reset中の破棄、`LATENCY=1`、入出力のサイクル整合。

以下では、実際に書いてみて修正した点を順番に見ていく。

## validとdataをシフトレジスタで運ぶ

固定レイテンシなので、validとdataを`LATENCY`段のシフトレジスタで運べばよい。

```systemverilog
logic [31: 0] r_data [LATENCY];
logic         r_valid [LATENCY];
```

validの側はこうなる。

```systemverilog
always_ff @ (posedge clk, negedge rst_n) begin
  if (!rst_n) begin
    for (int i = 0; i < LATENCY; i++) begin
      r_valid[i] <= 1'b0;
    end
  end else begin
    r_valid[0] <= in_valid;
    for (int i = 1; i < LATENCY; i++) begin
      r_valid[i] <= r_valid[i-1];
    end
  end
end

assign out_valid = r_valid [LATENCY-1];
```

サイクルtの`in_valid`は、そのサイクルの終わりのposedgeで`r_valid[0]`に入る。そこから1サイクルに1段ずつ進むので、サイクルt+`LATENCY`には`r_valid[LATENCY-1]`に到達している。ちょうど`LATENCY`サイクルである。

`LATENCY=1`の場合はfor-loopが`i = 1; i < 1`となって1回も回らない。`r_valid[0]`がそのまま出力になるので、特別扱いは要らない。

reset時には全段のvalidを0にしているので、パイプラインの途中にあったデータはすべて捨てられる。

## 演算を入れ忘れた

初版では`in_data`をそのまま`r_data[0]`に入れて、最終段をそのまま`out_data`に出していた。つまりただの遅延線で、肝心の+1が入っていなかった。

validのタイミングばかり考えていて、演算のことを忘れていた。

修正版では、初段に取り込むときに加算している。

```systemverilog
r_data [0] <= in_data + 'h1;
```

加算はどの段に入れてもレイテンシは変わらない。初段に入れると、加算器は入力側のパスに付く。最終段の後ろに入れると、出力側のパスに付く。

## dataのFFにresetは要るのか

dataはvalidが立っているときにしか意味を持たない。validさえresetしておけば、dataが何であっても外からは見えない。なのでdataのFFにはresetを付けないことにした。resetを付ければその分だけ面積とreset配線が増えるだけである。

ここまでは良かったのだが、初版ではvalidと同じ`always_ff`の中にdataを書いていた。

```systemverilog
always_ff @ (posedge clk, negedge rst_n) begin
  if (!rst_n) begin
    for (int i = 0; i < LATENCY; i++) begin
      r_valid[i] <= 1'b0;
    end
  end else begin
    r_valid[0] <= in_valid;
    r_data [0] <= in_data + 'h1;
    for (int i = 1; i < LATENCY; i++) begin
      r_valid[i] <= r_valid[i-1];
      r_data [i] <= r_data [i-1];
    end
  end
end
```

reset節では`r_data`に何も代入していないので、resetを付けていないつもりだった。

ところがこの書き方だと、`rst_n=0`の間にクロックが来たときは`if (!rst_n)`の側に入り、`r_data`には代入が起きない。RTLの意味としては「**`rst_n`がLowの間、`r_data`は値を保持する**」になる。

合成ツールはこの意味を忠実に実装するので、`rst_n`がdataのFFのイネーブルとして使われてしまう。`rst_n`の負荷を減らしたくてresetを外したのに、結局32×`LATENCY`個のFFすべてに`rst_n`が届くことになる。

動作としては正しいのだが、意図した回路にはなっていない。

そこで、dataだけresetなしの別の`always_ff`に分けた。

```systemverilog
always_ff @ (posedge clk) begin
  r_data [0] <= in_data + 'h1;
  for (int i = 1; i < LATENCY; i++) begin
    r_data [i] <= r_data [i-1];
  end
end

assign out_data  = r_data [LATENCY-1];
```

これでdataのFFは`rst_n`とは完全に無関係になる。「resetしない」という意図がそのまま回路になる。

resetするFFとしないFFは、同じ`always_ff`に混ぜない。単純なことだが、今回の一番の学びだった。

## 規模を大きくしたときの考察

**面積**：FFの数は`LATENCY × 33`個（data 32bit + valid 1bit）。`LATENCY`に比例して増える。

**クリティカルパス**：論理があるのは初段の32bit加算器だけで、2段目以降はFFからFFへの直結。したがって`LATENCY`を増やしてもクリティカルパスは変わらない。加算器を初段に置いたので、入力側の上流の論理と加算器が同じサイクルに入る点には注意が必要。

今回の演算は+1なので1サイクルに収まるが、本来このwrapperが包むのはもっと重い演算器のはず。その場合、演算の後ろにFFを並べておき、合成ツールのretimingでFFを演算の中に移動させる、という使い方ができる。

**消費電力**：今の実装では、`in_valid=0`のときもdataのFFは毎サイクル書き換わる。各段で前段のvalidをイネーブルにすれば、bubbleのときはdataが動かなくなり、クロックゲーティングも効く。その代わりvalidのファンアウトが増える。

**`LATENCY`が大きい場合**：シフトレジスタは毎サイクル全段のデータが動く。`LATENCY`が大きくなると、データを動かさずにwrite pointerとread pointerを回すリングバッファ（メモリ）の方が、面積・電力の両面で有利になる。

## 最終RTLについて

最終稿は、validのシフトレジスタ（非同期reset付き）と、dataのシフトレジスタ（resetなし）の2つの`always_ff`で構成した。モジュール名は`fixed_latency_wrapper`。RTLは[problems/day07/solution.sv](../problems/day07/solution.sv)に置いてある。

レビューで修正したのは、演算の入れ忘れと、dataの`always_ff`の分離の2点。

## まとめと今後の検証

今回のポイントは、固定レイテンシの回路そのものよりも、resetの書き方だった。

dataのFFをresetしないという判断は正しかったが、resetするFFと同じ`always_ff`に書いてしまうと、reset信号がイネーブルとしてdataのFFに入り込む。resetの有無でブロックを分けておけば、こういうことは起きない。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** レイテンシ、`LATENCY=1`、連続投入、bubble、reset中の破棄は机上で確認しただけである。
