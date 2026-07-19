`timescale 1ns/1ps
// 5-stage pipeline top using existing modules: regfile, alu, control_unit, hazard_unit
module pipeline_core(
    input logic clk, rst_n
);
    // Memories
    logic [31:0] imem [0:1023];
    logic [31:0] dmem [0:1023];

    // PC and fetch
    logic [31:0] pc, pc_next;
    logic [31:0] if_instr;

    // IF/ID
    logic [31:0] if_id_pc, if_id_instr;

    // ID stage wires
    logic [4:0] id_rs1, id_rs2, id_rd;
    logic [31:0] id_rd1, id_rd2, id_imm;
    logic id_reg_write, id_is_load, id_is_store, id_is_branch;
    logic [3:0] id_alu_op;
    // control signals not directly consumed elsewhere
    logic alu_src_b_sig, mem_to_reg_sig;

    // ID/EX regs
    logic [31:0] id_ex_pc, id_ex_rd1, id_ex_rd2, id_ex_imm;
    logic [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    logic id_ex_reg_write, id_ex_is_load, id_ex_is_store, id_ex_is_branch;
    logic [3:0] id_ex_alu_op;

    // EX stage wires
    logic [31:0] ex_alu_result; logic [31:0] ex_mem_write_data;
    logic [4:0] ex_rd; logic ex_reg_write, ex_is_load, ex_is_store;

    // EX/MEM regs
    logic [31:0] ex_mem_alu_res, ex_mem_write_data_reg, ex_mem_mem_read_data;
    logic [4:0] ex_mem_rd; logic ex_mem_reg_write, ex_mem_is_load, ex_mem_is_store;

    // MEM/WB regs
    logic [31:0] mem_wb_alu_res, mem_wb_mem_read_data;
    logic [4:0] mem_wb_rd; logic mem_wb_reg_write, mem_wb_is_load;

    // forwarding selection
    logic [31:0] forward_a, forward_b;

    // Hazard signals
    logic stall, flush_if_id;

    // Fetch stage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc <= 32'd0; else pc <= pc_next;
    end
    assign if_instr = imem[pc[11:2]];

    // IF/ID register (with stall support)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc <= 32'd0; if_id_instr <= 32'd0;
        end else begin
            if (!stall) begin
                if_id_pc <= pc; if_id_instr <= if_instr;
            end else begin
                // hold IF/ID to stall
                if_id_pc <= if_id_pc; if_id_instr <= if_id_instr;
            end
        end
    end

    // ID: decode - extract fields and immediates for all formats, then invoke control unit
    assign id_rs1 = if_id_instr[19:15];
    assign id_rs2 = if_id_instr[24:20];
    assign id_rd  = if_id_instr[11:7];

    // compute immediates inside a comb block to avoid extra top-level declarations
    always_comb begin
        logic [31:0] imm_i = {{20{if_id_instr[31]}}, if_id_instr[31:20]};
        logic [31:0] imm_s = {{20{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};
        logic [31:0] imm_b = {{19{if_id_instr[31]}}, if_id_instr[31], if_id_instr[7], if_id_instr[30:25], if_id_instr[11:8], 1'b0};
        logic [31:0] imm_u = {if_id_instr[31:12], 12'd0};
        logic [31:0] imm_j = {{11{if_id_instr[31]}}, if_id_instr[31], if_id_instr[19:12], if_id_instr[20], if_id_instr[30:21], 1'b0};
        case (if_id_instr[6:0])
            7'h03, 7'h13, 7'h67: id_imm = imm_i; // loads, ALU immediate, JALR
            7'h23: id_imm = imm_s; // stores
            7'h63: id_imm = imm_b; // branches
            7'h37, 7'h17: id_imm = imm_u; // LUI/AUIPC
            7'h6f: id_imm = imm_j; // JAL
            default: id_imm = imm_i;
        endcase
    end

    control_unit cu(.opcode(if_id_instr[6:0]), .funct3(if_id_instr[14:12]), .funct7(if_id_instr[31:25]),
        .reg_write(id_reg_write), .alu_src_b(alu_src_b_sig), .mem_read(id_is_load), .mem_write(id_is_store), .mem_to_reg(mem_to_reg_sig), .branch(id_is_branch), .alu_control(id_alu_op));

    // Read register file (combinational outputs)
    // Instantiate regfile but use a second interface: read-only by connecting we=0 on instances. For simplicity, use single regfile instance below and rely on writeback timing.

    // Instantiate regfile (single instance) - writeback performed by mem_wb stage via we signal
    logic rf_we; logic [31:0] rf_wd; logic [4:0] rf_wr;
    regfile rf(.clk(clk), .rst_n(rst_n), .we(rf_we), .rs1(id_rs1), .rs2(id_rs2), .rd(rf_wr), .wd(rf_wd), .rd1(id_rd1), .rd2(id_rd2));

    // ID/EX pipeline register (capture decode outputs)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_pc<=0; id_ex_rd1<=0; id_ex_rd2<=0; id_ex_imm<=0;
            id_ex_rs1<=0; id_ex_rs2<=0; id_ex_rd<=0; id_ex_reg_write<=0; id_ex_is_load<=0; id_ex_is_store<=0; id_ex_is_branch<=0; id_ex_alu_op<=0;
        end else begin
            if (!stall) begin
                id_ex_pc<=if_id_pc; id_ex_rd1<=id_rd1; id_ex_rd2<=id_rd2; id_ex_imm<=id_imm;
                id_ex_rs1<=id_rs1; id_ex_rs2<=id_rs2; id_ex_rd<=id_rd; id_ex_reg_write<=id_reg_write; id_ex_is_load<=id_is_load; id_ex_is_store<=id_is_store; id_ex_is_branch<=id_is_branch; id_ex_alu_op<=id_alu_op;
            end else begin
                // insert bubble: clear controls
                id_ex_pc<=0; id_ex_rd1<=0; id_ex_rd2<=0; id_ex_imm<=0;
                id_ex_rs1<=0; id_ex_rs2<=0; id_ex_rd<=0; id_ex_reg_write<=0; id_ex_is_load<=0; id_ex_is_store<=0; id_ex_is_branch<=0; id_ex_alu_op<=0;
            end
        end
    end

    // Hazard unit
    hazard_unit hz(.id_ex_is_load(id_ex_is_load), .id_ex_rd(id_ex_rd), .if_id_rs1(id_rs1), .if_id_rs2(id_rs2), .stall(stall), .flush_if_id(flush_if_id));

    // EX stage: forwarding simple priority: MEM/WB -> EX/MEM -> ID/EX
    // Forward A
    always_comb begin
        forward_a = id_ex_rd1;
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) forward_a = ex_mem_alu_res;
        if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) forward_a = mem_wb_is_load ? mem_wb_mem_read_data : mem_wb_alu_res;
    end
    always_comb begin
        forward_b = id_ex_rd2;
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) forward_b = ex_mem_alu_res;
        if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) forward_b = mem_wb_is_load ? mem_wb_mem_read_data : mem_wb_alu_res;
    end

    // ALU operand selection
    logic [31:0] alu_b;
    always_comb begin
        alu_b = forward_b;
        // Use immediate for load/store address calculation and I-type ops when immediate is present
        if (id_ex_is_load || id_ex_is_store) begin
            alu_b = id_ex_imm;
        end else if (id_ex_imm !== 32'd0) begin
            // heuristic: if imm captured is non-zero, prefer it for immediate ops
            alu_b = id_ex_imm;
        end
    end

    alu alu0(.a(forward_a), .b(alu_b), .alu_control(id_ex_alu_op), .result(ex_alu_result), .zero());
    ex_mem_write_data = forward_b;

    // EX/MEM register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_alu_res<=0; ex_mem_write_data_reg<=0; ex_mem_rd<=0; ex_mem_reg_write<=0; ex_mem_is_load<=0; ex_mem_is_store<=0;
        end else begin
            ex_mem_alu_res<=ex_alu_result; ex_mem_write_data_reg<=ex_mem_write_data; ex_mem_rd<=id_ex_rd; ex_mem_reg_write<=id_ex_reg_write; ex_mem_is_load<=id_ex_is_load; ex_mem_is_store<=id_ex_is_store;
        end
    end

    // MEM stage: simple single cycle mem
    always_ff @(posedge clk) begin
        if (ex_mem_is_store) dmem[ex_mem_alu_res[11:2]] <= ex_mem_write_data_reg;
        ex_mem_mem_read_data <= dmem[ex_mem_alu_res[11:2]];
    end

    // MEM/WB register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_alu_res<=0; mem_wb_mem_read_data<=0; mem_wb_rd<=0; mem_wb_reg_write<=0; mem_wb_is_load<=0;
        end else begin
            mem_wb_alu_res<=ex_mem_alu_res; mem_wb_mem_read_data<=ex_mem_mem_read_data; mem_wb_rd<=ex_mem_rd; mem_wb_reg_write<=ex_mem_reg_write; mem_wb_is_load<=ex_mem_is_load;
        end
    end

    // WB stage: writeback to regfile
    always_comb begin
        rf_we = mem_wb_reg_write;
        rf_wr = mem_wb_rd;
        rf_wd = mem_wb_is_load ? mem_wb_mem_read_data : mem_wb_alu_res;
    end

    // Next PC (no branch predictor): handle branch at EX stage by checking id_ex_is_branch+alu result==0
    // Simplified: if branch taken flush next IF/ID
    always_comb begin
        pc_next = pc + 4;
        // check branch in EX stage - using id_ex signals as proxy one cycle later is simplified
        if (id_ex_is_branch && (ex_alu_result == 32'd0)) begin
            pc_next = id_ex_pc + (id_ex_imm << 1); // naive branch target calc - for demo only
        end
    end

endmodule
