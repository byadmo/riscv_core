module aludec (
    input  logic       opb5,       // Bit 5 of the instruction (differentiates R-type from I-type)
    input  logic [2:0] funct3,     // Bits 14:12 of the instruction
    input  logic       funct7b5,   // Bit 30 of the instruction (tells us if it's ADD vs SUB, or SRL vs SRA)
    input  logic [1:0] aluop,      // The 2-bit signal coming from your Main Decoder
    output logic [3:0] alu_control // The 4-bit signal going directly to your ALU
);

    logic rtype_sub;
    
    // A subtraction only happens if it is an R-Type instruction (opb5 = 1) AND the modifier bit is 1.
    assign rtype_sub = funct7b5 & opb5;

    always_comb begin
        case(aluop)
            2'b00: alu_control = 4'b0000; // Load/Store Instructions: Force the ALU to ADD
            
            2'b01: alu_control = 4'b1000; // Branch Instructions (beq): Force the ALU to SUBTRACT
            
            2'b10: case(funct3)           // R-Type or I-Type: Look at the funct3 bits
                       3'b000: if (rtype_sub)
                                   alu_control = 4'b1000; // SUB
                               else
                                   alu_control = 4'b0000; // ADD
                       
                       3'b010: alu_control = 4'b0010;     // SLT  (Set Less Than)
                       3'b011: alu_control = 4'b0011;     // SLTU (Set Less Than Unsigned)
                       3'b100: alu_control = 4'b0100;     // XOR
                       3'b110: alu_control = 4'b0110;     // OR
                       3'b111: alu_control = 4'b0111;     // AND
                       3'b001: alu_control = 4'b0001;     // SLL  (Shift Left Logical)
                       3'b101: if (funct7b5)
                                   alu_control = 4'b1101; // SRA  (Shift Right Arithmetic)
                               else
                                   alu_control = 4'b0101; // SRL  (Shift Right Logical)
                       
                       default: alu_control = 4'b0000;
                   endcase
                   
            default: alu_control = 4'b0000;
        endcase
    end
endmodule