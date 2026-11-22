# 半導体フロントエンド設計100本ノック (20) Banked Register File

半導体フロントエンド設計100本ノック、第20問。

今回はBanked Register Fileを設計してみた。レジスタファイルを複数のbankに分割し、2つのread requestをできるだけ同時に処理する回路である。

単なるregister arrayの読み書きなら簡単そうに見えるが、bank conflictをどう扱うか、readとwriteが同時に来た場合にどの値が見えるか、そしてparameterizeしたときにアドレス幅をどう切り出すか、といったところで何度も修正が必要になった。

課題の詳細は[Day20 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/20)。

## 今回の問題：2-read / 1-writeのBanked Register File

今回作るのは、**レジスタを複数bankへ分散して、read requestを競合しない範囲で並列処理する回路**。2本のread requestが同時に届いても、同じbankを指定した場合はread portが足りないため、どちらかをstallさせる。

[元の課題Issue #20](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/20)の仕様を、記事だけで追えるようにまとめる。

### 容量・ポート・アドレス

- デフォルトは`NUM_REGS=32`、`DATA_W=32`、`NUM_BANKS=2`（2 banks × 16 rows）。addressは0〜31、`ADDR_W=$clog2(NUM_REGS)`。
- `NUM_REGS`と`NUM_BANKS`はいずれも2のべき乗、`NUM_REGS>=NUM_BANKS>=2`。4-bank構成も検討対象。
- **bank = address % NUM_BANKS**、**row = address / NUM_BANKS**。デフォルトでは5bit addressの下位1bitがbank、上位4bitがrow。
- 全体のread requestは**2ポート**、write requestは**1ポート**。各bankは1 read + 1 writeポートを持つ。
- `rd_valid[1:0]`と`rd_ready[1:0]`の各bitがport1/port0に対応し、readの受理は`rd_valid[p] && rd_ready[p]`。addressは`rd_addr0`/`rd_addr1`、dataは`rd_data0`/`rd_data1`。
- writeは`wr_en`/`wr_addr`/`wr_data`。writeのstallはなくposedgeで更新。
- `rst_n`はactive-low**同期reset**。posedgeで全レジスタを0にする。Register 0も普通に書き込み可能。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module sv020_banked_register #(
    parameter int unsigned NUM_REGS  = 32,
    parameter int unsigned DATA_W    = 32,
    parameter int unsigned NUM_BANKS = 2,
    parameter int unsigned ADDR_W    = $clog2(NUM_REGS)
) (
    input  logic              clk, rst_n,
    input  logic [1:0]        rd_valid,
    output logic [1:0]        rd_ready,
    input  logic [ADDR_W-1:0] rd_addr0, rd_addr1,
    output logic [DATA_W-1:0] rd_data0, rd_data1,
    input  logic              wr_en,
    input  logic [ADDR_W-1:0] wr_addr,
    input  logic [DATA_W-1:0] wr_data
);
    // ここにRTLを実装する
endmodule
```

### 受理ルールとread/writeのタイミング

- **別bankへの同時read**は両方受理する。
- **同一bankへの同時read**はport0固定優先。port1は`rd_ready[1]=0`でstall。**同一addressへの2readも競合**として扱う。
- port0が無効なら、port1は単独で受理できる。stallされたportの送信側はvalidとaddrを保持して再試行する（内部request FIFOは持たない）。
- 受理されたread結果は**同じcycleに組合せ出力**される。`rd_ready=0`のportのdataはdon't care。read側は非パイプライン。
- writeとreadは同じbankでも並列に動作し、writeのためにreadのreadyは下げない。
- **同一addressのread-during-write**は、posedgeの前に旧値、posedge後に更新値を観測する。bypass/forwardingはしない。

| `rd_valid` | addr0 | addr1 | 期待`rd_ready` | 説明 |
|---|---:|---:|---|---|
| `2'b01` | 2 | - | `2'b01` | port0単独 |
| `2'b10` | - | 5 | `2'b10` | port1単独 |
| `2'b11` | 2 | 3 | `2'b11` | bank0とbank1、両方accept |
| `2'b11` | 2 | 4 | `2'b01` | bank0同士、port0優先 |
| `2'b11` | 2 | 2 | `2'b01` | 同一addressでも競合 |

### 検証してほしいCorner Case

reset後に全addressが0であること、異なるbank/rowへの書き込みと読み出し、別bank同時read、同一bank競合とport1 retry、port1単独read、read/write同一bank・異address、同一addressのread/writeのposedge前後、reset途中投入、`NUM_BANKS=4`を確認する。

なお、Issueの制約は`NUM_REGS=NUM_BANKS`（1 bankあたり1 entry）も許すが、今回の解答ではこの構成を対象外とし、**1 bankあたり2 entry以上（`NUM_REGS > NUM_BANKS`）**を前提にした。理由は最後に書く。

以下では、実際に書いてみて修正した点を順番に見ていく。

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
    rd_valid[0] & (w_rd_bank0 == b_idx) ? w_rd_addr0 :
    rd_valid[1] & (w_rd_bank1 == b_idx) ? w_rd_addr1 :
    'h0;
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
    wr_en &
    (wr_addr[$clog2(NUM_BANKS)-1:0] == b_idx[$clog2(NUM_BANKS)-1:0]);
```

各bankの記憶配列はposedgeで更新する。resetも今回の仕様に合わせて同期方式にした。

```systemverilog
always_ff @(posedge clk) begin
    if (!rst_n) begin
        for (int i = 0; i < NA; i++) begin
            r_regs[b_idx][i] <= 'h0;
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

最終稿は、bank/row decode、固定優先のread arbitration、同期write、同期resetで構成した。モジュール名は`sv020_banked_register`。RTLは[problems/day20/solution.sv](../problems/day20/solution.sv)に置いてある。

何度かのレビューで、配列サイズ、アドレスのbit幅、resetの初期化先、組合せreadの`assign`漏れを修正した。デフォルト構成に加えて、`NUM_BANKS=4`でもbankとrowの切り出しが正しいことを机上で確認した。

対象外にしたのは、`NUM_REGS == NUM_BANKS`の構成である。各bankに1 entryしかないと`NA_W = $clog2(1) = 0`になり、`logic [NA_W-1:0]`は`[-1:0]`に、`[NB_W +: NA_W]`は幅0のpart-selectになってしまう。1 entryのbankにはrowを選ぶ必要がなく、レジスタファイルをbankに分ける構成として実用上の意味が薄いので、特別処理は入れなかった。**Issueの制約より狭い範囲での合格**である。

## まとめと今後の検証

今回のポイントは、物理的なbank構成を決めると、read request同士の競合が制御問題になるということだった。

2R1Wを完全なmultiport memoryで作る代わりにbankへ分散できるが、同一bankへのrequestが重なればstallが発生する。今回はport0固定優先にしたので、port1にはstarvationの可能性もある。

また、parameterizeでは「bankの数」「各bankのentry数」「そのaddress幅」を混同しないことが大事だった。

**Verilatorのlint（`--lint-only -Wall`）は、`NUM_REGS/NUM_BANKS`を32/2、32/4、8/2、8/4にしてエラーも警告もなく通した（ファイル名に関する警告を除く）。対象外にした`NUM_REGS == NUM_BANKS`（4/4、2/2）は、幅0のpart-selectでエラーになる。シミュレーションとテストベンチ実行は未実施である。** bank conflict、read-during-write、reset、`NUM_BANKS=4`の動作は机上で確認しただけである。Issueの必須テスト10項目は実行していない。
