# 半導体フロントエンド設計100本ノック (33) 2-way Cache Tag Lookup + Multi-hit Detection

半導体フロントエンド設計100本ノック、第33問。

今回は2-wayのキャッシュのtag比較を設計してみた。アドレスからtagを取り出し、2つのwayのtagと比較して、hitしたかどうか、どのwayか、両方にhitしていないかを出す回路である。

RTLは`assign`が数本だけなのだが、tagを取り出すbit位置を間違え、validの添字も付け忘れていた。どちらも文法としては通ってしまい、結果だけが違う。

課題の詳細は[Day33 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/33)。

## 今回の問題：2-wayキャッシュのtag比較

今回作るのは、**2-way set associativeキャッシュの、選択済みのsetに対するtag比較の組合せ回路**。

[元の課題Issue #33](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/33)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- アドレスは32bitのbyte address。キャッシュは16 KiB、2-way set associative、lineは64 byte。
- すでに選択されたsetの、各wayのvalidとtagが入力される。setをindexで引く部分は、このモジュールの外にある。
- requestのtagと2つのwayのtagを並列に比較し、`hit`、`hit_way`、`multi_hit`を出す。
- 両方のwayにhitするのは異常な状態で、`multi_hit`で検出する。そのときの`hit_way`は暫定で0。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module cache_tag_lookup
  (
    input  logic [31: 0] req_addr,
    input  logic [ 1: 0] way_valid,
    input  logic [37: 0] way_tags,
    output logic         hit,
    output logic         hit_way,
    output logic         multi_hit
  );
    // ここにRTLを実装する
endmodule
```

`way_tags`は、2-way分のtagを1本のvectorに並べたものである。

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **両方にhitしたときの`hit`**：1にする。`hit`は「どれかのwayに当たった」ことを表し、異常かどうかは`multi_hit`を別に見る。
- **`way_tags`の分割**：way0が下位側（`way_tags[18:0]`）、way1が上位側（`way_tags[37:19]`）。
- **missのときの`hit_way`**：不定扱い。
- **indexとoffset**：setはすでに選択されているので、このモジュールの中では使わない。

### 検証してほしいCorner Case

miss、両方のwayにhit、それぞれのwayにhit。

以下では、実際に書いてみて修正した点を順番に見ていく。

## アドレスを分解する

キャッシュの構成から、アドレスの各フィールドの幅を求める。

- lineが64 byteなので、line内の位置を表すoffsetは6bit。
- line数は16384 / 64 = 256。2-wayなので、set数は256 / 2 = 128。setを選ぶindexは7bit。
- 残りがtagで、32 - 7 - 6 = 19bit。

```text
 31            13 12       6 5      0
+----------------+----------+--------+
|   tag (19bit)  | index(7) | off(6) |
+----------------+----------+--------+
```

way数が増えると、同じ容量でもset数が減るのでindexが短くなり、その分tagが長くなる。16 KiBで4-wayなら、setは64個、indexは6bit、tagは20bitになる。

## tagの比較

```systemverilog
logic [18: 0] w_way_tags[2];
assign w_way_tags[0] = way_tags[18: 0];
assign w_way_tags[1] = way_tags[37:19];

logic [1: 0] w_way_hit;
assign w_way_hit[0] = way_valid[0] & (req_addr[6+7 +: 19] == w_way_tags[0]);
assign w_way_hit[1] = way_valid[1] & (req_addr[6+7 +: 19] == w_way_tags[1]);
```

`req_addr[6+7 +: 19]`は、bit 13から上へ19bit、つまり`req_addr[31:13]`である。開始位置を`6+7`と書いておくと、offsetとindexの幅から来た数字だと分かる。

wayごとに19bitの比較器を置き、そのwayのvalidとANDを取る。invalidなwayには、tagがたまたま一致していてもhitしない。

2つの比較は互いに依存しないので、並列に行われる。

## hit、hit_way、multi_hit

```systemverilog
assign hit          = |w_way_hit;
assign hit_way      = w_way_hit[0] ? 1'b0 : 1'b1;
assign multi_hit    = &w_way_hit;
```

`hit`は、どちらかのwayに当たれば1。`multi_hit`は、両方に当たったときだけ1。

`hit_way`は、way0に当たっていれば0、そうでなければ1。両方に当たったときは0になるので、Issueの「暫定0」と合う。missのときは1が出るが、`hit`が0なので意味を持たない。

## multi-hitはなぜ異常か

同じsetの2つのwayが、同じtagでどちらもvalidになっている、というのがmulti-hitである。同じアドレスのデータがキャッシュの中に2つあることになる。

正しく動いているキャッシュでは、これは起きない。lineを新しく入れるのはmissしたときだけで、missしたということは、そのtagがどのwayにもなかったということだからである。

起きるとすれば、tagを保持しているメモリのbitが反転した場合や、fillやinvalidateの制御に誤りがある場合である。どちらのwayのデータが正しいのかは分からないので、片方を選んで先へ進むのではなく、異常として検出する。

## 表で確認する

`way_valid`は`[1:0]`の順に書く。

| `way_valid` | way0のtag | way1のtag | `hit` | `hit_way` | `multi_hit` |
|---|---|---|---:|---:|---:|
| 11 | 一致 | 不一致 | 1 | 0 | 0 |
| 11 | 不一致 | 一致 | 1 | 1 | 0 |
| 11 | 一致 | 一致 | 1 | 0 | 1 |
| 11 | 不一致 | 不一致 | 0 | - | 0 |
| 10 | 一致 | 一致 | 1 | 1 | 0 |
| 01 | 不一致 | 一致 | 0 | - | 0 |
| 00 | 一致 | 一致 | 0 | - | 0 |

3行目がmulti-hitである。5行目は、tagは両方一致しているがway0がinvalidなので、way1だけのhitになり、`multi_hit`は立たない。

## 文法でつまずいたところ

今回の誤りは2つとも、文法としては通ってしまうものだった。

1つ目は、tagを取り出す位置。

```systemverilog
req_addr[7 +: 19]
```

これは`req_addr[25:7]`になる。tagの開始位置は、offsetの6bitとindexの7bitを足した13なのに、indexの幅の7を開始位置に使っていた。indexの一部をtagとして比較し、tagの上位6bitは見ていないことになる。

`+:`は開始位置と幅を書く記法なので、幅の19は合っていた。それで正しそうに見えてしまった。

2つ目は、validの添字を付け忘れたこと。

```systemverilog
assign w_way_hit[0] = way_valid & (req_addr[7 +: 19] == w_way_tags[0]);
assign w_way_hit[1] = way_valid & (req_addr[7 +: 19] == w_way_tags[1]);
```

`way_valid`は2bitである。1bitの比較結果とANDを取ると、比較結果の方が2bitに0拡張され、結果は`{1'b0, way_valid[0] & 比較結果}`になる。それを1bitの`w_way_hit`に代入するので、下位bitだけが残る。

つまり、way0もway1も`way_valid[0]`を見ていた。`way_valid[1]`はどこにも使われていない。way1がinvalidでも、way0がvalidでway1のtagが一致すればhitになる。

SystemVerilogは幅の違う信号の演算を黙って通す。Day21で、64bitのポートに添字を付けて1bitと比較してしまったのと同じ種類の誤りである。

## 規模を大きくしたときの考察

**比較器**：way数と同じ数の、tag幅の比較器が必要になる。4-wayなら4個、8-wayなら8個。比較は並列なので、way数を増やしても比較そのものの遅延はほとんど変わらないが、面積と消費電力はway数に比例して増える。

**hit_wayの生成**：2-wayでは`w_way_hit[0]`を見るだけで済んだ。N-wayでは、one-hotのhit vectorを番号にするencoderが必要になる。データを選ぶmuxには、番号にする前のone-hotをそのまま使った方が速い。

**multi-hitの検出**：2-wayでは2bitのANDで済んだ。N-wayでは「2つ以上のbitが立っている」ことの検出になり、hit vectorがone-hotかどうかを調べる回路が必要になる。way数が増えると、ここは単純なANDやORより重くなる。

**クリティカルパス**：実際のキャッシュでは、この回路の前にtagのメモリの読み出しがあり、後ろにデータを選ぶmuxがある。メモリの読み出し、tagの比較、wayの選択、データのmuxが直列に並び、キャッシュのアクセス時間を決める。way数を増やすとmuxが深くなる。

これを避けるために、hitするwayを予測して先にデータを読み出すway predictionや、tagの一部だけを先に比較する方法がある。

**tagの幅**：アドレスが64bitになれば、tagもその分長くなり、比較器が大きくなる。仮想アドレスでindexを引き、物理アドレスでtagを比較する構成では、tagの比較はTLBの結果を待つことになり、ここもクリティカルパスになる。

## 最終RTLについて

最終稿は、`way_tags`の分割、wayごとの比較とvalidのAND、hit / hit_way / multi_hitの生成で構成した。モジュール名は`cache_tag_lookup`。RTLは[problems/day33/solution.sv](../problems/day33/solution.sv)に置いてある。

レビューで修正したのは、tagを取り出すbit位置と、`way_valid`の添字の2点。

## まとめと今後の検証

今回のポイントは、アドレスのフィールドを正しく数えることだった。

offsetは6bit、indexは7bit、tagは19bitで、tagはbit 13から始まる。幅は合っていても、開始位置を間違えれば別のbitを比較することになる。

もう1つは、幅の違う信号の演算である。2bitの信号をそのまま1bitの式に書いても、エラーにはならない。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** 上の表は机上で追っただけである。今回の2つの誤りは、lintをかけていれば幅の不一致や未使用のbitとして警告が出た可能性が高い。
