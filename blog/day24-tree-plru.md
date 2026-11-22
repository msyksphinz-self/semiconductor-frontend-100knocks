# 半導体フロントエンド設計100本ノック (24) Tree-PLRU

半導体フロントエンド設計100本ノック、第24問。

今回は4-wayのTree-PLRUを設計してみた。キャッシュのあるsetが満杯のとき、どのwayを追い出すかを決める回路である。

RTLは20行ほどで書けてしまうのだが、stateのbitに「アクセスした側」を持たせるのか「追い出す側」を持たせるのかを途中で変えたせいで、コメントに書いたcycle表とRTLが食い違ったまま残っていた。レビューで指摘されるまで気づかなかった。

課題の詳細は[Day24 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/24)。

## 今回の問題：4-wayのTree-PLRU Replacement Controller

今回作るのは、**4-way set-associativeキャッシュの1 set分について、次に置き換えるway（victim）を出力する回路**。

[元の課題Issue #24](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/24)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- 4-wayのTree-PLRU。stateは**3bitのtree**で持つ。
- wayがアクセスされたら（hitまたはfill）、treeのbitを更新する。
- **invalidなwayがあれば、それを最優先でvictimにする**。invalidなwayが複数あれば、番号の最も小さいwayを選ぶ。
- 全wayがvalidのときは、PLRUのtreeからvictimを決める。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。Issueのテンプレートとはmodule名とポート名を変えているが、ポートの本数と意味は同じである。

```systemverilog
module tree_plru4_controller
  (
    input  logic       i_clk,
    input  logic       i_rst_n,

    // 現在各wayがvalidか
    input  logic [3:0] i_way_valid,

    // hitまたはfillによってwayが使用された
    input  logic       i_touch_valid,
    input  logic [1:0] i_touch_way,

    // replacement candidate
    output logic [1:0] o_victim_way
  );
    // ここにRTLを実装する
endmodule
```

### Tree-PLRUとは

4つのwayを2分木の葉に並べ、木の各nodeに1bitずつ持たせる。nodeは3つなので、stateは3bitになる。

```text
            [r_acc0]
           /        \
     [r_acc1[0]]  [r_acc1[1]]
       /    \       /    \
     way0  way1   way2  way3
```

各bitは、そのnodeの下の左右どちらが「最近使われていない側」かを表す。victimを決めるときは、rootから「最近使われていない側」へ降りていく。

### Issueで決まっていなかったこと

- **resetの方式**：非同期reset（`negedge i_rst_n`）にした。reset後のstateは全bit 0。

### 検証してほしいCorner Case

全wayがvalidの場合、複数のwayがinvalidの場合、reset。

以下では、実際に書いてみて考えた点を順番に見ていく。

## stateに何を持たせるか

stateは次の3bit。

```systemverilog
logic        r_acc0; // 最初のbranchで次に追い出す側 (0: way0/1, 1: way2/3)
logic [1: 0] r_acc1; // 2番目のbranchで次に追い出す側 ([0]: way0/1, [1]: way2/3)
```

各bitの意味には2通りの決め方がある。

- **アクセスした側を記録する**：victimを決めるときに、bitを反転してたどる。
- **追い出す側を保持する**：更新するときに、アクセスした側の反対を書き込む。victimを決めるときは、bitをそのままたどる。

どちらでも同じTree-PLRUになる。違うのはインバータが更新側に付くかvictim選択側に付くかと、reset値0の意味である。reset直後に全wayがvalidだとすると、前者ではway3が、後者ではway0がvictimになる。

今回のRTLは後者、つまり**追い出す側を保持する**方式にした。

## access時の更新

wayがアクセスされたら、rootと、アクセスした側のnodeを更新する。

```systemverilog
always_ff @ (posedge i_clk, negedge i_rst_n) begin
  if (!i_rst_n) begin
    r_acc0 <= 1'b0;
    r_acc1 <= 2'b00;
  end else begin
    if (i_touch_valid) begin
      r_acc0                 <= ~i_touch_way[1];
      r_acc1[i_touch_way[1]] <= ~i_touch_way[0];
    end
  end
end
```

`i_touch_way[1]`は、way0/1の側（0）かway2/3の側（1）かを表す。rootの`r_acc0`にはその反対を書き込む。

2段目は、アクセスした側のnodeだけを更新する。`r_acc1[i_touch_way[1]]`でnodeを選び、`i_touch_way[0]`の反対を書き込む。**反対側のnodeには触らない**。ここがTree-PLRUの要点で、1回のアクセスで更新するのは3bitのうち2bitだけである。

## victimの選択

全wayがvalidのときは、rootからstateの指す方向へ降りていけばよい。

```systemverilog
assign o_victim_way = &i_way_valid ? {r_acc0, r_acc1[r_acc0]} :
                      invalid_way_idx;
```

`r_acc0`が上位bit、つまりどちら側のnodeへ降りるかを決める。そのnodeの`r_acc1[r_acc0]`が下位bitになる。追い出す側を保持しているので、反転は要らない。

## cycle表で確認する

全wayがvalidとして、way0→1→2→3の順にアクセスした場合。

| 操作 | `r_acc0` | `r_acc1` | victim |
|---|---:|---:|---|
| reset後 | 0 | 00 | way0 |
| touch way0 | 1 | 01 | way2 |
| touch way1 | 1 | 00 | way2 |
| touch way2 | 0 | 10 | way0 |
| touch way3 | 0 | 00 | way0 |

4つのwayを順番に使ったあと、一番古いway0がvictimになっている。

way0→2→1→3の順にアクセスした場合。

| 操作 | `r_acc0` | `r_acc1` | victim |
|---|---:|---:|---|
| reset後 | 0 | 00 | way0 |
| touch way0 | 1 | 01 | way2 |
| touch way2 | 0 | 11 | way1 |
| touch way1 | 1 | 10 | way3 |
| touch way3 | 0 | 00 | way0 |

こちらも最後は一番古いway0がvictimになる。

## コメントとRTLが食い違っていた

RTLのファイルには、上のようなcycle表をコメントとして書いてあった。ところがその表は、**アクセスした側を記録する**方式の値で書かれていた。

最初は記録する方式で考えてコメントを書き、RTLを書く段階で追い出す側を保持する方式に変えた。そのときコメントの表を直さなかったので、stateの値がRTLとすべて逆になっていた。victimの値も、1つ目の表はどちらの方式で読んでも成り立たない下書きのままだった。

RTLの論理は正しかったので動作には影響しないが、後から読んだ人はコメントを信じてRTLを疑うことになる。stateの意味を変えたら、コメントも一緒に直す。

## invalid wayを優先する

全wayがvalidでない場合は、PLRUのstateを無視して、invalidなwayをvictimにする。

```systemverilog
logic [1: 0] invalid_way_idx;
always_comb begin
  invalid_way_idx = 3;
  for (int i = 3; i >= 0; i--) begin
    if (~i_way_valid[i]) begin
      invalid_way_idx = i;
    end
  end
end
```

空いているwayがあるのに、有効なデータの入ったwayを追い出す理由はない。追い出したデータに次にアクセスが来れば、避けられたはずのmissになる。だからinvalidなwayの選択をPLRUより優先する。

forループは3から0へ向かって回している。後から実行された代入が勝つので、最後に評価されるway0が最も優先され、番号の小さいinvalid wayが選ばれる。

## true LRUとの違い

Tree-PLRUは、最近アクセスした側の反対へ降りていくだけなので、本当に一番古いwayを選ぶとは限らない。

例えば、way0→1→2→3の順にアクセスしたあと、もう一度way0にアクセスしたとする。

- true LRUなら、一番古いのは**way1**である。
- Tree-PLRUでは、rootはway0の反対のway2/3側を指す。way2/3側のnodeは、最後にway3にアクセスしたときのままway2を指している。victimは**way2**になる。

Tree-PLRUが保証するのは「直前にアクセスしたwayは選ばない」ことくらいで、順序の全体は覚えていない。

その代わりstateが小さい。4-wayのtrue LRUは、4つのwayの順序が4! = 24通りあるので最低でも5bitが必要になる。Tree-PLRUは3bitで済む。

## 規模を大きくしたときの考察

**state bit数**：N-wayのTree-PLRUは、nodeの数だけbitを持つので**N-1 bit**。8-wayなら1 + 2 + 4 = 7bitになる。true LRUは順序を覚える必要があるので、way数が増えるとstateが急に大きくなる。Tree-PLRUが使われる理由はここにある。

**更新するbit数**：1回のアクセスで更新するのは、rootから葉までの経路上のnodeだけ。4-wayなら2bit、8-wayなら3bitで、**log2(N) bit**になる。

**クリティカルパス**：victimの選択は、rootから順にnodeを選んでいくmuxの連鎖で、段数はlog2(N)。これにinvalid wayのpriority encoderと、最後の選択のmuxが加わる。way数が増えると、priority encoderの方が先に効いてくる可能性がある。

**キャッシュ全体**：今回のモジュールは1 set分である。実際のキャッシュではsetの数だけstateが必要なので、stateはtagと同じようにset indexで引く配列に置くことになる。1 setあたりのbit数が小さいことは、そこで効いてくる。

## 最終RTLについて

最終稿は、3bitのstate、access時の更新、invalid wayのpriority選択、victimの選択で構成した。モジュール名は`tree_plru4_controller`。RTLは[problems/day24/solution.sv](../problems/day24/solution.sv)に置いてある。

レビューで修正したのはコメントのcycle表とstateの説明で、RTLの論理は初版から変わっていない。

## まとめと今後の検証

今回のポイントは、stateのbitの意味をはっきり決めることだった。

アクセスした側を記録しても、追い出す側を保持しても、同じTree-PLRUになる。ただし、どちらに決めたのかがコメントとRTLで食い違うと、cycle表はすべて逆になる。

Tree-PLRUそのものについては、アクセスした側のnodeだけを更新すること、invalid wayをPLRUより優先すること、true LRUとは違うwayを選ぶ場合があることを確認した。

**Verilatorのlint（`--lint-only -Wall`）は、エラーなしで通した。シミュレーションとテストベンチ実行は未実施である。** 残った警告はforループの`int`を2bitへ代入していることだけで、動作には影響しない。 cycle表は机上で追っただけである。
