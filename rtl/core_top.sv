// Top-level datapath (baseline, small-memory model)
`timescale 1ns/1ps
module core_top(
    input logic clk, rst_n
);
    // Simple instruction memory (small ROM)
    logic [31:0] imem [0:255];
    logic [31:0] dmem [0:255];
    logic [31:0] pc, instr;
    // regfile
    logic [31:0] rd1, rd2, wd;
    logic [4:0] rs1, rs2, rd;
    logic we;
    // control / alu
    logic [3:0] alu_op;
    logic [31:0] alu_res;

    // fetch
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc <= 32'd0; else pc <= pc + 4;
    end
    assign instr = imem[pc[9:2]];

    // decode (minimal fields)
    assign rs1 = instr[19:15];
    assign rs2 = instr[24:20];
    assign rd  = instr[11:7];

    control_unit cu(.opcode(instr[6:0]), .funct3(instr[14:12]), .funct7(instr[31:25]),
        .alu_op(alu_op), .is_load(), .is_store(), .is_branch(), .reg_write(we));

    regfile rf(.clk(clk), .rst_n(rst_n), .we(we), .rs1(rs1), .rs2(rs2), .rd(rd), .wd(wd),
        .rd1(rd1), .rd2(rd2));

    alu a(.alu_op(alu_op), .a(rd1), .b(rd2), .result(alu_res));

    // writeback from ALU directly for this baseline
    assign wd = alu_res;
endmodule