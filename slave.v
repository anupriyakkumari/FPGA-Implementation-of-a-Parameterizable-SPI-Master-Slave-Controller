`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 23:05:58
// Design Name: 
// Module Name: slave
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created/ Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//==============================================================================
// Module      : spi_slave
// File        : spi_slave.v
// Description : Synthesizable SPI Slave Controller
//               - Parameterizable data width
//               - Supports all four SPI modes via CPOL / CPHA parameters
//                 (must match the master)
//               - MSB-first, full-duplex
//               - Single system clock domain. SCLK, SS_n and MOSI are
//                 sampled by clk and edge-detected. SCLK is NOT used as
//                 a clock anywhere in this module - this avoids any
//                 gated / external clock issues on the FPGA.
//               - Synchronous, active-high reset.
//
// IMPORTANT   : This module assumes its SPI inputs are synchronous to clk,
//               i.e. driven by spi_master on the same FPGA running off the
//               same clk. For an off-chip / asynchronous master, add an
//               additional flop stage in front of the edge detect to handle
//               metastability.
//
// Timing      : With the matching spi_master.v, use CLK_DIV >= 2 to give
//               this slave enough setup time to drive the first MISO bit
//               (CPHA=0) before the master samples it.
//
// Parameters  :
//   DATA_WIDTH : Number of bits per SPI transfer (default 8)
//   CPOL       : Clock polarity (idle level of SCLK). Must match master.
//   CPHA       : Clock phase.                       Must match master.
//
// Ports       :
//   clk      : System clock (same domain as the master)
//   rst      : Synchronous, active-high reset
//   tx_data  : Word to transmit back to master on MISO. Latched at ss_n fall.
//   rx_data  : Word received from master on MOSI. Valid when rx_valid=1.
//   rx_valid : 1-cycle pulse when a full word has been received
//   sclk     : SPI serial clock (input, from master)
//   mosi     : Master Out, Slave In (input)
//   miso     : Master In,  Slave Out (output, driven by this slave)
//   ss_n     : Slave select, active low (input)
//
// FSM         : IDLE -> XFER -> IDLE
//==============================================================================

`timescale 1ns / 1ps

module slave #(
    parameter integer DATA_WIDTH = 8,
    parameter         CPOL       = 1'b0,
    parameter         CPHA       = 1'b0
)(
    // System
    input  wire                       clk,
    input  wire                       rst,

    // Parallel data interface
    input  wire  [DATA_WIDTH-1:0]     tx_data,
    output reg   [DATA_WIDTH-1:0]     rx_data,
    output reg                        rx_valid,

    // SPI bus
    input  wire                       sclk,
    input  wire                       mosi,
    output reg                        miso,
    input  wire                       ss_n
);

    //--------------------------------------------------------------------------
    // Input sampling for edge detection.
    // Single stage because sclk / ss_n are synchronous to clk in this design.
    // (Add another stage in front of these if you ever drive this slave
    //  from an off-chip / async master.)
    //--------------------------------------------------------------------------
    reg sclk_q;
    reg ss_n_q;

    always @(posedge clk) begin
        if (rst) begin
            sclk_q <= CPOL;
            ss_n_q <= 1'b1;
        end
        else begin
            sclk_q <= sclk;
            ss_n_q <= ss_n;
        end
    end

    // Edge pulses (1 system clock wide, in the cycle after the input changes)
    wire sclk_rise = sclk    & ~sclk_q;
    wire sclk_fall = ~sclk   &  sclk_q;
    wire ss_n_fall = ~ss_n   &  ss_n_q;

    // Leading / trailing SCLK edges, mapped by CPOL
    wire leading_edge  = (CPOL == 1'b0) ? sclk_rise : sclk_fall;
    wire trailing_edge = (CPOL == 1'b0) ? sclk_fall : sclk_rise;

    //--------------------------------------------------------------------------
    // FSM and datapath
    //   edge_cnt : counts SCLK transitions seen (0 .. 2*DATA_WIDTH-1)
    //   tx_shift : outgoing shift register (MSB-first)
    //   rx_shift : incoming shift register (MSB-first)
    //--------------------------------------------------------------------------
    localparam S_IDLE = 1'b0,
               S_XFER = 1'b1;

    reg                     state;
    reg  [DATA_WIDTH-1:0]   tx_shift;
    reg  [DATA_WIDTH-1:0]   rx_shift;
    reg  [7:0]              edge_cnt;

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            tx_shift <= {DATA_WIDTH{1'b0}};
            rx_shift <= {DATA_WIDTH{1'b0}};
            rx_data  <= {DATA_WIDTH{1'b0}};
            edge_cnt <= 8'd0;
            rx_valid <= 1'b0;
            miso     <= 1'b0;
        end
        else begin
            // Default: rx_valid is a 1-cycle pulse
            rx_valid <= 1'b0;

            case (state)

                //------------------------------------------------------------------
                // IDLE : park, wait for SS_n falling edge.
                //------------------------------------------------------------------
                S_IDLE: begin
                    edge_cnt <= 8'd0;
                    rx_shift <= {DATA_WIDTH{1'b0}};
                    if (ss_n_fall) begin
                        // Latch outgoing word from the parallel side.
                        tx_shift <= tx_data;
                        if (CPHA == 1'b0) begin
                            // CPHA=0 : first MISO bit must be valid BEFORE
                            // the first SCLK edge. Drive MSB now; pre-shift
                            // tx_shift so the next trailing edge presents bit
                            // [DATA_WIDTH-2] without further bookkeeping.
                            miso     <= tx_data[DATA_WIDTH-1];
                            tx_shift <= {tx_data[DATA_WIDTH-2:0], 1'b0};
                        end
                        state <= S_XFER;
                    end
                end

                //------------------------------------------------------------------
                // XFER : shift on every detected SCLK edge.
                //
                //   CPHA=0 : sample MOSI on leading edge,
                //            drive next MISO bit on trailing edge
                //   CPHA=1 : drive next MISO bit on leading edge,
                //            sample MOSI on trailing edge
                //
                //   2*DATA_WIDTH edges per transfer.
                //------------------------------------------------------------------
                S_XFER: begin
                    // Master deasserted SS_n -> finish immediately.
                    if (ss_n_q == 1'b1) begin
                        state <= S_IDLE;
                    end
                    else if (leading_edge || trailing_edge) begin
                        edge_cnt <= edge_cnt + 1'b1;

                        if (CPHA == 1'b0) begin
                            // ----- CPHA = 0 -----
                            if (leading_edge) begin
                                // Sample MOSI bit.
                                rx_shift <= {rx_shift[DATA_WIDTH-2:0], mosi};
                                // Last sample is the (DATA_WIDTH)-th leading edge,
                                // which is at edge_cnt = 2*DATA_WIDTH - 2.
                                if (edge_cnt == (2*DATA_WIDTH - 2)) begin
                                    rx_data  <= {rx_shift[DATA_WIDTH-2:0], mosi};
                                    rx_valid <= 1'b1;
                                end
                            end
                            else if (edge_cnt != (2*DATA_WIDTH - 1)) begin
                                // Trailing edge -> drive next MISO bit.
                                // Skip on the very last trailing edge: nothing
                                // more to send and master is about to deassert.
                                miso     <= tx_shift[DATA_WIDTH-1];
                                tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                            end
                        end
                        else begin
                            // ----- CPHA = 1 -----
                            if (leading_edge) begin
                                // Drive next MISO bit.
                                miso     <= tx_shift[DATA_WIDTH-1];
                                tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                            end
                            else begin
                                // Trailing edge -> sample MOSI.
                                rx_shift <= {rx_shift[DATA_WIDTH-2:0], mosi};
                                if (edge_cnt == (2*DATA_WIDTH - 1)) begin
                                    rx_data  <= {rx_shift[DATA_WIDTH-2:0], mosi};
                                    rx_valid <= 1'b1;
                                end
                            end
                        end

                        // End of byte
                        if (edge_cnt == (2*DATA_WIDTH - 1)) begin
                            state <= S_IDLE;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

