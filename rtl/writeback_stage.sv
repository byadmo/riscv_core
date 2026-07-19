// writeback_stage.sv - University Style Writeback Stage
// Selects the final result to be written back to the Register File.

module writeback_stage (
    input  logic        mem_to_reg,   // Control: 0 for ALU, 1 for Memory
    input  logic [31:0] alu_result,
    input  logic [31:0] read_data,
    output logic [31:0] wb_data       // Final data for Register File
);

    // Instantiate mux2 for final selection
    mux2 wb_mux (
        .d0  (alu_result),
        .d1  (read_data),
        .sel (mem_to_reg),
        .y   (wb_data)
    );

endmodule
