module cdc_handshake
  #(
    parameter int unsigned WIDTH = 32
  )
  (
    input  logic              src_clk,
    input  logic              src_rst_n,
    input  logic              src_valid,
    output logic              src_ready,
    input  logic [WIDTH-1: 0] src_data,

    input  logic              dst_clk,
    input  logic              dst_rst_n,
    output logic              dst_valid,
    input  logic              dst_ready,
    output logic [WIDTH-1: 0] dst_data
  );

  logic [WIDTH-1: 0] r_src_data;
  logic              r_req;
  logic              r_ack;

  logic [ 1: 0] r_req_2ff;
  logic [ 1: 0] r_ack_2ff;

  always_ff @ (posedge src_clk, negedge src_rst_n) begin
    if (!src_rst_n) begin
      r_req <= 1'b0;
      r_ack_2ff <= 2'b00;
    end else begin
      r_ack_2ff <= {r_ack_2ff[0], r_ack};
      if (r_req & r_ack_2ff[1]) begin
        r_req <= 1'b0;
      end else if (src_valid & src_ready) begin
        r_src_data <= src_data;
        r_req      <= 1'b1;
      end
    end
  end
  assign src_ready = !r_req & !r_ack_2ff[1];


  always_ff @ (posedge dst_clk, negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      dst_valid <= 1'b0;
      r_ack     <= 1'b0;
      r_req_2ff <= 2'b00;
    end else begin
      r_req_2ff <= {r_req_2ff[0], r_req};
      if (r_ack & !r_req_2ff[1]) begin
        r_ack <= 1'b0;
      end else if (dst_valid & dst_ready) begin
        dst_valid <= 1'b0;
        r_ack     <= 1'b1;
      end else if (!dst_valid & !r_ack & r_req_2ff[1]) begin
        dst_data  <= r_src_data;
        dst_valid <= 1'b1;
      end
    end
  end


endmodule
