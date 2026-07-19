// riscv_top.sv - RV32I Processor Top Level
// Physically wires the pipeline stages together into a single-cycle/simple-pipeline core.

module riscv_top (
    input  logic        clk,
    input  logic        rst_n,
    
    // External Instruction Memory Interface
    input  logic [31:0] instr_mem_data,
    output logic [31:0] instr_mem_addr,
    
    // External Data Memory Interface (optional, currently internal)
    output logic [31:0] data_out
);

    // --- Internal Wires/Buses ---
    // Fetch
    logic [31:0] pc;
    
    // Decode
    logic [31:0] rs1_data, rs2_data, imm_ext;
    logic [4:0]  rd_addr;
    logic [3:0]  alu_control;
    logic        alu_src_b, mem_read, mem_write, reg_write, branch, mem_to_reg;
    
    // Execute
    logic [31:0] alu_result, write_data_mem, branch_target;
    logic        alu_zero;
    
    // Memory
    logic [31:0] read_data_mem;
    
    // Writeback
    logic [31:0] wb_data;

    // --- Stage Instantiations ---

    // 1. Fetch Stage
    fetch_stage fetch (
        .clk           (clk),
        .rst_n         (rst_n),
        .pc_write      (1'b1), // No stall logic yet
        .branch_take   (branch && alu_zero), // Basic branch logic
        .branch_target (branch_target),
        .pc_out        (pc)
    );
    assign instr_mem_addr = pc;

    // 2. Control Unit (Part of Decode)
    control_unit control (
        .opcode     (instr_mem_data[6:0]),
        .funct3     (instr_mem_data[14:12]),
        .funct7     (instr_mem_data[31:25]),
        .reg_write  (reg_write),
        .alu_src_b  (alu_src_b),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .mem_to_reg (mem_to_reg),
        .branch     (branch),
        .alu_control(alu_control)
    );

    // 3. Decode Stage
    decode_stage decode (
        .clk          (clk),
        .rst_n        (rst_n),
        .instr        (instr_mem_data),
        .pc_in        (pc),
        .wb_rd_addr   (instr_mem_data[11:7]), // Note: WB addr must be handled in pipeline
        .wb_rd_data   (wb_data),
        .wb_reg_write (reg_write),
        .rs1_data     (rs1_data),
        .rs2_data     (rs2_data),
        .imm_ext      (imm_ext),
        .rd_addr      (), // Handled internally
        .alu_op       (), // Overridden by central control
        .alu_src_b    (), 
        .mem_read     (),
        .mem_write    (),
        .reg_write    (),
        .branch       ()
    );

    // 4. Execute Stage
    execute_stage execute (
        .pc_in         (pc),
        .rs1_data      (rs1_data),
        .rs2_data      (rs2_data),
        .imm_ext       (imm_ext),
        .alu_control   (alu_control),
        .alu_src_b     (alu_src_b),
        .alu_result    (alu_result),
        .write_data    (write_data_mem),
        .branch_target (branch_target),
        .zero          (alu_zero)
    );

    // 5. Memory Stage
    memory_stage memory (
        .clk        (clk),
        .rst_n      (rst_n),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .alu_result (alu_result),
        .write_data (write_data_mem),
        .read_data  (read_data_mem)
    );

    // 6. Writeback Stage
    writeback_stage writeback (
        .mem_to_reg (mem_to_reg),
        .alu_result (alu_result),
        .read_data  (read_data_mem),
        .wb_data    (wb_data)
    );

    assign data_out = wb_data;

endmodule
