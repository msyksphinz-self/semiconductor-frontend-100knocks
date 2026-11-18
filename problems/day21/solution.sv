module store_to_load_forward
  (
    input  logic [  1: 0] st_valid,
    input  logic [ 63: 0] st_addr,
    input  logic [127: 0] st_data,
    input  logic [ 31: 0] ld_addr,
    output logic          forward_valid,
    output logic [63: 0]  forward_data
  );

  logic [31: 0] w_st_addr[2];
  logic [63: 0] w_st_data[2];

  logic [63: 0] w_fwd_data[2];

  assign w_st_addr[0] = st_addr[31:  0];
  assign w_st_addr[1] = st_addr[63: 32];

  assign w_st_data[0] = st_data[ 63:  0];
  assign w_st_data[1] = st_data[127: 64];

  logic [ 1: 0] w_fwd_valid;

  generate for (genvar p = 0; p < 2; p++) begin: loop_STQ
    assign w_fwd_valid[p] = (ld_addr == w_st_addr[p]) & st_valid[p];
    assign w_fwd_data [p] = w_fwd_valid[p] ? w_st_data[p] : 'h0;
  end endgenerate

  assign forward_valid = |w_fwd_valid;
  always_comb begin
    forward_data = '0;
    for (int p = 0; p < 2; p++) begin
      if (w_fwd_valid[p]) begin
        forward_data = w_fwd_data[p];
      end
    end
  end

endmodule
