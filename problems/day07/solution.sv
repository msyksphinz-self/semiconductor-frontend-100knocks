module fixed_latency_wrapper
  #(
    parameter int LATENCY = 3
  )
  (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         in_valid,
    input  logic [31: 0] in_data,
    output logic         out_valid,
    output logic [31: 0] out_data
  );

  logic [31: 0] r_data [LATENCY];
  logic         r_valid [LATENCY];

  always_ff @ (posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < LATENCY; i++) begin
        r_valid[i] <= 1'b0;
      end
    end else begin
      r_valid[0] <= in_valid;
      for (int i = 1; i < LATENCY; i++) begin
        r_valid[i] <= r_valid[i-1];
      end
    end
  end

  always_ff @ (posedge clk) begin
    r_data [0] <= in_data + 'h1;
    for (int i = 1; i < LATENCY; i++) begin
      r_data [i] <= r_data [i-1];
    end
  end

  assign out_valid = r_valid [LATENCY-1];
  assign out_data  = r_data [LATENCY-1];

endmodule
