module gray_counter
  #(
    parameter int unsigned WIDTH = 4
  )
  (
    input logic clk,
    input logic rst_n,
    input logic en,
    output logic [WIDTH-1: 0] bin,
    output logic [WIDTH-1: 0] gray,
    output logic [WIDTH-1: 0] bin_next,
    output logic [WIDTH-1: 0] gray_next,
    output logic [WIDTH-1: 0] decoded_bin
  );

  always_ff @ (posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      bin <= 'h0;
      gray <= 'h0;
    end else begin
      if (en) begin
        bin <= bin_next;
        gray <= gray_next;
      end
    end
  end

  assign bin_next = en? bin + 'h1 : bin;
  assign gray_next = bin_next ^ (bin_next >> 1);

  assign decoded_bin[WIDTH-1] = gray[WIDTH-1];
  generate for (genvar i = WIDTH-2; i >= 0; i--) begin: loop_DECODED
    assign decoded_bin[i] = gray[i] ? ~decoded_bin[i+1] : decoded_bin[i+1];
  end endgenerate

endmodule
