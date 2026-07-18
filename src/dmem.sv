// Simple byte-addressable Data Memory supporting word reads/writes (word-aligned)
module dmem(
    input logic clk,
    input logic we,                  // write enable (word write)
    input logic [31:0] addr,         // byte address
    input logic [31:0] wd,           // write data
    output logic [31:0] rd           // read data (combinational from memory)
);
    localparam MEM_BYTES = 4096;
    logic [7:0] mem [0:MEM_BYTES-1];

    always_comb begin
        int unsigned idx = addr[11:0];
        rd = {mem[idx+3], mem[idx+2], mem[idx+1], mem[idx]};
    end

    always_ff @(posedge clk) begin
        if (we) begin
            int unsigned idx = addr[11:0];
            mem[idx]   <= wd[7:0];
            mem[idx+1] <= wd[15:8];
            mem[idx+2] <= wd[23:16];
            mem[idx+3] <= wd[31:24];
        end
    end

endmodule
