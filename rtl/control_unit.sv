// control_unit.sv - RV32I Central Control Unit
// Decodes instructions into control signals for the datapath.

module control_unit (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic       reg_write,
    output logic       alu_src_b,
    output logic       mem_read,
    output logic       mem_write,
    output logic       mem_to_reg,
    output logic       branch,
    output logic [3:0] alu_control
);

    // --- Main Decoder ---
    always_comb begin
        // Default signals to prevent latches
        reg_write  = 1'b0;
        alu_src_b  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        branch     = 1'b0;

        unique case (opcode)
            7'h33: reg_write = 1'b1; // R-type
            7'h13: begin             // I-type ALU
                reg_write = 1'b1;
                alu_src_b = 1'b1;
            end
            7'h03: begin             // LW (Load Word)
                reg_write  = 1'b1;
                alu_src_b  = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
            end
            7'h23: begin             // SW (Store Word)
                alu_src_b  = 1'b1;
                mem_write  = 1'b1;
            end
            7'h63: branch    = 1'b1; // B-type (Branch)
            default: ;
        endcase
    end

    // --- ALU Decoder ---
    always_comb begin
        alu_control = 4'b0000; // Default to ADD
        
        unique case (opcode)
            7'h33: begin // R-type
                case (funct3)
                    3'b000: alu_control = (funct7[5]) ? 4'b1000 : 4'b0000; // SUB : ADD
                    3'b111: alu_control = 4'b0111; // AND
                    3'b110: alu_control = 4'b0110; // OR
                    3'b100: alu_control = 4'b0100; // XOR
                    3'b001: alu_control = 4'b0001; // SLL
                    3'b101: alu_control = (funct7[5]) ? 4'b1101 : 4'b0101; // SRA : SRL
                    3'b010: alu_control = 4'b0010; // SLT
                    3'b011: alu_control = 4'b0011; // SLTU
                    default: alu_control = 4'b0000;
                endcase
            end
            7'h13: begin // I-type ALU
                case (funct3)
                    3'b000: alu_control = 4'b0000; // ADDI
                    3'b111: alu_control = 4'b0111; // ANDI
                    3'b110: alu_control = 4'b0110; // ORI
                    3'b100: alu_control = 4'b0100; // XORI
                    3'b001: alu_control = 4'b0001; // SLLI
                    3'b101: alu_control = (funct7[5]) ? 4'b1101 : 4'b0101; // SRAI : SRLI
                    3'b010: alu_control = 4'b0010; // SLTI
                    3'b011: alu_control = 4'b0011; // SLTIU
                    default: alu_control = 4'b0000;
                endcase
            end
            7'h03, 7'h23: alu_control = 4'b0000; // Load/Store uses ADD for address
            7'h63: alu_control = 4'b1000;        // Branch uses SUB for comparison
            default: alu_control = 4'b0000;
        endcase
    end

endmodule
