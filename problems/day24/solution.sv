// tree_plru4のSystemVerilog RTL
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


  // 3bitのPLRU stateと各bitの意味
  // 各bitはアクセスした側そのものではなく、その反対側 (次に追い出す側) を保持する
  logic        r_acc0; // 最初のbranchで次に追い出す側 (0: way0/1, 1: way2/3)
  logic [1: 0] r_acc1; // 2番目のbranchで次に追い出す側 ([0]: way0/1, [1]: way2/3)
  // way0～3をtouchした場合のstate更新 (全部validだった場合)
  //     reset後
  // -> r_acc0 = 0 / r_acc1 = 00
  // -> o_victim_way = way0
  // cycle 0:
  //     touch way0
  // -> r_acc0 = 1 / r_acc1 = 01
  // -> o_victim_way = way2
  // cycle 1:
  //     touch way1
  // -> r_acc0 = 1 / r_acc1 = 00
  // -> o_victim_way = way2
  // cycle 2:
  //     touch way2
  // -> r_acc0 = 0 / r_acc1 = 10
  // -> o_victim_way = way0
  // cycle 3:
  //     touch way3
  // -> r_acc0 = 0 / r_acc1 = 00
  // -> o_victim_way = 2'b00 = way0

  // 全way valid時のvictim selection logic
  // stateは最新のアクセスと逆の方向を保持しているので、stateの指す方向をそのままたどる

  // invalid wayがある場合のpriority logic
  // priority logicはlsbを検出する論理とする(実装方法はなんでもいい)

  // 上記corner case 1のcycle表
  //     reset後
  // -> r_acc0 = 0 / r_acc1 = 00
  // -> o_victim_way = way0
  // cycle 0:
  //     touch way0
  // -> r_acc0 = 1 / r_acc1 = 01
  // -> o_victim_way = way2
  // cycle 1:
  //     touch way2
  // -> r_acc0 = 0 / r_acc1 = 11
  // -> o_victim_way = way1
  // cycle 2:
  //     touch way1
  // -> r_acc0 = 1 / r_acc1 = 10
  // -> o_victim_way = way3
  // cycle 3:
  //     touch way3
  // -> r_acc0 = 0 / r_acc1 = 00
  // -> o_victim_way = 2'b00 = way0

  // invalid way選択がPLRUより優先される理由
  // 三項演算子による条件制御
  // Tree-PLRUとtrue LRUの違い
  // Tree-PLRUはトーナメントを逆に辿っているだけなので、真のLRUではない
  // 8-way Tree-PLRUへ拡張した場合に必要なstate bit数
  // r_acc0 = 1-bit, r_acc1 = 2-bit, r_acc2 = 4-bit = 7-bit
  // 8-wayの場合、touch時に何個のPLRU bitを更新することになるか
  // 3-bit

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


  logic [1: 0] invalid_way_idx;
  always_comb begin
    invalid_way_idx = 3;
    for (int i = 3; i >= 0; i--) begin
      if (~i_way_valid[i]) begin
        invalid_way_idx = i;
      end
    end
  end

  assign o_victim_way = &i_way_valid ? {r_acc0, r_acc1[r_acc0]} :
                        invalid_way_idx;

endmodule
