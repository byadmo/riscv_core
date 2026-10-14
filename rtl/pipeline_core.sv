`timescale 1ns/1ps
`default_nettype none
// Integrated five-stage educational RV32I-subset core.
// Pipeline: IF -> ID -> EX -> MEM -> WB. One-cycle data-memory read model.
// Instruction/data memory are testbench-initialized word arrays (no bus yet).
module pipeline_core(input wire clk, input wire rst_n);
    reg [31:0] imem [0:1023];
    reg [31:0] dmem [0:1023];

    reg [31:0] pc;
    reg [31:0] if_id_pc, if_id_instr;
    reg if_id_valid;
    wire [31:0] if_instr = imem[pc[11:2]];
    wire [6:0] id_opcode = if_id_instr[6:0];
    wire [2:0] id_funct3 = if_id_instr[14:12];
    wire [4:0] id_rs1 = if_id_instr[19:15];
    wire [4:0] id_rs2 = if_id_instr[24:20];
    wire [4:0] id_rd = if_id_instr[11:7];
    wire id_uses_rs1 = if_id_valid && (id_opcode==7'h33 || id_opcode==7'h13 ||
        id_opcode==7'h03 || id_opcode==7'h23 || id_opcode==7'h63 || id_opcode==7'h67);
    wire id_uses_rs2 = if_id_valid && (id_opcode==7'h33 || id_opcode==7'h23 || id_opcode==7'h63);

    reg [31:0] id_imm;
    always @* begin
        case (id_opcode)
            7'h03,7'h13,7'h67: id_imm = {{20{if_id_instr[31]}},if_id_instr[31:20]};
            7'h23: id_imm = {{20{if_id_instr[31]}},if_id_instr[31:25],if_id_instr[11:7]};
            7'h63: id_imm = {{19{if_id_instr[31]}},if_id_instr[31],if_id_instr[7],if_id_instr[30:25],if_id_instr[11:8],1'b0};
            7'h37,7'h17: id_imm = {if_id_instr[31:12],12'b0};
            7'h6f: id_imm = {{11{if_id_instr[31]}},if_id_instr[31],if_id_instr[19:12],if_id_instr[20],if_id_instr[30:21],1'b0};
            default: id_imm = 32'b0;
        endcase
    end

    wire cu_reg_write, cu_alu_src_b, cu_mem_read, cu_mem_write, cu_mem_to_reg, cu_branch;
    wire [3:0] cu_alu_control;
    control_unit cu(
        .opcode(id_opcode),.funct3(id_funct3),.funct7(if_id_instr[31:25]),
        .reg_write(cu_reg_write),.alu_src_b(cu_alu_src_b),.mem_read(cu_mem_read),
        .mem_write(cu_mem_write),.mem_to_reg(cu_mem_to_reg),
        .branch(cu_branch),.alu_control(cu_alu_control)
    );

    wire id_is_lui = id_opcode == 7'h37;
    wire id_is_auipc = id_opcode == 7'h17;
    wire id_is_jal = id_opcode == 7'h6f;
    wire id_is_jalr = id_opcode == 7'h67 && id_funct3 == 3'b000;
    wire id_reg_write = if_id_valid && ((cu_reg_write && (id_opcode!=7'h03 || id_funct3==3'b010)) ||
                                        id_is_lui || id_is_auipc || id_is_jal || id_is_jalr);
    wire id_mem_read = if_id_valid && cu_mem_read && id_funct3 == 3'b010;
    wire id_mem_write = if_id_valid && cu_mem_write && id_funct3 == 3'b010;
    wire id_branch = if_id_valid && cu_branch;
    wire id_use_imm = cu_alu_src_b || id_is_auipc;

    wire [31:0] id_rd1, id_rd2, rf_wd;
    wire [4:0] rf_wr;
    wire rf_we;
    regfile rf(.clk(clk),.rst_n(rst_n),.we(rf_we),.rs1(id_rs1),.rs2(id_rs2),
               .rd(rf_wr),.wd(rf_wd),.rd1(id_rd1),.rd2(id_rd2));

    // WB -> ID bypass covers the same-edge register-file write/read boundary.
    wire [31:0] id_value1 = (rf_we && rf_wr!=0 && rf_wr==id_rs1) ? rf_wd : id_rd1;
    wire [31:0] id_value2 = (rf_we && rf_wr!=0 && rf_wr==id_rs2) ? rf_wd : id_rd2;

    reg id_ex_valid;
    reg [31:0] id_ex_pc, id_ex_rd1, id_ex_rd2, id_ex_imm;
    reg [4:0] id_ex_rs1, id_ex_rs2, id_ex_rd;
    reg [2:0] id_ex_funct3;
    reg [3:0] id_ex_alu_op;
    reg id_ex_reg_write, id_ex_is_load, id_ex_is_store, id_ex_is_branch;
    reg id_ex_use_imm, id_ex_is_lui, id_ex_is_auipc, id_ex_is_jal, id_ex_is_jalr;

    // Load in EX produces data only in the next MEM stage. Freeze PC and
    // IF/ID, inject a bubble into ID/EX; ignore unused source-register fields.
    wire stall = id_ex_valid && id_ex_is_load && id_ex_rd!=0 && (
        (id_uses_rs1 && id_ex_rd==id_rs1) || (id_uses_rs2 && id_ex_rd==id_rs2));
    reg ex_mem_valid;
    reg [31:0] ex_mem_alu_res, ex_mem_write_data_reg;
    reg [4:0] ex_mem_rd;
    reg ex_mem_reg_write, ex_mem_is_load, ex_mem_is_store;
    reg mem_wb_valid;
    reg [31:0] mem_wb_alu_res, mem_wb_mem_read_data;
    reg [4:0] mem_wb_rd;
    reg mem_wb_reg_write, mem_wb_is_load;
    assign rf_we = mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 0;
    assign rf_wr = mem_wb_rd;
    assign rf_wd = mem_wb_is_load ? mem_wb_mem_read_data : mem_wb_alu_res;

    // Newer EX/MEM result wins over an older MEM/WB result. Load forwarding
    // from EX/MEM is deliberately disallowed until load data is available.
    wire ex_match1 = ex_mem_valid && ex_mem_reg_write && !ex_mem_is_load &&
                     ex_mem_rd!=0 && ex_mem_rd==id_ex_rs1;
    wire ex_match2 = ex_mem_valid && ex_mem_reg_write && !ex_mem_is_load &&
                     ex_mem_rd!=0 && ex_mem_rd==id_ex_rs2;
    wire wb_match1 = rf_we && rf_wr==id_ex_rs1;
    wire wb_match2 = rf_we && rf_wr==id_ex_rs2;
    wire [31:0] forward_a = ex_match1 ? ex_mem_alu_res :
                            wb_match1 ? rf_wd : id_ex_rd1;
    wire [31:0] forward_b = ex_match2 ? ex_mem_alu_res :
                            wb_match2 ? rf_wd : id_ex_rd2;
    wire [31:0] alu_a = id_ex_is_auipc ? id_ex_pc : forward_a;
    wire [31:0] alu_b = id_ex_use_imm ? id_ex_imm : forward_b;
    wire [31:0] ex_alu_result;
    alu alu0(.a(alu_a),.b(alu_b),.alu_control(id_ex_alu_op),.result(ex_alu_result),.zero());
    wire [31:0] ex_result = id_ex_is_lui ? id_ex_imm :
                            (id_ex_is_jal || id_ex_is_jalr) ? id_ex_pc+32'd4 : ex_alu_result;

    reg branch_condition;
    always @* begin
        case (id_ex_funct3)
            3'b000: branch_condition = forward_a == forward_b; // BEQ
            3'b001: branch_condition = forward_a != forward_b; // BNE
            3'b100: branch_condition = $signed(forward_a) < $signed(forward_b); // BLT
            3'b101: branch_condition = $signed(forward_a) >= $signed(forward_b); // BGE
            3'b110: branch_condition = forward_a < forward_b; // BLTU
            3'b111: branch_condition = forward_a >= forward_b; // BGEU
            default: branch_condition = 1'b0;
        endcase
    end
    wire redirect = id_ex_valid && ((id_ex_is_branch && branch_condition) ||
                                    id_ex_is_jal || id_ex_is_jalr);
    // B/J immediates already contain the low zero bit: never shift again.
    wire [31:0] redirect_target = id_ex_is_jalr ?
        ((forward_a + id_ex_imm) & 32'hffff_fffe) : id_ex_pc + id_ex_imm;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 0;
            if_id_pc <= 0;
            if_id_instr <= 0;
            if_id_valid <= 0;
        end else if (redirect) begin
            pc <= redirect_target;
            if_id_pc <= 0;
            if_id_instr <= 0;
            if_id_valid <= 0;
        end else if (!stall) begin
            pc <= pc + 32'd4;
            if_id_pc <= pc;
            if_id_instr <= if_instr;
            if_id_valid <= 1;
        end
    end

    // On redirect, kill the younger ID instruction before it executes.
    // On load-use stall, consume the EX load but inject one bubble.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || redirect || stall) begin
            id_ex_valid <= 0;
            id_ex_pc <= 0; id_ex_rd1 <= 0; id_ex_rd2 <= 0; id_ex_imm <= 0;
            id_ex_rs1 <= 0; id_ex_rs2 <= 0; id_ex_rd <= 0; id_ex_funct3 <= 0;
            id_ex_alu_op <= 0; id_ex_reg_write <= 0;
            id_ex_is_load <= 0; id_ex_is_store <= 0; id_ex_is_branch <= 0;
            id_ex_use_imm <= 0; id_ex_is_lui <= 0; id_ex_is_auipc <= 0;
            id_ex_is_jal <= 0; id_ex_is_jalr <= 0;
        end else begin
            id_ex_valid <= if_id_valid;
            id_ex_pc <= if_id_pc; id_ex_rd1 <= id_value1; id_ex_rd2 <= id_value2;
            id_ex_imm <= id_imm; id_ex_rs1 <= id_rs1; id_ex_rs2 <= id_rs2;
            id_ex_rd <= id_rd; id_ex_funct3 <= id_funct3;
            id_ex_alu_op <= cu_alu_control;
            id_ex_reg_write <= id_reg_write;
            id_ex_is_load <= id_mem_read; id_ex_is_store <= id_mem_write;
            id_ex_is_branch <= id_branch; id_ex_use_imm <= id_use_imm;
            id_ex_is_lui <= id_is_lui; id_ex_is_auipc <= id_is_auipc;
            id_ex_is_jal <= id_is_jal; id_ex_is_jalr <= id_is_jalr;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_valid <= 0; ex_mem_alu_res <= 0;
            ex_mem_write_data_reg <= 0; ex_mem_rd <= 0;
            ex_mem_reg_write <= 0; ex_mem_is_load <= 0; ex_mem_is_store <= 0;
        end else begin
            ex_mem_valid <= id_ex_valid;
            ex_mem_alu_res <= ex_result;
            ex_mem_write_data_reg <= forward_b;
            ex_mem_rd <= id_ex_rd;
            ex_mem_reg_write <= id_ex_reg_write;
            ex_mem_is_load <= id_ex_is_load;
            ex_mem_is_store <= id_ex_is_store;
        end
    end

    // One-cycle MEM model: word-aligned little-endian LW/SW only.
    // Read data for the current EX/MEM load and latch it with its matching
    // destination/control into MEM/WB (not a late extra EX/MEM register).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_valid <= 0; mem_wb_alu_res <= 0;
            mem_wb_mem_read_data <= 0; mem_wb_rd <= 0;
            mem_wb_reg_write <= 0; mem_wb_is_load <= 0;
        end else begin
            mem_wb_valid <= ex_mem_valid;
            mem_wb_alu_res <= ex_mem_alu_res;
            mem_wb_mem_read_data <= dmem[ex_mem_alu_res[11:2]];
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_is_load <= ex_mem_is_load;
        end
    end
    always @(posedge clk) begin
        if (rst_n && ex_mem_valid && ex_mem_is_store)
            dmem[ex_mem_alu_res[11:2]] <= ex_mem_write_data_reg;
    end
endmodule
`default_nettype wire
