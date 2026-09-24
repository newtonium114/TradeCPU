# TradeCPU Full System Specification

This document is self-contained: a reader with no prior context should be
able to build the RTL, the assembler/golden model, and the UART protocol
from this alone. Where a decision wasn't explicitly settled in earlier
discussion, a specific default is chosen here and flagged with **[DECISION]**
so it can be revisited, but nothing is left ambiguous.

---

## 1. Global parameters

| Parameter | Value |
|---|---|
| General-purpose registers | R0–R7 (8 total), **32-bit signed**, two's complement |
| Balance register | 1 dedicated register, `BALANCE`, 32-bit signed |
| Variable store | `VAR[0..14]` — 15 slots, **16-bit signed** each |
| Stock buffers | 5 buffers, `BUF[0..4]`, each a 30-entry circular buffer of **16-bit signed** integers |
| Program memory | 512 instruction words × 32 bits (loaded via UART) |
| Instruction word width | 32 bits (fixed); some instructions use a second 32-bit word for a 16-bit immediate |
| Target clock frequency | 50 MHz (revisit after Stage 1 timing report; not a hard requirement) |

**[DECISION] Register width is 32-bit, not 16-bit.** Earlier drafts assumed
16-bit registers throughout. That breaks for `BALANCE`: a starting balance
of even a few thousand dollars in cents overflows a 16-bit signed range
(max 32,767) almost immediately. Rather than special-case one register,
every general-purpose register and `BALANCE` are 32-bit. Buffers and
variables stay 16-bit (their values — prices, scaled ratios — comfortably
fit that range, and it keeps buffer/variable storage cheap). When a 16-bit
buffer or variable value is loaded into a 32-bit register, it is
**sign-extended**. When a 32-bit register value is stored into a 16-bit
variable slot (`ASSIGNVAR`), the **low 16 bits are stored**; the software
team should keep post-scaling intermediate values within 16-bit signed
range to avoid silent truncation.

---

## 2. Fixed-point convention

- All values represent scaled integers, never floats, at the hardware level.
- Booleans are integers 0 (false) / nonzero (true, canonically 1).
- **Ratio/percentage-style calculations must pre-multiply before dividing**
  to avoid truncating to 0 or 1 (the MACD-example bug): compute
  `(numerator * 100) / denominator`, then compare against scaled thresholds
  (e.g. compare to `100` and `50`, not `1` and `0.5`).
- `MUL` results are taken as the low 32 bits of the 32×32 product. Values
  should stay within a range where this doesn't overflow — the software
  team should keep scaling factors modest (×100 is safe for this use case).
- **Divide-by-zero behavior [DECISION]:** `DIV` by 0 returns `0` and does
  not halt or fault. Documented here so both the RTL and the golden model
  implement the same behavior.

---

## 3. Instruction word format

Every instruction's first word has this fixed 32-bit layout. Only the
fields relevant to a given opcode are meaningful; unused fields are zero.

```
Bit:    31    27 26    24 23    21 20    18 17    14 13    11 10    6  5      0
       [ opcode ][  Rd  ][ Rs1  ][ Rs2  ][var_id][buf_id][ imm5 ][ reserved ]
        5 bits   3 bits  3 bits  3 bits  4 bits  3 bits  5 bits   6 bits
```

- `opcode` — 5 bits (supports up to 32 opcodes; 25 used, 7 reserved)
- `Rd` — destination register, or the sole register operand for single-register ops
- `Rs1`, `Rs2` — source registers for 3-operand ALU ops; `Rs1` doubles as the
  quantity register for `UPDATEBALANCE`
- `var_id` — 0–14, selects a variable slot
- `buf_id` — 0–4, selects a stock buffer
- `imm5` — 0–30, the `days_before` window size for buffer-window opcodes
- `reserved` — zero-filled, reserved for future opcodes/operands

**Two-word instructions** (`LOAD_IMM`, `JMP`, `JMP_IF`): the first word carries
the opcode (and `Rd`/`Rs` if relevant); the **second word's low 16 bits**
carry a 16-bit immediate or a program-memory address, sign-extended when
loaded into a register.

---

## 4. Full opcode table

| Opcode (hex) | Mnemonic | Operands | Cycles | Semantics |
|---|---|---|---|---|
| `0x00` | `NOP` | — | 1 | No operation |
| `0x01` | `ADD` | Rd, Rs1, Rs2 | 1 | Rd = Rs1 + Rs2 |
| `0x02` | `SUB` | Rd, Rs1, Rs2 | 1 | Rd = Rs1 − Rs2 |
| `0x03` | `MUL` | Rd, Rs1, Rs2 | 1 | Rd = low 32 bits of Rs1 × Rs2 (DSP48E1) |
| `0x04` | `DIV` | Rd, Rs1, Rs2 | 16–20 (multi-cycle) | Rd = Rs1 ÷ Rs2; 0 if Rs2 = 0 |
| `0x05` | `CMP_GT` | Rd, Rs1, Rs2 | 1 | Rd = (Rs1 > Rs2) ? 1 : 0 |
| `0x06` | `CMP_LT` | Rd, Rs1, Rs2 | 1 | Rd = (Rs1 < Rs2) ? 1 : 0 |
| `0x07` | `AND` | Rd, Rs1, Rs2 | 1 | Rd = Rs1 && Rs2 (logical) |
| `0x08` | `OR` | Rd, Rs1, Rs2 | 1 | Rd = Rs1 \|\| Rs2 (logical) |
| `0x09` | `LOAD_IMM` | Rd, imm16 (2nd word) | 2 (2-word fetch) | Rd = sign-extended imm16 |
| `0x0A` | `JMP` | addr16 (2nd word) | 2 | PC = addr16 |
| `0x0B` | `JMP_IF` | Rs, addr16 (2nd word) | 2 | if Rs ≠ 0: PC = addr16 |
| `0x0C` | `ASSIGNVAR` | var_id, Rs | 1 | VAR[var_id] = low 16 bits of Rs |
| `0x0D` | `GETVAR` | Rd, var_id | 1 | Rd = sign-extended VAR[var_id] |
| `0x0E` | `GETBALANCE` | Rd | 1 | Rd = BALANCE |
| `0x0F` | `GETSTOCKPRICE` | Rd, buf_id | 1 | Rd = sign-extended BUF[buf_id][head] (most recent) |
| `0x10` | `GETSTOCKPRICEBEFORE` | Rd, buf_id, imm5 (days_before) | 1 | Rd = sign-extended BUF[buf_id][head − imm5], wrapped |
| `0x11` | `GETSUMPRICEBEFORE` | Rd, buf_id, imm5 (days_before) | up to 30 (multi-cycle) | Rd = sum of the last imm5 entries in BUF[buf_id] |
| `0x12` | `UPDATEBALANCE` | Rs1 (precomputed dollar amount, signed), buf_id | 1 | **BALANCE −= Rs1** (BALANCE is cash on hand). A positive amount is a buy, so cash goes down; a negative amount is a sell, so cash goes up. Confirmed per team spec: the host/compiler precomputes quantity × price before sending — the FPGA does **not** multiply internally for this opcode. `buf_id` is encoded but currently unused (reserved for a future `DECISION_EVENT` log) |
| `0x18` | `SETBALANCE` | Rs1 | 1 | BALANCE = Rs1, overwriting the previous value directly (no add, no sign change). Use once at program start to seed starting cash — e.g. `SETBALANCE` with `1000000` for $10,000.00. Never seed via a negative `UPDATEBALANCE`; that was considered and rejected as too error-prone (see §8) |
| `0x13` | `UPDATEALLSTOCKBUFFERS` | — | variable (blocking) | Stalls until a new tick has arrived for every tracked buffer, then advances all 5 buffer write pointers by one |
| `0x14` | `HALT` | — | 1 | Halts execution until next tick cycle begins |
| `0x15` | `CMP_GTE` | Rd, Rs1, Rs2 | 1 | Rd = (Rs1 ≥ Rs2) ? 1 : 0 |
| `0x16` | `CMP_LTE` | Rd, Rs1, Rs2 | 1 | Rd = (Rs1 ≤ Rs2) ? 1 : 0 |
| `0x17` | `SELECT` | Rd, Rs1 (cond), Rs2 (true val), Rs3 (false val, encoded in `buf_id` field) | 1 | Rd = (Rs1 ≠ 0) ? Rs2 : Rs3 |

Opcodes `0x19`–`0x1F` are reserved for future use (7 slots free).

**`SELECT`'s 4th operand [DECISION]:** every other opcode uses at most 3
register operands, matching the 3 register fields in the instruction word
(§3). `SELECT` needs a 4th (the false-value register). Rather than widen
the instruction format for one opcode, `SELECT` reuses the `buf_id` field
(bits `[13:11]`, 3 bits — exactly enough to address one of 8 registers) as
`Rs3`. This is opcode-specific field reinterpretation, consistent with how
`imm5`/`var_id`/`buf_id` already mean different things depending on the
opcode.

**`GETBALANCE` [DECISION]:** not in the original opcode list, added here
because `UPDATEBALANCE` writes `BALANCE` but nothing could read it —
required for a strategy to check funds or report a final result.

---

## 5. Memory map / addressing summary

- **Registers**: R0–R7, addressed by 3-bit fields in the instruction word. No hardwired-zero register.
- **BALANCE**: not register-file-addressed; accessed only via `GETBALANCE`/`UPDATEBALANCE`.
- **Variables**: `VAR[0..14]`, addressed by the 4-bit `var_id` field. The software team's `VAR1`/`VAR2`/`VAR3` naming maps to `var_id = 0/1/2` (compiler subtracts 1).
- **Buffers**: `BUF[0..4]`, addressed by the 3-bit `buf_id` field. Each is a 30-entry circular buffer; `head` is each buffer's current write-pointer position, advanced only by `UPDATEALLSTOCKBUFFERS`.
- **Program memory**: 512 × 32-bit words, addressed by the `addr16` field (only the low 9 bits are meaningful given 512 words; upper bits reserved for headroom).

---

## 6. UART wire protocol

Byte order: little-endian for all multi-byte fields. No delimiter bytes —
every message has a known fixed or length-prefixed size; both sides must
stay byte-aligned (a lightweight sync byte or checksum is an open
hardening option, not required for v1).

### 6.1 `LOAD_PROGRAM` (Host → FPGA)

| Bytes | Field | Meaning |
|---|---|---|
| 1 | `0x01` | Message type |
| 2 | Length (uint16) | Number of bytes of program data following (must be a multiple of 4) |
| N | Program data | Raw instruction words, 4 bytes each, little-endian |

### 6.2 `TICK` (Host → FPGA)

| Bytes | Field | Meaning |
|---|---|---|
| 1 | `0x02` | Message type |
| 1 | `buf_id` | Which of the 5 buffers this tick updates (0–4) |
| 2 | Price (int16) | Scaled integer price |

Total: 4 bytes. The FPGA does not advance a buffer on receipt of a `TICK` —
it stages the value; `UPDATEALLSTOCKBUFFERS` (opcode `0x13`) is what
actually advances all 5 buffers together once a new tick is staged for
each.

### 6.3 `DECISION_EVENT` (FPGA → Host)

| Bytes | Field | Meaning |
|---|---|---|
| 1 | `0x03` | Message type |
| 1 | `buf_id` | Which symbol |
| 1 | Action | `1` = buy, `0` = sell |
| 2 | Quantity (int16) | Shares |

Total: 5 bytes.

---

## 7. Build and verification plan

Same staged sequence as before, now grounded in the exact spec above —
each stage's testbenches should assert against Section 4's cycle counts
and semantics exactly.

| Stage | Scope | Exit criteria |
|---|---|---|
| 0 | ISA reference (this doc) + Python golden-model simulator implementing Section 4 exactly | Golden model runs a hand-written program and produces deterministic output |
| 0.5 | Tooling: VS Code (TerosHDL/Verible), Icarus Verilog + GTKWave for fast iteration, Vivado reserved for final checks and Divider Generator IP; every testbench self-checks against the golden model | Toolchain runs a trivial one-instruction program end to end |
| 1 | Register file (32-bit ×8), ALU (ADD/SUB/MUL, single-cycle), CMP_GT/CMP_LT, control unit fetch-decode-execute FSM | `(5+3)*2 > 6` style program, stored and read back correctly |
| 2 | JMP, JMP_IF, 2-word immediate fetch (LOAD_IMM) | If/else program takes the correct branch across 3+ scenarios |
| 3 | 5×30 circular buffers, GETSTOCKPRICE, GETSTOCKPRICEBEFORE, UPDATEALLSTOCKBUFFERS as a **blocking** op tied to tick arrival | Wraparound (day 31 on a 30-deep buffer) correct; blocking behavior verified under both "tick waiting" and "tick not yet arrived" |
| 4 | DIV (Vivado Divider Generator IP) and GETSUMPRICEBEFORE (general sequential accumulator, ≤30 cycles) | Divide-by-zero returns 0 as specified; sum at N=30 (wraparound-adjacent) correct |
| 5 | VAR store (ASSIGNVAR/GETVAR), BALANCE (GETBALANCE/UPDATEBALANCE — adds a precomputed dollar amount, no internal multiply) | Buy-then-sell sequence produces the hand-calculated balance |
| 6 | UART RX/TX + FIFO, LOAD_PROGRAM/TICK/DECISION_EVENT per Section 6 | Program loads over UART (not hardcoded); tick stream correctly updates buffers, observable via LEDs/serial echo |
| 7 | Full integration on Urbana hardware | A corrected real strategy program (e.g. the MACD example, rescaled per Section 2) produces correct decisions end-to-end on hardware |

---

## 8. Open items — not blocking, but need resolution before the stage listed

| Item | Needed by | Owner |
|---|---|---|
| ~~What `UpdateBalance`'s quantity represents~~ | — | **Resolved**: precomputed dollar amount, host-side. No FPGA multiply needed for this opcode. |
| ~~What BALANCE represents, and how to seed a starting value~~ | — | **Resolved** (Stage 5): BALANCE is cash on hand, not net-spend. `UPDATEBALANCE` was flipped to `BALANCE −= Rs1` so a buy decreases cash and a sell increases it, matching ordinary intuition. Seeding starting cash via a negative `UPDATEBALANCE` call was considered and rejected — it relies on a sign convention that's easy to get backwards silently, with no error if you do. A dedicated `SETBALANCE` opcode (`0x18`) was added instead: a direct overwrite, no sign trickery, same mental model as `LOAD_IMM`. Every strategy program should call `SETBALANCE` once, first, with its starting cash amount. |
| Software team applies the ×100 rescaling fix and corrected literals (the GT Hacks Prep doc's example program still has the raw-ratio-divide bug and the `0.5` literal unfixed) | Stage 7 (used as integration test case) | Software team |
| ~~What "cached variable for days_before" means for `GetSumPriceBefore`~~ | — | **Resolved**: no special hardware caching needed. Refers to the existing `ASSIGNVAR`/`GETVAR` pattern already in the spec — a computed average (e.g. 14-day, 26-day) is stored into a `VAR` slot once per tick for reuse by later instructions in that tick's decision logic. Confirms `GetSumPriceBefore` must support arbitrary `days_before` values (window sizes vary by strategy, not fixed to 14/26), consistent with the general sequential-accumulator design already in §4 — recomputed fresh each tick since buffer contents change via `UPDATEALLSTOCKBUFFERS`. |
| ~~Confirm 15 variable slots is enough~~ | — | **Resolved**: 15 confirmed as the actual maximum by the software team, matches §1. |
| ~~Confirm no strategy needs a window larger than 30~~ | — | **Resolved**: 30 confirmed as the actual maximum by the software team, matches §1. |
| ~~Confirm program memory size~~ | — | **Resolved**: 512 instruction words, hardware team's call (delegated). Real example programs run ~20-25 words; 512 gives ~20x headroom at <1% of BRAM budget. Unlike var count/window (fixed-width instruction fields), this is not tied to instruction encoding — low-risk to enlarge later if ever needed. |

Everything else in this document is a settled, buildable default — proceed
without waiting on the items above; none block Stages 0 through 6.
