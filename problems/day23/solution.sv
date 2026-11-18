module rr_ready_valid_arbiter
  (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [1: 0]  m_valid,
    output logic [1: 0]  m_ready,
    input  logic [63: 0] m_data,
    output logic         s_valid,
    input  logic         s_ready,
    output logic [31: 0] s_data
  );

  logic r_arb_priority;
  logic w_arb_priority_next;

  logic w_in_valid;
  logic r_in_valid;

  logic w_grant;

  logic [31: 0] r_in_data;

  always_comb begin
    w_arb_priority_next = r_arb_priority;
    w_grant = r_arb_priority;
    if (s_ready | !r_in_valid) begin
      if (r_arb_priority == 'h0) begin
        if (m_valid[0]) begin
          w_grant = 1'b0;
          w_arb_priority_next = 1'b1;
        end else if (m_valid[1]) begin
          w_grant = 1'b1;
          w_arb_priority_next = 1'b0;
        end
      end else begin
        if (m_valid[1]) begin
          w_grant = 1'b1;
          w_arb_priority_next = 1'b0;
        end else if (m_valid[0]) begin
          w_grant = 1'b0;
          w_arb_priority_next = 1'b1;
        end
      end
    end
  end

  assign m_ready[0] = (s_ready | !r_in_valid) & (w_grant == 1'b0);
  assign m_ready[1] = (s_ready | !r_in_valid) & (w_grant == 1'b1);

  always_ff @ (posedge clk) begin
    if (!rst_n) begin
      r_arb_priority <= 1'b0;
    end else begin
      r_arb_priority <= w_arb_priority_next;
    end
  end

  always_ff @ (posedge clk) begin
    if (!rst_n) begin
      r_in_valid <= 1'b0;
    end else begin
      if (r_in_valid) begin
        if (s_valid & s_ready) begin
          r_in_valid <= |(m_valid & m_ready);
          r_in_data <= (m_valid[0] & m_ready[0]) ? m_data[31: 0] : m_data[63:32];
        end
      end else begin
        r_in_valid <= |(m_valid & m_ready);
        r_in_data <= (m_valid[0] & m_ready[0]) ? m_data[31: 0] : m_data[63:32];
      end
    end
  end

  assign s_valid = r_in_valid;
  assign s_data  = r_in_data;

endmodule
