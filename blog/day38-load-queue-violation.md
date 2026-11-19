# 半導体フロントエンド設計100本ノック (38) Load Queue Memory Ordering Violation Detection

半導体フロントエンド設計100本ノック、第38問。

今回はmemory ordering violationの検出を設計してみた。storeのアドレスが確定したときにLoad Queueを検索し、先に実行されてしまったloadの中に、同じ場所を読んだものがないかを調べる回路である。

Day37はloadの側からStore Bufferを検索した。今回は向きが逆で、storeの側からLoad Queueを検索する。重なりの判定はDay37と同じなので、RTLは短い。ただ、これまで添字の付け忘れを繰り返してきた反動で、今回は付けなくてよいところに添字を付けていた。

課題の詳細は[Day38 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/38)。

## 今回の問題：Load Queueの違反検出

今回作るのは、**storeのアドレスが確定したサイクルに、4-entryのLoad Queueを検索して、そのstoreと重なる実行済みのloadを見つける組合せ回路**。

[元の課題Issue #38](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/38)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- Load Queueは4-entry。entry0がoldest。
- 古いstoreのアドレスが確定した（resolveした）サイクルに検索する。
- loadのentryがvalidで、すでに実行済み（executed）で、storeと同じ8-byteの領域にあり、byteが重なっていれば違反（violation）。
- storeは、Load Queueにあるすべてのloadより古いと仮定する。
- `o_violation[3:0]`には、違反したentryをすべて立てる。
- やり直し（replay）の対象は、entry0からentry3の順で最もoldestな違反を1つ選ぶ。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module load_queue_violation
  (
    input  logic         st_resolve_valid,
    input  logic [31: 0] st_addr,
    input  logic [ 7: 0] st_byte_mask,

    input  logic [ 3: 0] ld_valid,
    input  logic [ 3: 0] ld_executed,
    input  logic [31: 0] ld_addr     [4],
    input  logic [ 7: 0] ld_byte_mask[4],

    output logic [ 3: 0] o_violation,
    output logic         replay_valid,
    output logic [ 1: 0] replay_idx
  );
    // ここにRTLを実装する
endmodule
```

Issueのテンプレートでは、`ld_addr`と`ld_byte_mask`は4-entry分を1本に並べたvectorだった。Day37と同じく、entryごとの配列に変えている。

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **アドレスの比較**：`[31:3]`同士を比較する。下位3bitは見ない。領域の中の位置はbyte maskで与えられている。
- **`st_resolve_valid=0`のとき**：`o_violation`は全bit 0。
- **`replay_valid=0`のときの`replay_idx`**：0を出す。

### 検証してほしいCorner Case

複数の違反、maskが重ならない場合、未実行のload。

以下では、実際に書いてみて修正した点を順番に見ていく。

## memory ordering violationとは

Out-of-Orderのプロセッサでは、storeのアドレスの計算が終わる前に、それより若いloadを先に実行することがある。storeのアドレスが分かるまでloadを全部待たせていたら、性能が出ないからである。

先に実行したloadは、Store Bufferを検索しても該当するstoreが見つからない。storeのアドレスがまだ分かっていないのだから当然である。loadはメモリから値を読む。Day37でいう`memory_read`になる。

あとでstoreのアドレスが確定して、loadが読んだのと同じ場所への書き込みだったと分かったとする。プログラムの順序では、storeが先でloadが後である。loadはstoreの書いた値を読まなければならなかったのに、メモリの古い値を読んでしまった。これがmemory ordering violationである。

見つけたら、そのloadと、それ以降の命令をやり直す。

Day37との対応は次のとおり。

| | Day37 | Day38 |
|---|---|---|
| きっかけ | loadを実行するとき | storeのアドレスが確定したとき |
| 検索する相手 | Store Buffer（古いstore） | Load Queue（若いload） |
| 見つけたら | データをforwardする | やり直させる |
| 選ぶのは | byteごとにyoungest | oldestを1つ |

## 違反の条件

```systemverilog
generate for (genvar e = 0; e < 4; e++) begin: loop_ENTRY
  assign o_violation[e] = st_resolve_valid & ld_valid[e] & ld_executed[e] &
                          (ld_addr[e][31: 3] == st_addr[31: 3]) &
                          |(ld_byte_mask[e] & st_byte_mask);
end endgenerate
```

5つの条件のANDである。

- **`st_resolve_valid`**：このサイクルにstoreのアドレスが確定した。確定していないサイクルには、`st_addr`に何が載っていても違反にしない。
- **`ld_valid[e]`**：entryにloadが入っている。
- **`ld_executed[e]`**：そのloadはすでに実行済み。まだ実行していないloadは、これから実行するときにStore Bufferを検索して、確定したstoreを見つけられる。違反ではない。
- **アドレスの`[31:3]`が一致**：同じ8-byteの領域にある。
- **byte maskのANDが0でない**：その領域の中で、byteが1つでも重なっている。

最後の2つはDay37と同じ判定である。同じ領域でも、storeがlane 0〜3、loadがlane 4〜7なら重ならない。違反ではない。

今回はload側のbyte maskも入力として与えられるので、アドレスとsizeからmaskを作る回路は要らない。Load Queueにloadを入れるときに作ってある、という前提である。

storeがloadより古いかどうかの比較は入っていない。「storeは全loadより古い」と仮定しているからである。

## oldestを1つ選ぶ

```systemverilog
assign replay_valid = |o_violation;

always_comb begin
  replay_idx = 0;
  for (int e = 3; e >= 0; e--) begin
    if (o_violation[e]) begin
      replay_idx = e;
    end
  end
end
```

違反が1つでもあれば`replay_valid`を立てる。

`replay_idx`は、3から0へ向かう後勝ちのループで選ぶ。最後に評価されるentry0が最も優先されるので、違反の中で番号の最も小さい、つまり最もoldestなentryが残る。Day30と同じ向きである。

## なぜoldestを1つだけ選ぶのか

違反が複数あっても、やり直しの起点は1つでよい。

loadをやり直すときは、そのloadだけでなく、それより若い命令もすべてやり直す。間違った値を読んだloadの結果を使った命令が、後ろにどれだけあるか分からないからである。

oldestの違反からやり直せば、それより若い違反も巻き込まれてやり直される。逆に、若い方を起点にすると、それより古い違反が間違った値のまま残ってしまう。

Day37ではyoungestを選んだ。loadが読むべきなのは、一番最後に書かれた値だからである。今回はoldestを選ぶ。やり直しは、一番最初に間違えたところから始めるからである。

## 表で確認する

storeが、アドレス0x1000の領域のlane 0〜3（`st_byte_mask = 0000_1111`）に書き込むとする。

| entry | valid | executed | `ld_addr` | `ld_byte_mask` | 違反 | 理由 |
|---:|---:|---:|---|---|---:|---|
| 0 | 1 | 1 | 0x1000 | `1111_0000` | 0 | 同じ領域だがbyteが重ならない |
| 1 | 1 | 1 | 0x1000 | `0000_0011` | 1 | lane 0〜1が重なる |
| 2 | 1 | 0 | 0x1000 | `0000_1111` | 0 | まだ実行していない |
| 3 | 1 | 1 | 0x1002 | `0000_1100` | 1 | lane 2〜3が重なる |

`o_violation`は`1010`（`[3:0]`の順）、`replay_valid`は1、`replay_idx`は1になる。違反はentry1とentry3の2つで、oldestのentry1がやり直しの起点になる。

entry3は`ld_addr`の下位3bitが2だが、比較するのは`[31:3]`なので同じ領域と判定される。

このほかの場合。

| 状況 | `o_violation` | `replay_valid` |
|---|---|---:|
| `st_resolve_valid=0` | `0000` | 0 |
| loadがすべて別の領域（0x1008など） | `0000` | 0 |
| 重なるentryがすべてinvalid | `0000` | 0 |

## 間違えたところ

**storeのmaskに添字を付けた**：最初は次のように書いていた。

```systemverilog
|(ld_byte_mask[e] & st_byte_mask[e])
```

`st_byte_mask`はstore 1つ分の8bitのmaskである。`[e]`を付けると、その中の1bitを取り出すことになる。8bitと1bitのANDになり、lane 0しか比較されない。

Day33とDay37では添字の付け忘れだった。今回は付けすぎである。load側はentryごとにあるので`[e]`が要り、store側は1つしかないので要らない。信号が「entryごとにあるもの」なのか「1つだけのもの」なのかを考えずに、機械的に付けていた。

**`st_resolve_valid`を使っていなかった**：条件に入れ忘れていた。storeが確定していないサイクルにも、`st_addr`にたまたま載っている値で違反が検出される。

**genvarをループの外で使った**：`replay_valid`を`o_violation[e]`と書いていた。`e`はgenerateのループの中でしか使えない。

**アドレスを32bit全体で比較していた**：`ld_addr[e] == st_addr`と書いていた。入力のアドレスが8-byte境界に揃えてあれば動くが、揃っていないアドレスが入ってくると、同じ領域なのに不一致になって違反を見逃す。`[31:3]`同士の比較に直した。

## 規模を大きくしたときの考察

**比較器**：entryごとに、29bitのアドレスの比較器と、8bitのmaskのANDとORが必要になる。32-entryなら32組。Load Queueのentry数に比例する。storeが同時に複数確定するなら、さらにその本数倍になる。

**priority encoder**：oldestの違反を選ぶpriority encoderは、4-entryなら浅いが、32-entryでは段数が増える。アドレスの比較の後ろに直列に入るので、ここがクリティカルパスになる。

**クリティカルパス**：`st_addr`から、アドレスの比較、validなどとのAND、priority encoderを通って`replay_idx`に至る。`st_addr`自体が、アドレスの計算の結果なので遅い信号である。そのため実際には、storeのアドレスが確定したサイクルではなく、次のサイクルに検索することが多い。違反の検出が1サイクル遅れても、やり直しの判断が少し遅れるだけで、正しさには影響しない。

**oldestの定義**：今回はentry0がoldestで固定だった。実際のLoad Queueはリングバッファなので、oldestはpointerの位置で変わる。pointerを起点としたpriority encoderが必要になる。Day21やDay37で書いたのと同じ話である。

**storeとloadの年齢**：今回は「storeは全loadより古い」と仮定した。実際のLoad Queueには、そのstoreより古いloadも入っている。古いloadは、storeより先に実行されていて正しいので、違反にしてはいけない。loadごとに「このstoreより若いか」を判定する必要があり、年齢の比較かmaskが条件に加わる。

**forwardされていたload**：loadが、そのstoreよりさらに若い別のstoreからforwardを受けていた場合、読んだ値は正しい。今回の条件ではこれも違反になる。やり直しが余分に起きるだけで、正しさには影響しない。区別するには、loadがどのstoreからforwardを受けたかを覚えておく必要がある。

**違反を減らす**：やり直しは高くつくので、過去に違反を起こしたloadを覚えておき、次からは該当するstoreのアドレスが確定するまで待たせる予測器（memory dependence predictor）を持つことが多い。

## 最終RTLについて

最終稿は、entryごとの違反の判定、`replay_valid`のOR、後勝ちのループによるoldestの選択で構成した。モジュール名は`load_queue_violation`。RTLは[problems/day38/solution.sv](../problems/day38/solution.sv)に置いてある。

ポートは、Issueのテンプレートの平坦なvectorから、entryごとの配列に変えている。

## まとめと今後の検証

今回のポイントは、Day37と同じ重なりの判定を、逆の向きに使うことだった。

loadの側から古いstoreを探せばforwarding、storeの側から若いloadを探せば違反の検出になる。重なりの条件は同じで、選び方が違う。forwardingは最後に書かれた値が欲しいのでyoungest、違反の検出は最初に間違えたところからやり直すのでoldestを選ぶ。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** 上の表は机上で追っただけである。
