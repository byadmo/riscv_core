`timescale 1ns/1ps
`default_nettype none
// Integrated five-stage educational RV32I-subset core.
// Pipeline: IF -> ID -> EX -> MEM -> WB.
// Data memory uses a single-outstanding synchronous request/response model.
// Default educational mode keeps the original self-contained memories.
// EXTERNAL_PORTS=1 disconnects both arrays from the datapath and exposes
// independent, single-outstanding I and D request/response channels.
module pipeline_core #(
    parameter integer DATA_LATENCY = 1,
    parameter integer DATA_MAX_EXTRA = 0,
    parameter integer EXTERNAL_PORTS = 0,
    parameter integer DATA_RESPONSE_DELAY = 0,
    // Opt-in fail-stop diagnostic interface, NOT privileged RISC-V traps.
    // Default mode retains historical simulator $fatal behavior.
    parameter integer FAULT_HALT = 0
)(
    input wire clk, input wire rst_n,
    output wire i_req_valid, input wire i_req_ready,
    output wire [31:0] i_req_addr,
    output wire [7:0] i_req_tag,
    input wire i_rsp_valid, output wire i_rsp_ready,
    input wire [31:0] i_rsp_addr, input wire [7:0] i_rsp_tag,
    input wire [31:0] i_rsp_data,
    output wire d_req_valid, input wire d_req_ready,
    output wire d_req_write, output wire [31:0] d_req_addr,
    output wire [7:0] d_req_tag,
    output wire [31:0] d_req_wdata, output wire [3:0] d_req_wstrb,
    input wire d_rsp_valid, output wire d_rsp_ready,
    input wire [7:0] d_rsp_tag,
    input wire [31:0] d_rsp_rdata,
    output reg fault_valid,
    output reg [31:0] fault_cause,
    output reg [31:0] fault_pc,
    output reg [31:0] fault_tval
);
    reg [31:0] imem [0:1023];

    reg [31:0] pc;
    reg [31:0] if_id_pc, if_id_instr;
    reg if_id_valid;
    wire [31:0] if_instr = imem[pc[11:2]];
    // External fetch: only one request may be outstanding. Returned words are
    // buffered until decode can advance. Redirect increments an epoch so an
    // obsolete request can be drained without ever entering the pipeline.
    reg if_pending, if_buffer_valid, if_request_waiting;
    reg [31:0] if_pending_pc, if_buffer_instr, if_request_pc;
    reg [7:0] if_pending_tag, fetch_epoch, if_request_tag;
    wire if_old_request = if_pending && if_pending_tag != fetch_epoch;
    // Queue even before acceptance so valid/address/tag cannot change when
    // !req_ready. Redirect makes such a queued request stale, but it must
    // still be accepted and drained unless the bus offers cancellation.
    assign i_req_valid = EXTERNAL_PORTS && rst_n && if_request_waiting;
    assign i_req_addr = if_request_pc;
    assign i_req_tag = if_request_tag;
    assign i_rsp_ready = EXTERNAL_PORTS && rst_n && if_pending &&
                         !if_buffer_valid && (!mem_hold || if_old_request);
    wire fetch_accept = i_req_valid && i_req_ready;
    wire fetch_response = i_rsp_valid && i_rsp_ready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_pending <= 0; if_buffer_valid <= 0;
            if_pending_pc <= 0; if_buffer_instr <= 0;
            if_pending_tag <= 0; fetch_epoch <= 0;
            if_request_waiting <= 0; if_request_pc <= 0;
            if_request_tag <= 0;
        end else if (EXTERNAL_PORTS) begin
            if (!if_pending && !if_buffer_valid && !if_request_waiting &&
                !redirect && !mem_hold && !fault_event && !fault_valid) begin
                if_request_waiting <= 1;
                if_request_pc <= pc;
                if_request_tag <= fetch_epoch;
            end
            if (redirect || fault_event)
                fetch_epoch <= fetch_epoch + 1'b1;
            if (redirect || fault_event || fault_valid) begin
                if_buffer_valid <= 0;
            end else if (!mem_hold && !stall && if_buffer_valid)
                if_buffer_valid <= 0;
            if (fetch_accept) begin
                if_request_waiting <= 0;
                if_pending <= 1;
                if_pending_pc <= i_req_addr;
                if_pending_tag <= i_req_tag;
            end
            if (fetch_response) begin
                if_pending <= 0;
                if (!redirect && !fault_event && !fault_valid && !if_old_request) begin
                    if_buffer_valid <= 1;
                    if_buffer_instr <= i_rsp_data;
                end
            end
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk)
        if (rst_n && EXTERNAL_PORTS && fetch_response &&
            (i_rsp_addr !== if_pending_pc || i_rsp_tag !== if_pending_tag))
            $fatal(1,"Instruction response identity mismatch: expected PC=%08h tag=%0d, actual PC=%08h tag=%0d",
                   if_pending_pc,if_pending_tag,i_rsp_addr,i_rsp_tag);
`endif
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
    wire id_load_supported = id_funct3==3'b000 || id_funct3==3'b001 ||
                             id_funct3==3'b010 || id_funct3==3'b100 || id_funct3==3'b101;
    wire id_store_supported = id_funct3==3'b000 || id_funct3==3'b001 || id_funct3==3'b010;
    // Check the complete supported 32-bit instruction encoding, rather than
    // letting the legacy decoder quietly treat reserved encodings as NOPs.
    // RV32I SYSTEM, FENCE and privileged instructions remain unsupported.
    reg id_legal;
    always @* begin
        id_legal = 1'b0;
        case (id_opcode)
            7'h33: begin // OP: only ADD/SUB and SRL/SRA permit funct7=0100000.
                if (id_funct3 == 3'b000 || id_funct3 == 3'b101)
                    id_legal = if_id_instr[31:25] == 7'b0000000 ||
                               if_id_instr[31:25] == 7'b0100000;
                else
                    id_legal = if_id_instr[31:25] == 7'b0000000;
            end
            7'h13: begin // OP-IMM: exact upper immediate bits for shifts.
                if (id_funct3 == 3'b001)
                    id_legal = if_id_instr[31:25] == 7'b0000000;
                else if (id_funct3 == 3'b101)
                    id_legal = if_id_instr[31:25] == 7'b0000000 ||
                               if_id_instr[31:25] == 7'b0100000;
                else
                    id_legal = 1'b1;
            end
            7'h03: id_legal = id_load_supported;
            7'h23: id_legal = id_store_supported;
            7'h63: id_legal = id_funct3 == 3'b000 || id_funct3 == 3'b001 ||
                              id_funct3 == 3'b100 || id_funct3 == 3'b101 ||
                              id_funct3 == 3'b110 || id_funct3 == 3'b111;
            7'h67: id_legal = id_funct3 == 3'b000;
            7'h37, 7'h17, 7'h6f: id_legal = 1'b1;
            default: id_legal = 1'b0;
        endcase
    end
    wire id_reg_write = if_id_valid && ((cu_reg_write && (id_opcode!=7'h03 || id_load_supported)) ||
                                        id_is_lui || id_is_auipc || id_is_jal || id_is_jalr);
    wire id_mem_read = if_id_valid && cu_mem_read && id_load_supported;
    wire id_mem_write = if_id_valid && cu_mem_write && id_store_supported;
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
    reg [31:0] id_ex_instr;
    reg id_ex_illegal;
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
    reg [2:0] ex_mem_funct3;
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
    wire redirect = id_ex_valid && !mem_hold && ((id_ex_is_branch && branch_condition) ||
                                    id_ex_is_jal || id_ex_is_jalr);
    // B/J immediates already contain the low zero bit: never shift again.
    wire [31:0] redirect_target = id_ex_is_jalr ?
        ((forward_a + id_ex_imm) & 32'hffff_fffe) : id_ex_pc + id_ex_imm;
    wire [1:0] ex_mem_lane = ex_alu_result[1:0];
    wire ex_bad_align = (id_ex_is_load || id_ex_is_store) &&
        (((id_ex_funct3 == 3'b001 || id_ex_funct3 == 3'b101) && ex_mem_lane[0]) ||
         (id_ex_funct3 == 3'b010 && ex_mem_lane != 0));
    wire ex_bad_range = (id_ex_is_load || id_ex_is_store) && |ex_alu_result[31:12];
    wire ex_target_bad = redirect && redirect_target[1:0] != 2'b00;
    // Observe faults at EX, after any older memory operation drains. This
    // makes fault reporting precise without ever issuing the invalid D access.
    wire fault_event = FAULT_HALT && !fault_valid && id_ex_valid && !mem_hold &&
                       (id_ex_illegal || ex_bad_align || ex_bad_range || ex_target_bad);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_valid <= 0;
            fault_cause <= 0;
            fault_pc <= 0;
            fault_tval <= 0;
        end else if (fault_event) begin
            fault_valid <= 1;
            fault_pc <= id_ex_pc;
            if (id_ex_illegal) begin
                fault_cause <= 32'd2;
                fault_tval <= id_ex_instr;
            end else if (ex_bad_align) begin
                fault_cause <= id_ex_is_store ? 32'd6 : 32'd4;
                fault_tval <= ex_alu_result;
            end else if (ex_bad_range) begin
                fault_cause <= id_ex_is_store ? 32'd7 : 32'd5;
                fault_tval <= ex_alu_result;
            end else begin
                fault_cause <= 32'd0;
                fault_tval <= redirect_target;
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 0;
            if_id_pc <= 0;
            if_id_instr <= 0;
            if_id_valid <= 0;
        end else if (fault_event || fault_valid) begin
            // Stop fetch progression and discard younger prefetched work;
            // the exact faulting instruction PC is latched from ID/EX.
            if_id_valid <= 0;
            if_id_instr <= 0;
        end else if (mem_hold) begin
            // Older data-memory operation blocks any younger redirect or fetch.
        end else if (redirect) begin
            pc <= redirect_target;
            if_id_pc <= 0;
            if_id_instr <= 0;
            if_id_valid <= 0;
        end else if (!stall) begin
            if (EXTERNAL_PORTS) begin
                if_id_valid <= if_buffer_valid;
                if (if_buffer_valid) begin
                    pc <= pc + 32'd4;
                    if_id_pc <= pc;
                    if_id_instr <= if_buffer_instr;
                end
            end else begin
                pc <= pc + 32'd4;
                if_id_pc <= pc;
                if_id_instr <= if_instr;
                if_id_valid <= 1;
            end
        end
    end

    // On redirect, kill the younger ID instruction before it executes.
    // On load-use stall, consume the EX load but inject one bubble.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_valid <= 0;
            id_ex_instr <= 0; id_ex_illegal <= 0;
            id_ex_pc <= 0; id_ex_rd1 <= 0; id_ex_rd2 <= 0; id_ex_imm <= 0;
            id_ex_rs1 <= 0; id_ex_rs2 <= 0; id_ex_rd <= 0; id_ex_funct3 <= 0;
            id_ex_alu_op <= 0; id_ex_reg_write <= 0;
            id_ex_is_load <= 0; id_ex_is_store <= 0; id_ex_is_branch <= 0;
            id_ex_use_imm <= 0; id_ex_is_lui <= 0; id_ex_is_auipc <= 0;
            id_ex_is_jal <= 0; id_ex_is_jalr <= 0;
        end else if (mem_hold) begin
            // MEM/WB can retire during the first wait cycle. Preserve those
            // operands in a held ID/EX so forwarding is not lost when WB drains.
            if (rf_we && rf_wr == id_ex_rs1) id_ex_rd1 <= rf_wd;
            if (rf_we && rf_wr == id_ex_rs2) id_ex_rd2 <= rf_wd;
        end else if (fault_event || fault_valid || redirect || stall) begin
            id_ex_valid <= 0;
            id_ex_instr <= 0; id_ex_illegal <= 0;
            id_ex_pc <= 0; id_ex_rd1 <= 0; id_ex_rd2 <= 0; id_ex_imm <= 0;
            id_ex_rs1 <= 0; id_ex_rs2 <= 0; id_ex_rd <= 0; id_ex_funct3 <= 0;
            id_ex_alu_op <= 0; id_ex_reg_write <= 0;
            id_ex_is_load <= 0; id_ex_is_store <= 0; id_ex_is_branch <= 0;
            id_ex_use_imm <= 0; id_ex_is_lui <= 0; id_ex_is_auipc <= 0;
            id_ex_is_jal <= 0; id_ex_is_jalr <= 0;
        end else begin
            id_ex_valid <= if_id_valid;
            id_ex_instr <= if_id_instr;
            id_ex_illegal <= if_id_valid && !id_legal;
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
            ex_mem_funct3 <= 0;
        end else if (fault_event || fault_valid) begin
            // The older EX/MEM instruction still flows to WB this cycle; the
            // faulting EX instruction itself must never reach MEM.
            ex_mem_valid <= 0;
            ex_mem_reg_write <= 0;
            ex_mem_is_load <= 0;
            ex_mem_is_store <= 0;
        end else if (mem_hold) begin
            // A response completes exactly one outstanding operation. Vacate
            // EX/MEM but preserve younger ID/EX for the following cycle so a
            // newly returned load can forward from MEM/WB.
            if (mem_rsp_valid) begin
                ex_mem_valid <= 0;
                ex_mem_reg_write <= 0;
                ex_mem_is_load <= 0;
                ex_mem_is_store <= 0;
            end
        end else begin
            ex_mem_valid <= id_ex_valid;
            ex_mem_alu_res <= ex_result;
            ex_mem_write_data_reg <= forward_b;
            ex_mem_rd <= id_ex_rd;
            ex_mem_reg_write <= id_ex_reg_write;
            ex_mem_is_load <= id_ex_is_load;
            ex_mem_is_store <= id_ex_is_store;
            ex_mem_funct3 <= id_ex_funct3;
        end
    end
    wire mem_op = ex_mem_valid && (ex_mem_is_load || ex_mem_is_store);
    wire mem_hold = mem_op;
    reg mem_issued;
    reg [7:0] next_data_tag, data_outstanding_tag;
    // DATA_RESPONSE_DELAY intentionally makes the core deassert response
    // readiness for bounded cycles, exercising held external responses.
    localparam integer DCW = DATA_RESPONSE_DELAY > 0 ? $clog2(DATA_RESPONSE_DELAY+2) : 1;
    reg [DCW-1:0] data_response_wait;
    assign d_req_valid = EXTERNAL_PORTS && rst_n && mem_op && !mem_issued;
    assign d_req_write = ex_mem_is_store;
    assign d_req_addr = ex_mem_alu_res;
    assign d_req_tag = next_data_tag;
    assign d_req_wdata = mem_store_data;
    assign d_req_wstrb = mem_store_strb;
    assign d_rsp_ready = EXTERNAL_PORTS && rst_n && mem_op && mem_issued &&
                          data_response_wait >= DATA_RESPONSE_DELAY;
    wire d_req_fire = d_req_valid && d_req_ready;
    wire d_rsp_fire = d_rsp_valid && d_rsp_ready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_issued <= 0;
            data_response_wait <= 0;
            next_data_tag <= 0;
            data_outstanding_tag <= 0;
        end else if (EXTERNAL_PORTS) begin
            if (d_req_fire) begin
                mem_issued <= 1;
                data_outstanding_tag <= d_req_tag;
                next_data_tag <= next_data_tag + 1'b1;
                data_response_wait <= 0;
            end else if (mem_issued && mem_op && !d_rsp_fire) begin
                if (data_response_wait < DATA_RESPONSE_DELAY)
                    data_response_wait <= data_response_wait + 1'b1;
            end
            if (d_rsp_fire) begin
                mem_issued <= 0;
                data_response_wait <= 0;
            end
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk)
        if (rst_n && EXTERNAL_PORTS && d_rsp_fire && d_rsp_tag !== data_outstanding_tag)
            $fatal(1,"Data response tag mismatch: expected %0d actual %0d",
                   data_outstanding_tag,d_rsp_tag);
`endif
    wire mem_req_valid = mem_op && !EXTERNAL_PORTS;
    wire mem_req_ready, model_rsp_valid;
    wire [31:0] model_rsp_rdata;
    wire mem_rsp_valid = EXTERNAL_PORTS ? d_rsp_fire : model_rsp_valid;
    wire [31:0] mem_rsp_rdata = EXTERNAL_PORTS ? d_rsp_rdata : model_rsp_rdata;
    wire [1:0] mem_lane = ex_mem_alu_res[1:0];
    wire [4:0] mem_shift = {mem_lane,3'b000};
    wire [31:0] mem_store_data = ex_mem_write_data_reg << mem_shift;
    wire [3:0] mem_store_strb =
        ex_mem_funct3==3'b000 ? (4'b0001 << mem_lane) :
        ex_mem_funct3==3'b001 ? (4'b0011 << mem_lane) : 4'b1111;
    // Word memory returns an aligned 32-bit word. Extract requested little-
    // endian lane and sign/zero-extend in the CPU's final MEM step.
    wire [31:0] mem_shifted = mem_rsp_rdata >> mem_shift;
    reg [31:0] mem_load_value;
    always @* begin
        case (ex_mem_funct3)
            3'b000: mem_load_value = {{24{mem_shifted[7]}},mem_shifted[7:0]}; // LB
            3'b001: mem_load_value = {{16{mem_shifted[15]}},mem_shifted[15:0]}; // LH
            3'b100: mem_load_value = {24'b0,mem_shifted[7:0]}; // LBU
            3'b101: mem_load_value = {16'b0,mem_shifted[15:0]}; // LHU
            default: mem_load_value = mem_rsp_rdata; // LW
        endcase
    end
    latency_data_memory #(.LATENCY(DATA_LATENCY),.MAX_EXTRA(DATA_MAX_EXTRA)) mem_model (
        .clk(clk), .rst_n(rst_n), .req_valid(mem_req_valid),
        .req_ready(mem_req_ready), .req_write(ex_mem_is_store),
        .req_addr(ex_mem_alu_res), .req_wdata(mem_store_data),
        .req_wstrb(mem_store_strb), .rsp_valid(model_rsp_valid),
        .rsp_rdata(model_rsp_rdata)
    );
    // No exception/trap pipeline yet: reject unsupported addresses in
    // simulation rather than aliasing silently to a different word or lane.
    wire mem_bad_align = ((ex_mem_funct3 == 3'b001 || ex_mem_funct3 == 3'b101) && mem_lane[0]) ||
                         (ex_mem_funct3 == 3'b010 && mem_lane != 0);
    wire mem_bad_range = |ex_mem_alu_res[31:12];
`ifndef SYNTHESIS
    always @(posedge clk)
        if (rst_n && ((EXTERNAL_PORTS && d_req_fire) ||
                      (!EXTERNAL_PORTS && mem_req_valid && mem_req_ready)) &&
            (mem_bad_align || mem_bad_range))
            $fatal(1, "Unsupported memory access: address=%08h funct3=%03b align=%b range=%b",
                   ex_mem_alu_res,ex_mem_funct3,mem_bad_align,mem_bad_range);
`endif
    // Response is consumed at most once and paired with destination/control.
    // A waiting memory operation bubbles MEM/WB after the old WB has retired;
    // it cannot repeatedly commit a store or register write.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_valid <= 0; mem_wb_alu_res <= 0;
            mem_wb_mem_read_data <= 0; mem_wb_rd <= 0;
            mem_wb_reg_write <= 0; mem_wb_is_load <= 0;
        end else if (fault_valid) begin
            // One older non-memory instruction may have reached WB on the
            // preceding fault edge; let it commit exactly once, then drain.
            mem_wb_valid <= 0;
        end else if (mem_hold) begin
            mem_wb_valid <= mem_rsp_valid && ex_mem_valid;
            mem_wb_alu_res <= ex_mem_alu_res;
            mem_wb_mem_read_data <= mem_load_value;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_is_load <= ex_mem_is_load;
        end else begin
            mem_wb_valid <= ex_mem_valid;
            mem_wb_alu_res <= ex_mem_alu_res;
            mem_wb_mem_read_data <= 0;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_is_load <= ex_mem_is_load;
        end
    end
endmodule
`default_nettype wire
