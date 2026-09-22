`timescale 1ns/1ps

// No external I/O yet (no UART, no ticks), so just clk/rst_n for now.
// Testbenches reach into internal state via hierarchical refs instead
// of needing debug ports here.

module tradecpu_core (
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

    control_unit u_control_unit (
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
