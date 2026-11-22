`timescale 1ns/1ps
// Self-checking TB for Day41, written from the Issue spec.
module tb #(parameter int unsigned WIDTH = 4);
  logic clk = 0, rst_n = 1, en = 0;
  logic [WIDTH-1:0] bin, gray, bin_next, gray_next, decoded_bin;

  gray_counter #(.WIDTH(WIDTH)) dut (.*);

  bit run_clk = 0;
  always #5 if (run_clk) clk = ~clk;

  int errs = 0;
  longint checks = 0, incs = 0;
  logic [WIDTH-1:0] m = '0, prev_gray = '0;

  function automatic logic [WIDTH-1:0] to_gray(logic [WIDTH-1:0] b);
    return b ^ (b >> 1);
  endfunction

  task automatic fail(string s);
    errs++;
    if (errs <= 10) $display("FAIL W=%0d t=%0t %s en=%b m=%h bin=%h gray=%h bin_next=%h gray_next=%h decoded=%h",
                             WIDTH, $time, s, en, m, bin, gray, bin_next, gray_next, decoded_bin);
  endtask

  task automatic check();
    logic [WIDTH-1:0] n = en ? m + 1'b1 : m;
    checks++;
    if (bin !== m) fail("bin");
    if (gray !== to_gray(m)) fail("gray");
    if (decoded_bin !== m) fail("decoded_bin");
    if (bin_next !== n) fail("bin_next");
    if (gray_next !== to_gray(n)) fail("gray_next");
  endtask

  // Drive en at negedge, check before the next posedge, then update the model.
  task automatic step(bit e);
    @(negedge clk);
    en = e;
    #1;
    check();
    if (e) begin
      prev_gray = gray;
      m = m + 1'b1;
      incs++;
      @(posedge clk);
      #1;
      if ($countones(gray ^ prev_gray) != 1) fail("gray changed by other than one bit");
    end else begin
      prev_gray = gray;
      @(posedge clk);
      #1;
      if (gray !== prev_gray) fail("gray changed while en=0");
    end
  endtask

  task automatic async_reset();
    @(negedge clk);
    #2;
    rst_n = 0;
    en = 0;
    m = '0;
    #1;
    check();
    @(posedge clk);
    #1;
    check();
    @(negedge clk);
    rst_n = 1;
    #1;
    check();
  endtask

  initial begin
    int full = 1 << WIDTH;
    // Reset with no clock edge: must clear asynchronously.
    #1 rst_n = 0; #1;
    check();
    rst_n = 1; #1;
    check();
    run_clk = 1;

    repeat (2 * full + 3) step(1);              // every value, including wrap
    repeat (20) step(0);                        // hold
    repeat (20000) step($urandom_range(1));     // random enable
    for (int r = 0; r < 50; r++) begin
      repeat ($urandom_range(full + 3)) step($urandom_range(3) != 0);
      async_reset();
    end
    repeat (2 * full) step(1);                  // full loop again after reset

    $display("day41 W=%0d checks=%0d increments=%0d errors=%0d", WIDTH, checks, incs, errs);
    if (errs == 0) $display("RESULT PASS"); else $display("RESULT FAIL");
    $finish;
  end
endmodule
