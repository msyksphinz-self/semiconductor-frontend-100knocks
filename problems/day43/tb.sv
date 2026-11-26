`timescale 1ps/1ps
// Self-checking TB for Day43, written from the Issue spec.
// Clock periods are multiples of 1000 ps and RD_OFS is not a multiple of 500 ps,
// so wr and rd clock edges never coincide.
module tb #(
  parameter int unsigned WIDTH  = 32,
  parameter int unsigned DEPTH  = 16,
  parameter int unsigned WR_PER = 10000,
  parameter int unsigned RD_PER = 10000,
  parameter int unsigned RD_OFS = 3137
);
  logic             wr_clk = 0, wr_rst_n = 1, wr_valid = 0, wr_ready;
  logic [WIDTH-1:0] wr_data = '0;
  logic             rd_clk = 0, rd_rst_n = 1, rd_valid, rd_ready = 0;
  logic [WIDTH-1:0] rd_data;

  async_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut (.*);

  bit run_clk = 0, active = 0, checking = 0;
  initial begin @(posedge run_clk); forever #(WR_PER/2) wr_clk = ~wr_clk; end
  initial begin @(posedge run_clk); #(RD_OFS); forever #(RD_PER/2) rd_clk = ~rd_clk; end

  // mode: 0 continuous, 1 random, 2 fill (no reads), 3 drain (no writes),
  //       4 fast writer / slow reader, 5 slow writer / fast reader
  int errs = 0, mode = 0, to_send = 0;
  int accepted = 0, delivered = 0, occ = 0, max_occ = 0;
  longint wr_edges = 0, rd_edges = 0;
  // A pointer change at the other domain's edge stamped s (that domain's edge count)
  // can be seen through Gray FF + 2FF + flag FF no earlier than edge s+4 here.
  longint rd_stamp_in_wr[$], wr_stamp_in_rd[$];   // per read / per write, in the other domain's edges
  int reads_visible = 0, writes_visible = 0;
  bit wr_fire = 0, prev_wr_ready = 1, prev_wr_fire = 0;
  bit rd_fire = 0, prev_rd_valid = 0, prev_rd_ready = 0;
  logic [WIDTH-1:0] prev_rd_data = '0;
  logic [WIDTH-1:0] q[$];

  task automatic fail(string s);
    errs++;
    if (errs >= 20) begin $display("RESULT FAIL (stopped after 20 errors)"); $finish; end
    if (errs <= 10) $display("FAIL W=%0d D=%0d wr=%0d rd=%0d t=%0t mode=%0d %s wr_ready=%b rd_valid=%b rd_data=%h occ=%0d acc=%0d del=%0d",
                             WIDTH, DEPTH, WR_PER, RD_PER, $time, mode, s, wr_ready, rd_valid, rd_data, occ, accepted, delivered);
  endtask

  // ---- drivers: inputs change at the negedge of their own clock ----
  always @(negedge wr_clk) if (active) begin
    if (mode == 3) begin
      wr_valid = 0;
      wr_data  = $urandom;
    end else if (!wr_valid || wr_fire) begin
      case (mode)
        1:       wr_valid = (to_send > 0) && $urandom_range(1);
        5:       wr_valid = (to_send > 0) && ($urandom_range(9) < 3);
        default: wr_valid = (to_send > 0);
      endcase
      wr_data = {$urandom, $urandom};
    end
  end

  always @(negedge rd_clk) if (active) begin
    case (mode)
      0, 3, 5: rd_ready = 1;
      1:       rd_ready = $urandom_range(1);
      2:       rd_ready = 0;
      default: rd_ready = ($urandom_range(9) < 3);
    endcase
  end

  // ---- write-side monitor ----
  always @(posedge wr_clk) if (checking) begin
    wr_edges++;
    if (wr_ready && occ >= DEPTH) fail("wr_ready=1 while the FIFO is full (overflow)");
    if (!wr_ready && prev_wr_ready && !prev_wr_fire) fail("wr_ready fell without a write");
    while (rd_stamp_in_wr.size() != 0 && rd_stamp_in_wr[0] <= wr_edges - 4) begin
      void'(rd_stamp_in_wr.pop_front());
      reads_visible++;
    end
    if (wr_ready && occ < DEPTH && accepted - reads_visible >= DEPTH)
      fail("wr_ready=1 based on a read pointer that a 2FF synchronizer cannot have delivered yet");
    wr_fire = wr_valid && wr_ready;
    prev_wr_fire = wr_fire;
    prev_wr_ready = wr_ready;
    if (wr_fire) begin
      q.push_back(wr_data);
      wr_stamp_in_rd.push_back(rd_edges);
      accepted++;
      to_send--;
      occ++;
      if (occ > max_occ) max_occ = occ;
    end
  end

  // ---- read-side monitor ----
  always @(posedge rd_clk) if (checking) begin
    rd_edges++;
    if (rd_valid && occ <= 0) fail("rd_valid=1 while the FIFO is empty (underflow)");
    if (prev_rd_valid && !(prev_rd_ready) && !rd_valid) fail("rd_valid fell without a read");
    if (prev_rd_valid && !prev_rd_ready && rd_valid && rd_data !== prev_rd_data) fail("rd_data changed while rd_ready=0");
    if (rd_valid && occ > 0 && rd_data !== q[0]) fail("rd_data differs from the oldest written value");
    while (wr_stamp_in_rd.size() != 0 && wr_stamp_in_rd[0] <= rd_edges - 4) begin
      void'(wr_stamp_in_rd.pop_front());
      writes_visible++;
    end
    if (rd_valid && occ > 0 && writes_visible - delivered <= 0)
      fail("rd_valid=1 based on a write pointer that a 2FF synchronizer cannot have delivered yet");
    rd_fire = rd_valid && rd_ready;
    if (rd_fire) begin
      if (q.size() != 0) void'(q.pop_front());
      rd_stamp_in_wr.push_back(wr_edges);
      delivered++;
      occ--;
    end
    prev_rd_valid = rd_valid;
    prev_rd_ready = rd_ready;
    prev_rd_data  = rd_data;
  end

  function automatic int slow_ratio();
    return (WR_PER > RD_PER ? WR_PER / RD_PER : RD_PER / WR_PER) + 1;
  endfunction

  task automatic wait_cycles(int n);
    repeat (n) @(posedge wr_clk);
    repeat (n) @(posedge rd_clk);
  endtask

  // Send n items in the given mode, then let the FIFO drain.
  task automatic run_phase(int m, int n);
    int base = delivered;
    int limit = n * 20 * slow_ratio() + 2000;
    int cycles = 0;
    mode = m;
    to_send = n;
    while (delivered < base + n && cycles < limit) begin
      @(posedge rd_clk);
      cycles++;
    end
    if (delivered < base + n) fail("timeout: data did not arrive");
    to_send = 0;
    wait_cycles(30);
  endtask

  // Fill with reads stopped: exactly DEPTH accepted, DEPTH+1-th refused.
  // Then stop writes and read everything: exactly occ items, then rd_valid=0.
  task automatic fill_and_drain();
    int stable = 0, start;
    mode = 2;
    to_send = 1 << 30;
    for (int g = 0; stable < 40; g++) begin
      @(posedge wr_clk);
      stable = (!wr_ready) ? stable + 1 : 0;
      if (g > 200 * DEPTH * slow_ratio()) begin fail("never became full"); break; end
    end
    start = accepted;
    wait_cycles(20 * slow_ratio());       // wr_valid stays 1: the DEPTH+1-th must not be accepted
    if (accepted != start) fail("accepted a write while full");
    if (occ != DEPTH) fail($sformatf("full with %0d entries (expected DEPTH)", occ));
    if (wr_ready !== 1'b0) fail("wr_ready=1 after filling");
    if (rd_valid !== 1'b1) fail("rd_valid=0 with a full FIFO");
    mode = 3;
    to_send = 0;
    stable = 0;
    for (int g = 0; stable < 40; g++) begin
      @(posedge rd_clk);
      stable = (!rd_valid) ? stable + 1 : 0;
      if (g > 200 * DEPTH * slow_ratio()) begin fail("never became empty"); break; end
    end
    wait_cycles(10);
    if (occ != 0) fail($sformatf("rd_valid=0 with %0d entries left", occ));
    if (rd_valid !== 1'b0) fail("rd_valid=1 after draining");
    if (wr_ready !== 1'b1) fail("wr_ready=0 after draining");
  endtask

  initial begin
    // Reset with no clock edge: both domains must clear asynchronously.
    #1000;
    wr_rst_n = 0; rd_rst_n = 0;
    #1000;
    if (wr_ready !== 1'b1) fail("wr_ready after async reset");
    if (rd_valid !== 1'b0) fail("rd_valid after async reset");
    run_clk = 1;
    repeat (5) @(posedge wr_clk);
    repeat (5) @(posedge rd_clk);
    fork
      begin @(negedge wr_clk); wr_rst_n = 1; end
      begin @(negedge rd_clk); rd_rst_n = 1; end
    join
    repeat (5) @(posedge wr_clk);
    repeat (5) @(posedge rd_clk);
    if (wr_ready !== 1'b1) fail("wr_ready after reset release");
    if (rd_valid !== 1'b0) fail("rd_valid after reset release");
    checking = 1;
    active = 1;

    run_phase(0, 40 * DEPTH);        // continuous, many wraps
    run_phase(1, 3000);              // random wr_valid / rd_ready
    repeat (3) fill_and_drain();     // full and empty boundaries
    run_phase(4, 1500);              // fast writer, slow reader: mostly full
    run_phase(5, 1500);              // slow writer, fast reader: mostly empty
    run_phase(1, 1000);
    fill_and_drain();

    if (accepted != delivered) fail("accepted and delivered counts differ");
    if (q.size() != 0) fail("data left in the scoreboard");
    if (max_occ != DEPTH) fail("FIFO never reached DEPTH entries");
    $display("day43 W=%0d D=%0d wr=%0d rd=%0d accepted=%0d delivered=%0d max_occ=%0d errors=%0d",
             WIDTH, DEPTH, WR_PER, RD_PER, accepted, delivered, max_occ, errs);
    if (errs == 0) $display("RESULT PASS"); else $display("RESULT FAIL");
    $finish;
  end
endmodule
