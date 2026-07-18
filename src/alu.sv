module alu (
    input  logic [31:0] a,           // 32-bit Input A
    input  logic [31:0] b,           // 32-bit Input B
    input  logic [3:0]  alu_control, // 4-bit signal telling the ALU what to do
    output logic [31:0] result,      // 32-bit Output
    output logic        zero         // Flag that is high if the result is exactly 0
);

    always_comb begin
        case (alu_control)
            4'b0000: result = a + b;                        // ADD
            4'b1000: result = a - b;                        // SUBTRACT
            4'b0111: result = a & b;                        // BITWISE AND
            4'b0110: result = a | b;                        // BITWISE OR
            4'b0100: result = a ^ b;                        // BITWISE XOR
            4'b0001: result = a << b[4:0];                  // SHIFT LEFT LOGICAL
            4'b0101: result = a >> b[4:0];                  // SHIFT RIGHT LOGICAL
            4'b1101: result = $signed(a) >>> b[4:0];        // SHIFT RIGHT ARITHMETIC
            4'b0010: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SET LESS THAN
            4'b0011: result = (a < b) ? 32'd1 : 32'd0;      // SET LESS THAN UNSIGNED
            default: result = 32'd0;                        // DEFAULT CATCH-ALL
        endcase
    end

    // The zero flag is purely checking if all 32 bits of the result are 0.
    assign zero = (result == 32'd0);

endmodule