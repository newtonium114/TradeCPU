`timescale 1ns/1ps

// SYNTHESIS-CHECKPOINT HARNESS FILE -- see checkpoints/README.md.
// NOT part of the real design; not wired into rtl/ or sim/.
//
// Snapshot of rtl/control_unit.v as of Stage 2, renamed
// control_unit_checkpoint, with exactly one addition: an initial
// $readmemh block for prog_mem, so prog_mem has real synthesizable
// content for a standalone Vivado check. Plain top-level synthesis of
// tradecpu_core sweeps control_unit to 0 cells otherwise, since prog_mem
// is never written in synthesizable RTL -- only Stage 6's real UART
// loader will do that. rtl/control_unit.v itself is untouched.
//
// This file goes stale the moment rtl/control_unit.v changes (new
// opcodes, FSM changes, etc). Regenerate it before reusing at a later
// stage -- see checkpoints/README.md for the exact procedure.

module control_unit_checkpoint (
    input  wire        clk,
    input  wire        rst_n,

    output wire        rf_we,
    output wire [2:0]  rf_waddr,
    output wire [31:0] rf_wdata,
    output wire [2:0]  rf_raddr1,
    output wire [2:0]  rf_raddr2,
    input  wire [31:0] rf_rdata1,
    input  wire [31:0] rf_rdata2,

    output wire [4:0]  alu_opcode,
    output wire [31:0] alu_in1,
    output wire [31:0] alu_in2,
    input  wire [31:0] alu_result
);

    localparam OP_NOP      = 5'h00;
    localparam OP_ADD      = 5'h01;
    localparam OP_SUB      = 5'h02;
    localparam OP_MUL      = 5'h03;
    localparam OP_CMP_GT   = 5'h05;
    localparam OP_CMP_LT   = 5'h06;
    localparam OP_LOAD_IMM = 5'h09;
    localparam OP_JMP      = 5'h0A;
    localparam OP_JMP_IF   = 5'h0B;

    localparam S_FETCH     = 3'd0;
    localparam S_DECODE    = 3'd1;
    localparam S_FETCH2    = 3'd2;
    localparam S_EXECUTE   = 3'd3;
    localparam S_WRITEBACK = 3'd4;

    reg [2:0]  state;
    reg [8:0]  pc;           // 512-word prog mem -> 9 bits
    reg [31:0] ir;
    reg [31:0] ir2;          // second word of a two-word instruction

    reg [31:0] prog_mem [0:511];

    // checkpoint-only: gives prog_mem real content so synthesis has
    // something to analyze. See file header.
    initial begin
        $readmemh("C:/Users/abhay/OneDrive/Documents/projects/Trade CPU/checkpoints/tradecpu_stage2_checkpoint.hex", prog_mem);
    end

    wire [4:0] opcode_f = ir[31:27];
    wire [2:0] rd_f     = ir[26:24];
    wire [2:0] rs1_f    = ir[23:21];
    wire [2:0] rs2_f    = ir[20:18];

    wire [8:0] addr_f  = ir2[8:0];   // only low 9 bits matter, 512-word memory
    wire [15:0] imm16_f = ir2[15:0];

    wire is_write_opcode = (opcode_f == OP_ADD)    ||
                            (opcode_f == OP_SUB)    ||
                            (opcode_f == OP_MUL)    ||
                            (opcode_f == OP_CMP_GT) ||
                            (opcode_f == OP_CMP_LT);

    wire is_load_imm = (opcode_f == OP_LOAD_IMM);
    wire is_jmp      = (opcode_f == OP_JMP);
    wire is_jmp_if   = (opcode_f == OP_JMP_IF);
    wire is_two_word = is_load_imm || is_jmp || is_jmp_if;

    assign rf_raddr1  = rs1_f;
    assign rf_raddr2  = rs2_f;
    assign alu_opcode = opcode_f;
    assign alu_in1    = rf_rdata1;
    assign alu_in2    = rf_rdata2;

    assign rf_waddr = rd_f;
    assign rf_wdata = is_load_imm ? {{16{imm16_f[15]}}, imm16_f} : alu_result;
    assign rf_we    = (state == S_WRITEBACK) && (is_write_opcode || is_load_imm);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_FETCH;
            pc    <= 9'd0;
            ir    <= 32'd0;
            ir2   <= 32'd0;
        end else begin
            case (state)
                S_FETCH: begin
                    ir    <= prog_mem[pc];
                    state <= S_DECODE;
                end

                S_DECODE: begin
                    state <= is_two_word ? S_FETCH2 : S_EXECUTE;
                end

                S_FETCH2: begin
                    ir2   <= prog_mem[pc + 9'd1];
                    state <= S_EXECUTE;
                end

                S_EXECUTE: begin
                    state <= S_WRITEBACK;
                end

                S_WRITEBACK: begin
                    if (is_jmp)
                        pc <= addr_f;
                    else if (is_jmp_if)
                        pc <= (rf_rdata1 != 32'sd0) ? addr_f : (pc + 9'd2);
                    else if (is_load_imm)
                        pc <= pc + 9'd2;
                    else
                        pc <= pc + 9'd1;

                    state <= S_FETCH;
                end

                default: state <= S_FETCH;
            endcase
        end
    end

endmodule
