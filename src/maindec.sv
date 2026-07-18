module maindec (
    input  logic [6:0] op,         // The 7-bit opcode from the instruction
    output logic       branch,     // High if instruction is a branch (e.g., beq)
    output logic       jump,       // High if instruction is a jump (e.g., jal)
    output logic       resultsrc,  // Chooses whether to send ALU result or Memory result to RegFile
    output logic       memwrite,   // High if writing to Data Memory (e.g., sw)
    output logic       alusrc,     // Chooses ALU input B (0 = Register, 1 = Immediate/Constant)
    output logic [1:0] immsrc,     // Tells the Sign Extension unit how to format the immediate
    output logic       regwrite,   // High if saving a result back to the RegFile
    output logic [1:0] aluop       // 2-bit code telling the ALU Decoder what math to do
);

    always_comb begin
        case(op)
            // R-type (e.g., add, sub)
            7'b0110011: begin regwrite=1; immsrc=2'bxx; alusrc=0; memwrite=0; resultsrc=0; branch=0; jump=0; aluop=2'b10; end
            
            // I-type (e.g., addi)
            7'b0010011: begin regwrite=1; immsrc=2'b00; alusrc=1; memwrite=0; resultsrc=0; branch=0; jump=0; aluop=2'b10; end
            
            // Load Word (lw)
            7'b0000011: begin regwrite=1; immsrc=2'b00; alusrc=1; memwrite=0; resultsrc=1; branch=0; jump=0; aluop=2'b00; end
            
            // Store Word (sw)
            7'b0100011: begin regwrite=0; immsrc=2'b01; alusrc=1; memwrite=1; resultsrc=0; branch=0; jump=0; aluop=2'b00; end
            
            // Branch if Equal (beq)
            7'b1100011: begin regwrite=0; immsrc=2'b10; alusrc=0; memwrite=0; resultsrc=0; branch=1; jump=0; aluop=2'b01; end
            
            // Default catch-all to prevent inferred latches
            default:    begin regwrite=0; immsrc=2'b00; alusrc=0; memwrite=0; resultsrc=0; branch=0; jump=0; aluop=2'b00; end
        endcase
    end
endmodule