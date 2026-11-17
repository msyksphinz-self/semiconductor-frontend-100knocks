module w1c_interrupt_status
  #(
    parameter int WIDTH = 8
  )
  (
    input  logic              clk,
    input  logic              rst_n,
    input  logic [WIDTH-1: 0] hw_set,
    input  logic [WIDTH-1: 0] sw_clear,
    output logic [WIDTH-1: 0] status
  );

  logic [WIDTH-1: 0] r_status;

  generate for (genvar i = 0; i < WIDTH; i++) begin: loop_STATUS
    always_ff @ (posedge clk, negedge rst_n) begin
      if (!rst_n) begin
        r_status[i] <= 1'b0;
      end else begin
        if (hw_set[i]) begin
          r_status[i] <= 1'b1;
        end else if (sw_clear[i]) begin
          r_status[i] <= 1'b0;
        end
      end
    end
  end endgenerate

  assign status = r_status;

endmodule
