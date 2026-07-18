// Single-cycle RV32I CPU wiring using existing decoders and ALU
// Assumes maindec, aludec, alu exist in src/ with compatible ports.

`include "maindec.sv"
`include "aludec.sv"
`include "alu.sv"

module cpu(
    input logic clk,
    input logic reset
);
    // IF stage
    logic [31:0] pc, next_pc, instr;
    pc u_pc(.clk(clk), .reset(reset), .pc_in(next_pc), .pc_out(pc));
    imem u_imem(.addr(pc), .instr(instr));

    // ID stage: decode fields
    logic [6:0] opcode = instr[6:0];
    logic [4:0] rd     = instr[11:7];
    logic [2:0] funct3 = instr[14:12];
    logic [4:0] rs1    = instr[19:15];
    logic [4:0] rs2    = instr[24:20];
    logic [6:0] funct7 = instr[31:25];

    // control signals from main decoder
    logic memtoreg, memwrite, branch, alusrc, regwrite, jump; // common signals
    logic [1:0] immsrc;
    logic [1:0] aluop;
    logic resultsrc;

    maindec u_maindec(.op(opcode), .memtoreg(memtoreg), .memwrite(memwrite), .branch(branch), .jump(jump), .alusrc(alusrc), .immsrc(immsrc), .regwrite(regwrite), .resultsrc(resultsrc), .aluop(aluop));

    // register file
    logic [31:0] reg_rd1, reg_rd2;
    // single regfile instance: writeback data is wb_data (combinational) and is written on posedge
    regfile u_regfile(.clk(clk), .we(regwrite), .ra1(rs1), .ra2(rs2), .wa(rd), .wd(wb_data), .rd1(reg_rd1), .rd2(reg_rd2));

    // immediate generation (simple for I-type, S-type, B-type, U, J) - minimal implementations
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j, imm;
    // I-type
    assign imm_i = {{20{instr[31]}}, instr[31:20]};
    // S-type
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    // B-type (branch) imm: imm[12|10:5|4:1|11]<<1
    assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    // U-type
    assign imm_u = {instr[31:12], 12'b0};
    // J-type
    assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // choose immediate based on opcode class (maindec could expose this; for now use opcode checks)
    // minimal selection: if opcode == 7'b0000011 (LW) -> I-type; if 7'b0100011 (SW) -> S-type; if branch -> B-type; else I-type
    localparam OP_LW = 7'b0000011;
    localparam OP_SW = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL = 7'b1101111;
    localparam OP_JALR = 7'b1100111;

    always_comb begin
        unique case (immsrc)
            2'b00: imm = imm_i; // I-type / LW
            2'b01: imm = imm_s; // S-type / SW
            2'b10: imm = imm_b; // B-type / Branches
            default: imm = imm_i;
        endcase
        // handle J/JALR explicitly (override when opcode indicates)
        if (opcode == OP_JAL) imm = imm_j;
        if (opcode == OP_JALR) imm = imm_i;
    end

    // EX stage: ALU
    logic [31:0] alu_in2;
    assign alu_in2 = alusrc ? imm : reg_rd2;

    // ALU control from aludec
    logic [3:0] alu_control;
    aludec u_aludec(.opb5(instr[5]), .funct3(funct3), .funct7b5(instr[30]), .aluop(aluop), .alu_control(alu_control));

    logic [31:0] alu_out;
    logic zero;
    alu u_alu(.a(reg_rd1), .b(alu_in2), .alu_control(alu_control), .result(alu_out), .zero(zero));

    // Branch decision
    logic take_branch = branch && zero;
    logic [31:0] branch_target;
    branch_adder u_ba(.pc(pc), .imm(imm), .target(branch_target));

    // MEM stage: data memory access
    logic [31:0] mem_rd;
    dmem u_dmem(.clk(clk), .we(memwrite), .addr(alu_out), .wd(reg_rd2), .rd(mem_rd));

    // WB stage: writeback selection
    logic [31:0] wb_data;
    always_comb begin
        if (jump) begin
            wb_data = pc + 32'd4; // JAL/JALR writeback
        end else begin
            // resultsrc: 0 = ALU, 1 = MEM
            wb_data = resultsrc ? mem_rd : alu_out;
        end
    end


    // PC next: default PC+4, branch, jal, jalr
    logic [31:0] pc_plus4 = pc + 32'd4;
    always_comb begin
        if (opcode == OP_JAL)
            next_pc = pc + imm; // J-type target
        else if (opcode == OP_JALR)
            next_pc = (reg_rd1 + imm) & ~32'd1;
        else if (take_branch)
            next_pc = branch_target;
        else
            next_pc = pc_plus4;
    end

endmodule
