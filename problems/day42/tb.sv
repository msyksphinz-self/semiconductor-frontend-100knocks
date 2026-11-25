`timescale 1ps/1ps
// Self-checking TB for Day42, written from the Issue spec.
// Clock periods are multiples of 1000 ps and DST_OFS is not a multiple of 500 ps,
// so src and dst clock edges never coincide.
module tb #(
  parameter int unsigned WIDTH   = 32,
  parameter int unsigned SRC_PER = 10000,
  parameter int unsigned DST_PER = 10000,
  parameter int unsigned DST_OFS = 3137
);
  logic             src_clk = 0, src_rst_n = 1, src_valid = 0, src_ready;
  logic [WIDTH-1:0] src_data = '0;
  logic             dst_clk = 0, dst_rst_n = 1, dst_valid, dst_ready = 0;
  logic [WIDTH-1:0] dst_data;

  cdc_handshake #(.WIDTH(WIDTH)) dut (.*);

  bit run_clk = 0, active = 0, checking = 0;
  initial begin @(posedge run_clk); forever #(SRC_PER/2) src_clk = ~src_clk; end
  initial begin @(posedge run_clk); #(DST_OFS); forever #(DST_PER/2) dst_clk = ~dst_clk; end

  int errs = 0, mode = 0, to_send = 0, stall = 0, stalled = 0;
  int accepted = 0, delivered = 0;
  int src_since_deliver = 1000, dst_since_deliver = 1000, dst_since_accept = 1000;
  bit src_fire = 0, prev_src_ready = 1, prev_dst_valid = 0, prev_dst_ready = 0, prev_dst_fire = 0;
  logic [WIDTH-1:0] prev_dst_data = '0;
  logic [WIDTH-1:0] q[$];

  task automatic fail(string s);
    errs++;
    if (errs <= 10) $display("FAIL W=%0d src=%0d dst=%0d t=%0t %s src_ready=%b dst_valid=%b dst_data=%h accepted=%0d delivered=%0d",
                             WIDTH, SRC_PER, DST_PER, $time, s, src_ready, dst_valid, dst_data, accepted, delivered);
  endtask

  // ---- drivers: inputs change at the negedge of their own clock ----
  always @(negedge src_clk) if (active) begin
    if (!src_valid || src_fire) begin
      src_valid = (to_send > 0) && (mode == 0 || $urandom_range(3) != 0);
      src_data  = $urandom;   // data also changes right after acceptance
    end
  end

  always @(negedge dst_clk) if (active) begin
    case (mode)
      0: dst_ready = 1;
      1: dst_ready = $urandom_range(1);
      default:
        if (dst_valid && stall > 0) begin dst_ready = 0; stall--; stalled++; end
        else dst_ready = dst_valid;
    endcase
  end

  // ---- source monitor ----
  always @(posedge src_clk) if (checking) begin
    src_since_deliver++;
    if (src_ready && q.size() != 0) fail("src_ready=1 while a transaction is in flight");
    // Return path: ack 2FF + req clear, req 2FF + ack clear, ack 2FF.
    if (src_ready && !prev_src_ready) begin
      if (src_since_deliver < 6) fail("src_ready returned before the 4-phase handshake completed (src side)");
      if (dst_since_deliver < 3) fail("src_ready returned before the 4-phase handshake completed (dst side)");
    end
    prev_src_ready = src_ready;
    src_fire = src_valid && src_ready;
    if (src_fire) begin
      q.push_back(src_data);
      accepted++;
      to_send--;
      dst_since_accept = 0;
    end
  end

  // ---- destination monitor ----
  always @(posedge dst_clk) if (checking) begin
    dst_since_accept++;
    dst_since_deliver++;
    if (prev_dst_fire && dst_valid) fail("dst_valid did not fall after the transfer");
    if (prev_dst_valid && !prev_dst_ready) begin
      if (!dst_valid) fail("dst_valid dropped before dst_ready");
      else if (dst_data !== prev_dst_data) fail("dst_data changed while waiting for dst_ready");
    end
    if (dst_valid && !prev_dst_valid) begin
      if (q.size() == 0) fail("dst_valid with no transaction (duplicate or spurious)");
      else if (dst_since_accept < 4) fail("dst_valid too early for a 2FF req synchronizer");
    end
    if (dst_valid && q.size() != 0 && dst_data !== q[0]) fail("dst_data differs from the accepted value");
    prev_dst_fire = dst_valid && dst_ready;
    if (prev_dst_fire) begin
      if (q.size() != 0) q.pop_front();
      delivered++;
      src_since_deliver = 0;
      dst_since_deliver = 0;
      stall = $urandom_range(300, 100);
    end
    prev_dst_valid = dst_valid;
    prev_dst_ready = dst_ready;
    prev_dst_data  = dst_data;
  end

  task automatic run_phase(int m, int n);
    int base = delivered;
    int limit = n * (500 + 40 * (SRC_PER / DST_PER + 1));
    int cycles = 0;
    mode = m;
    stall = $urandom_range(300, 100);
    to_send = n;
    while (delivered < base + n && cycles < limit) begin
      @(posedge dst_clk);
      cycles++;
    end
    if (delivered < base + n) fail("timeout: transactions did not complete");
    to_send = 0;
    repeat (40) @(posedge src_clk);
    repeat (40) @(posedge dst_clk);
    if (src_ready !== 1'b1) fail("src_ready is not 1 when idle");
    if (dst_valid !== 1'b0) fail("dst_valid is not 0 when idle");
  endtask

  initial begin
    int total = 600 + 1200 + 30 + 100;
    // Reset with no clock edge: both domains must clear asynchronously.
    #1000;
    src_rst_n = 0; dst_rst_n = 0;
    #1000;
    if (src_ready !== 1'b1) fail("src_ready after async reset");
    if (dst_valid !== 1'b0) fail("dst_valid after async reset");
    run_clk = 1;
    repeat (5) @(posedge src_clk);
    repeat (5) @(posedge dst_clk);
    if (src_ready !== 1'b1) fail("src_ready during reset");
    if (dst_valid !== 1'b0) fail("dst_valid during reset");
    fork
      begin @(negedge src_clk); src_rst_n = 1; end
      begin @(negedge dst_clk); dst_rst_n = 1; end
    join
    repeat (5) @(posedge src_clk);
    repeat (5) @(posedge dst_clk);
    if (src_ready !== 1'b1) fail("src_ready after reset release");
    if (dst_valid !== 1'b0) fail("dst_valid after reset release");
    checking = 1;
    active = 1;

    run_phase(0, 600);    // continuous traffic
    run_phase(1, 1200);   // random src_valid and dst_ready
    run_phase(2, 30);     // long dst_ready=0
    run_phase(0, 100);    // continuous again after the stalls

    if (accepted != total || delivered != total) fail("transaction count mismatch");
    if (q.size() != 0) fail("transactions left undelivered");
    if (stalled == 0) fail("long-stall test did not run");
    $display("day42 W=%0d src=%0d dst=%0d accepted=%0d delivered=%0d stalled=%0d errors=%0d",
             WIDTH, SRC_PER, DST_PER, accepted, delivered, stalled, errs);
    if (errs == 0) $display("RESULT PASS"); else $display("RESULT FAIL");
    $finish;
  end
endmodule
