// decode_stage.sv - University Style Instruction Decode
// Decodes RV32I instructions and manages the register file interface.

module decode_stage (
    input  logic        clk,
    input  logic        rst_n,
    
    // Inputs from Fetch/Pipeline
    input  logic [31:0] instr,
    input  logic [31:0] pc_in,
    
    // Writeback interface (from the end of the pipeline)
    input  logic [4:0]  wb_rd_addr,
    input  logic [31:0] wb_rd_data,
    input  logic        wb_reg_write,
    
    // Outputs to Execute Stage
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data,
    output logic [31:0] imm_ext,
    output logic [4:0]  rd_addr,
    output logic [3:0]  alu_op,      // Simplified ALU control
    output logic        alu_src_b,   // 0: rs2, 1: imm
    output logic        mem_read,
    output logic        mem_write,
    output logic        reg_write,
    output logic        branch       // Signals a branch instruction
);

    // Internal wires for fields
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;

    assign opcode   = instr[6:0];
    assign rd_addr  = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign funct7   = instr[31:25];

    // Instantiate Register File
    register_file reg_file_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .rs1_addr   (rs1_addr),
        .rs2_addr   (rs2_addr),
        .rd_addr    (wb_rd_addr),
        .rd_data    (wb_rd_data),
        .reg_write  (wb_reg_write),
        .rs1_data   (rs1_data),
        .rs2_data   (rs2_data)
    );

    // Immediate Extraction (I-type, S-type, B-type, etc.)
    always_comb begin
        case (opcode)
            7'h13: imm_ext = {{20{instr[31]}}, instr[31:20]};                         // I-type (ADDI, etc)
            7'h23: imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};           // S-type (SW)
            7'h63: imm_ext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; // B-type (BEQ)
            default: imm_ext = 32'h0;
        endcase
    end

    // Simple Control Unit Logic
    always_comb begin
        // Defaults
        alu_op    = 4'b0000; // Default ADD
        alu_src_b = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        reg_write = 1'b0;
        branch    = 1'b0;

        case (opcode)
            7'h33: begin // R-type
                reg_write = 1'b1;
                // Add more complex funct3/funct7 decoding here later
            end
            7'h13: begin // I-type (ALU)
                reg_write = 1'b1;
                alu_src_b = 1'b1;
            end
            7'h63: begin // B-type
                branch = 1'b1;
            end
            default: ;
        endcase
    end

endmodule
