# 半導体フロントエンド設計100本ノック (6) Async Input + Debounce

半導体フロントエンド設計100本ノック、第6問。

今回は非同期入力をクロックドメインへ同期化し、その後にdebounceをかける回路を作る。

スイッチのような外部入力はクロックとは無関係なタイミングで変化するので、そのままRTL内部で使うことはできない。まず2段FFで同期化し、その後、一定期間同じ値が続いた場合だけ出力を更新する。

一見すると単純な回路だが、実際に書いてみるとcounterのoff-by-oneやreset、`$clog2`の幅など、細かいところで考えることが多かった。

## 問題

以下のような回路を作る。

```systemverilog
module async_input_debounce #(
    parameter int unsigned STABLE_CYCLES = 8
) (
    input  logic clk,
    input  logic rst_n,
    input  logic async_in,
    output logic debounced_out
);
```

`async_in` はクロック `clk` に非同期な1-bit入力。

まず2段FFで同期化し、その同期化済み信号が現在の `debounced_out` と異なる状態を `STABLE_CYCLES` 回連続で観測した場合だけ、`debounced_out` を更新する。

途中で元の値に戻った場合はcounterを0に戻す。

つまり、同期化とdebounceは別の処理として考える。

## まず2FF synchronizer

非同期入力を直接debounce counterへ入れるのではなく、最初に2段FFを通す。

```systemverilog
logic [1:0] r_sync;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_sync <= 2'b00;
    end else begin
        r_sync[0] <= async_in;
        r_sync[1] <= r_sync[0];
    end
end
```

`r_sync[0]` が最初の同期化FFで、`r_sync[1]` が後段。

debounce側では `async_in` や `r_sync[0]` は使わず、`r_sync[1]` だけを見る。

2段FFはチャタリングを消すためではなく、メタステーブルが後段ロジックへ伝播する確率を下げるためのもの。debounceは時間方向のフィルタなので、この2つは役割が違う。

## debounce counter

次に、同期化済みの入力が現在の確定値と異なる期間を数える。

考え方としては単純で、

```text
r_sync[1] == r_debounced_out
    -> counter = 0

r_sync[1] != r_debounced_out
    -> counterを進める
```

とする。

途中で元の値へ戻れば、それまで数えていた値は無効なのでcounterをクリアする。

最初はcounterが `STABLE_CYCLES` に到達してから出力を更新するように書いていた。

```systemverilog
if (r_counter < STABLE_CYCLES) begin
    r_counter <= r_counter + 1'b1;
end else begin
    r_debounced_out <= r_sync[1];
end
```

しかしこれだと1cycle遅い。

例えば `STABLE_CYCLES=5` の場合、5回目の観測でcounterが5になり、実際に出力を更新するのは6回目になる。

nonblocking assignmentでは、そのcycleの条件式は更新前のcounter値を見るので、このあたりは典型的なoff-by-oneになる。

そこで、現在のサンプルを含めて `STABLE_CYCLES` 回目になったところで更新する。

```systemverilog
if (r_counter == STABLE_CYCLES - 1) begin
    r_debounced_out <= r_sync[1];
    r_counter       <= '0;
end else begin
    r_counter <= r_counter + 1'b1;
end
```

これなら `STABLE_CYCLES=1` の場合も、

```text
r_counter == 0
STABLE_CYCLES - 1 == 0
```

となるので、最初の不一致サンプルでそのまま出力を更新できる。

## RTL

最終的なdebounce部分はかなり単純になった。

```systemverilog
module async_input_debounce #(
    parameter int unsigned STABLE_CYCLES = 8
) (
    input  logic clk,
    input  logic rst_n,
    input  logic async_in,
    output logic debounced_out
);

    logic [1:0] r_sync;
    logic       r_debounced_out;

    localparam int unsigned COUNTER_W =
        (STABLE_CYCLES <= 1) ? 1 : $clog2(STABLE_CYCLES);

    logic [COUNTER_W-1:0] r_counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_sync <= 2'b00;
        end else begin
            r_sync[0] <= async_in;
            r_sync[1] <= r_sync[0];
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            r_debounced_out <= 1'b0;
            r_counter       <= '0;
        end else begin
            if (r_debounced_out == r_sync[1]) begin
                r_counter <= '0;
            end else begin
                if (r_counter == STABLE_CYCLES - 1) begin
                    r_debounced_out <= r_sync[1];
                    r_counter       <= '0;
                end else begin
                    r_counter <= r_counter + 1'b1;
                end
            end
        end
    end

    assign debounced_out = r_debounced_out;

endmodule
```

## counter幅

最初は以下のようにしていた。

```systemverilog
logic [$clog2(STABLE_CYCLES+1)-1:0] r_counter;
```

これでも動作自体はする。

ただし、この実装でcounterが保持する最大値は `STABLE_CYCLES-1` なので、例えば `STABLE_CYCLES=8` なら0〜7を表現できればよく、3bitで足りる。

そこで、

```systemverilog
localparam int unsigned COUNTER_W =
    (STABLE_CYCLES <= 1) ? 1 : $clog2(STABLE_CYCLES);
```

とした。

`STABLE_CYCLES=1` では `$clog2(1)==0` になって0-bit幅のvectorを作ってしまう可能性があるので、最低1bitを確保している。

## resetについて

今回もう1つ考えたのがreset。

問題の仕様ではactive-low synchronous resetとしていたが、最初に書いた2FF synchronizerは、

```systemverilog
always_ff @(posedge clk or negedge rst_n)
```

としてasync resetにしていた。

async resetそのものが間違いというわけではない。むしろsynchronizerにasync resetを使う設計もある。

ただしresetのdeassertがclock edge近傍に来ると、recovery/removalの観点で注意が必要になる。そのため実設計ではasynchronous assert / synchronous deassertの形にしたり、CDC/STA側でreset経路をきちんと扱う必要がある。

今回の課題では「仕様に合わせる」という意味ではsynchronous resetへ統一するのが素直。一方で、単純に「async resetだからNG」という話ではない、という整理になった。

## 今回ハマったところ

今回、最初のRTLから修正したのは主に以下。

- `$clog` と書いていた箇所を `$clog2` へ修正
- debounce counterのreset漏れ
- `STABLE_CYCLES` 回とRTL上のcounter比較のoff-by-one
- `STABLE_CYCLES=1` の境界条件
- async resetとsync resetの違い

特にoff-by-oneは、RTLを書いていると何度も出てくる。

「counterがいくつになったら処理するか」ではなく、「現在のcycleのイベントを含めて何回目なのか」で考えた方が分かりやすい。

同期化とdebounceも、コード上では小さい回路だが役割を分けて考えることで整理しやすかった。

第6問はこれで完了。
