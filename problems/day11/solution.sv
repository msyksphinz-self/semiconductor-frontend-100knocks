module arbitrary_depth_fifo
  #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 5
  )
  (
    input  logic              clk,
    input  logic              rst_n,
    input  logic              push_valid,
    input  logic              pop_ready,
    input  logic [WIDTH-1: 0] push_data,
    output logic              push_ready,
    output logic              pop_valid,
    output logic [WIDTH-1: 0] pop_data
  );

  logic [DEPTH-1: 0]         r_valid;
  logic [WIDTH-1: 0]         r_fifo_data[DEPTH];

  logic [$clog2(DEPTH)-1: 0] r_head;
  logic [$clog2(DEPTH)-1: 0] r_tail;

  always_ff @ (posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      r_head  <= 'h0;
      r_tail  <= 'h0;
      r_valid <= 'h0;
    end else begin
      if (push_valid & push_ready) begin
        r_head              <= r_head == DEPTH-1 ? 'h0 : r_head + 'h1;
        r_valid[r_head]     <= 1'b1;
      end
      if (pop_valid & pop_ready) begin
        r_tail          <= r_tail == DEPTH-1 ? 'h0 : r_tail + 'h1;
        r_valid[r_tail] <= 1'b0;
      end
    end
  end

  always_ff @ (posedge clk) begin
    if (push_valid & push_ready) begin
      r_fifo_data[r_head] <= push_data;
    end
  end

  assign pop_data   = r_fifo_data[r_tail];
  assign push_ready = ~(&r_valid);
  assign pop_valid  = |r_valid;

endmodule
