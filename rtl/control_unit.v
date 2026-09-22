`timescale 1ns/1ps

// Stage 1 opcodes only -- no JMP/LOAD_IMM/buffers/VAR/BALANCE/UART yet.
//
// prog_mem is loaded directly by the testbench for now; the UART loader
// is Stage 6.

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
    input  wire [31:0] alu_result
);

    localparam OP_NOP    = 5'h00;
    localparam OP_ADD    = 5'h01;
    localparam OP_SUB    = 5'h02;
    localparam OP_MUL    = 5'h03;
    localparam OP_CMP_GT = 5'h05;
    localparam OP_CMP_LT = 5'h06;

    localparam S_FETCH     = 2'd0;
    localparam S_DECODE    = 2'd1;
    localparam S_EXECUTE   = 2'd2;
    localparam S_WRITEBACK = 2'd3;

    reg [1:0]  state;
    reg [8:0]  pc;           // 512-word prog mem -> 9 bits
    reg [31:0] ir;

    reg [31:0] prog_mem [0:511];

    wire [4:0] opcode_f = ir[31:27];
    wire [2:0] rd_f     = ir[26:24];
    wire [2:0] rs1_f    = ir[23:21];
    wire [2:0] rs2_f    = ir[20:18];

    wire is_write_opcode = (opcode_f == OP_ADD)    ||
                            (opcode_f == OP_SUB)    ||
                            (opcode_f == OP_MUL)    ||
                            (opcode_f == OP_CMP_GT) ||
                            (opcode_f == OP_CMP_LT);

    assign rf_raddr1  = rs1_f;
    assign rf_raddr2  = rs2_f;
    assign alu_opcode = opcode_f;
    assign alu_in1    = rf_rdata1;
    assign alu_in2    = rf_rdata2;

    assign rf_waddr = rd_f;
    assign rf_wdata = alu_result;
    assign rf_we    = (state == S_WRITEBACK) && is_write_opcode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_FETCH;
            pc    <= 9'd0;
            ir    <= 32'd0;
        end else begin
            case (state)
                S_FETCH: begin
                    ir    <= prog_mem[pc];
                    state <= S_DECODE;
                end

                S_DECODE: begin
                    // decode already happened combinationally above,
                    // this state is just a placeholder for now
                    state <= S_EXECUTE;
                end

                S_EXECUTE: begin
                    state <= S_WRITEBACK;
                end

                S_WRITEBACK: begin
                    pc    <= pc + 9'd1;
                    state <= S_FETCH;
                end

                default: state <= S_FETCH;
            endcase
        end
    end

endmodule
