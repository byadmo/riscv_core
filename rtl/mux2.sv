// mux2.sv - Generic 32-bit 2-to-1 Multiplexer
// Used for selecting between register data and immediate values.

module mux2 (
    input  logic [31:0] d0,    // Input 0
    input  logic [31:0] d1,    // Input 1
    input  logic        sel,   // Select signal
    output logic [31:0] y      // Output
);

    always_comb begin
        unique case (sel)
            1'b0:    y = d0;
            1'b1:    y = d1;
            default: y = d0; // Safety fallback to avoid latches
        endcase
    end

endmodule
