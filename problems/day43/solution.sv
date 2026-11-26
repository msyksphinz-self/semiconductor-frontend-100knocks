module async_fifo
  #(
    parameter int unsigned WIDTH = 32,
    parameter int unsigned DEPTH = 16
  )
  (
    // Write domain
    input  logic              wr_clk,
    input  logic              wr_rst_n,
    input  logic              wr_valid,
    output logic              wr_ready,
    input  logic [WIDTH-1: 0] wr_data,

    // Read domain
    input  logic              rd_clk,
    input  logic              rd_rst_n,
    output logic              rd_valid,
    input  logic              rd_ready,
    output logic [WIDTH-1: 0] rd_data
  );

  logic [WIDTH-1: 0]       r_fifo [DEPTH];
  logic [$clog2(DEPTH): 0] r_wr_bin_cnt;
  logic [$clog2(DEPTH): 0] r_rd_bin_cnt;
  logic [$clog2(DEPTH): 0] w_wr_bin_cnt_next;
  logic [$clog2(DEPTH): 0] w_rd_bin_cnt_next;
  logic [$clog2(DEPTH): 0] r_wr_gray_cnt;
  logic [$clog2(DEPTH): 0] r_rd_gray_cnt;
  logic [$clog2(DEPTH): 0] w_wr_gray_cnt_next;
  logic [$clog2(DEPTH): 0] w_rd_gray_cnt_next;

  logic [$clog2(DEPTH): 0] r_rd_gray_cnt_2ff[2];
  logic [$clog2(DEPTH): 0] r_wr_gray_cnt_2ff[2];

  logic                    r_full;
  logic                    r_empty;

  always_comb begin
    w_wr_bin_cnt_next = r_wr_bin_cnt;
    if (wr_valid & wr_ready) begin
      w_wr_bin_cnt_next = r_wr_bin_cnt + 'h1;
    end
    w_wr_gray_cnt_next = w_wr_bin_cnt_next ^ (w_wr_bin_cnt_next >> 1);
  end

  always_ff @ (posedge wr_clk, negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      r_wr_bin_cnt         <= 'h0;
      r_wr_gray_cnt        <= 'h0;

      r_rd_gray_cnt_2ff[0] <= 'h0;
      r_rd_gray_cnt_2ff[1] <= 'h0;

      r_full               <= 1'b0;
    end else begin
      r_rd_gray_cnt_2ff[0] <= r_rd_gray_cnt;
      r_rd_gray_cnt_2ff[1] <= r_rd_gray_cnt_2ff[0];

      r_wr_bin_cnt         <= w_wr_bin_cnt_next;
      r_wr_gray_cnt        <= w_wr_gray_cnt_next;

      r_full <= (w_wr_gray_cnt_next[$clog2(DEPTH) -: 2] == ~r_rd_gray_cnt_2ff[1][$clog2(DEPTH) -: 2]) &
                (w_wr_gray_cnt_next[$clog2(DEPTH)-2: 0] ==  r_rd_gray_cnt_2ff[1][$clog2(DEPTH)-2: 0]);
    end
  end

  always_ff @ (posedge wr_clk) begin
    if (wr_valid & wr_ready) begin
      r_fifo[r_wr_bin_cnt[$clog2(DEPTH)-1: 0]] <= wr_data;
    end
  end

  assign wr_ready = !r_full;

  always_comb begin
    w_rd_bin_cnt_next = r_rd_bin_cnt;
    if (rd_valid & rd_ready) begin
      w_rd_bin_cnt_next = r_rd_bin_cnt + 'h1;
    end
    w_rd_gray_cnt_next = w_rd_bin_cnt_next ^ (w_rd_bin_cnt_next >> 1);
  end

  always_ff @ (posedge rd_clk, negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      r_rd_bin_cnt         <= 'h0;
      r_rd_gray_cnt        <= 'h0;

      r_wr_gray_cnt_2ff[0] <= 'h0;
      r_wr_gray_cnt_2ff[1] <= 'h0;

      r_empty              <= 1'b1;
    end else begin
      r_wr_gray_cnt_2ff[0] <= r_wr_gray_cnt;
      r_wr_gray_cnt_2ff[1] <= r_wr_gray_cnt_2ff[0];

      r_rd_bin_cnt         <= w_rd_bin_cnt_next;
      r_rd_gray_cnt        <= w_rd_gray_cnt_next;

      r_empty              <= w_rd_gray_cnt_next == r_wr_gray_cnt_2ff[1];
    end
  end
  assign rd_valid = !r_empty;

  assign rd_data  = r_fifo[r_rd_bin_cnt[$clog2(DEPTH)-1: 0]];

endmodule
