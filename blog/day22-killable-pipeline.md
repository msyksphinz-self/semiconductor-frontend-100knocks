# 半導体フロントエンド設計100本ノック (22) Killable Pipeline

半導体フロントエンド設計100本ノック、第22問。

今回はflushで中身をkillできるパイプラインを設計してみた。transactionにtagを付けておき、flushで指定されたtagと一致するものを捨てる回路である。

パイプラインといっても1段だけなので、RTLは30行ほどで終わる。ただ、flushが来たサイクルに「killすべきtransaction」がどこにいるのかを数えてみると2か所あって、片方だけ見ていると漏れる。今回はそこを考えた。

課題の詳細は[Day22 Issue](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/22)。

## 今回の問題：flushでkillできる1段パイプライン

今回作るのは、**tag付きのtransactionを1段のFFで受けて次のサイクルに出し、flushで指定されたtagのtransactionは後段に出さない回路**。

[元の課題Issue #22](https://github.com/msyksphinz-self/semiconductor-frontend-100knocks/issues/22)の仕様を、記事だけで追えるようにまとめる。

### 仕様

- 1段のパイプライン。backpressureはなく、毎サイクル入力を受理する。
- transactionは`valid`、4bitの`tag`、32bitの`data`を持つ。
- `flush_valid=1`のとき、tagが`flush_tag`と一致するtransactionをkillする。killされたtransactionは後段へ副作用を出さない。

モジュールの外部インターフェースは次のとおり（解答部分は省略）。

```systemverilog
module killable_pipeline (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         in_valid,
  input  logic [3: 0]  in_tag,
  input  logic [31: 0] in_data,
  input  logic         flush_valid,
  input  logic [3: 0]  flush_tag,
  output logic         out_valid,
  output logic [3: 0]  out_tag,
  output logic [31: 0] out_data
);
    // ここにRTLを実装する
endmodule
```

### Issueで決まっていなかったこと

Issueには書かれていなかったので、今回は次のように決めた。

- **stageにいるtransactionをkillするタイミング**：flushのサイクルに`out_valid`を組合せで0にする。flushのサイクルから後段には見えない。
- **flushと同じサイクルに入ってくるtransaction**：tagが一致すればこれもkillして、stageに入れない。
- **tagの比較**：等値比較。「flush_tagより若いものをすべてkill」という年齢比較ではない。
- **resetの方式**：同期reset。
- **`out_valid=0`のときの`out_tag` / `out_data`**：不定扱い。

### 検証してほしいCorner Case

flushと投入が同時の場合、対象外のtag、reset。

以下では、実際に書いてみて考えた点を順番に見ていく。

## killすべきtransactionはどこにいるか

1段のパイプラインなので、あるサイクルに存在しうるtransactionは2つしかない。

```text
in_valid/in_tag/in_data ──▶ [FF 1段] ──▶ out_valid/out_tag/out_data
        ①                     ②
```

- ① そのサイクルに入力に来ているtransaction。次のサイクルにFFに入る。
- ② 前のサイクルに受理されて、いまFFに入っているtransaction。このサイクルに出力されている。

flushが来たサイクルには、この両方がkillの対象になりうる。②だけ見ていると、flushと同時に入ってきた①が次のサイクルに何事もなく出力されてしまう。①だけ見ていると、flushのサイクルに②がそのまま後段に出ていく。

なので、flushの判定は入力側と出力側の両方に入れた。

## 入力側のkill

```systemverilog
logic r_valid;

always_ff @ (posedge clk) begin
  if (!rst_n) begin
    r_valid <= 1'b0;
  end else begin
    if (flush_valid & (in_tag == flush_tag)) begin
      r_valid <= 1'b0;
    end else begin
      r_valid <= in_valid;
    end
  end
end
```

flushと入力のtagが一致したら、`in_valid`が1でも`r_valid`に0を書く。つまりflushが通常の進行より優先される。

`in_valid=0`のときに`in_tag`がたまたま`flush_tag`と一致しても、もともと0を書くところに0を書くだけなので害はない。`in_valid`を条件に入れる必要はない。

## 出力側のkill

```systemverilog
assign out_valid = flush_valid & (out_tag == flush_tag) ? 1'b0 : r_valid;
```

FFに入っているtransactionのtagが一致したら、そのサイクルの`out_valid`を0にする。

ここで`r_valid`のFFをクリアする方法も考えられるが、それでは間に合わない。FFが0になるのは次のサイクルで、flushのサイクルには`out_valid=1`が後段に見えてしまう。「後段へ副作用を出さない」ためには、組合せでマスクする必要がある。

逆に、`r_valid`のFFをクリアする必要はない。1段のパイプラインで毎サイクル入力を受理するので、FFの中身は次のサイクルには新しい入力で上書きされる。

## tagとdataはresetしない

```systemverilog
always_ff @ (posedge clk) begin
  out_tag  <= in_tag;
  out_data <= in_data;
end
```

`out_tag`と`out_data`はresetなしのFFで、毎サイクル入力をそのまま取り込む。意味があるかどうかは`out_valid`が決めるので、resetする必要はない。Day07やDay11と同じ考え方である。

resetのない`always_ff`を、resetのある`r_valid`の`always_ff`と分けて書いているのも同じ理由による。

## 波形で追ってみる

各サイクルの入力と、そのサイクルにFFから出ている値を並べる。

| cycle | 入力 | flush | FFの中身 | `out_valid` | 説明 |
|---:|---|---|---|---:|---|
| 1 | A (tag3) | なし | 空 | 0 | Aが入る |
| 2 | B (tag5) | なし | A (tag3) | 1 | Aが出る |
| 3 | C (tag7) | tag5 | B (tag5) | 0 | **Bを出力側でkill**。Cは入る |
| 4 | D (tag2) | tag2 | C (tag7) | 1 | Cが出る。**Dを入力側でkill** |
| 5 | E (tag4) | なし | 空 | 0 | Dは出てこない |
| 6 | F (tag4) | tag4 | E (tag4) | 0 | **EとFを両方kill** |
| 7 | なし | tag9 | 空 | 0 | Fは出てこない |

cycle 3ではFFにいるBが、cycle 4では入力に来ているDがkillされる。cycle 6は両方のtagが一致する場合で、両方ともkillされる。cycle 4のCのように、tagが一致しないtransactionはflushの影響を受けない。

## 規模を大きくしたときの考察

**クリティカルパス**：`flush_valid`と`flush_tag`から、4bitの比較器を通って`out_valid`へ抜ける組合せパスがある。flushは分岐の解決結果のように遅く確定する信号であることが多いので、これが後段の論理と合わせてクリティカルパスになりやすい。入力側の比較はFFのDで止まるので、こちらは軽い。

出力側のマスクをやめてFFのクリアだけにすればこのパスは消えるが、flushのサイクルに`out_valid`が出てしまう。その場合は、後段が同じflushを見て自分で捨てることになる。どちらで捨てるかの違いで、どこかでflushと比較する必要があることは変わらない。

**多段にした場合**：N段にすると、flushのサイクルにkillの対象になりうるtransactionは、入力の1つと各段のN個で、N+1個になる。比較器もN+1個必要になる。途中の段のtransactionは、出力側のように組合せでマスクする必要はなく、次の段へ進むときのvalidを0にすればよい。組合せのマスクが要るのは、後段に見えている最終段だけである。

**tagの比較**：今回は等値比較にした。実際のプロセッサでは「この分岐より若い命令をすべて捨てる」という年齢比較になることが多く、tagがwrapする場合の大小比較が必要になる。分岐ごとに1bitを割り当てたmaskを各transactionに持たせ、flushされた分岐のbitが立っているものを捨てる方法もある。こちらは比較がANDとORだけで済む。

**消費電力**：`out_tag`と`out_data`は`in_valid=0`のサイクルにも更新される。動作としては問題ないが、36bitのFFが無駄にtoggleする。`in_valid`をenableにすれば止められ、clock gatingも効くようになる。

## 最終RTLについて

最終稿は、同期resetの`r_valid`、resetなしの`out_tag` / `out_data`、入力側と出力側のflush判定で構成した。モジュール名は`killable_pipeline`。RTLは[problems/day22/solution.sv](../problems/day22/solution.sv)に置いてある。

今回はレビューでの修正はなかった。

## まとめと今後の検証

今回のポイントは、flushのサイクルにkillすべきtransactionがどこにいるかを数えることだった。

1段のパイプラインでは、FFの中と入力の2か所にいる。FFの中のものは、そのサイクルに後段へ見えているので組合せでマスクする。入力のものは、FFに入れるvalidを0にする。

**シミュレータでのコンパイル・テストベンチ実行は未実施。** 上の表は机上で追っただけである。
