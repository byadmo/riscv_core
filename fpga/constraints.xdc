# Placeholder XDC constraints for FPGA bring-up
# Define clocks and simple I/O mapping per your board
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
# Add real pin mappings when targeting a specific board
