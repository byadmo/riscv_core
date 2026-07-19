// execute_stage.sv - University Style Execute Stage
// Orchestrates the ALU, operand selection, and branch target calculation.

module execute_stage (
    // Inputs from Decode Stage
    input  logic [31:0] pc_in,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [31:0] imm_ext,
    input  logic [3:0]  alu_control,
    input  logic        alu_src_b,    // 0: rs2_data, 1: imm_ext
    
    // Outputs to Memory/Fetch
    output logic [31:0] alu_result,
    output logic [31:0] write_data,   // rs2_data passed for Store instructions
    output logic [31:0] branch_target,
    output logic        zero          // Zero flag to Branch/Control logic
);

    logic [31:0] src_b;

    // --- Operand B Multiplexer ---
    // Selects between Register file output and sign-extended immediate
    mux2 alu_mux_b (
        .d0  (rs2_data),
        .d1  (imm_ext),
        .sel (alu_src_b),
        .y   (src_b)
    );

    // --- Main Arithmetic Logic Unit ---
    alu main_alu (
        .a           (rs1_data),
        .b           (src_b),
        .alu_control (alu_control),
        .result      (alu_result),
        .zero        (zero)
    );

    // --- Dedicated Branch Target Adder ---
    // Independent adder to calculate Target = Current PC + Immediate
    // This removes the adder from the critical path of the main ALU.
    assign branch_target = pc_in + imm_ext;

    // Pass rs2_data directly through for Memory Stage (SW instructions)
    assign write_data = rs2_data;

endmodule
