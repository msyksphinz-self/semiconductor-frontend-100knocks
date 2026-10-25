# 半導体フロントエンド設計100本ノック (20) Banked Register File

半導体フロントエンド設計100本ノック、第20問。

今回はBanked Register Fileを設計してみた。レジスタファイルを複数のbankに分割し、2つのread requestをできるだけ同時に処理する回路である。

単なるregister arrayの読み書きなら簡単そうに見えるが、bank conflictをどう扱うか、readとwriteが同時に来た場合にどの値が見えるか、そしてparameterizeしたときにアドレス幅をどう切り出すか、といったところで何度も修正が必要になった。

課題の詳細は[Day20 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/20)。

## 今回の問題

デフォルトでは32本の32-bitレジスタを2つのbankに分ける。read portは2本、write portは1本。各bankにはread portとwrite portが1本ずつあると考える。

- 異なるbankへの2件のreadは同時受理する。
- 同じbankへの2件のreadは競合する。port0を優先し、port1はstallさせる。
- writeはreadと独立して受理する。
- readは組合せ出力、writeはposedgeで更新する。
- 同一addressのread/writeでは、posedge直前のread値は旧データ、posedge後は新データになる。
- resetはactive-low synchronous reset。

本格的なCPU Register Fileではwritebackの多重化やbypass、タイミング制約なども考えるが、今回はbank分割とconflict arbitrationに論点を絞る。

## Bank番号とRow番号の対応

アドレスは下位bitをbank番号、上位bitをbank内のrow番号として使う。

デフォルトの`NUM_REGS=32`、`NUM_BANKS=2`なら、addressは5bit。そのうち下位1bitがbank、上位4bitがrowになる。

```text
Address[4:0]
+---------------+-+
| Row [4:1]     |B|
+---------------+-+

addr 0 -> bank 0, row 0
addr 1 -> bank 1, row 0
addr 2 -> bank 0, row 1
addr 3 -> bank 1, row 1
...
```

RTLでは次のパラメータを使った。

```systemverilog
localparam NB_W = $clog2(NUM_BANKS);
localparam NA   = NUM_REGS / NUM_BANKS;
localparam NA_W = $clog2(NA);
```

ここで何度も混乱したのが、`NA`と`NA_W`の違い。

`NA`はbank内の**エントリ数**、`NA_W`はそれを指すための**address幅**だ。例えば各bankに16エントリあるとき、row番号は4bitあれば十分。

```systemverilog
logic [DATA_W-1:0] r_regs[NUM_BANKS][NA-1:0];

logic [NA_W-1:0] w_wr_addr;
logic [NB_W-1:0] w_rd_bank0, w_rd_bank1;
logic [NA_W-1:0] w_rd_addr0, w_rd_addr1;

assign w_wr_addr  = wr_addr[NB_W +: NA_W];
assign w_rd_bank0 = rd_addr0[NB_W-1:0];
assign w_rd_bank1 = rd_addr1[NB_W-1:0];
assign w_rd_addr0 = rd_addr0[NB_W +: NA_W];
assign w_rd_addr1 = rd_addr1[NB_W +: NA_W];
```

初版ではアドレス信号まで`[NA-1:0]`としてしまい、16bitのアドレスを宣言していた。配列の個数と、そのindexを表すbit幅は分けて考えないといけない。

## 同一BankでReadが衝突したら

2つのread requestが同じbankを要求した場合、そのbankのread portは1本しかない。今回はport0を優先する。

```systemverilog
assign rd_ready[0] = rd_valid[0];

assign rd_ready[1] =
    (~rd_valid[0] & rd_valid[1]) |
    (rd_valid[0] & rd_valid[1] &
     (w_rd_bank0 != w_rd_bank1));
```

例えば次のようになる。

| rd_valid | addr0 | addr1 | rd_ready | 意味 |
|---|---:|---:|---|---|
| 2'b01 | 2 | - | 2'b01 | port0だけ受理 |
| 2'b10 | - | 5 | 2'b10 | port1だけ受理 |
| 2'b11 | 2 | 3 | 2'b11 | bankが違うので両方受理 |
| 2'b11 | 2 | 4 | 2'b01 | bank0で衝突、port0優先 |

stallされたport1のrequestは外側で保持し、次のcycle以降に再試行する。Queueを内部に持たせていないので、この回路単体ではpending readを記憶しない。

各bankのread addressもport0優先で選ぶ。

```systemverilog
assign w_rd_local_addr =
    rd_valid[0] && (w_rd_bank0 == b_idx) ? w_rd_addr0 :
    rd_valid[1] && (w_rd_bank1 == b_idx) ? w_rd_addr1 :
    '0;
```

結果を各bankから組合せreadし、要求したbank番号で出力を選択する。

```systemverilog
assign w_rd_data[b_idx] = r_regs[b_idx][w_rd_local_addr];

assign rd_data0 = w_rd_data[w_rd_bank0];
assign rd_data1 = w_rd_data[w_rd_bank1];
```

readが受理されていないportの`rd_data`はdon't careとする仕様なので、競合したport1の値は使わない。

## WriteとReset

write先bankはアドレスの下位bitで決まる。

```systemverilog
assign w_wr_en =
    wr_en &&
    (wr_addr[NB_W-1:0] == NB_W'(b_idx));
```

各bankの記憶配列はposedgeで更新する。resetも今回の仕様に合わせて同期方式にした。

```systemverilog
always_ff @(posedge clk) begin
    if (!rst_n) begin
        for (int i = 0; i < NA; i++) begin
            r_regs[b_idx][i] <= '0;
        end
    end else if (w_wr_en) begin
        r_regs[b_idx][w_wr_addr] <= wr_data;
    end
end
```

初版ではresetのfor-loop内で`i`を使わず、同じrowに何度も書き込んでいた。これだと全entryを初期化できない。さらに最初は非同期resetにしていたので、Issueで指定した同期resetへ修正した。

## Read-during-writeのタイミング

read dataは組合せ出力、writeはposedge更新にしたので、同じaddressをreadしながらwriteする場合は次の動きになる。

```text
posedgeより前 : read_data = old value
posedge発生   : 対象のregisterを更新
posedgeより後 : read_data = new value
```

ただしこれはこのFFベースのRTLモデルでの話。実際のSRAM macroはread-during-writeの挙動が異なる場合があり、マクロ仕様を確認する必要がある。

## 最終RTLについて

今回の最終投稿では、`NUM_REGS=32`、`NUM_BANKS=2`に対するbank/row decode、固定優先read arbitration、同期write、同期resetを実装した。モジュール名は`sv020_banked_register`。

何度かのレビューで、配列サイズ、アドレスのbit幅、resetの初期化先、組合せreadの`assign`漏れを修正した。最終稿の主要部分は上の抜粋に示したとおり。

なお、最後に残った境界条件がある。`NUM_REGS == NUM_BANKS`なら各bankに1 entryしかなく、`NA_W = $clog2(1) = 0`になる。現在の`[NB_W +: NA_W]`というpart-selectはそのままでは使えない。1-entry bankを許すなら特別処理が必要。今回は**このパラメータ境界の改修は未実施**で、デフォルト構成の設計レビューまでを終えた。

## まとめと今後の検証

今回のポイントは、物理的なbank構成を決めると、read request同士の競合が制御問題になるということだった。

2R1Wを完全なmultiport memoryで作る代わりにbankへ分散できるが、同一bankへのrequestが重なればstallが発生する。今回はport0固定優先にしたので、port1にはstarvationの可能性もある。

また、parameterizeでは「bankの数」「各bankのentry数」「そのaddress幅」を混同しないことが大事だった。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** 別bank同時read、同一bank衝突、port1単独read、同一addressのread/write、NUM_BANKS=4、reset、そして1-entry bankの境界条件を今後確認する。現状はDay20のデフォルト構成についてRTL設計レビューを終えた段階であり、Issueの完全なPass/Closeを意味しない。
