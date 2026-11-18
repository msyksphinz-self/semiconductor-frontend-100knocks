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

  assign out_valid = flush_valid & (out_tag == flush_tag) ? 1'b0 : r_valid;

  always_ff @ (posedge clk) begin
    out_tag  <= in_tag;
    out_data <= in_data;
  end

endmodule
