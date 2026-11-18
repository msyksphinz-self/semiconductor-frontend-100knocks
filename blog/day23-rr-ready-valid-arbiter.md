# 半導体フロントエンド設計100本ノック (23) 2-master→1-slave RR Ready/Valid Arbiter

半導体フロントエンド設計100本ノック、第23問。

今回は2つのmasterからのready/valid transactionを、round-robinで1つのslaveへ仲裁する回路を設計してみた。

仲裁そのものは2択なので難しくないのだが、「slaveが受け取ってくれない間、選んだtransactionをどう保持するか」を決める必要がある。今回は選んだtransactionをモジュールの中のFFに取り込んでしまう方式にした。構成はそれでよかったのだが、「次の優先順位」の信号を「誰にreadyを返すか」にも流用したところ、最初の版ではreadyが逆のmasterに返っていた。最終的には、選んだmasterを表す信号を別に作ることにした。

課題の詳細は[Day23 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/23)。

## 今回の問題：2-masterのround-robin arbiter

今回作るのは、**2つのmasterのready/valid transactionを、round-robinで1つのslaveへ渡す回路**。

[元の課題Issue #23](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/23)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- masterは2つ。それぞれ32bitのデータをready/validで送ってくる。
- 2つのmasterをround-robinで仲裁し、1つのslaveへready/validで渡す。
- **stall中はgrantとdataを保持する**。slaveが受け取るまで、選んだtransactionを変えない。
- **優先順位はhandshakeが成立したときだけ更新する**。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module rr_ready_valid_arbiter
  (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [1: 0]  m_valid,
    output logic [1: 0]  m_ready,
    input  logic [63: 0] m_data,
    output logic         s_valid,
    input  logic         s_ready,
    output logic [31: 0] s_data
  );
    // ここにRTLを実装する
endmodule
```

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **stall中の保持の方法**：選んだtransactionをモジュールの中のFFに取り込む。masterが受理された次のサイクルにslaveへ出る。
- **優先順位を更新するタイミング**：master側のhandshake、つまりFFに取り込んだとき。
- **更新のルール**：取り込んだmasterの反対側を次の優先にする。片方だけが要求していた場合も同じ。
- **reset後の優先**：master0。
- **`m_data`の分割**：master0が下位側（`m_data[31:0]`）、master1が上位側（`m_data[63:32]`）。
- **resetの方式**：同期reset。
- **`s_valid=0`のときの`s_data`**：不定扱い。

### 検証してほしいCorner Case

両方のmasterが要求する場合、長期のstall、fairness。

以下では、実際に書いてみて修正した点を順番に見ていく。

## 優先順位を保持するだけでは足りない

「優先順位はhandshakeのときだけ更新する」と決めても、それだけではstall中の選択は固定されない。

例えば優先がmaster0で、master1だけが要求しているとする。master0は要求していないので、master1が選ばれる。slaveがreadyを返さず待たされている間に、master0が要求を出したらどうなるか。優先はmaster0のままなので、選択がmaster0に切り替わる。`s_valid`は1のまま、`s_data`だけが途中で変わってしまう。

これを防ぐ方法は2つある。

- stall中であることと、選んでいたmasterをFFに覚えておき、handshakeまで選択を固定する。
- 選んだtransactionのデータごとFFに取り込んでしまう。

今回は後者にした。取り込んでしまえば、その後にmaster側で何が起きても`s_data`は変わらない。その代わり、latencyが1サイクル増える。

## 構成

状態は、優先順位の1bit、滞留を表す1bit、データの32bit。

```systemverilog
logic r_arb_priority;
logic w_arb_priority_next;

logic r_in_valid;

logic w_grant;

logic [31: 0] r_in_data;
```

`w_grant`は状態ではなく、そのサイクルに選んだmasterの番号を表す組合せ信号である。

`r_in_valid`は、モジュールの中にtransactionが滞留していることを表す。これがそのまま`s_valid`になる。

```systemverilog
assign s_valid = r_in_valid;
assign s_data  = r_in_data;
```

## 新しいリクエストを取得できる条件

滞留している間は、新しいリクエストを受け付けられない。受け付けられるのは、滞留していないときと、滞留しているtransactionがそのサイクルに出ていくときである。

```systemverilog
s_ready | !r_in_valid
```

「出ていくサイクルにも受け付ける」としたので、slaveが毎サイクル受け取ってくれるなら、毎サイクル1つずつ流せる。「滞留していないときだけ受け付ける」にすると、2サイクルに1つしか流せなくなる。

## 仲裁と優先順位の更新

```systemverilog
always_comb begin
  w_arb_priority_next = r_arb_priority;
  w_grant = r_arb_priority;
  if (s_ready | !r_in_valid) begin
    if (r_arb_priority == 'h0) begin
      if (m_valid[0]) begin
        w_grant = 1'b0;
        w_arb_priority_next = 1'b1;
      end else if (m_valid[1]) begin
        w_grant = 1'b1;
        w_arb_priority_next = 1'b0;
      end
    end else begin
      if (m_valid[1]) begin
        w_grant = 1'b1;
        w_arb_priority_next = 1'b0;
      end else if (m_valid[0]) begin
        w_grant = 1'b0;
        w_arb_priority_next = 1'b1;
      end
    end
  end
end

always_ff @ (posedge clk) begin
  if (!rst_n) begin
    r_arb_priority <= 1'b0;
  end else begin
    r_arb_priority <= w_arb_priority_next;
  end
end
```

`r_arb_priority`は、いま優先するmasterの番号。取得できる状態で、優先するmasterが要求していればそれを選び、していなければもう一方を選ぶ。選んだmasterの番号を`w_grant`に、その反対側を次の優先として`w_arb_priority_next`に入れる。

取得できないとき、どちらのmasterも要求していないときは、先頭の既定値のとおり優先順位を変えない。優先順位が変わるのはmasterを受理したときだけなので、「handshakeのときだけ更新する」を満たす。

## readyを返す

```systemverilog
assign m_ready[0] = (s_ready | !r_in_valid) & (w_grant == 1'b0);
assign m_ready[1] = (s_ready | !r_in_valid) & (w_grant == 1'b1);
```

取得できる状態のときに、`w_grant`の指すmasterにだけreadyを返す。stall中はどちらにも返さない。

`w_grant`は1bitの番号なので、「誰も選んでいない」を表せない。どちらのmasterも要求していないときは、既定値のとおり優先している側の番号になり、そちらのreadyが1になる。validが立っていないのでhandshakeは成立せず、害はない。

## FFへの取り込み

```systemverilog
always_ff @ (posedge clk) begin
  if (!rst_n) begin
    r_in_valid <= 1'b0;
  end else begin
    if (r_in_valid) begin
      if (s_valid & s_ready) begin
        r_in_valid <= |(m_valid & m_ready);
        r_in_data <= (m_valid[0] & m_ready[0]) ? m_data[31: 0] : m_data[63:32];
      end
    end else begin
      r_in_valid <= |(m_valid & m_ready);
      r_in_data <= (m_valid[0] & m_ready[0]) ? m_data[31: 0] : m_data[63:32];
    end
  end
end
```

滞留しているtransactionが出ていくとき、または滞留していないときに、master側でhandshakeが成立していれば取り込む。成立していなければ`r_in_valid`は0になる。

滞留していてslaveが受け取らないときは、どの分岐にも入らないので、`r_in_valid`も`r_in_data`も変わらない。これがstall中の保持である。

## 波形で追ってみる

master0のデータをA0, A1, ...、master1のデータをB0, B1, ...とする。

| cycle | 優先 | `m_valid` | `m_ready` | 滞留 | `s_valid` | `s_ready` | 説明 |
|---:|---:|---|---|---|---:|---:|---|
| 1 | 0 | 11 | 01 | 空 | 0 | - | A0を取り込む |
| 2 | 1 | 11 | 10 | A0 | 1 | 1 | A0が出る。B0を取り込む |
| 3 | 0 | 11 | 00 | B0 | 1 | 0 | stall。何も取り込まない |
| 4 | 0 | 11 | 00 | B0 | 1 | 0 | stall。B0を保持 |
| 5 | 0 | 11 | 01 | B0 | 1 | 1 | B0が出る。A1を取り込む |
| 6 | 1 | 01 | 01 | A1 | 1 | 1 | A1が出る。master1が要求していないのでA2を取り込む |
| 7 | 1 | 00 | 10 | A2 | 1 | 1 | A2が出る。取り込むものがない |
| 8 | 1 | 00 | 10 | 空 | 0 | - | |

`m_valid`と`m_ready`は`[1:0]`の順に書いている。

cycle 1〜2では、両方が要求しているのでmaster0、master1の順に受理される。cycle 3〜4はstallで、`m_ready`は00になり、優先順位も0のまま変わらない。cycle 5でstallが解けると、優先順位のとおりmaster0が受理される。

cycle 6では優先はmaster1だが、master1が要求していないのでmaster0が受理される。次の優先はmaster1のままである。cycle 7〜8では、優先しているmaster1に`m_ready`が返っているが、validが立っていないので何も起きない。

## readyが逆のmasterに返っていた

初版には`w_grant`がなく、readyを次のように書いていた。

```systemverilog
assign m_ready[0] = w_arb_priority_next == 1'b0;
assign m_ready[1] = w_arb_priority_next == 1'b1;
```

`w_arb_priority_next`は「次に優先するmaster」である。master0を選んだら1になる。それを「いまreadyを返す相手」としてそのまま使ったので、master0を選ぶとmaster1にreadyが返っていた。

reset後にmaster0だけが要求している場合、次のようになる。

| cycle | 優先 | `m_valid` | `w_arb_priority_next` | `m_ready` | 取り込み |
|---:|---:|---|---:|---|---|
| 1 | 0 | 01 | 1 | 10 | なし |
| 2 | 1 | 01 | 1 | 10 | なし |
| 3 | 1 | 01 | 1 | 10 | なし |

master0のvalidとmaster1のreadyが立っているだけで、どちらのhandshakeも成立しない。master0は永久に受理されない。

もう1つ、この式ではreadyが常にどちらか一方に立つ。stall中にも立つので、master側はhandshakeが成立したと判断して次のデータへ進む。しかしFFはstall中には取り込まないので、そのデータは消える。取得できる条件`(s_ready | !r_in_valid)`をreadyにも入れる必要があった。

この2つは、式の極性を入れ替えて条件を足せば直る。実際それで正しく動く版もできた。ただ、「次に優先するmaster」から「いま選んだmaster」を逆算する書き方は、読むたびに頭の中で反転させる必要がある。そこで、選んだmasterを表す`w_grant`を別に作り、同じ分岐の中で両方を代入する形に書き直した。

## 文法でつまずいたところ

初版の`always_comb`には、先頭の既定値がなかった。`w_arb_priority_next`で一度直したのに、`w_grant`を足したときにも同じことをやった。

stall中と、どちらのmasterも要求していないときは、どの分岐にも入らないので何も代入されない。`always_comb`の中に代入されない経路があると、値を保持する必要があるのでlatchになる。`always_comb`はlatchを作らないことを意図した書き方なので、ツールによっては警告やエラーになる。

「何もしないとき」の値を、先頭で代入しておけばよい。`always_comb`に信号を足したら、既定値も一緒に足す。

## 規模を大きくしたときの考察

**fairness**：両方が要求し続けている限り、受理は必ず交互になる。片方が待たされるのは最大で相手の1 transaction分である。優先順位はhandshakeのときしか変わらないので、stallがどれだけ長くても順番は飛ばない。

**クリティカルパス**：`s_ready`から`m_ready`への組合せパスがある。slave側のreadyが遅いと、それがそのままmaster側へ伝わる。「滞留していないときだけ受け付ける」にすればこのパスは切れるが、スループットが半分になる。両立させるには、FFをもう1段持ってskid bufferにする。

`m_valid`から`m_ready`への組合せパスもある。優先していない側のreadyは、優先している側のvalidに依存するからである。master側がreadyを見てからvalidを決めるような作りだと、組合せループになる。ready/validでは、validをreadyに依存させないのが普通である。

**grantの持ち方**：今回の`w_grant`は1bitの番号にした。「誰も選んでいない」を表せないので、readyを作るところで取得できる条件をもう一度ANDしている。masterごとに1bitを持つone-hotにして既定値を0にすれば、「誰も選んでいない」が全bit 0で表せる。readyは`w_grant`をそのまま返すだけになり、masterが3つ以上になっても同じ形で書ける。

**N-masterへの拡張**：round-robinの優先順位は、最後に受理したmasterの番号で持つ。仲裁は、その次の番号から順に探すpriority encoderになる。maskを掛けたrequestと掛けないrequestの2つにpriority encoderを通し、前者にヒットがあればそれを、なければ後者を使う構成がよく使われる。

**データのFF**：今回は`r_in_data`を、reset付きの`always_ff`の中に書いた。resetの分岐で代入していないので、`rst_n`がenableとして付く。Day07のように別の`always_ff`に分けた方が素直である。

## 最終RTLについて

最終稿は、1bitの優先順位、選んだmasterを表す`w_grant`、滞留を表す`r_in_valid`、取り込んだデータの`r_in_data`で構成した。モジュール名は`rr_ready_valid_arbiter`。RTLは[problems/day23/solution.sv](../problems/day23/solution.sv)に置いてある。

レビューで修正したのは、readyを返す相手、stall中のready、`always_comb`の既定値の3点。そのうえで、`w_grant`を使う形に書き直した。

## まとめと今後の検証

今回のポイントは、stall中に選択を保持する方法だった。

優先順位をhandshakeのときだけ更新しても、後から来た要求で選択が切り替わることがある。選んだtransactionをFFに取り込んでしまえば、その心配はなくなる。

もう1つは、1本の信号に2つの意味を持たせないことである。「次に優先するmaster」と「いま選んだmaster」は、2-masterでは互いに反対の値になるので流用できるが、極性を間違えるとreadyが逆のmasterに返る。別の信号にしておけば、間違えようがない。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** 上の表は机上で追っただけである。
