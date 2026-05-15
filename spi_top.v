`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 23:14:25
// Design Name: 
// Module Name: spi_top
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
// Company:
// Engineer:
//
// Create Date: 11.05.2026 22:50:41
// Design Name:
// Module Name: top
// Project Name: spi_fpga
// Target Devices:
// Tool Versions:
// Description:
//   Top-level wrapper that demonstrates the SPI link on an FPGA by instantiating
//   the `master` and `slave` modules from master.v / slave.v and wiring their
//   SPI buses together internally.
//
//   Demo behaviour:
//     - sw[7:0]       : data the MASTER will transmit on MOSI to the slave
//     - start_btn     : push button -> single-shot SPI transfer
//     - rst_btn       : push button -> synchronous reset
//     - The SLAVE always replies with the constant SLAVE_TX_PATTERN (default 0xA5)
//       so the master's rx_data can also be observed.
//     - led_slave_rx  : last byte the SLAVE received (should match sw after a xfer)
//     - led_master_rx : last byte the MASTER received from the slave (= 0xA5)
//     - led_busy      : asserted while a transfer is in progress
//     - led_done      : toggles on each completed master transfer (visible blink)
//     - sclk_o / mosi_o / miso_o / ss_n_o : SPI bus brought out to pins for
//                       optional scope / logic-analyzer probing
//
//   Mapping the parameter CLK_DIV to a real FPGA: on a 100 MHz board,
//   CLK_DIV = 50 gives an SCLK of 100 MHz / (2 * 50) = 1 MHz, which is slow
//   enough to be observed on a basic logic analyzer or even toggled to LEDs.
//
// Dependencies:
//   - master.v (module `master`)
//   - slave.v  (module `slave`)
//
// Revision:
// Revision 0.02 - Top module implemented for SPI master/slave demo
//////////////////////////////////////////////////////////////////////////////////


module spi_top #(
    parameter integer DATA_WIDTH       = 8,
    // 100 MHz / (2 * CLK_DIV) = SCLK frequency.
    // CLK_DIV >= 2 is required by the slave (see slave.v header).
    parameter integer CLK_DIV          = 50,
    parameter         CPOL             = 1'b0,
    parameter         CPHA             = 1'b0,
    // Constant pattern the slave sends back to the master.
    parameter [DATA_WIDTH-1:0] SLAVE_TX_PATTERN = 8'hA5
)(
    // System
    input  wire                       clk,            // FPGA board clock
    input  wire                       rst_btn,        // Active-high reset push button
    input  wire                       start_btn,      // Active-high start push button

    // Parallel data input from board switches
    input  wire [DATA_WIDTH-1:0]      sw,             // Master TX data

    // LED status / data outputs
    output wire [DATA_WIDTH-1:0]      led_slave_rx,   // What the slave received
    output wire [DATA_WIDTH-1:0]      led_master_rx,  // What the master received
    output wire                       led_busy,       // Master busy
    output wire                       led_done,       // Toggles on every transfer

    // SPI bus signals brought out to pins (for probing / debugging)
    output wire                       sclk_o,
    output wire                       mosi_o,
    input  wire                       miso_pad,       // Tie unused or leave floating
    output wire                       miso_o,         // For probing internal miso
    output wire                       ss_n_o
);

    //--------------------------------------------------------------------------
    // Reset synchronizer (2-FF). Keeps the synchronous reset clean even if the
    // raw button is asynchronous to clk.
    //--------------------------------------------------------------------------
    reg [1:0] rst_sync;
    wire      rst;

    always @(posedge clk) begin
        rst_sync <= {rst_sync[0], rst_btn};
    end
    assign rst = rst_sync[1];

    //--------------------------------------------------------------------------
    // Start button: synchronize, then rising-edge detect, then gate with !busy
    // so a single press triggers exactly one transfer and bounces during a
    // transfer are ignored.
    //--------------------------------------------------------------------------
    reg [2:0] start_sync;
    wire      master_busy;
    wire      start_edge;
    wire      start_pulse;

    always @(posedge clk) begin
        if (rst)
            start_sync <= 3'b000;
        else
            start_sync <= {start_sync[1:0], start_btn};
    end

    // Rising edge on the synchronized button
    assign start_edge  = start_sync[1] & ~start_sync[2];
    // Only fire when the master is idle (gate by !busy)
    assign start_pulse = start_edge & ~master_busy;

    //--------------------------------------------------------------------------
    // SPI bus nets (master drives sclk/mosi/ss_n, slave drives miso)
    //--------------------------------------------------------------------------
    wire                  sclk_int;
    wire                  mosi_int;
    wire                  miso_int;
    wire                  ss_n_int;

    //--------------------------------------------------------------------------
    // Master parallel-side wires
    //--------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] master_rx_data;
    wire                  master_done;

    //--------------------------------------------------------------------------
    // Slave parallel-side wires
    //--------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] slave_rx_data;
    wire                  slave_rx_valid;

    //--------------------------------------------------------------------------
    // SPI MASTER instance
    //   - Parameters must match the slave's CPOL/CPHA/DATA_WIDTH.
    //--------------------------------------------------------------------------
    master #(
        .DATA_WIDTH (DATA_WIDTH),
        .CLK_DIV    (CLK_DIV),
        .CPOL       (CPOL),
        .CPHA       (CPHA)
    ) u_master (
        .clk     (clk),
        .rst     (rst),
        .start   (start_pulse),
        .tx_data (sw),
        .rx_data (master_rx_data),
        .done    (master_done),
        .busy    (master_busy),
        .sclk    (sclk_int),
        .mosi    (mosi_int),
        .miso    (miso_int),
        .ss_n    (ss_n_int)
    );

    //--------------------------------------------------------------------------
    // SPI SLAVE instance
    //   - tx_data is held constant; the slave latches it on the falling edge
    //     of ss_n (see slave.v IDLE state).
    //--------------------------------------------------------------------------
    slave #(
        .DATA_WIDTH (DATA_WIDTH),
        .CPOL       (CPOL),
        .CPHA       (CPHA)
    ) u_slave (
        .clk      (clk),
        .rst      (rst),
        .tx_data  (SLAVE_TX_PATTERN),
        .rx_data  (slave_rx_data),
        .rx_valid (slave_rx_valid),
        .sclk     (sclk_int),
        .mosi     (mosi_int),
        .miso     (miso_int),
        .ss_n     (ss_n_int)
    );

    //--------------------------------------------------------------------------
    // Latch received data into registers for LED display.
    //   - master_done is a 1-cycle pulse from the master at end of transfer.
    //   - slave_rx_valid is a 1-cycle pulse from the slave at end of word.
    //   - led_done toggles each completed transfer so it is visible as a blink.
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] master_rx_reg;
    reg [DATA_WIDTH-1:0] slave_rx_reg;
    reg                  done_toggle;

    always @(posedge clk) begin
        if (rst) begin
            master_rx_reg <= {DATA_WIDTH{1'b0}};
            slave_rx_reg  <= {DATA_WIDTH{1'b0}};
            done_toggle   <= 1'b0;
        end
        else begin
            if (master_done) begin
                master_rx_reg <= master_rx_data;
                done_toggle   <= ~done_toggle;
            end
            if (slave_rx_valid) begin
                slave_rx_reg  <= slave_rx_data;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Output assignments
    //--------------------------------------------------------------------------
    assign led_master_rx = master_rx_reg;
    assign led_slave_rx  = slave_rx_reg;
    assign led_busy      = master_busy;
    assign led_done      = done_toggle;

    // Expose the (internal) SPI bus on package pins for scope probing.
    // miso_pad is provided so a synthesis tool will not optimize an input
    // port away; it is unused in the loopback demo.
    assign sclk_o = sclk_int;
    assign mosi_o = mosi_int;
    assign miso_o = miso_int;
    assign ss_n_o = ss_n_int;

    // Keep miso_pad in the netlist (no-op tie). Slave's miso drives the bus.
    // synthesis translate_off
    wire _unused_miso_pad = miso_pad;
    // synthesis translate_on

endmodule
