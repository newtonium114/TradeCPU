`timescale 1ns/1ps

// Stage 1 opcodes (NOP/ADD/SUB/MUL/CMP_GT/CMP_LT), Stage 2's
// LOAD_IMM/JMP/JMP_IF, and Stage 3's buffer ops -- no VAR/BALANCE/UART yet.
//
// prog_mem is loaded directly by the testbench for now; the UART loader
// is Stage 6.
//
// LOAD_IMM/JMP/JMP_IF are two-word instructions (spec section 3): word0
// carries the opcode plus Rd or Rs1, word1's low bits carry the
// immediate/address. That needs an extra fetch cycle (S_FETCH2) between
// DECODE and EXECUTE to pull word1 in before we can act on it.
//
// GETSTOCKPRICE/GETSTOCKPRICEBEFORE are plain 1-word ops: stock_buffers'
// read port is combinational, so the sign-extended value is written back
// on the normal WRITEBACK cycle.
//
// UPDATEALLSTOCKBUFFERS is blocking: DECODE goes to S_WAIT_TICKS instead
// of EXECUTE and sits there, with no timeout, until every buffer has a
// staged tick. buf_advance is asserted for exactly that one cycle, then
// WRITEBACK moves the PC on as usual. With all ticks already waiting it
// takes the same 4 cycles as any other 1-word op.

module control_unit (
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
    input  wire [31:0] alu_result,

    output wire [2:0]  buf_rd_id,
    output wire [4:0]  buf_rd_days_before,
    input  wire [15:0] buf_rd_data,
    input  wire        buf_all_ticks_pending,
    output wire        buf_advance
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
    localparam OP_GETSTOCKPRICE         = 5'h0F;
    localparam OP_GETSTOCKPRICEBEFORE   = 5'h10;
    localparam OP_UPDATEALLSTOCKBUFFERS = 5'h13;

    localparam S_FETCH     = 3'd0;
    localparam S_DECODE    = 3'd1;
    localparam S_FETCH2    = 3'd2;
    localparam S_EXECUTE   = 3'd3;
    localparam S_WRITEBACK = 3'd4;
    localparam S_WAIT_TICKS = 3'd5;

    reg [2:0]  state;
    reg [8:0]  pc;           // 512-word prog mem -> 9 bits
    reg [31:0] ir;
    reg [31:0] ir2;          // second word of a two-word instruction

    reg [31:0] prog_mem [0:511];

    wire [4:0] opcode_f = ir[31:27];
    wire [2:0] rd_f     = ir[26:24];
    wire [2:0] rs1_f    = ir[23:21];
    wire [2:0] rs2_f    = ir[20:18];
    wire [2:0] buf_id_f = ir[13:11];
    wire [4:0] imm5_f   = ir[10:6];

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

    wire is_get_price        = (opcode_f == OP_GETSTOCKPRICE);
    wire is_get_price_before = (opcode_f == OP_GETSTOCKPRICEBEFORE);
    wire is_buf_read         = is_get_price || is_get_price_before;
    wire is_update_bufs      = (opcode_f == OP_UPDATEALLSTOCKBUFFERS);

    assign rf_raddr1  = rs1_f;
    assign rf_raddr2  = rs2_f;
    assign alu_opcode = opcode_f;
    assign alu_in1    = rf_rdata1;
    assign alu_in2    = rf_rdata2;

    // GETSTOCKPRICE is just "0 days before"; force it rather than trust
    // the unused imm5 field to be zero
    assign buf_rd_id          = buf_id_f;
    assign buf_rd_days_before = is_get_price_before ? imm5_f : 5'd0;
    assign buf_advance        = (state == S_WAIT_TICKS) && buf_all_ticks_pending;

    assign rf_waddr = rd_f;
    assign rf_wdata = is_load_imm ? {{16{imm16_f[15]}}, imm16_f} :
                      is_buf_read ? {{16{buf_rd_data[15]}}, buf_rd_data} :
                                    alu_result;
    assign rf_we    = (state == S_WRITEBACK) && (is_write_opcode || is_load_imm || is_buf_read);

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
                    if (is_two_word)
                        state <= S_FETCH2;
                    else if (is_update_bufs)
                        state <= S_WAIT_TICKS;
                    else
                        state <= S_EXECUTE;
                end

                S_WAIT_TICKS: begin
                    if (buf_all_ticks_pending)
                        state <= S_WRITEBACK;
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
