module sv020_banked_register #(
  parameter int unsigned NUM_REGS = 32,
  parameter int unsigned DATA_W = 32,
  parameter int unsigned NUM_BANKS = 2,
  parameter int unsigned ADDR_W = $clog2(NUM_REGS)
) (
  input  logic              clk,
  input  logic              rst_n,

  // Two read request ports: port0=LSB側
  input  logic [1:0]        rd_valid,
  output logic [1:0]        rd_ready,
  input  logic [ADDR_W-1:0] rd_addr0,
  input  logic [ADDR_W-1:0] rd_addr1,
  output logic [DATA_W-1:0] rd_data0,
  output logic [DATA_W-1:0] rd_data1,

  // One independent write port
  input  logic              wr_en,
  input  logic [ADDR_W-1:0] wr_addr,
  input  logic [DATA_W-1:0] wr_data
);

  localparam NB_W = $clog2(NUM_BANKS);
  localparam NA   = NUM_REGS/NUM_BANKS;
  localparam NA_W = $clog2(NA);

  logic [DATA_W-1: 0] r_regs[NUM_BANKS][NA-1: 0];

  logic [NA_W-1: 0]   w_wr_addr;
  assign w_wr_addr = wr_addr[NB_W +: NA_W];

  logic [NB_W-1: 0] w_rd_bank0;
  logic [NB_W-1: 0] w_rd_bank1;
  logic [NA_W-1: 0] w_rd_addr0;
  logic [NA_W-1: 0] w_rd_addr1;
  assign w_rd_bank0 = rd_addr0[NB_W-1: 0];
  assign w_rd_bank1 = rd_addr1[NB_W-1: 0];
  assign w_rd_addr0 = rd_addr0[NB_W +: NA_W];
  assign w_rd_addr1 = rd_addr1[NB_W +: NA_W];

  logic [DATA_W-1: 0] w_rd_data[NUM_BANKS];

  generate for (genvar b_idx = 0; b_idx < NUM_BANKS; b_idx++) begin: bank_loop
    logic w_wr_en;
    assign w_wr_en = wr_en & (wr_addr[$clog2(NUM_BANKS)-1: 0] == b_idx[$clog2(NUM_BANKS)-1: 0]);

    logic [NA_W-1: 0] w_rd_local_addr;
    assign w_rd_local_addr = rd_valid[0] & (w_rd_bank0 == b_idx) ? w_rd_addr0 :
                             rd_valid[1] & (w_rd_bank1 == b_idx) ? w_rd_addr1 :
                             'h0;

    always_ff @ (posedge clk) begin
      if (!rst_n) begin
        for (int i = 0; i < NA; i++) begin
          r_regs[b_idx][i] <= 'h0;
        end
      end else if (w_wr_en) begin
        r_regs[b_idx][w_wr_addr] <= wr_data;
      end
    end

    assign w_rd_data[b_idx] = r_regs[b_idx][w_rd_local_addr];

  end endgenerate

  assign rd_ready[0] = rd_valid[0];
  assign rd_ready[1] = ~rd_valid[0] & rd_valid[1] | rd_valid[0] & rd_valid[1] & (w_rd_bank0 != w_rd_bank1);
  assign rd_data0    = w_rd_data[w_rd_bank0];
  assign rd_data1    = w_rd_data[w_rd_bank1];

endmodule
