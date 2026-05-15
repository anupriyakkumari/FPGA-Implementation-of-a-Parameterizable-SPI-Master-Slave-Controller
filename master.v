`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 23:04:46
// Design Name: 
// Module Name: master
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

//==============================================================================
// Module      : spi_master
// File        : spi_master.v
// Description : Synthesizable SPI Master Controller
//               - Parameterizable data width and SCLK clock divider
//               - Supports all four SPI modes via CPOL / CPHA parameters
//               - MSB-first, full-duplex (MOSI out and MISO in per bit)
//               - Single system clock domain. SCLK is a *generated signal*,
//                 not a gated clock, so it is FPGA-synthesis friendly.
//               - Synchronous, active-high reset.
//
// Parameters  :
//   DATA_WIDTH : Number of bits per SPI transfer (default 8)
//   CLK_DIV    : System-clock cycles per half-SCLK period (default 4)
//                => SCLK frequency = clk / (2 * CLK_DIV)
//   CPOL       : Clock polarity (idle level of SCLK). 0 = idle low.
//   CPHA       : Clock phase. 0 = sample on leading edge, shift on trailing.
//                              1 = shift on leading edge, sample on trailing.
//
// Ports       :
//   clk      : System clock
//   rst      : Synchronous, active-high reset
//   start    : 1-cycle pulse, asserted while state == IDLE, to begin a transfer
//   tx_data  : Word to transmit on MOSI (latched on start)
//   rx_data  : Word received on MISO; valid when done == 1
//   done     : 1-cycle pulse asserted at end of transfer
//   busy     : High while a transfer is in progress
//   sclk     : SPI serial clock output
//   mosi     : Master Out, Slave In
//   miso     : Master In,  Slave Out
//   ss_n     : Slave select, active low
//
// FSM         : IDLE -> LOAD -> XFER -> DONE -> IDLE
//==============================================================================

`timescale 1ns / 1ps

module master #(
    parameter integer DATA_WIDTH = 8,
    parameter integer CLK_DIV    = 4,
    parameter         CPOL       = 1'b0,
    parameter         CPHA       = 1'b0
)(
    // System
    input  wire                       clk,
    input  wire                       rst,

    // Control / data interface
    input  wire                       start,
    input  wire  [DATA_WIDTH-1:0]     tx_data,
    output reg   [DATA_WIDTH-1:0]     rx_data,
    output reg                        done,
    output reg                        busy,

    // SPI bus
    output reg                        sclk,
    output reg                        mosi,
    input  wire                       miso,
    output reg                        ss_n
);

    //--------------------------------------------------------------------------
    // FSM state encoding
    //--------------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0,
                     S_LOAD = 2'd1,
                     S_XFER = 2'd2,
                     S_DONE = 2'd3;

    reg [1:0] state;

    //--------------------------------------------------------------------------
    // Internal registers
    //   clk_cnt  : counts system clocks within a half-SCLK period
    //   edge_cnt : counts SCLK transitions (2 per data bit -> 2*DATA_WIDTH)
    //   tx_shift : outgoing shift register (MSB-first)
    //   rx_shift : incoming shift register (MSB-first)
    //--------------------------------------------------------------------------
    reg [15:0]              clk_cnt;
    reg [7:0]               edge_cnt;
    reg [DATA_WIDTH-1:0]    tx_shift;
    reg [DATA_WIDTH-1:0]    rx_shift;

    //--------------------------------------------------------------------------
    // Main sequential logic (single always block - FSM + datapath)
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            clk_cnt  <= 16'd0;
            edge_cnt <= 8'd0;
            tx_shift <= {DATA_WIDTH{1'b0}};
            rx_shift <= {DATA_WIDTH{1'b0}};
            rx_data  <= {DATA_WIDTH{1'b0}};
            done     <= 1'b0;
            busy     <= 1'b0;
            sclk     <= CPOL;
            mosi     <= 1'b0;
            ss_n     <= 1'b1;
        end
        else begin
            // Default: done is a 1-cycle pulse
            done <= 1'b0;

            case (state)

                //------------------------------------------------------------------
                // IDLE : wait for start. Bus is parked (SS high, SCLK at idle).
                //------------------------------------------------------------------
                S_IDLE: begin
                    sclk     <= CPOL;
                    ss_n     <= 1'b1;
                    busy     <= 1'b0;
                    clk_cnt  <= 16'd0;
                    edge_cnt <= 8'd0;
                    if (start) begin
                        tx_shift <= tx_data;
                        rx_shift <= {DATA_WIDTH{1'b0}};
                        busy     <= 1'b1;
                        state    <= S_LOAD;
                    end
                end

                //------------------------------------------------------------------
                // LOAD : assert SS_n low, hold SCLK at idle, and for CPHA=0 place
                //        the MSB on MOSI *before* the first SCLK edge.
                //        Spends exactly 1 system-clock in this state, which gives
                //        the slave time to see ss_n fall before SCLK toggles.
                //------------------------------------------------------------------
                S_LOAD: begin
                    ss_n <= 1'b0;
                    sclk <= CPOL;
                    if (CPHA == 1'b0) begin
                        // First bit must be valid before any SCLK transition.
                        mosi     <= tx_shift[DATA_WIDTH-1];
                        tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                    end
                    state <= S_XFER;
                end

                //------------------------------------------------------------------
                // XFER : run the clock divider; every CLK_DIV system clocks we
                //        toggle SCLK and (depending on CPHA / edge parity) either
                //        sample MISO or shift the next MOSI bit out.
                //
                //   edge_cnt[0] == 0 -> we're producing the LEADING edge of a bit
                //   edge_cnt[0] == 1 -> we're producing the TRAILING edge of a bit
                //
                //   CPHA=0 : sample on leading, shift on trailing
                //   CPHA=1 : shift on leading,  sample on trailing
                //
                //   Total SCLK edges per transfer = 2 * DATA_WIDTH.
                //------------------------------------------------------------------
                S_XFER: begin
                    if (clk_cnt == CLK_DIV - 1) begin
                        clk_cnt  <= 16'd0;
                        sclk     <= ~sclk;
                        edge_cnt <= edge_cnt + 1'b1;

                        if (CPHA == 1'b0) begin
                            // CPHA = 0
                            if (edge_cnt[0] == 1'b0) begin
                                // Leading edge -> sample MISO
                                rx_shift <= {rx_shift[DATA_WIDTH-2:0], miso};
                            end
                            else if (edge_cnt != (2*DATA_WIDTH - 1)) begin
                                // Trailing edge -> shift next bit onto MOSI.
                                // Skip on the very last trailing edge (no more bits).
                                mosi     <= tx_shift[DATA_WIDTH-1];
                                tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                            end
                        end
                        else begin
                            // CPHA = 1
                            if (edge_cnt[0] == 1'b0) begin
                                // Leading edge -> shift next bit onto MOSI
                                mosi     <= tx_shift[DATA_WIDTH-1];
                                tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                            end
                            else begin
                                // Trailing edge -> sample MISO
                                rx_shift <= {rx_shift[DATA_WIDTH-2:0], miso};
                            end
                        end

                        // After producing the final edge, finish.
                        if (edge_cnt == (2*DATA_WIDTH - 1)) begin
                            state <= S_DONE;
                        end
                    end
                    else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                //------------------------------------------------------------------
                // DONE : park the bus (SS high, SCLK at idle), latch rx_data,
                //        and pulse done for one cycle.
                //------------------------------------------------------------------
                S_DONE: begin
                    sclk    <= CPOL;
                    ss_n    <= 1'b1;
                    rx_data <= rx_shift;
                    done    <= 1'b1;
                    busy    <= 1'b0;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule


