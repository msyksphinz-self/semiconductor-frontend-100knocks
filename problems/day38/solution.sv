module load_queue_violation
  (
    input  logic         st_resolve_valid,
    input  logic [31: 0] st_addr,
    input  logic [ 7: 0] st_byte_mask,

    input  logic [ 3: 0] ld_valid,
    input  logic [ 3: 0] ld_executed,
    input  logic [31: 0] ld_addr     [4],
    input  logic [ 7: 0] ld_byte_mask[4],

    output logic [ 3: 0] o_violation,
    output logic         replay_valid,
    output logic [ 1: 0] replay_idx
  );

  generate for (genvar e = 0; e < 4; e++) begin: loop_ENTRY
    assign o_violation[e] = st_resolve_valid & ld_valid[e] & ld_executed[e] &
                            (ld_addr[e][31: 3] == st_addr[31: 3]) &
                            |(ld_byte_mask[e] & st_byte_mask);
  end endgenerate
  assign replay_valid = |o_violation;

  always_comb begin
    replay_idx = 0;
    for (int e = 3; e >= 0; e--) begin
      if (o_violation[e]) begin
        replay_idx = e;
      end
    end
  end

endmodule
