`timescale 1ns/1ps

// Only external I/O so far is the tick staging port. There's no UART
// yet (Stage 6), so testbenches drive it directly; Stage 6's TICK decoder
// drives the same three signals (one 1-cycle tick_valid strobe per
// decoded TICK message, spec 6.2). Tie tick_valid low if unused.
// Testbenches reach into internal state via hierarchical refs instead
// of needing debug ports here.

module tradecpu_core (
    input wire        clk,
    input wire        rst_n,

    input wire        tick_valid,
    input wire [2:0]  tick_buf_id,
    input wire [15:0] tick_price
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

    wire [2:0]  buf_rd_id;
    wire [4:0]  buf_rd_days_before;
    wire [15:0] buf_rd_data;
    wire [4:0]  buf_tick_pending;
    wire        buf_all_ticks_pending;
    wire        buf_advance;

    wire        div_start;
    wire [31:0] div_dividend;
    wire [31:0] div_divisor;
    wire        div_done;
    wire [31:0] div_quotient;

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

    stock_buffers u_stock_buffers (
        .clk               (clk),
        .rst_n             (rst_n),
        .tick_valid        (tick_valid),
        .tick_buf_id       (tick_buf_id),
        .tick_price        (tick_price),
        .tick_pending      (buf_tick_pending),
        .all_ticks_pending (buf_all_ticks_pending),
        .advance           (buf_advance),
        .rd_buf_id         (buf_rd_id),
        .rd_days_before    (buf_rd_days_before),
        .rd_data           (buf_rd_data)
    );

    // stand-in for the Divider Generator IP, see divider.v
    divider u_divider (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (div_start),
        .dividend (div_dividend),
        .divisor  (div_divisor),
        .done     (div_done),
        .quotient (div_quotient)
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
        .alu_result (alu_result),
        .buf_rd_id             (buf_rd_id),
        .buf_rd_days_before    (buf_rd_days_before),
        .buf_rd_data           (buf_rd_data),
        .buf_all_ticks_pending (buf_all_ticks_pending),
        .buf_advance           (buf_advance),
        .div_start             (div_start),
        .div_dividend          (div_dividend),
        .div_divisor           (div_divisor),
        .div_done              (div_done),
        .div_quotient          (div_quotient)
    );

endmodule
