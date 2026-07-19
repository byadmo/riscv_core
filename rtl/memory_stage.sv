// memory_stage.sv - University Style Memory Stage
// Handles data memory access (RAM) for Load and Store instructions.

module memory_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem_read,     // Control signal for reading
    input  logic        mem_write,    // Control signal for writing
    input  logic [31:0] alu_result,   // Memory address
    input  logic [31:0] write_data,   // Data to be stored (from rs2)
    output logic [31:0] read_data     // Data read from memory
);

    // Simplified Data Memory (RAM)
    // In a real university project, this might be an external IP or a larger array.
    // We'll use a small internal array for demonstration and synthesizability.
    logic [31:0] data_mem [255:0]; // 256 words of memory

    // Synchronous Write Logic
    always_ff @(posedge clk) begin
        if (mem_write) begin
            data_mem[alu_result[9:2]] <= write_data; // Word-aligned addressing
        end
    end

    // Combinational Read Logic
    // Note: Some designs use synchronous reads; here we use combinational for simplicity
    // in the pipeline logic, common in 2nd/3rd year lab assignments.
    assign read_data = (mem_read) ? data_mem[alu_result[9:2]] : 32'h0;

endmodule
