// fetch_stage.sv - University Style Instruction Fetch
// Part of a 32-bit pipelined RISC-V (RV32I) processor core.
// Designed for readability and synthesizability in a digital systems design context.

module fetch_stage (
    input  logic        clk,
    input  logic        rst_n,          // Asynchronous active-low reset
    input  logic        pc_write,       // PC write enable from Hazard Unit (High = update, Low = stall)
    input  logic        branch_take,    // Branch/Jump control signal from Execute Stage
    input  logic [31:0] branch_target,  // Target address for branches or jumps
    output logic [31:0] pc_out          // Current PC sent to Instruction Memory
);

    logic [31:0] pc_reg;
    logic [31:0] pc_next;

    // --- Combinational Logic ---
    // Select the next PC value: either the branch target or the incremented PC
    always_comb begin
        if (branch_take) begin
            pc_next = branch_target;
        } else begin
            pc_next = pc_reg + 32'd4;
        end
    end

    // --- Sequential Logic ---
    // PC Register update on the positive clock edge
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg <= 32'h00000000;     // Reset PC to the start of memory
        end else if (pc_write) begin
            pc_reg <= pc_next;          // Only update PC if pc_write is asserted
        end
    end

    // Continuous assignment to drive the output port
    assign pc_out = pc_reg;

endmodule
