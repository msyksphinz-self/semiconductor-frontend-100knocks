# 半導体フロントエンド設計100本ノック (19) In-order Completion Queue

半導体フロントエンド設計100本ノック、第19問。

今回は、演算結果がout-of-orderで帰ってきても、投入した順番でretireするCompletion Queueを設計する。

Queueといっても、単に入ったものを順に出すFIFOとは少し違う。Allocationは順番どおりでも、Completionは順不同。完了済みの後続entryがあっても、最古のentryが未完了ならretireできない。

実装を何度か見直して、最終的にはslot番号をtagとし、拡張したhead/tail pointerでFull/Emptyを判定する形にした。

## 問題

[Day19のIssue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/19) の仕様に従う。

デフォルトはDEPTH=4、DATA_W=32。各cycleに最大1件のAllocation、Completion、Retirementを扱う。

例えば、次のようなケース。

```text
Allocation : A -> B -> C
Completion :      B -> C -> A
Retirement :                A -> B -> C
```

B、Cが先にcompleteしていても、Aがcompleteするまではretireしない。

今回は簡略化のため、allocationで払い出すtagをqueueのslot番号そのものとする。full時のsame-cycle retireを利用したallocationや、completionした瞬間のsame-cycle retire bypassは行わない。

## Entryの管理

Queueの各slotは以下の3つを持つ。

```systemverilog
typedef struct {
    logic              valid;
    logic [DATA_W-1:0] data;
    logic              complete;
} queue_t;

queue_t r_queue [DEPTH-1:0];
```

`valid` はallocate済みかどうか、`complete` は結果が届いているかどうか。単純なFIFOではなく、slotごとに完了状態を保持する。

更新するslotも3種類のイベントで異なる。

- Allocation：tail（`r_push_idx`）のslotを確保し、`complete=0` にする。
- Completion：`complete_tag` のslotに結果を格納し、`complete=1` にする。
- Retirement：head（`r_pop_idx`）のslotの`valid`を落とす。

最初はCompletionやRetirementでもpush pointerのslotを更新してしまっていた。条件でtagを比較していても、実際の書き込み先が違えば意味がない。このあたりは修正するまで気づきにくかった。

## Full/Emptyをどう区別するか

headとtailを単純なslot番号だけで管理すると、同じ値になった時にEmptyなのかFullなのか区別できない。

そこでpointerをslot番号のbit幅より1bit広くする。

```systemverilog
logic [TAG_W:0] r_push_idx;
logic [TAG_W:0] r_pop_idx;
```

最上位bitを周回情報とし、下位`TAG_W` bitをslot番号として使う。

```systemverilog
logic w_full;
logic w_empty;

assign w_full =
    (r_push_idx[TAG_W] != r_pop_idx[TAG_W]) &&
    (r_push_idx[TAG_W-1:0] == r_pop_idx[TAG_W-1:0]);

assign w_empty = (r_push_idx == r_pop_idx);
assign alloc_ready = !w_full;
assign alloc_tag   = r_push_idx[TAG_W-1:0];
```

`alloc_ready` はFullの時だけ0。以前、Full判定をそのままReadyに接続したり、`w_alloc_ready` という別名へassignして出力を未駆動にしてしまったことがあった。

## 非2のべき乗DEPTHでも動かす

DEPTH=4なら下位2bitが自然に0〜3でwrapするが、DEPTH=3の場合は単純なincrementではslot3を指してしまう。

そこで、末尾slotの次で下位を0に戻し、周回bitだけ反転する。

```systemverilog
if (r_push_idx[TAG_W-1:0] == TAG_W'(DEPTH-1)) begin
    r_push_idx <= {~r_push_idx[TAG_W], {TAG_W{1'b0}}};
end else begin
    r_push_idx <= r_push_idx + 1'b1;
end
```

DEPTH=3の場合、pointerは次の順になる。

```text
000 -> 001 -> 010 -> 100 -> 101 -> 110 -> 000
```

pop側も同じ処理にする。これにより、非2冪DEPTHでもslot番号と周回情報を分離して管理できる。

## CompletionとRetirement

Completionはtagで指定されたslotが有効かつ未完了の場合だけ受理する。

```systemverilog
always_comb begin
    complete_ready = 1'b0;
    for (int i = 0; i < DEPTH; i++) begin
        if (complete_tag == TAG_W'(i)) begin
            complete_ready =
                r_queue[i].valid &&
                !r_queue[i].complete;
        end
    end
end
```

DEPTH=3でtag=3が来た場合など、存在しないslotへの参照を避けるため、全entryと比較する形にしている。

Retirementは、QueueがEmptyではなくheadが完了済みの時だけ有効になる。

```systemverilog
assign retire_valid =
    !w_empty &&
    r_queue[r_pop_idx[TAG_W-1:0]].valid &&
    r_queue[r_pop_idx[TAG_W-1:0]].complete;

assign retire_tag  = r_pop_idx[TAG_W-1:0];
assign retire_data = r_queue[r_pop_idx[TAG_W-1:0]].data;
```

後続entryの結果が先に到着していても、headが未完了であれば`retire_valid=0`のままになる。

## 書いてみて引っかかったところ

何度か修正した論点は、主に以下。

- active-low resetの条件を逆にしていた。最終稿ではsync resetに統一。
- Allocation、Completion、Retirementそれぞれが更新するslotを取り違えていた。
- Fullと`alloc_ready`を逆に考えていた。
- 拡張pointerの全bitをそのまま配列indexとして使ってしまった。
- DEPTH=3など非2冪におけるwrap処理を忘れていた。
- Completion Readyを無条件に1にしてしまい、不正tagや二重completionを受理する形になっていた。

実装の核心は「Allocationの順序を保持する情報」と「どのentryが完了したかを示す情報」を別に管理することだった。

## 検証と今後

今回のコードはレビューで設計方針を確認した段階であり、**シミュレーションによる動作確認は未実施**。少なくともDEPTH=3/4、Full→Retire→再Allocation、C→B→Aという逆順Completion、Retirementのstall、3イベントの同時成立、reset中断、tag再利用は確認しておきたい。

また、tagにslot番号のみを使うため、古い世代の遅延completionが再利用済みslotへ到着すると識別できない。今回の問題ではそのような入力を禁止する前提にしているが、実機のROBなどではgeneration管理を考える必要がある。

今回は、queueの順序制御とcompletion statusを分けるだけで、かなり見通しが良くなることを学んだ。

第19問はRTLレビューを区切りとして完了とし、シミュレーションは今後の追加検証項目として残す。
