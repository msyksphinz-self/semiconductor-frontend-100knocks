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

  logic        r_run;

  logic [7: 0] r_len;
  logic [3: 0] r_step;

  assign start_ready = !r_run;

  logic [12: 0] w_base_addr;
  logic         w_addr_aligned;
  logic         w_error;
  assign w_base_addr    = {1'b0, start_addr[11: 0]} + {len * (1 << size)};
  assign w_addr_aligned = (start_addr & ((1 << size) - 1)) != 'h0;
  assign w_error        = w_base_addr[12] | w_addr_aligned;

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

endmodule
