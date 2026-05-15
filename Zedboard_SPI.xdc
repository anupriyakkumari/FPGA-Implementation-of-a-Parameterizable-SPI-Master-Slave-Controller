## ============================================================================
## Zedboard XDC for spi_top demo
##
## Board   : Avnet / Digilent ZedBoard (Xilinx Zynq-7000 XC7Z020-CLG484-1)
## Top     : spi_top
## Clock   : 100 MHz on-board oscillator -> Y9 (GCLK)
##
## Pin numbers cross-checked against Digilent's official "Zedboard-Master.xdc"
## (digilent-xdc repo, master branch). Bank voltages:
##   - Bank 13 (Pmods, GCLK, OLED, FMC subset)    : fixed 3.3 V -> LVCMOS33
##   - Bank 33 (LEDs LD0..LD7, HDMI, VGA)         : fixed 3.3 V -> LVCMOS33
##   - Bank 34 (Push buttons)                     : 1.8 V default (Vadj/J18)
##                                                  -> LVCMOS18 by default
##   - Bank 35 (DIP switches SW0..SW7)            : 1.8 V default (Vadj/J18)
##                                                  -> LVCMOS18 by default
##
## **CHECK YOUR J18 (Vadj) JUMPER** before programming. The factory default is
## 1.8 V. If yours is set to 2.5 V or 3.3 V you must change every LVCMOS18
## below to LVCMOS25 or LVCMOS33 respectively (or move the jumper back).
##
## --- Trade-off note ----------------------------------------------------------
## Zedboard has only 8 user LEDs (LD0..LD7), but spi_top has 18 output bits
## it would like to display (8 slave_rx + 8 master_rx + busy + done).
## Choices made here:
##
##   On-board LEDs (LD0..LD7) -> led_slave_rx[7:0]
##       The most obviously "vivid" demo: set switches, press BTNC, watch the
##       LEDs change to match. Proves the MASTER -> SLAVE direction works.
##
##   Pmod JB1..JB8           -> led_master_rx[7:0]
##       The byte the master got back from the slave. Should always be
##       1010_0101 (= 0xA5) after a transfer. Attach a Digilent Pmod-8LD or
##       eight jumper-LEDs to JB to see it, or probe with a logic analyzer.
##       This proves the SLAVE -> MASTER direction works.
##
##   Pmod JA1..JA4            -> SPI bus (sclk, mosi, miso, ss_n) for scope
##   Pmod JA7..JA10           -> miso_pad input + busy + done status
##
## If you'd rather see the 0xA5 pattern on the on-board LEDs instead, just
## swap the led_slave_rx and led_master_rx PACKAGE_PIN sections below.
## ============================================================================


## ---------------------------------------------------------------------------
## Clock signal : 100 MHz system clock on Y9 (GCLK, Bank 13)
## ---------------------------------------------------------------------------
set_property PACKAGE_PIN Y9 [get_ports clk]
    set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports clk]


## ---------------------------------------------------------------------------
## DIP Switches : SW0..SW7 -> sw[7:0]  (Bank 35, LVCMOS18 @ Vadj=1.8V)
## ---------------------------------------------------------------------------
set_property PACKAGE_PIN F22 [get_ports {sw[0]}]
set_property PACKAGE_PIN G22 [get_ports {sw[1]}]
set_property PACKAGE_PIN H22 [get_ports {sw[2]}]
set_property PACKAGE_PIN F21 [get_ports {sw[3]}]
set_property PACKAGE_PIN H19 [get_ports {sw[4]}]
set_property PACKAGE_PIN H18 [get_ports {sw[5]}]
set_property PACKAGE_PIN H17 [get_ports {sw[6]}]
set_property PACKAGE_PIN M15 [get_ports {sw[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {sw[*]}]


## ---------------------------------------------------------------------------
## User LEDs : LD0..LD7 -> led_slave_rx[7:0]  (Bank 33, LVCMOS33)
##
## When you press BTNC, these light up to match SW0..SW7. That is your
## "the SPI link works" smoke test: master transmitted what you set, slave
## received it, parallel-side latched it, on board LEDs show it.
## ---------------------------------------------------------------------------
set_property PACKAGE_PIN T22 [get_ports {led_slave_rx[0]}]
set_property PACKAGE_PIN T21 [get_ports {led_slave_rx[1]}]
set_property PACKAGE_PIN U22 [get_ports {led_slave_rx[2]}]
set_property PACKAGE_PIN U21 [get_ports {led_slave_rx[3]}]
set_property PACKAGE_PIN V22 [get_ports {led_slave_rx[4]}]
set_property PACKAGE_PIN W22 [get_ports {led_slave_rx[5]}]
set_property PACKAGE_PIN U19 [get_ports {led_slave_rx[6]}]
set_property PACKAGE_PIN U14 [get_ports {led_slave_rx[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_slave_rx[*]}]


## ---------------------------------------------------------------------------
## Push buttons : BTNC -> start, BTNU -> reset  (Bank 34, LVCMOS18 @ Vadj=1.8V)
## ---------------------------------------------------------------------------
set_property PACKAGE_PIN P16 [get_ports start_btn]
    set_property IOSTANDARD LVCMOS18 [get_ports start_btn]
set_property PACKAGE_PIN T18 [get_ports rst_btn]
    set_property IOSTANDARD LVCMOS18 [get_ports rst_btn]


## ---------------------------------------------------------------------------
## Pmod JB : led_master_rx[7:0]   (Bank 13, LVCMOS33)
##
## Attach a Digilent Pmod 8LD here (or jumper 8 LED+resistors to ground)
## to physically see the byte the master received from the slave. After
## a transfer this should always be 1010_0101 (0xA5) = pins
## JB8, JB6 (no, see below), JB3, JB1 lit.  Map (Pmod pin index : signal):
##   JB1=W12   -> led_master_rx[0]
##   JB2=W11   -> led_master_rx[1]
##   JB3=V10   -> led_master_rx[2]
##   JB4=W8    -> led_master_rx[3]
##   JB7=V12   -> led_master_rx[4]
##   JB8=W10   -> led_master_rx[5]
##   JB9=V9    -> led_master_rx[6]
##   JB10=V8   -> led_master_rx[7]
## ---------------------------------------------------------------------------
set_property PACKAGE_PIN W12 [get_ports {led_master_rx[0]}]
set_property PACKAGE_PIN W11 [get_ports {led_master_rx[1]}]
set_property PACKAGE_PIN V10 [get_ports {led_master_rx[2]}]
set_property PACKAGE_PIN W8  [get_ports {led_master_rx[3]}]
set_property PACKAGE_PIN V12 [get_ports {led_master_rx[4]}]
set_property PACKAGE_PIN W10 [get_ports {led_master_rx[5]}]
set_property PACKAGE_PIN V9  [get_ports {led_master_rx[6]}]
set_property PACKAGE_PIN V8  [get_ports {led_master_rx[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_master_rx[*]}]


## ---------------------------------------------------------------------------
## Pmod JA : SPI bus probing + busy / done status  (Bank 13, LVCMOS33)
##
##   JA1  = Y11   -> sclk_o      (1 MHz with CLK_DIV=50 @ 100 MHz clk)
##   JA2  = AA11  -> mosi_o
##   JA3  = Y10   -> miso_o      (driven by the on-chip slave)
##   JA4  = AA9   -> ss_n_o
##   JA7  = AB11  -> miso_pad    (external MISO input, unused in loopback)
##   JA8  = AB10  -> led_busy    (8 us pulse per transfer; scope-visible)
##   JA9  = AB9   -> led_done    (TOGGLES each completed transfer - tie a
##                                jumper-LED here and it will flip on every
##                                BTNC press, even though it's a Pmod pin)
##   JA10 = AA8   -> (unused)
## ---------------------------------------------------------------------------
set_property PACKAGE_PIN Y11  [get_ports sclk_o]
set_property PACKAGE_PIN AA11 [get_ports mosi_o]
set_property PACKAGE_PIN Y10  [get_ports miso_o]
set_property PACKAGE_PIN AA9  [get_ports ss_n_o]
set_property PACKAGE_PIN AB11 [get_ports miso_pad]
set_property PACKAGE_PIN AB10 [get_ports led_busy]
set_property PACKAGE_PIN AB9  [get_ports led_done]

set_property IOSTANDARD LVCMOS33 \
    [get_ports {sclk_o mosi_o miso_o ss_n_o miso_pad led_busy led_done}]

## miso_pad is not driven anywhere in the loopback demo. Give it a defined
## level so it doesn't float and burn power.
set_property PULLDOWN TRUE [get_ports miso_pad]


## ---------------------------------------------------------------------------
## Bitstream / configuration
## ---------------------------------------------------------------------------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]


## ---------------------------------------------------------------------------
## Timing exceptions
##
## The SPI bus signals only drive header pins for probing; the real
## master <-> slave handshake happens inside one clock domain. Don't let
## STA flag meaningless I/O delay violations on these.
## ---------------------------------------------------------------------------
set_false_path -to   [get_ports {sclk_o mosi_o ss_n_o miso_o \
                                 led_busy led_done             \
                                 led_slave_rx[*] led_master_rx[*]}]
set_false_path -from [get_ports miso_pad]
set_false_path -from [get_ports {rst_btn start_btn sw[*]}]
