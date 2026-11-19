module byte_store_load_forward
  (
    input  logic [3: 0]  st_valid,
    input  logic [31: 0] st_addr [4],
    input  logic [63: 0] st_data [4],
    input  logic [7: 0]  st_byte_en[4],

    input  logic [31: 0] ld_addr,
    input  logic [1: 0]  ld_size,

    output logic         forward,
    output logic         stall,
    output logic         memory_read,
    output logic [63: 0] forward_data
  );

  logic [7: 0] ld_byte_mask;
  always_comb begin
    case (ld_size)
      2'b00   : ld_byte_mask = 8'b0000_0001 <<  ld_addr[2: 0];         // Byte
      2'b01   : ld_byte_mask = 8'b0000_0011 << {ld_addr[2: 1], 1'b0};  // Half
      2'b10   : ld_byte_mask = 8'b0000_1111 << {ld_addr[2: 2], 2'b00}; // Word
      2'b11   : ld_byte_mask = 8'b1111_1111;                           // DWord
      default : ld_byte_mask = 8'b0000_0000;
    endcase
  end

  logic [7: 0] w_byte_hit [4];
  generate for (genvar e = 0; e < 4; e++) begin: loop_ENTRY
    logic [7: 0] w_byte_hit_raw;
    assign w_byte_hit_raw = ld_byte_mask & st_byte_en[e];
    assign w_byte_hit[e]  = (st_valid[e] & (st_addr[e][31: 3] == ld_addr[31: 3]) & |w_byte_hit_raw) ? w_byte_hit_raw : 'h0;
  end endgenerate

  logic [7: 0] forward_byte;
  always_comb begin
    forward_byte = 'h0;
    forward_data = 'h0;
    for (int b = 0; b < 8; b++) begin
      for (int e = 0; e < 4; e++) begin
        if (w_byte_hit[e][b]) begin
          forward_data[b*8 +: 8] = st_data[e][b*8 +: 8];
          forward_byte[b]        = 1'b1;
        end
      end
    end
  end

  assign memory_read = forward_byte == 'h0;
  assign forward     = forward_byte == ld_byte_mask;
  assign stall       = !memory_read & !forward;

endmodule
