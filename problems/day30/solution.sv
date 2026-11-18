module priority_wakeup_selector
  (
    input  logic [3: 0]  valid,
    input  logic [3: 0]  src_ready,
    input  logic [23: 0] src_tag,
    input  logic         wakeup_valid,
    input  logic [5: 0]  wakeup_tag,
    output logic         select_valid,
    output logic [1: 0]  select_idx
  );

  logic [5: 0] w_src_tag[4];
  assign w_src_tag[0] = src_tag[5: 0];
  assign w_src_tag[1] = src_tag[11: 6];
  assign w_src_tag[2] = src_tag[17:12];
  assign w_src_tag[3] = src_tag[23:18];

  logic [3: 0] w_select_int_valid;

  generate for (genvar e = 0; e < 4; e++) begin: loop_ENTRY
    logic w_wakeup_hit;
    assign w_wakeup_hit = wakeup_valid & (w_src_tag[e] == wakeup_tag);
    assign w_select_int_valid[e] = valid[e] & (src_ready[e] | w_wakeup_hit);
  end endgenerate

  assign select_valid = |w_select_int_valid;
  always_comb begin
    select_idx = 0;
    for (int e = 3; e >= 0; e--) begin
      if (w_select_int_valid[e]) begin
        select_idx = e;
      end
    end
  end

endmodule
