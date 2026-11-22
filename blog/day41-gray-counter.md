# 半導体フロントエンド設計100本ノック (41) Gray Code Counter

半導体フロントエンド設計100本ノック、第41問。

今回はGray codeのカウンタを設計してみた。binaryの値とGray codeの両方をFFで持つカウンタで、後で非同期FIFOのpointerとして使う部品である。

Gray codeは`bin ^ (bin >> 1)`で作れる。今回は、なぜこの式で1 bitしか変わらないのかを、binaryの進み方から追いかけてみた。

課題の詳細は[Day41 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/41)。

## 今回の問題：Gray codeをFFから出すカウンタ

binaryカウンタの値を複数bitのままclock domainをまたいで渡すと、桁上がりで複数bitが同時に変化し、受信側で存在しない値を観測することがある。Gray codeは隣り合う値で1 bitしか変化しないので、受信側がどのタイミングでサンプルしても「変化前」か「変化後」のどちらかになる。

### 仕様

- `WIDTH >= 2`。デフォルトは`WIDTH=4`。
- `en=1`のposedgeで1増える。`2^WIDTH-1`の次は0へwrapする。`en=0`なら保持する。
- resetはactive-low非同期resetで、`bin`と`gray`を0にする。
- `bin_next`は次のcycleの`bin`（`en ? bin+1 : bin`）を組合せで出す。
- `gray_next`は`bin_next ^ (bin_next >> 1)`を組合せで出す。
- `gray`は`gray_next`を取り込むFFの出力とする。`bin`から組合せで変換してはいけない。
- `decoded_bin`は`gray`だけからbinaryへ戻した値を組合せで出す。常に`bin`と一致する。

```systemverilog
module gray_counter #(
    parameter int unsigned WIDTH = 4
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             en,
    output logic [WIDTH-1:0] bin,
    output logic [WIDTH-1:0] gray,
    output logic [WIDTH-1:0] bin_next,
    output logic [WIDTH-1:0] gray_next,
    output logic [WIDTH-1:0] decoded_bin
);
    // ここにRTLを実装する
endmodule
```

`WIDTH=3`のGray codeは次の順になる。

| `bin` | `gray` | 前の値から変化するbit |
|---:|---:|---|
| 000 | 000 | （100から）bit2 |
| 001 | 001 | bit0 |
| 010 | 011 | bit1 |
| 011 | 010 | bit0 |
| 100 | 110 | bit2 |
| 101 | 111 | bit0 |
| 110 | 101 | bit1 |
| 111 | 100 | bit0 |

## なぜ`bin ^ (bin >> 1)`で1 bitしか変わらないのか

`bin ^ (bin >> 1)`は、各bitについて1つ上のbitとのXORを取っている。

```text
g[i] = b[i] ^ b[i+1]
```

つまり、Gray codeの各bitは「1つ上のbitと値が違えば1、同じなら0」を表している。

一方、binaryの+1は、**最も低い位置の0を1に反転し、そこから下の1を全部0に反転する**操作である。

```text
0111 → 1000
```

ここで、`g[i]`が反転するのは、`b[i]`と`b[i+1]`の**片方だけが反転したとき**である。両方反転すると、XORの結果は変わらない。

+1で0→1になる位置を`k`とすると、binaryで反転するのはbit `k`からbit 0までの連続した範囲になる。

| 位置 | `b[i]` | `b[i+1]` | `g[i]` |
|---|---|---|---|
| `i > k` | そのまま | そのまま | 変わらない |
| `i = k` | 反転 | そのまま | **反転** |
| `i < k` | 反転 | 反転 | 変わらない |

反転する範囲と反転しない範囲の境界は`k`の1か所だけなので、Gray codeも1 bitだけ変わる。**binaryで0→1になった位置のGray bitだけが変化する**ということになる。

```text
bin : 0111 → 1000
gray: 0100 → 1100   (bit3 だけ変化)
```

### wrapの場合

`1111 → 0000`には「最も低い位置の0」がない。ただ、`>> 1`でMSBの上には0が入るので、`b[WIDTH]=0`という反転しないbitがあると考えられる。全bitが反転しても、境界はMSBと`b[WIDTH]`の間に1か所残るので、`g[WIDTH-1]`だけが変わる。

```text
bin : 1111 → 0000
gray: 1000 → 0000
```

## Gray codeからbinaryへ戻す

`g[i] = b[i] ^ b[i+1]`を`b[i]`について解くと、次の式になる。

```text
b[WIDTH-1] = g[WIDTH-1]
b[i]       = g[i] ^ b[i+1]
```

言葉にすると、**上から順に、Gray codeが1なら上位のbitを反転し、0なら同じ値を続ける**ということである。`gray=110`なら次のように戻る。

```text
b[2] = g[2]         = 1
b[1] = g[1] ^ b[2]  = 1 ^ 1 = 0
b[0] = g[0] ^ b[1]  = 0 ^ 0 = 0     → bin = 100
```

## RTL

```systemverilog
always_ff @ (posedge clk, negedge rst_n) begin
  if (!rst_n) begin
    bin <= 'h0;
    gray <= 'h0;
  end else begin
    if (en) begin
      bin <= bin_next;
      gray <= gray_next;
    end
  end
end

assign bin_next = en? bin + 'h1 : bin;
assign gray_next = bin_next ^ (bin_next >> 1);

assign decoded_bin[WIDTH-1] = gray[WIDTH-1];
generate for (genvar i = WIDTH-2; i >= 0; i--) begin: loop_DECODED
  assign decoded_bin[i] = gray[i] ? ~decoded_bin[i+1] : decoded_bin[i+1];
end endgenerate
```

`gray[i] ? ~decoded_bin[i+1] : decoded_bin[i+1]`は、`gray[i] ^ decoded_bin[i+1]`と同じである。「1なら反転、0ならそのまま」という考え方をそのまま書いた。

`bin_next`がすでに`en`を見ているので、`always_ff`の`if (en)`はなくても動作は同じである。

## 間違えたところ

**`bin_next`に`en`が入っていなかった**：最初は`assign bin_next = bin + 'h1;`と書いていた。FF側に`if (en)`があるので`bin`と`gray`は正しく動くが、`en=0`のときの`bin_next` / `gray_next`が「次のcycleの値」にならない。

## lintの警告

`verilator --lint-only -Wall`はエラーなしで通り、警告が2種類残った。

- `DECLFILENAME`：ファイル名`sv041_gray_counter`とモジュール名`gray_counter`が違う。
- `UNOPTFLAT`：`decoded_bin`が自分自身に依存する組合せループに見える。

`UNOPTFLAT`は本物のループではない。`decoded_bin[i]`は`decoded_bin[i+1]`を読むだけで、bit単位ではMSBからLSBへの一方向である。Verilatorが信号をまとめて見ているために出る警告で、シミュレーションが少し遅くなる可能性があるだけである。`always_comb`の中で降順の`for`にすると、この警告は消える。今回は`generate`のままにした。

## 規模を大きくしたときの考察

**`gray`をFFから直接出す理由**：`assign gray = bin ^ (bin >> 1)`でも値は同じになる。しかし、`bin`の複数bitが変わるcycleでは、XORの出力に一瞬glitchが出る。別のclock domainがそのglitchをサンプルすると、1 bitしか変わらないという前提が崩れる。

**変換のdelay**：Gray→binaryはMSBからのXORの連鎖なので、LSBまでのパスは`WIDTH-1`段のXORになる。`WIDTH`が大きくてタイミングが厳しいなら、`b[i]`が`g[WIDTH-1:i]`の全bitのXORであることを使って、XOR treeで組むこともできる。

**2以上飛ぶカウンタ**：1 bitしか変わらないのは、反転する範囲が連続しているからである。+2すると、`00 → 10`のGray codeは`00 → 11`となり2 bit変わる。CDCでは、途中の値を受信側が観測する可能性がある。

**depthが2のべき乗でない場合**：`0〜5`で回すと、wrapは`gray(5)=111`から`gray(0)=000`になり、3 bit同時に変化する。非同期FIFOのpointerでdepthを2のべき乗にする理由の1つである。

## 最終RTLについて

RTLは[problems/day41/solution.sv](../problems/day41/solution.sv)に置いてある。testbenchは[problems/day41/tb.sv](../problems/day41/tb.sv)。

## まとめと今後の検証

Gray codeの各bitは隣のbitとの差を表していて、binaryの+1で反転する範囲の境界は1か所しかない。だから1 bitしか変わらない。

**Verilatorのlint（`--lint-only -Wall`）はエラーなしで通した。今回からIssueの仕様をもとに別に作成したself-checking testbenchも実行し、`WIDTH=2, 3, 4, 8`の各3 seedで不一致は0件だった。** 確認したのは、clockなしの非同期reset、wrapを含む全値の一周、1 bit変化、`en`のランダム、`bin_next` / `gray_next`、`decoded_bin`、動作途中のresetである。`gray`がFF出力かどうかは動作では区別できないので、RTLを読んで確認した。
