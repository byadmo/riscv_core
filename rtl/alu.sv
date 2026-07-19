// alu.sv - RV32I Arithmetic Logic Unit
// Supports standard arithmetic, logical, and comparison operations.

module alu (
    input  logic [31:0] a,           // Operand A
    input  logic [31:0] b,           // Operand B
    input  logic [3:0]  alu_control, // Control signal (4-bit)
    output logic [31:0] result,      // ALU result
    output logic        zero         // Zero flag for branches
);

    always_comb begin
        // Default values to prevent inferred latches
        result = 32'd0;
        
        unique case (alu_control)
            4'b0000: result = a + b;                      // ADD
            4'b1000: result = a - b;                      // SUB
            4'b0110: result = a | b;                      // OR
            4'b0111: result = a & b;                      // AND
            4'b0100: result = a ^ b;                      // XOR
            4'b0001: result = a << b[4:0];                // SLL (Shift Left Logical)
            4'b0101: result = a >> b[4:0];                // SRL (Shift Right Logical)
            4'b1101: result = $signed(a) >>> b[4:0];      // SRA (Shift Right Arithmetic)
            4'b0010: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT (Set Less Than)
            4'b0011: result = (a < b) ? 32'd1 : 32'd0;    // SLTU (Set Less Than Unsigned)
            default: result = 32'd0;
        endcase
    end

    assign zero = (result == 32'd0);

endmodule
