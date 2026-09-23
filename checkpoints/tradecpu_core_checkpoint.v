`timescale 1ns/1ps

// SYNTHESIS-CHECKPOINT HARNESS FILE -- see checkpoints/README.md.
// NOT part of the real design; not wired into rtl/ or sim/.
//
// Wires the REAL, unmodified rtl/register_file.v and rtl/alu.v to
// control_unit_checkpoint.v (same directory) instead of the real
// rtl/control_unit.v, purely so prog_mem has synthesizable content for
// a one-off resource/timing check. Same port list and internal wiring
// as rtl/tradecpu_core.v, which itself is untouched.

module tradecpu_core_checkpoint (
    input wire clk,
    input wire rst_n
);

    wire        rf_we;
    wire [2:0]  rf_waddr;
    wire [31:0] rf_wdata;
    wire [2:0]  rf_raddr1;
    wire [2:0]  rf_raddr2;
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;

    wire [4:0]  alu_opcode;
    wire [31:0] alu_in1;
    wire [31:0] alu_in2;
    wire [31:0] alu_result;

    register_file u_register_file (
        .clk    (clk),
        .rst_n  (rst_n),
        .we     (rf_we),
        .waddr  (rf_waddr),
        .wdata  (rf_wdata),
        .raddr1 (rf_raddr1),
        .raddr2 (rf_raddr2),
        .rdata1 (rf_rdata1),
        .rdata2 (rf_rdata2)
    );

    alu u_alu (
        .opcode (alu_opcode),
        .in1    (alu_in1),
        .in2    (alu_in2),
        .result (alu_result)
    );

    control_unit_checkpoint u_control_unit (
        .clk        (clk),
        .rst_n      (rst_n),
        .rf_we      (rf_we),
        .rf_waddr   (rf_waddr),
        .rf_wdata   (rf_wdata),
        .rf_raddr1  (rf_raddr1),
        .rf_raddr2  (rf_raddr2),
        .rf_rdata1  (rf_rdata1),
        .rf_rdata2  (rf_rdata2),
        .alu_opcode (alu_opcode),
        .alu_in1    (alu_in1),
        .alu_in2    (alu_in2),
        .alu_result (alu_result)
    );

endmodule
