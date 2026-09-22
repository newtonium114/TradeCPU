# TradeCPU Build Roadmap

Guiding principle: get something **end-to-end and stupidly simple** working
first (blink an LED based on a hardcoded bytecode program), then widen scope.
Never spend more than half a day on any one piece before wiring it into the
full pipeline, even badly.

Assumes a ~48hr hackathon. Adjust proportionally if you have less time.

---

## Phase 0 — Environment setup (do this BEFORE the hackathon starts)

**Goal:** Vivado installed, board recognized, a trivial design loads onto it.

1. Install Vivado ML Edition (WebPACK, free) — large download, budget real time
2. Get Real Digital's Urbana board files added to Vivado so it recognizes the
   board (not just a generic XC7S50 part)
3. Confirm your USB cable/connector and get power + programming working
4. Load the simplest possible "hello world" — a counter driving an LED, or
   Real Digital's example blink project — just to prove the toolchain works
5. Set up a serial terminal tool (PuTTY, screen, or Python `pyserial`) and
   confirm you can see UART output from the board

**Do not start this during the hackathon.** Toolchain/driver issues eat hours
and have nothing to do with your actual project.

---

## Phase 1 — Minimal CPU core, simulated only (Hours 0–6)

**Goal:** fetch-decode-execute loop working in Vivado's simulator, no board yet.

Start with the smallest possible instruction subset:
- `NOP`, `LOAD_IMM`, `MOV`, `HALT`

Build:
1. Register file (8 x 16-bit registers)
2. Program counter + simple fetch logic (read from a small BRAM/array you
   initialize by hand in the testbench, not via UART yet)
3. Decode logic (case statement on opcode bits)
4. Execute logic for just these 4 instructions
5. A testbench that loads a hand-written 5-instruction program and checks
   register values at the end

**Milestone check:** can you simulate a program that loads a value into R1 and
halts, and see the correct value in the waveform viewer? If yes, move on —
resist the urge to add more opcodes yet.

---

## Phase 2 — Expand the instruction set (Hours 6–14)

**Goal:** full ISA implemented and passing simulation tests.

Add incrementally, testing each before moving to the next:
1. `ADD`, `SUB` (arithmetic)
2. `CMP_GT`, `CMP_LT` (comparisons)
3. `JMP`, `JMP_IF` (control flow — this is where FSM bugs tend to hide, budget
   extra time)
4. `LOAD_PRICE`, `LOAD_IND` (reads from a small register-mapped "symbol table"
   — for now, hardcode fake price/indicator values in the testbench)
5. `BUY`, `SELL` (write to an output register or FIFO you can observe)

**Milestone check:** simulate the RSI example program from the ISA doc end to
end — confirm it produces the correct BUY or SELL signal for different
hardcoded RSI inputs.

---

## Phase 3 — Get the CPU running on real hardware (Hours 14–20)

**Goal:** same program, but actually running on the Urbana board, with
hardcoded/testbench-driven program memory replaced by something you can load.

1. Synthesize and implement the Phase 2 design, program the board
2. Hardcode ONE test program directly into BRAM at synthesis time (via
   `$readmemh` or an initial block) — don't build the UART loader yet
3. Wire `BUY`/`SELL` outputs to LEDs so you can visually confirm correct
   execution without needing UART working yet
4. Confirm on real hardware: power cycle, program loads, correct LED behavior

**This is your first "it's alive" moment** — a hardcoded strategy visibly
producing buy/sell decisions on real silicon. If you run out of time later,
this alone with a rehearsed explanation is a legitimate demo.

---

## Phase 4 — UART program loader (Hours 20–28)

**Goal:** load new bytecode into program memory over UART without resynthesizing.

1. Design a dead-simple loading protocol: e.g., host sends a start byte, a
   16-bit length, then that many bytes of program data; CPU writes them
   sequentially into program BRAM
2. Implement the UART receiver (Spartan-7 doesn't have hardware UART — you
   need a simple RX shift-register module; there are well-known reference
   designs for this, don't build it from scratch if you can avoid it)
3. Write a tiny Python script on the host side that sends a hand-crafted byte
   array over serial
4. Confirm: send a NEW program over UART (different from the hardcoded one),
   watch LED behavior change without touching Vivado again

**Milestone check:** this is the single most important "wow" moment in your
whole demo — reprogramming behavior in milliseconds, no reflash. Get this
working even with a crude/manual byte array before touching the compiler.

---

## Phase 5 — Tick streaming (Hours 28–34)

**Goal:** price/indicator values also come from the host over UART, not
hardcoded, so the demo can show live-ish data driving decisions.

1. Extend the UART protocol: a separate message type for "here's a new tick"
   (symbol id, price, indicator values)
2. CPU's symbol table register-file updates when a tick message arrives
3. Python host script reads from a CSV of historical prices (or just
   generates synthetic ticks) and streams them at a demo-friendly pace
   (e.g., one tick per second, not real market speed)

**Milestone check:** feed a sequence of ticks that cross your RSI thresholds,
watch the board buy/sell in response, live.

---

## Phase 6 — Retarget the BabyQuant compiler (Hours 34–42)

**Goal:** Blockly block tree → bytecode, instead of hand-crafted byte arrays.

1. In `src/frontend/src/generators/`, add a new generator alongside the
   existing Python one — same block-walking logic, different emission target
2. Map each block type to bytecode per the table in the ISA doc (comparison
   blocks → `CMP_GT`/`CMP_LT`, if blocks → `JMP_IF` + label resolution, etc.)
3. Handle jump target resolution — you'll likely do a simple two-pass
   assembler: first pass emits instructions with placeholder addresses and
   records label positions, second pass fills in real addresses
4. Output: a byte array your Phase 4 UART loader can send directly

**This is the highest-risk phase for scope creep.** Support only the blocks
you actually need for your demo strategy — don't try to handle every possible
BabyQuant block type.

**Fallback if this runs long:** keep a hand-written bytecode assembler (even
just a Python dict-based one, not touching the Blockly frontend at all) as
your backup. A working hand-assembled demo beats a half-working compiler.

---

## Phase 7 — Integration + demo polish (Hours 42–48)

**Goal:** the full pipeline works reliably, and you can present it clearly.

1. Full run-through: drag blocks → compile → UART → FPGA executes → visible
   output, at least 3 times in a row without manual intervention
2. Add a simple visualization on the host side (even a basic terminal log or
   a small web page showing tick-by-tick decisions) — judges respond well to
   seeing the live decision stream, not just LEDs
3. Prepare a fallback: record a video of it working, in case live demo WiFi/
   hardware gremlins strike
4. Rehearse the explanation: ISA design choices, why bytecode reload beats
   resynthesis, what the compiler retargeting actually did

---

## Time budget summary

| Phase | Hours | Cumulative |
|---|---|---|
| 0 — Setup (pre-hackathon) | — | — |
| 1 — Minimal CPU, simulated | 6 | 6 |
| 2 — Full ISA, simulated | 8 | 14 |
| 3 — Running on hardware (hardcoded program) | 6 | 20 |
| 4 — UART program loader | 8 | 28 |
| 5 — Tick streaming | 6 | 34 |
| 6 — Compiler retarget | 8 | 42 |
| 7 — Integration + polish | 6 | 48 |

## Fallback checkpoints (what to demo if you run out of time)

- **Worst case (through Phase 3 only):** hardcoded strategy running live on
  hardware, LEDs showing buy/sell. Still a real hardware demo.
- **Middle case (through Phase 5):** live reprogramming over UART + live tick
  streaming, driven by hand-crafted bytecode. This is already a strong demo —
  the compiler is a "and here's how you'd generate this automatically" story
  told with slides/code walkthrough if Phase 6 doesn't finish.
- **Best case (through Phase 7):** full drag-blocks-to-hardware pipeline live.

Each checkpoint is independently demoable — that's the point of this ordering.
