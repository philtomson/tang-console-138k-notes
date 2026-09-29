create_clock -name sys_clk -period 20.000 [get_ports {clk}]
create_clock -name memory_clock -period 2.500 [get_nets {memory_clk}]
create_clock -name controller_clock -period 10.000 [get_pins {u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]
set_clock_groups -asynchronous -group [get_clocks {memory_clock}] -group [get_clocks {controller_clock}] -group [get_clocks {sys_clk}]
