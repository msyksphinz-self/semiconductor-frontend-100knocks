# 半導体フロントエンド設計100本ノック (11) Arbitrary-depth FIFO

半導体フロントエンド設計100本ノック、第11問。

今回はdepthが2のべき乗でなくてもよい同期FIFOを設計してみた。depthが3でも5でも動くFIFOである。

2のべき乗のFIFOなら、pointerは放っておいても勝手に0へ戻る。今回はそれができないので、pointerのwrapとfull/emptyの判定を自分で決める必要がある。今回はentryごとにvalid bitを持たせる方法にしたのだが、そのvalid bitの極性を逆に書いてしまい、最初の版はFIFOとしてまったく動かないものになっていた。

課題の詳細は[Day11 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/11)。

## 今回の問題：任意のdepthの同期FIFO

今回作るのは、**depthが2のべき乗に限定されない、ready/validインターフェースの同期FIFO**。

[元の課題Issue #11](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/11)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- `DEPTH >= 2`。デフォルトは`WIDTH=32`、`DEPTH=5`。
- push側は`push_valid` / `push_ready` / `push_data`、pop側は`pop_valid` / `pop_ready` / `pop_data`。それぞれvalidとreadyが両方1のサイクルに受理される。
- 2のべき乗でないdepthに対応するため、**pointerは明示的にwrapさせる**。`DEPTH-1`の次は0。
- fullのときはpushを受けない（`push_ready=0`）。emptyのときはpopを出さない（`pop_valid=0`）。
- `pop_data`は先頭の要素を**組合せ出力**する。
- **fullのときの同時push/popは受理しない**。fullなら、同じサイクルにpopがあっても`push_ready=0`のままとする単純な仕様。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module arbitrary_depth_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 5
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             push_valid,
    input  logic             pop_ready,
    input  logic [WIDTH-1:0] push_data,
    output logic             push_ready,
    output logic             pop_valid,
    output logic [WIDTH-1:0] pop_data
);
    // ここにRTLを実装する
endmodule
```

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **resetの方式**：非同期reset（`negedge rst_n`）にした。
- **full/emptyの判定方法**：occupancy counterではなく、entryごとのvalid bitで判定する。
- **emptyのときの同時push/pop**：pushだけを受理する。pushしたデータがそのサイクルに`pop_data`へ抜けることはない。
- **`pop_valid=0`のときの`pop_data`**：不定扱い。

### 検証してほしいCorner Case

`DEPTH=3`と`DEPTH=5`、full/emptyの境界、同時push/pop、wrap、reset。

以下では、実際に書いてみて修正した点を順番に見ていく。

## 2のべき乗でないと何が困るのか

depthが2のべき乗、例えば8のFIFOなら、pointerを3bitにしておけば7の次は勝手に0へ戻る。さらにpointerを1bit余分に持たせて4bitにすると、下位3bitが一致していて最上位bitが違うときがfull、4bitすべて一致しているときがempty、と判定できる。

depthが5だとこれが使えない。3bitのpointerは4の次に5へ進んでしまうので、自分で0へ戻す必要がある。1bit余分に持たせても、pointerが自然に一周しないので、最上位bitの比較だけではfullを判定できない。

そして、書き込みpointerと読み出しpointerが同じ値になるのは、emptyのときとfullのときの両方である。pointerだけではこの2つを区別できないので、何か別の情報を持つ必要がある。

方法はいくつかある。

- 中に入っている個数を数えるoccupancy counterを持つ。
- pointerが一周するたびに反転するbitを持つ。
- entryごとにvalid bitを持つ。

今回は3つ目の、entryごとのvalid bitにした。

## pointerとvalid bit

状態は次のとおり。

```systemverilog
logic [DEPTH-1: 0]         r_valid;
logic [WIDTH-1: 0]         r_fifo_data[DEPTH];

logic [$clog2(DEPTH)-1: 0] r_head;
logic [$clog2(DEPTH)-1: 0] r_tail;
```

`r_head`が書き込み側、`r_tail`が読み出し側のpointer。一般的にはheadが先頭（読み出し側）、tailが末尾（書き込み側）なので、名前は逆になっている。

pointerの幅は`$clog2(DEPTH)`。`DEPTH=5`なら3bitで、0〜4の値を取る。

## pushとpop

```systemverilog
always_ff @ (posedge clk, negedge rst_n) begin
  if (!rst_n) begin
    r_head  <= 'h0;
    r_tail  <= 'h0;
    r_valid <= 'h0;
  end else begin
    if (push_valid & push_ready) begin
      r_head              <= r_head == DEPTH-1 ? 'h0 : r_head + 'h1;
      r_valid[r_head]     <= 1'b1;
    end
    if (pop_valid & pop_ready) begin
      r_tail          <= r_tail == DEPTH-1 ? 'h0 : r_tail + 'h1;
      r_valid[r_tail] <= 1'b0;
    end
  end
end
```

pushが受理されたら、`r_head`の指すentryのvalid bitを1にして、`r_head`を進める。popが受理されたら、`r_tail`の指すentryのvalid bitを0にして、`r_tail`を進める。

pointerは`DEPTH-1`に達していたら0に戻す。これが明示的なwrapである。

full/emptyの判定はvalid bitから作る。

```systemverilog
assign push_ready = ~(&r_valid);
assign pop_valid  = |r_valid;
```

全bitが1ならfullなので、そうでなければpushできる。1つでも1があれば中身があるので、popできる。

`push_ready`は`pop_ready`を見ていない。fullのときに同時にpopが来ても、そのサイクルのpushは受理しない。仕様どおりである。

## pushとpopは同じvalid bitを書かない

pushとpopが同じサイクルに受理されると、`r_valid[r_head]`への1の代入と`r_valid[r_tail]`への0の代入が同時に起きる。もし`r_head`と`r_tail`が同じ値だったら、同じbitに2つの代入がぶつかることになる。

しかしこれは起きない。`r_head`と`r_tail`が一致するのはemptyのときかfullのときだけで、emptyならpopが、fullならpushが受理されない。両方が同時に受理されるのはemptyでもfullでもないときで、そのとき2つのpointerは必ず違うentryを指している。

## DEPTH=3で追ってみる

`r_valid`は`[2:0]`の順に書く。

| 操作 | `r_head` | `r_tail` | `r_valid` | `push_ready` | `pop_valid` |
|---|---:|---:|---:|---:|---:|
| reset後 | 0 | 0 | 000 | 1 | 0 |
| push A | 1 | 0 | 001 | 1 | 1 |
| push B | 2 | 0 | 011 | 1 | 1 |
| push C | 0 | 0 | 111 | 0 | 1 |
| pop（A） | 0 | 1 | 110 | 1 | 1 |
| push D | 1 | 1 | 111 | 0 | 1 |
| pop（B） | 1 | 2 | 101 | 1 | 1 |
| pop（C） | 1 | 0 | 001 | 1 | 1 |
| pop（D） | 1 | 1 | 000 | 1 | 0 |

push Cで`r_head`が2から0へwrapし、fullになる。このとき`r_head`と`r_tail`はどちらも0で、reset直後と同じ値だが、`r_valid`が111なのでfullと分かる。

pop（C）では`r_tail`が2から0へwrapしている。最後のpop（D）のあとは`r_head`と`r_tail`がどちらも1で、`r_valid`が000なのでemptyである。

## valid bitの極性を逆に書いた

初版では、valid bitの扱いがすべて逆になっていた。

```systemverilog
if (push_valid & push_ready) begin
  ...
  r_valid[r_head]     <= 1'b0;
end
if (pop_valid & pop_ready) begin
  ...
  r_valid[r_tail] <= 1'b1;
end
...
assign pop_valid  = |(~r_valid);
```

pushで0、popで1にしている。`pop_valid`も「1つでもinvalidならpopできる」になっている。

reset直後は全bitが0なので、空のFIFOなのに`pop_valid=1`が出る。pushしてもvalid bitは0のままなので、fullにもならない。

pushとpopの代入を直したあとも、`pop_valid`の式だけ直し忘れていた。この状態だと、fullになったとき`pop_valid=0`かつ`push_ready=0`になり、FIFOがそこで止まってしまう。

## 文法でつまずいたところ

1つ目は、`r_valid`をunpacked配列で宣言していたこと。

```systemverilog
logic                      r_valid [DEPTH];
```

unpacked配列には、`r_valid <= 'h0`という一括代入も、`&r_valid`というreduction演算も、`~r_valid`というbit反転も使えない。1bitの信号を`DEPTH`個並べたいだけなら、packedのvectorにしておけば3つともそのまま書ける。

```systemverilog
logic [DEPTH-1: 0]         r_valid;
```

2つ目は、`r_fifo_data`を2つの`always_ff`から代入していたこと。

dataはresetしなくてよいので、Day07と同じように、resetなしの別の`always_ff`に分けた。

```systemverilog
always_ff @ (posedge clk) begin
  if (push_valid & push_ready) begin
    r_fifo_data[r_head] <= push_data;
  end
end

assign pop_data   = r_fifo_data[r_tail];
```

ところが、元のreset付きの`always_ff`の中にも同じ代入を残したままにしていた。同じ変数を複数の`always_ff`から代入することはできない。分けたら、元の方は消す。

## 規模を大きくしたときの考察

**full/emptyの判定**：今回の方式は、valid bitが`DEPTH`個、判定は`DEPTH`bitのANDとORになる。occupancy counterなら状態は`$clog2(DEPTH+1)`bitで済むが、pushとpopに応じて加算と減算をする論理が要る。depthが小さいうちはvalid bitの方式で十分で、depthが大きくなるとcounterの方が小さくなる。

valid bitの方式のままでも、判定は軽くできる。fullなら書き込みpointerの指すentryが必ずvalidで、emptyなら読み出しpointerの指すentryが必ずinvalidなので、`r_valid[r_head]`と`r_valid[r_tail]`を見るだけでも判定できる。

**クリティカルパス**：`pop_data`は`r_fifo_data`を`r_tail`で選ぶ`DEPTH`入力のmuxを通る組合せ出力である。depthが大きくなると、このmuxが下流の論理と合わせてクリティカルパスになりやすい。

**push_readyとpop_ready**：`push_ready`が`pop_ready`に依存しないので、pop側からpush側へ抜ける組合せパスがない。fullのときにpopと同時のpushを受理する仕様にすると、このパスができる。受理しない仕様にしたことで失うのは、fullに達した直後にpushが1サイクル待たされることだけである。

**面積**：dataは`DEPTH × WIDTH`個のFF。depthが大きくなればSRAMに置き換えたくなるが、同期読み出しのSRAMでは`pop_data`の組合せ出力という仕様をそのままでは満たせない。

## 最終RTLについて

最終稿は、明示的にwrapする2本のpointer、entryごとのvalid bit、resetなしのdata配列で構成した。モジュール名は`arbitrary_depth_fifo`。RTLは[problems/day11/solution.sv](../problems/day11/solution.sv)に置いてある。

レビューで修正したのは、valid bitの極性、`r_valid`の宣言、`r_fifo_data`の二重代入の3点。

## まとめと今後の検証

今回のポイントは、2本のpointerが一致したときにemptyとfullを区別する方法だった。

entryごとのvalid bitを持つ方式は、判定の式が「全部1ならfull、全部0ならempty」と単純で、pushとpopが同じbitを取り合うこともない。ただしその単純な式でも、極性を逆に書けば動かない。DEPTH=3くらいで表を書いて追ってみれば、すぐに気づけたはずだった。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** 上のDEPTH=3の表は机上で追っただけである。`DEPTH=5`、同時push/pop、resetも同じく机上の確認のみである。
