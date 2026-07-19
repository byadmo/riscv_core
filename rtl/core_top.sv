// Top-level datapath with simple forwarding and load/store model
`timescale 1ns/1ps
module core_top(
    input logic clk, rst_n
);
    // Memories
    logic [31:0] imem [0:255];
    logic [31:0] dmem [0:255];

    // PC / fetch
    logic [31:0] pc; logic [31:0] instr;

    // decode fields
    logic [4:0] rs1, rs2, rd;

    // regfile
    logic [31:0] rd1, rd2, wd;
    logic we;

    // control
    logic [3:0] alu_op; logic is_load, is_store, is_branch; logic reg_write;

    // EX results
    logic [31:0] alu_res;
    logic [31:0] mem_read_data;

    // simple previous-instruction tracking for forwarding
    logic [4:0] prev_rd; logic [31:0] prev_alu_res; logic [31:0] prev_mem_data; logic prev_reg_write; logic prev_is_load;

    // fetch stage with simple stall support
    logic stall;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'd0;
        end else begin
            if (!stall) pc <= pc + 4;
            else pc <= pc; // hold
        end
    end
    assign instr = imem[pc[9:2]];

    // decode
    assign rs1 = instr[19:15];
    assign rs2 = instr[24:20];
    assign rd  = instr[11:7];

    control_unit cu(.opcode(instr[6:0]), .funct3(instr[14:12]), .funct7(instr[31:25]),
        .alu_op(alu_op), .is_load(is_load), .is_store(is_store), .is_branch(is_branch), .reg_write(reg_write));

    // read register file
    regfile rf(.clk(clk), .rst_n(rst_n), .we(we), .rs1(rs1), .rs2(rs2), .rd(rd), .wd(wd), .rd1(rd1), .rd2(rd2));

    // immediates (I-type and S-type simple extraction)
    logic [31:0] imm_i, imm_s;
    assign imm_i = {{20{instr[31]}}, instr[31:20]};
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};

    // effective address for load/store
    logic [31:0] eff_addr;
    assign eff_addr = rd1 + (is_load ? imm_i : (is_store ? imm_s : 32'd0));

    // forwarding: if previous destination matches source, forward
    logic [31:0] op_a, op_b;
    always_comb begin
        op_a = rd1;
        op_b = rd2;
        // forward from prev (EX/MEM or MEM/WB simplified)
        if (prev_reg_write && (prev_rd != 5'd0)) begin
            if (prev_rd == rs1) begin
                op_a = prev_is_load ? prev_mem_data : prev_alu_res;
            end
            if (prev_rd == rs2) begin
                op_b = prev_is_load ? prev_mem_data : prev_alu_res;
            end
        end
    end

    // detect load-use hazard: if prev was load and current uses prev_rd
    always_comb begin
        stall = 0;
        if (prev_is_load && ( (prev_rd == rs1) || (prev_rd == rs2) )) stall = 1;
    end

    // ALU operand selection (use immediate for I-type ADDI opcode 0010011)
    logic [6:0] opcode;
    assign opcode = instr[6:0];
    logic [31:0] alu_b;
    always_comb begin
        if (opcode == 7'b0010011) alu_b = imm_i; else alu_b = op_b;
    end

    // ALU
    alu a(.alu_op(alu_op), .a(op_a), .b(alu_b), .result(alu_res));

    // Data memory access (simple single-cycle model)
    always_ff @(posedge clk) begin
        // store
        if (is_store) begin
            dmem[eff_addr[9:2]] <= op_b; // use forwarded store data if needed
        end
        // read
        mem_read_data <= dmem[eff_addr[9:2]];
    end

    // writeback selection
    assign wd = is_load ? mem_read_data : alu_res;

    // drive regfile write enable: only when reg_write and not stalling
    // Note: regfile writes on posedge; freeze write during stall to implement load-use bubble
    assign we = reg_write && !stall;

    // update prev_* tracking at cycle boundary
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_rd <= 5'd0; prev_alu_res <= 32'd0; prev_mem_data <= 32'd0; prev_reg_write <= 1'b0; prev_is_load <= 1'b0;
        end else begin
            // capture results of current instruction for next-cycle forwarding
            prev_rd <= rd;
            prev_alu_res <= alu_res;
            prev_mem_data <= mem_read_data;
            prev_reg_write <= reg_write;
            prev_is_load <= is_load;
        end
    end

endmodule
