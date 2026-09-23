# SYNTHESIS-CHECKPOINT HARNESS FILE -- see checkpoints/README.md.
# NOT part of the real design; not Urbana.xdc, not committed there.
#
# 100MHz clock for tradecpu_core_checkpoint's `clk` port (Urbana.xdc's
# own create_clock line is commented out and targets a port name that
# wouldn't exist on tradecpu_core anyway -- see README). Plus DONT_TOUCH
# on the checkpoint wrapper's 3 submodule instances: tradecpu_core_
# checkpoint has no output ports, so even with prog_mem driven, nothing
# in the design provably escapes to an observable pin -- DONT_TOUCH stops
# synthesis from sweeping the whole thing away on that basis. Instance
# names below must match tradecpu_core_checkpoint.v's instantiations.

create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]
set_property DONT_TOUCH true [get_cells u_register_file]
set_property DONT_TOUCH true [get_cells u_alu]
set_property DONT_TOUCH true [get_cells u_control_unit]
