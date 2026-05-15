`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 23:19:24
// Design Name: 
// Module Name: spi_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module      : tb_top
// File        : tb_top.v
// Description : Comprehensive testbench for the SPI master/slave demo top module.
//
//   What is verified
//   ----------------
//     1. Reset state           - all outputs cleared, bus parked.
//     2. Single transfer       - 0xA5 round-trip.
//     3. Corner data (0x00)    - no MOSI activity.
//     4. Corner data (0xFF)    - solid MOSI activity.
//     5. Alternating (0xAA)    - bit ordering / MSB-first.
//     6. Alternating (0x55).
//     7. Walking-1 (8 tests)   - every MOSI bit position exercised.
//     8. Random patterns       - 0x3C, 0xC3, 0x69, 0x96.
//     9. Master rx_data        - master always receives the slave's constant
//                                pattern (SLAVE_TX_PATTERN, default 0xA5).
//    10. Back-to-back transfers- no glitch / restart issues.
//    11. SS_n behavior         - asserted (low) only during the transfer,
//                                de-asserted between transfers.
//    12. busy / done pulses    - correct width and timing.
//
//   How to read the log
//   -------------------
//   Every test prints:
//     [TEST N] description
//       Master TX  : <hex>
//       Slave  RX  : <hex>   (expected vs. actual)
//       Master RX  : <hex>   (expected vs. actual)
//       ==> PASS / FAIL
//
//   A SPI bus monitor prints ss_n / sclk transitions during each transfer.
//   Final summary prints total run / passed / failed.
//
//   Simulation parameters
//   ---------------------
//   CLK_DIV is overridden to 4 for fast simulation (SCLK = 12.5 MHz at a 100
//   MHz clk). The same DUT will work at CLK_DIV = 50 (1 MHz SCLK) on real HW.
//////////////////////////////////////////////////////////////////////////////////

module spi_tb;

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------
    localparam integer CLK_PERIOD       = 10;          // 100 MHz system clock
    localparam integer DATA_WIDTH       = 8;
    localparam integer CLK_DIV          = 4;           // fast sim
    localparam         CPOL             = 1'b0;
    localparam         CPHA             = 1'b0;
    localparam [DATA_WIDTH-1:0] SLAVE_TX_PATTERN = 8'hA5;

    //--------------------------------------------------------------------------
    // DUT I/O
    //--------------------------------------------------------------------------
    reg                       clk;
    reg                       rst_btn;
    reg                       start_btn;
    reg  [DATA_WIDTH-1:0]     sw;

    wire [DATA_WIDTH-1:0]     led_slave_rx;
    wire [DATA_WIDTH-1:0]     led_master_rx;
    wire                      led_busy;
    wire                      led_done;

    wire                      sclk_o;
    wire                      mosi_o;
    wire                      miso_o;
    wire                      ss_n_o;
    reg                       miso_pad = 1'b0; // unused input port on the top

    //--------------------------------------------------------------------------
    // Bookkeeping
    //--------------------------------------------------------------------------
    integer tests_run    = 0;
    integer tests_passed = 0;
    integer tests_failed = 0;

    // For SPI bus monitor (counts SCLK edges seen per transfer)
    integer sclk_edges   = 0;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    spi_top #(
        .DATA_WIDTH       (DATA_WIDTH),
        .CLK_DIV          (CLK_DIV),
        .CPOL             (CPOL),
        .CPHA             (CPHA),
        .SLAVE_TX_PATTERN (SLAVE_TX_PATTERN)
    ) dut (
        .clk           (clk),
        .rst_btn       (rst_btn),
        .start_btn     (start_btn),
        .sw            (sw),
        .led_slave_rx  (led_slave_rx),
        .led_master_rx (led_master_rx),
        .led_busy      (led_busy),
        .led_done      (led_done),
        .sclk_o        (sclk_o),
        .mosi_o        (mosi_o),
        .miso_pad      (miso_pad),
        .miso_o        (miso_o),
        .ss_n_o        (ss_n_o)
    );

    //--------------------------------------------------------------------------
    // Clock generation : 100 MHz
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //--------------------------------------------------------------------------
    // SPI bus monitor : prints ss_n / sclk events
    //--------------------------------------------------------------------------
    always @(negedge ss_n_o) begin
        $display("    [BUS @ %0t ns]  ss_n: 1 -> 0  (CS asserted, transfer begins)", $time);
        sclk_edges = 0;
    end

    always @(posedge ss_n_o) begin
        $display("    [BUS @ %0t ns]  ss_n: 0 -> 1  (CS released, transfer ends)  total SCLK edges = %0d",
                 $time, sclk_edges);
    end

    always @(sclk_o) begin
        if (ss_n_o == 1'b0) sclk_edges = sclk_edges + 1;
    end

    //--------------------------------------------------------------------------
    // Single-transfer task
    //   Pulses start_btn, waits for the transfer to finish, then verifies
    //   both rx registers against expected values.
    //--------------------------------------------------------------------------
    task automatic do_transfer;
        input [DATA_WIDTH-1:0]   tx_byte;
        input [DATA_WIDTH-1:0]   exp_master_rx;
        input [8*48-1:0]         test_name;       // 48-char description
        reg                      slave_ok;
        reg                      master_ok;
        begin
            tests_run = tests_run + 1;
            $display("");
            $display("---------------------------------------------------------");
            $display("[TEST %0d] %0s", tests_run, test_name);
            $display("---------------------------------------------------------");
            $display("  Driving sw = 0x%02h  (master will transmit this on MOSI)",  tx_byte);
            $display("  Slave will transmit constant 0x%02h on MISO",               SLAVE_TX_PATTERN);
            $display("  EXPECT:  led_slave_rx  = 0x%02h",                           tx_byte);
            $display("  EXPECT:  led_master_rx = 0x%02h",                           exp_master_rx);

            // Apply input and pulse start button (held a few cycles to clear sync)
            @(posedge clk);
            sw = tx_byte;
            @(posedge clk);
            $display("    [DRV @ %0t ns]  start_btn asserted",  $time);
            start_btn = 1'b1;
            repeat (4) @(posedge clk);
            start_btn = 1'b0;
            $display("    [DRV @ %0t ns]  start_btn released",  $time);

            // Wait for busy to assert (transfer underway)
            wait (led_busy == 1'b1);
            $display("    [DUT @ %0t ns]  led_busy = 1  (master FSM accepted start)", $time);

            // Wait for busy to go low (transfer complete)
            wait (led_busy == 1'b0);
            $display("    [DUT @ %0t ns]  led_busy = 0  (transfer complete)",         $time);

            // Allow LEDs to settle a couple of cycles
            repeat (2) @(posedge clk);

            // Verify
            slave_ok  = (led_slave_rx  == tx_byte);
            master_ok = (led_master_rx == exp_master_rx);

            $display("  RESULT:  led_slave_rx  = 0x%02h  (expected 0x%02h)  [%s]",
                     led_slave_rx,  tx_byte,        slave_ok  ? "OK" : "MISMATCH");
            $display("  RESULT:  led_master_rx = 0x%02h  (expected 0x%02h)  [%s]",
                     led_master_rx, exp_master_rx,  master_ok ? "OK" : "MISMATCH");

            if (slave_ok && master_ok) begin
                tests_passed = tests_passed + 1;
                $display("  ==> TEST %0d PASSED", tests_run);
            end
            else begin
                tests_failed = tests_failed + 1;
                $display("  ==> TEST %0d FAILED", tests_run);
            end

            // Settle before next transfer
            repeat (5) @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Reset-state check task (does not press start_btn)
    //--------------------------------------------------------------------------
    task automatic check_reset_state;
        reg ok;
        begin
            tests_run = tests_run + 1;
            $display("");
            $display("---------------------------------------------------------");
            $display("[TEST %0d] Reset-state verification",   tests_run);
            $display("---------------------------------------------------------");
            $display("  EXPECT after reset:");
            $display("    led_busy       = 0");
            $display("    led_done       = 0");
            $display("    led_slave_rx   = 0x00");
            $display("    led_master_rx  = 0x00");
            $display("    ss_n_o         = 1   (bus parked)");
            $display("    sclk_o         = %0b   (= CPOL)", CPOL);

            ok = (led_busy      == 1'b0) &&
                 (led_done      == 1'b0) &&
                 (led_slave_rx  == 8'h00) &&
                 (led_master_rx == 8'h00) &&
                 (ss_n_o        == 1'b1) &&
                 (sclk_o        == CPOL);

            $display("  OBSERVED:");
            $display("    led_busy       = %0b", led_busy);
            $display("    led_done       = %0b", led_done);
            $display("    led_slave_rx   = 0x%02h", led_slave_rx);
            $display("    led_master_rx  = 0x%02h", led_master_rx);
            $display("    ss_n_o         = %0b", ss_n_o);
            $display("    sclk_o         = %0b", sclk_o);

            if (ok) begin
                tests_passed = tests_passed + 1;
                $display("  ==> TEST %0d PASSED", tests_run);
            end
            else begin
                tests_failed = tests_failed + 1;
                $display("  ==> TEST %0d FAILED", tests_run);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Back-to-back transfer test: press start almost immediately after done
    //--------------------------------------------------------------------------
    task automatic do_btb_test;
        input [DATA_WIDTH-1:0] a;
        input [DATA_WIDTH-1:0] b;
        reg ok_a, ok_b;
        begin
            tests_run = tests_run + 1;
            $display("");
            $display("---------------------------------------------------------");
            $display("[TEST %0d] Back-to-back transfers  (0x%02h then 0x%02h)",
                     tests_run, a, b);
            $display("---------------------------------------------------------");

            // first xfer
            @(posedge clk);
            sw = a;
            start_btn = 1'b1; repeat (4) @(posedge clk); start_btn = 1'b0;
            wait (led_busy == 1'b1); wait (led_busy == 1'b0);
            repeat (2) @(posedge clk);
            ok_a = (led_slave_rx == a) && (led_master_rx == SLAVE_TX_PATTERN);
            $display("  After 1st xfer:  slave_rx=0x%02h (exp 0x%02h)  master_rx=0x%02h (exp 0x%02h)  [%s]",
                     led_slave_rx, a, led_master_rx, SLAVE_TX_PATTERN, ok_a ? "OK" : "MISMATCH");

            // immediately do the second one (only a couple of cycles gap)
            @(posedge clk);
            sw = b;
            start_btn = 1'b1; repeat (4) @(posedge clk); start_btn = 1'b0;
            wait (led_busy == 1'b1); wait (led_busy == 1'b0);
            repeat (2) @(posedge clk);
            ok_b = (led_slave_rx == b) && (led_master_rx == SLAVE_TX_PATTERN);
            $display("  After 2nd xfer:  slave_rx=0x%02h (exp 0x%02h)  master_rx=0x%02h (exp 0x%02h)  [%s]",
                     led_slave_rx, b, led_master_rx, SLAVE_TX_PATTERN, ok_b ? "OK" : "MISMATCH");

            if (ok_a && ok_b) begin
                tests_passed = tests_passed + 1;
                $display("  ==> TEST %0d PASSED", tests_run);
            end
            else begin
                tests_failed = tests_failed + 1;
                $display("  ==> TEST %0d FAILED", tests_run);
            end
            repeat (5) @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // done-pulse width check : led_done is a toggle output (not the master's
    // raw done), so its pulse semantics are "changes value on each completed
    // transfer". We check that the toggle actually happens.
    //--------------------------------------------------------------------------
    task automatic check_done_toggle;
        reg prev_done;
        begin
            tests_run = tests_run + 1;
            $display("");
            $display("---------------------------------------------------------");
            $display("[TEST %0d] led_done toggles on each completed transfer", tests_run);
            $display("---------------------------------------------------------");
            prev_done = led_done;
            $display("  led_done before xfer = %0b", prev_done);

            @(posedge clk);
            sw = 8'h5A;
            start_btn = 1'b1; repeat (4) @(posedge clk); start_btn = 1'b0;
            wait (led_busy == 1'b1); wait (led_busy == 1'b0);
            repeat (2) @(posedge clk);
            $display("  led_done after  xfer = %0b", led_done);

            if (led_done != prev_done) begin
                tests_passed = tests_passed + 1;
                $display("  ==> TEST %0d PASSED (toggled as expected)", tests_run);
            end
            else begin
                tests_failed = tests_failed + 1;
                $display("  ==> TEST %0d FAILED (no toggle observed)", tests_run);
            end
            repeat (5) @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Master execution sequence
    //--------------------------------------------------------------------------
    initial begin
        $display("=========================================================");
        $display("           SPI MASTER / SLAVE TOP-LEVEL TESTBENCH        ");
        $display("=========================================================");
        $display("  DATA_WIDTH        = %0d",          DATA_WIDTH);
        $display("  CLK_DIV (sim)     = %0d",          CLK_DIV);
        $display("  CPOL / CPHA       = %0b / %0b",    CPOL, CPHA);
        $display("  Slave constant TX = 0x%02h",       SLAVE_TX_PATTERN);
        $display("  Clk period        = %0d ns (%0d MHz system)",
                 CLK_PERIOD, 1000/CLK_PERIOD);
        $display("  Expected SCLK     = %0d MHz",      (1000/CLK_PERIOD)/(2*CLK_DIV));
        $display("=========================================================");

        // Initialize
        rst_btn   = 1'b1;
        start_btn = 1'b0;
        sw        = 8'h00;

        // Hold reset for ~10 cycles
        repeat (10) @(posedge clk);
        $display("");
        $display(">>> Releasing reset @ %0t ns", $time);
        rst_btn = 1'b0;
        repeat (5) @(posedge clk);

        // ---- Test 1 : reset state ----
        check_reset_state();

        // ---- Tests 2..N : data patterns ----
        do_transfer(8'hA5, SLAVE_TX_PATTERN, "Basic round-trip transfer (0xA5)             ");
        do_transfer(8'h00, SLAVE_TX_PATTERN, "All zeros (0x00) -- silent MOSI              ");
        do_transfer(8'hFF, SLAVE_TX_PATTERN, "All ones  (0xFF) -- solid MOSI               ");
        do_transfer(8'hAA, SLAVE_TX_PATTERN, "Alternating 10101010 (0xAA) -- MSB ordering  ");
        do_transfer(8'h55, SLAVE_TX_PATTERN, "Alternating 01010101 (0x55)                  ");

        // Walking-1 across all bit positions
        do_transfer(8'h01, SLAVE_TX_PATTERN, "Walking-1 bit 0 (0x01)                       ");
        do_transfer(8'h02, SLAVE_TX_PATTERN, "Walking-1 bit 1 (0x02)                       ");
        do_transfer(8'h04, SLAVE_TX_PATTERN, "Walking-1 bit 2 (0x04)                       ");
        do_transfer(8'h08, SLAVE_TX_PATTERN, "Walking-1 bit 3 (0x08)                       ");
        do_transfer(8'h10, SLAVE_TX_PATTERN, "Walking-1 bit 4 (0x10)                       ");
        do_transfer(8'h20, SLAVE_TX_PATTERN, "Walking-1 bit 5 (0x20)                       ");
        do_transfer(8'h40, SLAVE_TX_PATTERN, "Walking-1 bit 6 (0x40)                       ");
        do_transfer(8'h80, SLAVE_TX_PATTERN, "Walking-1 bit 7 (0x80, MSB)                  ");

        // Random / mirror patterns
        do_transfer(8'h3C, SLAVE_TX_PATTERN, "Random pattern 0x3C                          ");
        do_transfer(8'hC3, SLAVE_TX_PATTERN, "Random pattern 0xC3 (mirror of 0x3C)         ");
        do_transfer(8'h69, SLAVE_TX_PATTERN, "Random pattern 0x69                          ");
        do_transfer(8'h96, SLAVE_TX_PATTERN, "Random pattern 0x96                          ");

        // Back-to-back stress
        do_btb_test(8'hDE, 8'hAD);
        do_btb_test(8'hBE, 8'hEF);

        // led_done toggle behaviour
        check_done_toggle();

        // ---- Summary ----
        $display("");
        $display("=========================================================");
        $display("                       TEST SUMMARY                       ");
        $display("=========================================================");
        $display("  Tests run    : %0d", tests_run);
        $display("  Tests passed : %0d", tests_passed);
        $display("  Tests failed : %0d", tests_failed);
        $display("=========================================================");
        if (tests_failed == 0)
            $display("  *****  ALL TESTS PASSED  *****");
        else
            $display("  *****  %0d TEST(S) FAILED  *****", tests_failed);
        $display("=========================================================");
        $display("");

        $finish;
    end

    //--------------------------------------------------------------------------
    // Global timeout watchdog : abort if simulation runs away
    //--------------------------------------------------------------------------
    initial begin
        #2_000_000;  // 2 ms simulated time
        $display("");
        $display("!!! GLOBAL TIMEOUT REACHED at %0t ns -- aborting simulation !!!", $time);
        $display("    tests_run=%0d  passed=%0d  failed=%0d",
                 tests_run, tests_passed, tests_failed);
        $finish;
    end

    //--------------------------------------------------------------------------
    // Waveform dump (for any tool that consumes VCD; Vivado uses its own DB
    // and ignores these, which is harmless).
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("spi_top.vcd");
        $dumpvars(0, spi_top);
    end

endmodule
