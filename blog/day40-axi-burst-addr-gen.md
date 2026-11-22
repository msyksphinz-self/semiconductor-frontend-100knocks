# 半導体フロントエンド設計100本ノック (40) AXI Burst Address Generator

半導体フロントエンド設計100本ノック、第40問。

今回はAXIのINCR burstのアドレスを生成する回路を設計してみた。開始アドレス、beat数、beatの大きさを受け取り、beatごとのアドレスを順番に出す回路である。

アドレスを足していくだけに見えるが、request自体が正しいかどうかを最初に検査する必要がある。特に4KB境界の判定は、off-by-oneとbit幅の話がまとめて出てくる。4KBの判定はうまく書けたのに、状態を表すFFの更新を忘れ、alignmentの検査では演算子の優先順位に引っかかった。

課題の詳細は[Day40 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/40)。

## 今回の問題：INCR burstのアドレス生成

今回作るのは、**start handshakeで受け取ったburstを検査し、正しければbeatごとのアドレスとlastをready/validで出力する回路**。

[元の課題Issue #40](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/40)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- 簡略化したAXI4のINCR burst。1 requestずつ処理する。
- `start_valid` / `start_ready`のhandshakeで、32bitの開始アドレス、`len`、`size`を受け取る。
- beat数は`len+1`（1〜256）。beatの大きさは1/2/4/8 byte。
- `beat_valid` / `beat_ready`で、beatごとのアドレスと、最後のbeatを示す`beat_last`を出す。
- 開始アドレスがsizeの境界に揃っていないrequestと、4KB境界をまたぐrequestは不正とする。beatを出さず、startのサイクルだけ`error`を立てる。
- stall中は、アドレス、last、カウンタを保持する。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module axi_burst_addr_gen (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start_valid,
  output logic        start_ready,
  input  logic [31:0] start_addr,
  input  logic [7:0]  len,
  input  logic [1:0]  size,
  output logic        error,
  output logic        beat_valid,
  input  logic        beat_ready,
  output logic [31:0] beat_addr,
  output logic        beat_last
);
    // ここにRTLを実装する
endmodule
```

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **次のrequestを受け付けるタイミング**：idleのときだけ。最後のbeatが出ていくサイクルには受け付けない。
- **`error`の出し方**：start handshakeのサイクルに組合せで出す。
- **最初のbeat**：startを受理した次のサイクルから出す。
- **`size`の符号化**：0/1/2/3が1/2/4/8 byte。
- **不正なrequest**：受理して捨てる。次のサイクルもidleのまま。
- **resetの方式**：非同期reset。
- **`beat_valid=0`のときの`beat_addr` / `beat_last`**：不定扱い。

### 検証してほしいCorner Case

`len=0`と`len=255`、4KB境界、stall、last。

以下では、実際に書いてみて修正した点を順番に見ていく。

## lenとsize

`len`は「beat数 - 1」である。`len=3`なら4 beatになる。`size`はbeatの大きさの対数で、1 beatのbyte数は`1 << size`である。

| `len` | beat数 | `size` | 1 beat | 総byte数 |
|---:|---:|---:|---:|---:|
| 0 | 1 | 0 | 1 byte | 1 |
| 3 | 4 | 2 | 4 byte | 16 |
| 255 | 256 | 3 | 8 byte | 2048 |

例えば`start_addr=0x1000, len=3, size=2`なら、アドレスは`0x1000 → 0x1004 → 0x1008 → 0x100C`で、4つ目が`beat_last=1`になる。

## なぜ4KB境界をまたいではいけないのか

AXIでは、burstが4KBのアドレス境界をまたぐことは禁止されている。制限されているのは大きさではなく、境界をまたぐことである。20 byteのburstでも`0x0FF0`から始めれば`0x1000`をまたぐのでNGで、4096 byteのburstでも`0x1000`から始めればOKである。

AXIのburstでは、アドレスは先頭の1回しか送られない。interconnectはその先頭アドレスだけを見て行き先のslaveを決める。slaveに割り当てるアドレス空間の最小単位は4KBなので、4KB境界をまたがなければ、burst全体が同じslaveに収まることが保証される。

またぐ転送が必要なときは、master側でburstを2つに分ける。今回の回路は分割はせず、`error`で拒否する。

## 4KB境界の判定

`start_addr + (1 << size) * len`は、**最後のbeatの先頭アドレス**である。

```text
start=0x0FF0, 4 byte, len=3
beat:  0x0FF0  0x0FF4  0x0FF8  0x0FFC
                                 ↑ start + 4*3
```

このbeatの最後のbyteはもう少し先にあるが、アドレスがsizeの境界に揃っていれば、4KB境界がbeatの途中に来ることはない。なので、最後のbeatの先頭が同じページにあるかどうかを見れば足りる。

ページの中の位置だけを見ればよいので、下位12bitで計算する。

```systemverilog
logic [12: 0] w_base_addr;
assign w_base_addr = {1'b0, start_addr[11: 0]} + {len * (1 << size)};
```

結果のbit 12が立っていれば、次のページへ繰り上がったということで、境界をまたいでいる。

bit幅は次のように決まる。`(1 << size) * len`の最大は8 × 255 = 2040で11bit、それに下位12bitの最大4095を足すと6135で13bitになる。

| `start_addr` | 1 beat | `len` | 最後のbeat | 判定 |
|---|---:|---:|---|---|
| `0x0FF0` | 4 | 3 | `0x0FFC` | OK |
| `0x0FF0` | 4 | 4 | `0x1000` | error |
| `0x0FFF` | 1 | 0 | `0x0FFF` | OK |
| `0x0FFF` | 1 | 1 | `0x1000` | error |
| `0x0800` | 8 | 255 | `0x0FF8` | OK（ページの終わりまでちょうど使う） |
| `0x0808` | 8 | 255 | `0x1000` | error |

なお、`{len * (1 << size)}`の値が正しいのは、少し運がよいところがある。`{ }`の中は周りの幅の影響を受けず、自分自身の幅で計算される。リテラルの`1`が32bitなのでこの式は32bitで計算され、上位が落ちない。もし`4'd1 << size`のように書くと8bitで計算され、2040が切り捨てられる。

## alignmentの検査

```systemverilog
logic w_addr_aligned;
logic w_error;
assign w_addr_aligned = (start_addr & ((1 << size) - 1)) != 'h0;
assign w_error        = w_base_addr[12] | w_addr_aligned;
```

`(1 << size) - 1`は、`size`に対応する下位bitのmaskである。4 byteなら`2'b11`になる。`start_addr`とのANDが0でなければ、揃っていない。

| `size` | 1 beat | 0でなければならないbit |
|---:|---:|---|
| 0 | 1 byte | なし |
| 1 | 2 byte | `[0]` |
| 2 | 4 byte | `[1:0]` |
| 3 | 8 byte | `[2:0]` |

4KBの判定は揃っていることを前提にしている。例えば`0x0FFF`からの2 byte × 1 beatは、4KBの式では`0x0FFF`でOKに見えるが、実際は`0x1000`にかかる。これはalignmentの検査で別にerrorになるので、2つの検査をORすれば問題ない。

信号名は`w_addr_aligned`のままだが、この式が1になるのは**揃っていない**ときである。名前と意味が逆なので、`w_addr_misaligned`とした方がよかった。

## 状態の更新

```systemverilog
logic        r_run;
logic [7: 0] r_len;
logic [3: 0] r_step;

assign start_ready = !r_run;

always_ff @ (posedge clk, negedge rst_n) begin
  if (!rst_n) begin
    r_run <= 1'b0;
  end else begin
    if (start_valid & start_ready & !w_error) begin
      beat_addr <= start_addr;
      r_len     <= len;
      r_step    <= 1 << size;
      r_run     <= 1'b1;
    end else if (r_run) begin
      if (beat_ready) begin
        beat_addr <= beat_addr + r_step;
        if (r_len != 'h0) begin
          r_len <= r_len - 'h1;
        end else begin
          r_run <= 1'b0;
        end
      end
    end
  end
end

assign beat_valid = r_run;
assign beat_last  = r_len == 'h0;

assign error      = start_valid & start_ready & w_error;
```

`r_run`はburstを実行中であることを表す。これがそのまま`beat_valid`になり、その反転が`start_ready`になる。

`r_len`は残りのbeat数を表す。`len`をそのまま取り込み、beatが受理されるたびに1減らす。0になったら最後のbeatである。`len=0`なら最初のbeatが`beat_last=1`になり、`len=255`なら255から0まで数えて256 beatになる。

`beat_ready=0`の間は何も更新しないので、アドレスもカウンタも保持される。

## 波形で追ってみる

`start_addr=0x1000, len=2, size=2`で、途中に1サイクルのstallを入れる。

| cycle | `start_ready` | `beat_valid` | `beat_addr` | `beat_last` | `beat_ready` | 説明 |
|---:|---:|---:|---|---:|---:|---|
| 1 | 1 | 0 | - | - | - | startを受理 |
| 2 | 0 | 1 | `0x1000` | 0 | 1 | 1 beat目 |
| 3 | 0 | 1 | `0x1004` | 0 | 0 | stall |
| 4 | 0 | 1 | `0x1004` | 0 | 1 | 2 beat目 |
| 5 | 0 | 1 | `0x1008` | 1 | 1 | 最後のbeat |
| 6 | 1 | 0 | - | - | - | idleに戻る |

不正なrequestの場合は、受理したサイクルに`error=1`になるだけで、`r_run`は0のままなので、beatは出ない。

## 間違えたところ

**`r_run`の更新を忘れた**：最初の版では、`r_run`への代入がresetの0だけだった。`beat_valid`は常に0で、burstが始まらない。次の版ではセットだけを足し、クリアがなかったので、最初のburstが終わっても余分なbeatが出続け、次のrequestを受け付けなくなる。状態を表すFFは、入る条件と出る条件を組で書く。

**alignmentの検査がなかった**：最初は4KBの判定だけだった。

**演算子の優先順位**：alignmentの式を次のように書いていた。

```systemverilog
assign w_addr_aligned = start_addr & ((1 << size) - 1) != 'h0;
```

`!=`は`&`より先に評価される。右側は「`size`が0でない」という1bitになり、結果は`start_addr[0] & (size != 0)`になる。奇数アドレスしか検出できないので、`0x1002`からの4 byteや`0x1004`からの8 byteが正常なrequestとして通ってしまう。`&`の方を括弧で囲む必要があった。

**`error`にhandshakeが入っていなかった**：`start_valid & w_error`にしていたので、burstの実行中に上流が不正なrequestを待たせていると、受理していないのに`error`が立ち続ける。

## 規模を大きくしたときの考察

**スループット**：idleのときだけ受け付けるので、burstの間に最低1サイクルの空きができる。`len=0`のrequestが連続すると、2サイクルに1 beatになる。最後のbeatが出ていくサイクルにも受け付ければ連続で流せるが、`beat_ready`から`start_ready`への組合せパスができる。

**アドレスの加算器**：burstは4KB境界をまたがないので、beatの間で変わるのは下位12bitだけである。今回は32bitで足しているが、上位20bitは保持するだけにして、加算器を12bitにできる。4KBの制約がslaveの回路を小さくする理由の1つである。

**判定のパス**：`start_addr`、`len`、`size`から、shift、12bitの加算、ORを通って`error`へ抜ける組合せパスがある。上流の論理と合わせて厳しくなるなら、requestを一度FFに取り込んでから検査すればよい。その場合、`error`は1サイクル遅れる。

**乗算器**：`len * (1 << size)`は実質的にshiftである。`len`を11bitに広げてから`<< size`と書いた方が、意図が明確になる。

**resetなしのFF**：`beat_addr`、`r_len`、`r_step`はresetの分岐に書かれていないので、`rst_n`がenableとして付く。Day07のように別の`always_ff`に分けた方が素直である。

**他のburst type**：FIXEDは`r_step`を0にするだけで済む。WRAPは、beatの総byte数の境界でアドレスを折り返すmaskが必要になる。

**分割**：実際のDMAのようなmasterでは、errorにせず4KB境界で2つのburstに分ける。最初のburstの長さを、ページの残りbyte数から計算することになる。

## 最終RTLについて

最終稿は、alignmentと4KBの検査、実行中を表す`r_run`、残りbeat数の`r_len`、アドレスの更新で構成した。モジュール名は`axi_burst_addr_gen`。RTLは[problems/day40/solution.sv](../problems/day40/solution.sv)に置いてある。

レビューで修正したのは、`r_run`のセットとクリア、alignmentの検査の追加と優先順位、`error`のhandshakeの4点。

## まとめと今後の検証

今回のポイントは、burstの検査を正しいbit幅で書くことと、状態の出入りを組で書くことだった。

4KBの判定は、最後のbeatの先頭アドレスの下位を13bitで計算し、繰り上がりを見るだけで済む。ただしこれはアドレスが揃っている前提なので、alignmentの検査と組で使う。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** 上の表は机上で追っただけである。演算子の優先順位のような誤りは、テストベンチで`0x1002`からの4 byteを1回流せばすぐに見つかったはずである。
