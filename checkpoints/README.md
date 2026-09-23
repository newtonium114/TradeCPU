# checkpoints/

A read-only Vivado synthesis/timing sanity-check harness for `tradecpu_core`
at a given stage. **Not part of the real design** -- nothing in `rtl/` or
`sim/` depends on anything here, and nothing here is wired into the actual
Vivado project long-term (a checkpoint run adds these files to the project
temporarily, then removes them again when it's done).

## Why this exists

Plain top-level synthesis of `tradecpu_core` sweeps the **entire** design
away to 0 cells. `control_unit`'s `prog_mem` array is never written in
synthesizable RTL -- only testbenches poke it via hierarchical reference
(simulation-only), and real program loading is Stage 6's UART-loader job.
With no driver, Vivado's synthesis treats every `prog_mem` read as a
constant and collapses everything downstream -- the whole FSM, decode
logic, PC control -- as dead logic. `tradecpu_core` also has no output
ports yet (no UART/debug output), so even once `prog_mem` has content,
nothing else in the design provably escapes to an observable pin either.

This harness works around both problems without touching a single line of
`rtl/control_unit.v` or `rtl/tradecpu_core.v`:

- `control_unit_checkpoint.v` -- a snapshot of `rtl/control_unit.v`
  (as of Stage 2), renamed `control_unit_checkpoint`, with exactly one
  addition: an `initial $readmemh` block that preloads `prog_mem` from
  the paired `.hex` file. Plain Verilog has no way for an *external*
  module to drive another module's private internal array, so giving
  `prog_mem` real content requires the `$readmemh` to live in the same
  module scope that declares it -- hence the clone instead of a wrapper
  reaching in from outside.
- `tradecpu_core_checkpoint.v` -- wires the **real, unmodified**
  `rtl/register_file.v` and `rtl/alu.v` to `control_unit_checkpoint.v`
  (not the real `rtl/control_unit.v`). This is the synthesis top for a
  checkpoint run.
- `tradecpu_stage2_checkpoint.hex` -- hand-assembled instruction words
  covering every opcode Stage 2 added (`LOAD_IMM`/`JMP`/`JMP_IF`, plus
  Stage 1's `ADD`/`SUB`/`CMP_GT`), so no decode branch looks
  dead-code-eliminable to synthesis. Reuses `sim/tb_stage2_core.v`'s
  if/else and backward-loop programs directly. Only ~28 of `prog_mem`'s
  512 addresses are populated -- the rest are don't-care. **Because of
  that, synthesis is likely to implement `prog_mem` as combinational
  constant-select logic rather than infer real Block RAM, and
  `control_unit`'s reported resource usage will underestimate Stage 6's
  real footprint** (once `prog_mem` gets a genuine read/write port with
  unconstrained runtime content). Treat these numbers as a floor, not a
  final figure.
- `checkpoint_clk_and_dont_touch.xdc` -- a 100MHz `create_clock` on
  `tradecpu_core_checkpoint`'s `clk` port (`Urbana.xdc`'s own clock line
  is commented out and targets a port name that wouldn't exist on
  `tradecpu_core` anyway -- see "Known outstanding issue" below), plus
  `DONT_TOUCH` on the checkpoint wrapper's 3 submodule instances so
  synthesis doesn't sweep them away for lack of an observable top-level
  output.

## Before reusing at a later stage

These files are **frozen snapshots** -- they go stale the moment
`rtl/control_unit.v` changes (new opcodes, FSM changes, wider fields,
etc). Before reusing at Stage 3+:

1. Copy the *current* `rtl/control_unit.v` over `control_unit_checkpoint.v`,
   rename the module to `control_unit_checkpoint`, and re-add the single
   `initial $readmemh` block (see the existing file for the exact
   placement -- right after `prog_mem`'s declaration).
2. Hand-assemble a short program covering every opcode the new stage
   added (reuse the relevant `sim/tb_stageN_core.v`'s instruction
   encodings where possible, the same way this Stage 2 checkpoint reused
   `tb_stage2_core.v`'s), write it to a new
   `tradecpu_stageN_checkpoint.hex`, and update the `$readmemh` path in
   `control_unit_checkpoint.v` to point at it.
3. `tradecpu_core_checkpoint.v` and `checkpoint_clk_and_dont_touch.xdc`
   don't need changes unless port names or instance names change.

## How to re-run it

Non-interactive, via Vivado's Tcl console (never edit `Trade_CPU.xpr` by
hand):

```
"<vivado install>/bin/vivado.bat" -mode batch -source run_checkpoint.tcl
```

where `run_checkpoint.tcl` is:

```tcl
set proj_path  {<repo>/Trade_CPU vivado/Trade_CPU.xpr}
set ckpt_dir   {<repo>/checkpoints}
set report_dir {<wherever you want the .rpt files written>}

open_project $proj_path

add_files -norecurse [list \
    "$ckpt_dir/control_unit_checkpoint.v" \
    "$ckpt_dir/tradecpu_core_checkpoint.v" \
]
add_files -fileset constrs_1 -norecurse "$ckpt_dir/checkpoint_clk_and_dont_touch.xdc"

set_property top tradecpu_core_checkpoint [current_fileset]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

open_run synth_1 -name synth_1
set cell_count [llength [get_cells -hierarchical]]
puts "CELL_COUNT_AFTER_SYNTH: $cell_count"
report_utilization -file "$report_dir/synth_utilization.rpt"
report_utilization -hierarchical -file "$report_dir/synth_utilization_hier.rpt"
close_design

if {$cell_count > 0} {
    reset_run impl_1
    launch_runs impl_1 -jobs 4
    wait_on_run impl_1

    open_run impl_1 -name impl_1
    report_timing_summary -file "$report_dir/impl_timing_summary.rpt" -max_paths 10
    report_utilization -file "$report_dir/impl_utilization.rpt"
    close_design
} else {
    puts "SKIPPING_IMPL_STILL_EMPTY -- prog_mem is probably undriven again, check the readmemh path"
}

# restore the project to point at the real design again -- don't leave
# the checkpoint files/top wired into the project long-term
remove_files "$ckpt_dir/checkpoint_clk_and_dont_touch.xdc"
remove_files [list \
    "$ckpt_dir/control_unit_checkpoint.v" \
    "$ckpt_dir/tradecpu_core_checkpoint.v" \
]
set_property top tradecpu_core [current_fileset]
update_compile_order -fileset sources_1

close_project
```

This does **not** generate a bitstream -- `launch_runs impl_1` alone stops
after `route_design`.

Notes:
- Close Vivado's GUI first if the project is open there -- a second batch
  process against the same `.xpr` will conflict.
- The `cell_count` check matters: if it comes back 0, something (usually a
  stale `$readmemh` path after regenerating the checkpoint, or an
  un-renamed module) is still leaving `prog_mem` undriven, and
  `place_design` will fail with "the design is empty" if you proceed to
  implementation anyway.
- Expect roughly 100+ "Critical Warnings" from `Urbana.xdc` board-pin
  mismatches (`SW`/`LED`/`BTN`/7-segment ports that don't exist on
  `tradecpu_core`) -- that's expected noise, not a real issue.

## Known outstanding issue (flagged, not fixed here)

`Urbana.xdc`'s own `create_clock` line is commented out
(`#create_clock -period 10.000 -name gclk [get_ports clk_100MHz]`) and
even active would target a port name (`clk_100MHz`) that doesn't exist on
`tradecpu_core` anyway -- only the physical `CLK_100MHZ` pin assignment is
active. This needs a real fix before Stage 6 hardware bring-up. It isn't
blocking these checkpoints since `checkpoint_clk_and_dont_touch.xdc`
supplies its own clock constraint targeting the right port name.
