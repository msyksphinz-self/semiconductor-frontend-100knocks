module two_source_operand_wakeup
  (
    input  logic        entry_valid,
    input  logic        src0_ready,
    input  logic        src1_ready,
    input  logic [5: 0] src0_tag,
    input  logic [5: 0] src1_tag,
    input  logic        wakeup_valid,
    input  logic [5: 0] wakeup_tag,
    output logic        src0_ready_now,
    output logic        src1_ready_now,
    output logic        issue_ready
  );

  assign src0_ready_now = entry_valid &
                          (src0_ready |
                           (wakeup_valid & (src0_tag == wakeup_tag)));
  assign src1_ready_now = entry_valid &
                          (src1_ready |
                           (wakeup_valid & (src1_tag == wakeup_tag)));
  assign issue_ready = entry_valid & (src0_ready_now & src1_ready_now);

endmodule
