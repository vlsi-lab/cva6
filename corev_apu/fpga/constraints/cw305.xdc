## Clock (PLL_CLK1)
set_property -dict {PACKAGE_PIN N13  IOSTANDARD LVCMOS33} [get_ports clk]

## Buttons
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports cpu_resetn]

## To use Digilent HS2 (no TRST_N connected.)
set_property -dict { PACKAGE_PIN B12  IOSTANDARD LVCMOS33 } [get_ports { tck    }];
set_property -dict { PACKAGE_PIN A13   IOSTANDARD LVCMOS33 } [get_ports { tdo    }];
set_property -dict { PACKAGE_PIN B15   IOSTANDARD LVCMOS33 } [get_ports { tdi    }];
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports { tms    }];

## UART (PMOD USBUART)
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports tx]
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports rx]

## LEDs
set_property -dict {PACKAGE_PIN T4 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T2 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
## Switches
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {sw[2]}]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {sw[3]}]

## SPI
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports {spi_mosi}]
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports {spi_miso}]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports {spi_ss}]
set_property -dict {PACKAGE_PIN F12 IOSTANDARD LVCMOS33} [get_ports {spi_clk_o}]

# Genesys 2 has a quad SPI flash
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]

## Main Clock
create_clock -name sys_clk -waveform {0.0 41.5} -period 83 [get_nets clk]

## JTAG
# minimize routing delay
create_clock -name jtag_clk -waveform {0.0 50.0} -period 100.0 [get_nets tck] 
set_output_delay -clock [get_clocks jtag_clk] -max 10.0   [get_ports { tdo } ] 
set_input_delay -clock [get_clocks jtag_clk] -max 10.0 [get_ports { tms } ] 
set_input_delay -clock [get_clocks jtag_clk] -min 2.0 [get_ports {tms } ]
set_input_delay -clock [get_clocks jtag_clk] -max 10.0 [get_ports { tdi } ] 
set_input_delay -clock [get_clocks jtag_clk] -min 2.0 [get_ports { tdi } ] 

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets tck_IBUF]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]