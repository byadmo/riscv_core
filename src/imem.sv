// Simple Instruction ROM (word-addressable)
module imem(
    input logic [31:0] addr,    // byte address
    output logic [31:0] instr
);
    localparam MEM_WORDS = 256;
    logic [31:0] mem [0:MEM_WORDS-1];

    initial begin
        // Optional preload file: imem.hex
        $readmemh("imem.hex", mem);
    end

    assign instr = mem[addr[9:2]];

endmodule
