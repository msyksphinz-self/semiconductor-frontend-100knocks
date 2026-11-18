# 半導体フロントエンド設計100本ノック (21) Store-to-Load Forwarding

半導体フロントエンド設計100本ノック、第21問。

今回はStore-to-Load Forwardingを設計してみた。Store Queueの中に、loadと同じアドレスへのstoreが残っていたら、そのデータをloadへ渡す回路である。

entryは2つだけで、clkもresetもない組合せ回路なのだが、2つのentryの両方にヒットしたときにどうすればよいのかが分からず、初版では両方のデータをORして出していた。これは誤りで、新しい方のstoreを選ばなければならない。

課題の詳細は[Day21 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/21)。

## 今回の問題：2-entryのStore-to-Load Forwarding

今回作るのは、**2-entryのStore Queueを検索し、loadのアドレスと一致するstoreのデータをforwardする組合せ回路**。

[元の課題Issue #21](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/21)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- Store Queueは2-entry。各entryはvalid、32bitのアドレス、64bitのデータを持つ。
- loadのアドレスと一致するvalidなstoreがあれば、そのデータをforwardする。
- **entry1がyoungest**。両方のentryが一致したら、entry1のデータを選ぶ。
- 一致するstoreがなければ`forward_valid=0`。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module store_to_load_forward
  (
    input  logic [  1: 0] st_valid,
    input  logic [ 63: 0] st_addr,
    input  logic [127: 0] st_data,
    input  logic [ 31: 0] ld_addr,
    output logic          forward_valid,
    output logic [63: 0]  forward_data
  );
    // ここにRTLを実装する
endmodule
```

`st_addr`と`st_data`は、2-entry分を1本のvectorに並べたものである。

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **vectorの分割**：entry0が下位側（`st_addr[31:0]`、`st_data[63:0]`）、entry1が上位側（`st_addr[63:32]`、`st_data[127:64]`）。
- **`forward_valid=0`のときの`forward_data`**：0を出す。
- **アドレスの比較**：32bit全体の完全一致。アクセスサイズやbyte単位の重なりは扱わない。
- **load側のvalid**：ポートにないので、このモジュールは常に`ld_addr`と比較する。loadが有効かどうかは外側で見る。

### 検証してほしいCorner Case

両方のentryが一致する場合、invalidなentry、一致なし。

以下では、実際に書いてみて修正した点を順番に見ていく。

## Store-to-Load Forwardingとは

Out-of-Orderのプロセッサでは、storeはcommitされるまでメモリに書き込まれず、Store Queueの中で待っている。その間に同じアドレスへのloadが実行されると、メモリにはまだ古い値しかない。

そこでloadは、メモリを読むのと並行してStore Queueを検索する。自分より前のstoreで、同じアドレスに書こうとしているものがあれば、メモリの値ではなくそのstoreのデータを使う。これがStore-to-Load Forwardingである。

アドレスをキーにして全entryを同時に比較するので、CAMの構造になる。

## vectorをentryごとに分ける

```systemverilog
logic [31: 0] w_st_addr[2];
logic [63: 0] w_st_data[2];

assign w_st_addr[0] = st_addr[31:  0];
assign w_st_addr[1] = st_addr[63: 32];

assign w_st_data[0] = st_data[ 63:  0];
assign w_st_data[1] = st_data[127: 64];
```

ポートは1本のvectorなので、最初にentryごとの配列に分けておく。以降はすべて`w_st_addr[p]`と`w_st_data[p]`で書ける。

## アドレスの比較

```systemverilog
logic [ 1: 0] w_fwd_valid;

generate for (genvar p = 0; p < 2; p++) begin: loop_STQ
  assign w_fwd_valid[p] = (ld_addr == w_st_addr[p]) & st_valid[p];
  assign w_fwd_data [p] = w_fwd_valid[p] ? w_st_data[p] : 'h0;
end endgenerate

assign forward_valid = |w_fwd_valid;
```

entryごとに32bitの比較器を置き、`st_valid`とANDを取る。invalidなentryには、アドレスがたまたま一致していてもヒットしない。

`forward_valid`は、どちらかのentryにヒットしていれば1。こちらは単純なORでよい。

## 両方ヒットしたらyoungestを選ぶ

```systemverilog
always_comb begin
  forward_data = '0;
  for (int p = 0; p < 2; p++) begin
    if (w_fwd_valid[p]) begin
      forward_data = w_fwd_data[p];
    end
  end
end
```

forループはentry0からentry1へ向かって回している。`always_comb`の中では後から実行された代入が勝つので、両方にヒットした場合は最後に評価されるentry1のデータが残る。Day24でinvalid wayの番号を選んだときと同じ書き方である。

どちらにもヒットしなければ、最初に代入した0がそのまま出る。

## ORでは駄目な理由

初版では、ここをORで書いていた。

```systemverilog
always_comb begin
  forward_data = '0;
  for (int p = 0; p < 2; p++) begin
    forward_data  |= w_fwd_data[p];
  end
end
```

ヒットが1つだけならこれで正しい。しかし両方にヒットすると、2つのデータをbitごとにORした値が出る。entry0のデータが`0x00FF`、entry1のデータが`0xFF00`なら、`0xFFFF`が出てくる。どちらのstoreが書いた値でもない。

なぜyoungestなのかは、メモリに何が残るかを考えれば分かる。同じアドレスに2回storeしたら、メモリに最終的に残るのは後から書いた方の値である。loadはその2つのstoreより後の命令なので、見えるべきなのは後から書いた方、つまりyoungestのstoreのデータになる。

ORでまとめる構造そのものが悪いわけではない。ヒットをone-hotにしてからORすれば正しく動く。entry0のデータを通す条件を「entry0にヒットし、かつentry1にヒットしていない」にすればよい。

## 表で確認する

entry0のデータをD0、entry1のデータをD1とする。

| `st_valid` | entry0のaddr一致 | entry1のaddr一致 | `forward_valid` | `forward_data` |
|---|---|---|---:|---|
| 11 | 一致 | 不一致 | 1 | D0 |
| 11 | 不一致 | 一致 | 1 | D1 |
| 11 | 一致 | 一致 | 1 | **D1** |
| 11 | 不一致 | 不一致 | 0 | 0 |
| 01 | 一致 | 一致 | 1 | D0 |
| 10 | 一致 | 一致 | 1 | D1 |
| 00 | 一致 | 一致 | 0 | 0 |

3行目が両方のentryにヒットする場合で、youngestのentry1が選ばれる。5行目は、entry1のアドレスも一致しているがinvalidなので、entry0が選ばれる。

## 文法でつまずいたところ

今回は、typoのようにすぐエラーになるものとは別に、気づきにくい誤りが2つあった。

1つ目は、分割する前のポートをそのまま比較に使っていたこと。

```systemverilog
assign w_fwd_valid[p] = (ld_addr == st_addr[p]) & st_valid[p];
```

`st_addr`は64bitのvectorなので、`st_addr[p]`はその中の**1bit**である。32bitの`ld_addr`と1bitの比較になり、文法としては通ってしまう。そしてほとんどの場合は不一致になる。せっかく`w_st_addr`に分けたのだから、そちらを使う。

2つ目は、配列の添字を間違えていたこと。

```systemverilog
assign w_st_data[2] = st_data[127: 63];
```

`w_st_data`は`[2]`で宣言しているので、有効な添字は0と1である。`[2]`は範囲外で、`w_st_data[1]`には何も接続されない。定数の添字が範囲外のとき、エラーにするか警告で済ませるかはツールによる。sliceの方も`[127:63]`では65bitになってしまう。正しくは`[127:64]`である。

このほか、`w_fwd_data`の幅を32bitで宣言していて、64bitのデータの上位が落ちていた。

## 規模を大きくしたときの考察

**比較器**：entryごとにアドレス幅の比較器が1つ必要になる。N-entryのStore QueueならN個で、loadを同時に複数実行するなら、それがloadの本数倍になる。Store Queueを大きくしにくい理由の1つである。

**youngestの選択**：今回はentry1がyoungestと決まっていたので、固定の優先順位で済んだ。実際のStore Queueはリングバッファなので、どのentryがyoungestかはpointerの位置で変わる。さらに、Store Queueにはloadより後のstoreも入っているので、「loadより前のstoreの中で一番新しいもの」を選ぶ必要がある。pointerを起点にしたpriority encoderが必要になり、ここがクリティカルパスになりやすい。

**クリティカルパス**：今回の回路は、32bitの比較、validとのAND、優先順位の選択、64bitのデータのmuxが直列に並ぶ。entry数が増えると、優先順位の選択とデータのmuxが深くなる。

**アドレスの完全一致**：今回は32bit全体の一致だけを見た。実際にはアクセスサイズがあるので、storeがloadの範囲を完全に覆っているか、一部だけ重なっているかを区別する必要がある。一部だけ重なる場合は、forwardできないのでloadを待たせるか、byte単位で複数のstoreから集めることになる。これはDay37で扱う。

**forward不可の場合**：アドレスは一致しているが、storeのデータがまだ確定していない場合もある。今回のモジュールにはその入力がないが、実際にはデータのvalidも見て、確定していなければloadを待たせる必要がある。

## 最終RTLについて

最終稿は、vectorの分割、entryごとのアドレス比較、後勝ちのforループによるyoungestの選択で構成した。モジュール名は`store_to_load_forward`。RTLは[problems/day21/solution.sv](../problems/day21/solution.sv)に置いてある。

レビューで修正したのは、両方ヒットしたときの選択（ORからyoungest優先へ）、比較に使う信号、配列の添字とslice、`w_fwd_data`の幅。

## まとめと今後の検証

今回のポイントは、複数のstoreにヒットしたときにyoungestを選ぶことだった。

ORでまとめる書き方は、ヒットがone-hotであることが保証されている場合にしか使えない。Store Queueでは同じアドレスへのstoreが複数残ることは普通にあるので、優先順位を付ける必要がある。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** 上の表は机上で追っただけである。1bitとの比較や範囲外の添字は、lintやシミュレーションをかければもっと早く見つかったはずである。
