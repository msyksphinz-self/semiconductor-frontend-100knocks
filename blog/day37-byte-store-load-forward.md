# 半導体フロントエンド設計100本ノック (37) Byte-granular Store-to-Load Forwarding

半導体フロントエンド設計100本ノック、第37問。

今回はDay21のStore-to-Load Forwardingを、byte単位に拡張したものを設計してみた。Day21は「アドレスが一致したstoreのデータを丸ごと渡す」だったが、今回はloadの読むbyteを1つずつ見て、byteごとに一番新しいstoreを選ぶ。

書く前に、入力の形式を理解するのに時間がかかった。storeのアドレスが8-byte境界に揃っているとはどういうことか、byte enableは何を基準にした位置なのか。そこが分かってから書いたRTLも、shift量、配列の添字、generateの書き方、forwardの条件と、ひととおり間違えた。

課題の詳細は[Day37 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/37)。

## 今回の問題：byte単位のStore-to-Load Forwarding

今回作るのは、**4-entryのStore Bufferを検索し、loadの読むbyteごとに最も新しいstoreのデータを選んで合成する組合せ回路**。

[元の課題Issue #37](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/37)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- Store Bufferは4-entry。entry0がoldest、entry3がyoungest。
- 各entryは、valid、8-byte境界に揃えたアドレス、64bitのデータ、8bitのbyte enableを持つ。
- loadは1/2/4/8 byte。アドレスとsizeから、8-byteの領域の中でどのbyteを読むかを表すbyte maskを作る。8-byteの領域をまたぐloadは対象外。
- byte laneごとに、一致するstoreのうち最もyoungなものを選ぶ。
- loadの読むbyteが**すべて**storeで覆われていれば`forward`、**一部だけ**覆われていれば`stall`、**まったく重ならなければ**`memory_read`。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module byte_store_load_forward
  (
    input  logic [3: 0]  st_valid,
    input  logic [31: 0] st_addr [4],
    input  logic [63: 0] st_data [4],
    input  logic [7: 0]  st_byte_en[4],

    input  logic [31: 0] ld_addr,
    input  logic [1: 0]  ld_size,

    output logic         forward,
    output logic         stall,
    output logic         memory_read,
    output logic [63: 0] forward_data
  );
    // ここにRTLを実装する
endmodule
```

Issueのテンプレートでは、`st_addr`、`st_data`、`st_byte_en`は4-entry分を1本に並べたvectorだった。Day21とDay33で、vectorの分割と添字を何度も間違えたので、今回はポートをentryごとの配列にした。`st_valid`だけは、1bitを4つ並べるだけなのでpackedのままにしている。

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **`ld_size`の符号化**：0が1 byte、1が2 byte、2が4 byte、3が8 byte。
- **loadのアドレス**：sizeの境界に揃っている前提。2-byteのloadは2の倍数、4-byteのloadは4の倍数の位置にある。揃っていないアドレスの下位bitは無視する。
- **storeのアドレスの比較**：`[31:3]`同士を比較する。下位3bitは見ない。
- **`forward_data`の位置**：8-byteの領域の中の位置のまま出す。loadの先頭が下に来るように詰めることはしない。
- **覆われていないbyteの`forward_data`**：0を出す。
- **`forward=0`のときの`forward_data`**：不定扱い。
- **3つの出力の関係**：`forward`、`stall`、`memory_read`は、必ずどれか1つだけが1になる。

### 検証してほしいCorner Case

byte merge、partial coverage、offset。

以下では、実際に書いてみて修正した点を順番に見ていく。

## storeは8-byteの領域とbyte laneで表す

最初に引っかかったのは、storeの入力の形式だった。

例えばアドレス0x4と0x5への2-byteのstoreは、「アドレス0x4、byte enableは下の2bit」と入ってくるのかと思った。そうではなく、次のように入ってくる。

| フィールド | 値 | 意味 |
|---|---|---|
| `st_addr` | `0x0` | 8-byteの領域の先頭 |
| `st_byte_en` | `8'b0011_0000` | byte lane 4と5が有効 |
| `st_data` | `[47:32]`に書くデータ | lane 4〜5の位置に置く |

```text
アドレス     0x7  0x6  0x5  0x4  0x3  0x2  0x1  0x0
byte lane     7    6    5    4    3    2    1    0
byte_en       0    0    1    1    0    0    0    0
st_data       .    .   D1   D0    .    .    .    .
```

アドレスは8-byteの領域の先頭を指し、byte enableとデータは、その領域の中の絶対位置で表す。データも右詰めではなく、laneの位置に置かれている。AXIの`WSTRB`と同じ考え方である。

この形式にしておくと、storeをbufferに入れるときに一度だけshiftしておけば、あとの比較が単純になる。アドレスは`[31:3]`の等値比較だけ、byteの重なりはmask同士のANDだけ、データはlaneごとに同じ位置から取るだけで済む。

## loadのbyte maskを作る

load側は揃っていないアドレスのまま入ってくるので、store側と同じlaneの表現に直す。

```systemverilog
logic [7: 0] ld_byte_mask;
always_comb begin
  case (ld_size)
    2'b00   : ld_byte_mask = 8'b0000_0001 <<  ld_addr[2: 0];         // Byte
    2'b01   : ld_byte_mask = 8'b0000_0011 << {ld_addr[2: 1], 1'b0};  // Half
    2'b10   : ld_byte_mask = 8'b0000_1111 << {ld_addr[2: 2], 2'b00}; // Word
    2'b11   : ld_byte_mask = 8'b1111_1111;                           // DWord
    default : ld_byte_mask = 8'b0000_0000;
  endcase
end
```

sizeから下に詰めたmaskを作り、領域の中の開始位置だけ左にshiftする。開始位置は`ld_addr[2:0]`である。

loadはsizeの境界に揃っている前提にしたので、2-byteでは最下位の1bit、4-byteでは下位の2bitを0に固定している。

| size | `ld_addr[2:0]` | mask |
|---|---:|---|
| 1 byte | 5 | `0010_0000` |
| 2 byte | 4 | `0011_0000` |
| 2 byte | 6 | `1100_0000` |
| 4 byte | 4 | `1111_0000` |
| 8 byte | 0 | `1111_1111` |

## entryごとに重なるbyteを求める

```systemverilog
logic [7: 0] w_byte_hit [4];
generate for (genvar e = 0; e < 4; e++) begin: loop_ENTRY
  logic [7: 0] w_byte_hit_raw;
  assign w_byte_hit_raw = ld_byte_mask & st_byte_en[e];
  assign w_byte_hit[e]  = (st_valid[e] & (st_addr[e][31: 3] == ld_addr[31: 3]) & |w_byte_hit_raw) ? w_byte_hit_raw : 'h0;
end endgenerate
```

loadのbyte maskとstoreのbyte enableのANDが、「loadが読み、かつそのstoreが書くbyte」である。entryがvalidで、同じ8-byteの領域を指していれば、それがそのentryのヒットになる。

Day21では、アドレスが一致すればヒットだった。今回は、アドレスの`[31:3]`が一致していても、byteが重なっていなければヒットしない。同じ領域のlane 4〜7に書くstoreは、lane 0〜3を読むloadとは無関係である。

## byteごとにyoungestを選ぶ

```systemverilog
logic [7: 0] forward_byte;
always_comb begin
  forward_byte = 'h0;
  forward_data = 'h0;
  for (int b = 0; b < 8; b++) begin
    for (int e = 0; e < 4; e++) begin
      if (w_byte_hit[e][b]) begin
        forward_data[b*8 +: 8] = st_data[e][b*8 +: 8];
        forward_byte[b]        = 1'b1;
      end
    end
  end
end
```

外側のループがbyte lane、内側のループがentryである。laneごとに、entry0からentry3へ向かって見ていき、ヒットしていればそのentryのデータで上書きする。後から実行された代入が勝つので、laneごとに一番youngなentryのデータが残る。Day21と同じ後勝ちのループを、laneごとに回している。

`forward_byte`は、laneごとに「どれかのstoreで覆われた」ことを表す。Issueのいうcovered maskである。`w_byte_hit`に最初から`ld_byte_mask`をANDしてあるので、`forward_byte`はloadの読む範囲にしか立たない。

## byte merge

例えば次の場合。

```text
byte lane      7  6  5  4  3  2  1  0
entry1 (old)   .  .  .  .  A3 A2 A1 A0    4-byteのstore
entry3 (young) .  .  .  .  .  .  B1 B0    2-byteのstore
load (4 byte)              ^  ^  ^  ^
forward_data   0  0  0  0  A3 A2 B1 B0
```

lane 0〜1はentry1とentry3の両方がヒットするので、youngなentry3のデータになる。lane 2〜3はentry1だけがヒットする。2つのstoreのデータを、byteごとに合成したものがloadへ渡る。

Day21のように「一番youngなentryを1つ選ぶ」やり方だと、entry3が選ばれ、lane 2〜3のデータが足りなくなる。byteごとに選ぶ必要があるのはこのためである。

## forward、stall、memory_read

```systemverilog
assign memory_read = forward_byte == 'h0;
assign forward     = forward_byte == ld_byte_mask;
assign stall       = !memory_read & !forward;
```

- `forward_byte`が0なら、loadの読むbyteは1つもstoreで覆われていない。メモリから読めばよい。
- `forward_byte`が`ld_byte_mask`と一致すれば、読むbyteがすべて覆われている。Store Bufferだけでデータが揃う。
- どちらでもなければ、一部だけ覆われている。

`ld_byte_mask`は必ず1 byte以上立っているので、上の2つが同時に成り立つことはない。3つの出力は、必ずどれか1つだけが1になる。

一部だけ覆われている場合にstallする理由は、どちらから読んでも正しい値にならないからである。Store Bufferだけでは足りないbyteがある。メモリから読むと、まだ書き込まれていないstoreの分が古い値になる。メモリの値とStore Bufferの値をbyteごとに合成すれば作れるが、今回はそこまではやらず、loadを待たせる。storeがメモリに書き込まれてStore Bufferから消えれば、次に試したときは`memory_read`になる。

## 表で確認する

lane 0〜3を読む4-byteのload（`ld_byte_mask = 0000_1111`）で、同じ領域へのstoreがある場合。

| storeの状況 | `forward_byte` | 出力 |
|---|---|---|
| lane 0〜3に4-byteのstore | `0000_1111` | `forward` |
| lane 0〜7に8-byteのstore | `0000_1111` | `forward` |
| lane 0〜1とlane 2〜3に別々の2-byteのstore | `0000_1111` | `forward` |
| lane 0〜1に2-byteのstoreだけ | `0000_0011` | `stall` |
| lane 4〜7に4-byteのstoreだけ | `0000_0000` | `memory_read` |
| lane 0〜3にstoreがあるがinvalid | `0000_0000` | `memory_read` |
| 別の領域へのstoreだけ | `0000_0000` | `memory_read` |

offsetのある場合。アドレスの下位3bitが6の2-byteのloadは、`ld_byte_mask`が`1100_0000`になる。同じ領域に8-byteのstoreがあれば`forward`で、データは`forward_data[63:48]`に出る。下に詰めては出さない。

## 間違えたところ

今回は直した箇所が多かったので、順に書いておく。

**shift量**：最初は、2-byteのloadを`ld_addr[1:0]`、4-byteのloadを`ld_addr[0:0]`でshiftしていた。次に、下位を0に固定しようとして`{ld_addr[1:0], 1'b0}`、`{ld_addr[0:0], 2'b00}`と書いた。どちらも、取り出すbitが下にずれている。開始位置は`ld_addr[2:0]`の3bitで、下位を0に固定するなら残すのは上位側である。アドレス0x4の4-byteのloadで試せば、shift量が0になってしまうことにすぐ気づけた。

**配列の添字**：ポートを配列にしたのに、`st_byte_en`、`st_valid`、`st_addr`に`[e]`を付け忘れた。`st_addr[31:3]`と書くと、配列の31番目から3番目の要素という意味になってしまう。

**generateの中のif**：generateブロックの中に、信号を条件にした`if`と、`assign`の付かない代入を書いていた。generateの中の`if`はgenerate-ifで、条件は定数でなければならない。信号で切り替えるなら、三項演算子の`assign`か、`always_comb`の中に書く。

**`forward_byte`**：ヒットしたときに`1'b0`を代入していた。初期値も0なので、常に0だった。

**`forward`の条件**：最初は`|forward_byte`、つまり「1 byteでも覆われていればforward」にしていた。これだと一部だけ覆われている場合もforwardになり、`stall`が1になることがない。次に`&forward_byte`にしたが、これは「8つのlaneがすべて覆われている」で、8-byteのload以外では成り立たない。比べる相手は、全bitが1のvectorではなく、loadのbyte maskである。

**`forward_data`の既定値**：`always_comb`の先頭で`forward_byte`には0を代入していたが、`forward_data`には代入していなかった。ヒットしなかったlaneには何も代入されないので、latchになる。Day23と同じである。

## 規模を大きくしたときの考察

**比較器**：アドレスの比較器はentryごとに1つで、Day21と変わらない。8-byteの領域の単位で比較するので、幅は3bit短い29bitになる。

**byteごとの選択**：youngestを選ぶ論理が、Day21では1つだったのに対し、今回はlaneごとに1つ、合わせて8つになる。データのmuxも、64bitを1つではなく、8bitを8つ持つことになる。entry数が増えると、この部分がentry数に比例して大きくなる。

**クリティカルパス**：アドレスの比較、byte maskとのAND、laneごとのyoungestの選択、データのmux、という順に並ぶ。`forward`と`stall`は、さらにその後ろで`forward_byte`を`ld_byte_mask`と比較する。loadを待たせるかどうかの判定がデータより遅くなるので、パイプラインの制御に使うには厳しい信号になる。

判定だけなら、データを選ぶ前に作れる。laneごとに全entryのヒットのORを取れば`forward_byte`と同じものになり、youngestの選択を通らずに済む。

**領域をまたぐアクセス**：今回は8-byteの領域をまたぐloadを対象外にした。またぐ場合は、2つの領域のそれぞれについて同じ検索をする必要がある。storeの側も、またぐstoreを2つのentryに分けて入れるか、またぐことを表す情報を持つことになる。

**youngestの定義**：今回はentry3がyoungestで固定だった。Day21でも書いたとおり、実際のStore Bufferはリングバッファなので、youngestはpointerの位置で変わる。loadより後のstoreを除外する必要もある。byteごとの選択と組み合わせると、laneごとにpointerを起点としたpriority encoderが必要になる。

**partial coverageの扱い**：今回はstallにした。メモリから読んだ値とbyteごとに合成すれば待たせずに済むが、合成のためのmuxがメモリの読み出しの後ろに入り、loadのパスが伸びる。頻度が低いので、待たせるだけにすることが多い。

## 最終RTLについて

最終稿は、loadのbyte maskの生成、entryごとのbyteのヒット、laneごとの後勝ちのループによるyoungestの選択、`forward_byte`からの3つの判定で構成した。モジュール名は`byte_store_load_forward`。RTLは[problems/day37/solution.sv](../problems/day37/solution.sv)に置いてある。

ポートは、Issueのテンプレートの平坦なvectorから、entryごとの配列に変えている。

## まとめと今後の検証

今回のポイントは、storeもloadも「8-byteの領域とbyte lane」という同じ表現に揃えることだった。

揃えてしまえば、重なりの判定はmask同士のANDになり、データの合成はlaneごとの選択になる。Day21の「アドレスが一致したら丸ごと渡す」を、laneの数だけ並べた形である。

判定は、覆われたbyteのmaskをloadのbyte maskと比べる。すべて覆われていればforward、1つも覆われていなければmemory read、その間がstallである。

**Verilatorのlint（`--lint-only -Wall`）は、エラーも警告もなく通した（ファイル名に関する警告を除く）。シミュレーションとテストベンチ実行は未実施である。** 上の表は机上で追っただけである。今回は直した箇所が多く、動作の見落としが残っている可能性は、これまでの問題より高い。
