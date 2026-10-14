`timescale 1ns/1ps
`default_nettype none
// Independent latency-aware, architectural RV32I memory regression.
//
// Run one configuration at a time:
//   iverilog -g2012 -s tb_memory_latency_rv32i \
//     -Ptb_memory_latency_rv32i.DATA_LATENCY=4 \
//     rtl/pipeline_core.sv rtl/latency_data_memory.sv rtl/alu.sv \
//     rtl/control_unit.sv rtl/regfile.sv tb/tb_memory_latency_rv32i.sv \
//     -o /tmp/memory_latency.vvp
//   vvp /tmp/memory_latency.vvp
// Repeat with DATA_LATENCY=1,2,4 and optionally
// -Ptb_memory_latency_rv32i.DATA_MAX_EXTRA=3 to vary transaction latency.
// The memory model must implement aligned
// little-endian LB/LBU/LH/LHU/SB/SH alongside LW/SW.
//
// Memory state and the complete register file are the oracle: this test does
// not rely on names or timing of private pipeline stall/ready machinery.
module tb_memory_latency_rv32i #(
    parameter integer DATA_LATENCY = 1,
    parameter integer DATA_MAX_EXTRA = 0
);
    localparam integer MEMORY_WORDS = 1024;
    localparam [31:0] NOP = 32'h00000013;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    pipeline_core #(
        .DATA_LATENCY(DATA_LATENCY),
        .DATA_MAX_EXTRA(DATA_MAX_EXTRA)
    ) dut(
        .clk(clk), .rst_n(rst_n)
    );

    reg [31:0] expected_regs [0:31];
    reg [31:0] expected_mem [0:MEMORY_WORDS-1];
    reg [8*80-1:0] case_name;
    integer cases_passed = 0;
    integer state_checks = 0;
    integer req_count = 0;
    integer rsp_count = 0;
    integer store_req_count = 0;
    integer store_rsp_count = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.mem_model.req_valid && dut.mem_model.req_ready) begin
                req_count = req_count + 1;
                if (dut.mem_model.req_write)
                    store_req_count = store_req_count + 1;
            end
            if (dut.mem_model.rsp_valid) begin
                rsp_count = rsp_count + 1;
                if (dut.mem_model.response_write)
                    store_rsp_count = store_rsp_count + 1;
            end
        end
    end

    function automatic [31:0] encode_i(
        input integer imm,
        input [4:0] rs1,
        input [2:0] f3,
        input [4:0] rd,
        input [6:0] opcode
    );
        encode_i = {imm[11:0], rs1, f3, rd, opcode};
    endfunction

    function automatic [31:0] encode_r(
        input [6:0] f7,
        input [4:0] rs2, rs1,
        input [2:0] f3,
        input [4:0] rd
    );
        encode_r = {f7,rs2,rs1,f3,rd,7'h33};
    endfunction

    function automatic [31:0] encode_s(
        input integer imm,
        input [4:0] rs2, rs1,
        input [2:0] f3
    );
        encode_s = {imm[11:5],rs2,rs1,f3,imm[4:0],7'h23};
    endfunction

    function automatic [31:0] encode_b(
        input integer offset,
        input [4:0] rs1, rs2,
        input [2:0] f3
    );
        begin
            if ((offset & 1) != 0 || offset < -4096 || offset > 4094)
                $fatal(1,"Invalid B-type byte offset %0d",offset);
            encode_b = {offset[12],offset[10:5],rs2,rs1,f3,
                        offset[4:1],offset[11],7'h63};
        end
    endfunction

    function automatic [31:0] addi(input [4:0] rd,rs1,input integer imm);
        addi = encode_i(imm,rs1,3'b000,rd,7'h13);
    endfunction

    function automatic [31:0] add(input [4:0] rd,rs1,rs2);
        add = encode_r(7'b0,rs2,rs1,3'b000,rd);
    endfunction

    function automatic [31:0] lw(input [4:0] rd,rs1,input integer imm);
        lw = encode_i(imm,rs1,3'b010,rd,7'h03);
    endfunction

    function automatic [31:0] sw(input [4:0] rs2,rs1,input integer imm);
        sw = encode_s(imm,rs2,rs1,3'b010);
    endfunction

    function automatic [31:0] beq(input [4:0] rs1,rs2,input integer offset);
        beq = encode_b(offset,rs1,rs2,3'b000);
    endfunction

    function automatic [31:0] bne(input [4:0] rs1,rs2,input integer offset);
        bne = encode_b(offset,rs1,rs2,3'b001);
    endfunction

    // Each case runs on an independently reset CPU with defined RAM contents.
    // Reset remains asserted while we load the program and data words.
    task automatic prepare(input [8*80-1:0] label);
        integer k;
        begin
            @(negedge clk);
            rst_n = 0;
            case_name = label;
            req_count = 0;
            rsp_count = 0;
            store_req_count = 0;
            store_rsp_count = 0;
            for (k=0; k<MEMORY_WORDS; k=k+1) begin
                dut.imem[k] = NOP;
                dut.mem_model.words[k] = 32'b0;
                expected_mem[k] = 32'b0;
            end
            for (k=0; k<32; k=k+1)
                expected_regs[k] = 32'b0;
        end
    endtask

    task automatic preload(input integer index,input [31:0] value);
        begin
            if (index < 0 || index >= MEMORY_WORDS)
                $fatal(1,"Invalid preload index %0d",index);
            dut.mem_model.words[index] = value;
            expected_mem[index] = value;
        end
    endtask

    task automatic expect_reg(input integer index,input [31:0] value);
        begin
            if (index < 0 || index > 31)
                $fatal(1,"Invalid register index %0d",index);
            expected_regs[index] = value;
        end
    endtask

    task automatic expect_mem(input integer index,input [31:0] value);
        begin
            if (index < 0 || index >= MEMORY_WORDS)
                $fatal(1,"Invalid memory index %0d",index);
            expected_mem[index] = value;
        end
    endtask

    task automatic check_architecture;
        integer k;
        begin
            for (k=0;k<32;k=k+1) begin
                if (dut.rf.regs[k] !== expected_regs[k]) begin
                    $display("FAIL latency=%0d case=%0s x%0d expected=%08h actual=%08h pc=%08h",
                             DATA_LATENCY,case_name,k,expected_regs[k],dut.rf.regs[k],dut.pc);
                    $fatal(1,"Architectural register mismatch");
                end
                state_checks = state_checks + 1;
            end
            for (k=0;k<MEMORY_WORDS;k=k+1) begin
                if (dut.mem_model.words[k] !== expected_mem[k]) begin
                    $display("FAIL latency=%0d case=%0s dmem[%0d] expected=%08h actual=%08h pc=%08h",
                             DATA_LATENCY,case_name,k,expected_mem[k],dut.mem_model.words[k],dut.pc);
                    $fatal(1,"Architectural memory mismatch");
                end
                state_checks = state_checks + 1;
            end
        end
    endtask

    // x31 is a unique completion marker, written by the LAST instruction of
    // each directed program. It accommodates stalls/variable latency without
    // making assumptions about exact pipeline cycles or stage valid signals.
    // Read state at negedge after a bounded drain to catch late wrong-path
    // writes as well as delayed stores.
    task automatic run_case(input [31:0] done_marker,input integer max_cycles,
                            input integer expected_requests,input integer expected_stores);
        integer cycles;
        begin
            repeat (3) @(negedge clk);
            rst_n = 1;
            cycles = 0;
            while (dut.rf.regs[31] !== done_marker && cycles < max_cycles) begin
                @(negedge clk);
                cycles = cycles+1;
                if (^dut.pc === 1'bx)
                    $fatal(1,"Unknown PC latency=%0d case=%0s cycle=%0d",
                           DATA_LATENCY,case_name,cycles);
            end
            if (dut.rf.regs[31] !== done_marker)
                $fatal(1,"Completion timeout latency=%0d case=%0s cycles=%0d pc=%08h x31=%08h",
                       DATA_LATENCY,case_name,cycles,dut.pc,dut.rf.regs[31]);
            repeat (12+DATA_LATENCY*4) @(negedge clk);
            check_architecture();
            if (req_count !== expected_requests ||
                rsp_count !== expected_requests ||
                store_req_count !== expected_stores ||
                store_rsp_count !== expected_stores)
                $fatal(1,"Request/response cardinality: latency=%0d extra=%0d case=%0s expected req/store %0d/%0d; got req/rsp/storeReq/storeRsp %0d/%0d/%0d/%0d",
                       DATA_LATENCY,DATA_MAX_EXTRA,case_name,expected_requests,expected_stores,
                       req_count,rsp_count,store_req_count,store_rsp_count);
            cases_passed = cases_passed + 1;
            $display("PASS DATA_LATENCY=%0d extra=%0d %-35s cycles=%0d req/rsp=%0d/%0d stores=%0d",
                     DATA_LATENCY,DATA_MAX_EXTRA,case_name,cycles,req_count,rsp_count,store_rsp_count);
        end
    endtask

    task automatic test_dense_memory;
        begin
            prepare("back-to-back LW/SW, RAW and address");
            // Back-to-back stores, loads and store-to-load same-address ordering.
            // Includes EX->store-data forwarding and load->store-data dependency.
            preload(10,32'h1badb002); // untouched sentry
            dut.imem[0]  = addi(1,0,73);
            dut.imem[1]  = sw(1,0,0);
            dut.imem[2]  = sw(1,0,4);
            dut.imem[3]  = lw(2,0,0);
            dut.imem[4]  = lw(3,0,4);
            dut.imem[5]  = add(4,2,3);
            dut.imem[6]  = sw(4,0,8);
            dut.imem[7]  = lw(5,0,8);
            dut.imem[8]  = addi(6,5,-1);
            dut.imem[9]  = sw(6,0,12);
            dut.imem[10] = lw(7,0,12);
            dut.imem[11] = sw(7,0,16);
            dut.imem[12] = lw(8,0,16);
            dut.imem[13] = addi(9,0,32);
            dut.imem[14] = sw(8,9,-12);
            dut.imem[15] = lw(10,9,-12);
            dut.imem[16] = addi(31,0,1);
            expect_reg(1,73); expect_reg(2,73); expect_reg(3,73);
            expect_reg(4,146); expect_reg(5,146); expect_reg(6,145);
            expect_reg(7,145); expect_reg(8,145); expect_reg(9,32);
            expect_reg(10,145); expect_reg(31,1);
            expect_mem(0,73); expect_mem(1,73); expect_mem(2,146);
            expect_mem(3,145); expect_mem(4,145); expect_mem(5,145);
            run_case(1,120+(DATA_LATENCY+DATA_MAX_EXTRA)*90,12,6);
        end
    endtask

    task automatic test_consecutive_loads;
        begin
            prepare("consecutive delayed loads and stores");
            preload(12,32'hfffffff9); // -7
            preload(13,256);
            preload(14,3);
            preload(18,32'hfeedbaad); // sentinel against stray stores
            dut.imem[0]  = lw(1,0,48);
            dut.imem[1]  = lw(2,0,52);
            dut.imem[2]  = lw(3,0,56);
            dut.imem[3]  = add(4,1,2);        // -7+256=249
            dut.imem[4]  = add(5,4,3);        // 252
            dut.imem[5]  = sw(5,0,60);
            dut.imem[6]  = lw(6,0,60);
            dut.imem[7]  = addi(7,6,-7);      // 245
            dut.imem[8]  = sw(7,0,64);
            dut.imem[9]  = lw(8,0,64);
            dut.imem[10] = add(9,8,0);
            dut.imem[11] = sw(9,0,68);
            dut.imem[12] = lw(10,0,68);
            dut.imem[13] = addi(31,0,2);
            expect_reg(1,32'hfffffff9); expect_reg(2,256);
            expect_reg(3,3); expect_reg(4,249); expect_reg(5,252);
            expect_reg(6,252); expect_reg(7,245); expect_reg(8,245);
            expect_reg(9,245); expect_reg(10,245); expect_reg(31,2);
            expect_mem(15,252); expect_mem(16,245); expect_mem(17,245);
            run_case(2,120+(DATA_LATENCY+DATA_MAX_EXTRA)*90,9,3);
        end
    endtask

    task automatic test_branch_flush;
        begin
            prepare("loads + redirect + wrong-path stores");
            preload(20,9);
            preload(21,9);
            preload(22,32'h4444);
            preload(23,32'h5555);
            preload(26,32'h9999);
            dut.imem[0]  = lw(1,0,80);
            dut.imem[1]  = lw(2,0,84);
            dut.imem[2]  = beq(1,2,16);      // taken -> instruction 6
            dut.imem[3]  = sw(1,0,88);       // wrong-path store: must preserve sentinel
            dut.imem[4]  = lw(10,0,92);      // wrong-path load must not write x10
            dut.imem[5]  = addi(11,0,55);    // wrong-path register write
            dut.imem[6]  = lw(3,0,88);       // sentinel 0x4444
            dut.imem[7]  = addi(4,3,1);      // 0x4445, immediate load-use
            dut.imem[8]  = bne(3,4,12);      // taken -> instruction 11
            dut.imem[9]  = sw(4,0,92);       // wrong-path store
            dut.imem[10] = addi(12,0,71);    // wrong-path write
            dut.imem[11] = sw(4,0,96);       // legitimate store after branch
            dut.imem[12] = lw(5,0,96);
            dut.imem[13] = beq(5,4,8);       // taken -> instruction 15
            dut.imem[14] = sw(5,0,100);      // wrong-path store
            dut.imem[15] = addi(6,0,6);
            dut.imem[16] = bne(6,6,8);       // not taken
            dut.imem[17] = addi(7,0,7);
            dut.imem[18] = sw(7,0,100);
            dut.imem[19] = lw(8,0,100);
            dut.imem[20] = addi(9,0,22);
            dut.imem[21] = sw(9,0,104);      // older store must complete
            dut.imem[22] = beq(9,9,8);       // taken with store outstanding
            dut.imem[23] = sw(0,0,104);      // wrong-path store must not overwrite
            dut.imem[24] = lw(13,0,104);
            dut.imem[25] = addi(31,0,3);
            expect_reg(1,9); expect_reg(2,9); expect_reg(3,32'h4444);
            expect_reg(4,32'h4445); expect_reg(5,32'h4445);
            expect_reg(6,6); expect_reg(7,7); expect_reg(8,7);
            expect_reg(9,22); expect_reg(13,22); expect_reg(31,3);
            expect_mem(24,32'h4445); expect_mem(25,7); expect_mem(26,22);
            run_case(3,140+(DATA_LATENCY+DATA_MAX_EXTRA)*100,9,3);
        end
    endtask

    task automatic test_backward_branch;
        begin
            prepare("loaded loop bound and backward branch");
            preload(40,3);
            preload(41,32'hdeadbeef);
            dut.imem[0]  = lw(1,0,160);      // loop bound from delayed memory
            dut.imem[1]  = addi(2,0,0);
            dut.imem[2]  = addi(2,2,1);
            dut.imem[3]  = bne(2,1,-4);       // taken twice, then exit
            dut.imem[4]  = sw(2,0,164);
            dut.imem[5]  = lw(3,0,164);
            dut.imem[6]  = beq(3,1,12);       // taken -> instruction 9
            dut.imem[7]  = sw(0,0,164);       // wrong path must preserve loop result
            dut.imem[8]  = addi(20,0,90);     // wrong path
            dut.imem[9]  = sw(3,0,168);
            dut.imem[10] = lw(4,0,168);
            dut.imem[11] = addi(31,0,4);
            expect_reg(1,3); expect_reg(2,3); expect_reg(3,3);
            expect_reg(4,3); expect_reg(31,4);
            expect_mem(41,3); expect_mem(42,3);
            run_case(4,120+(DATA_LATENCY+DATA_MAX_EXTRA)*100,5,2);
        end
    endtask

    // Reset while a store request is outstanding must cancel that request,
    // clear the pipeline, and allow a fresh program to run against unchanged
    // RAM. For LATENCY=1 there is no multi-cycle busy window; assert reset
    // before the pending store's completion edge instead.
    task automatic test_reset_pending_store;
        integer cycles;
        reg observed_pending;
        begin
            prepare("reset during pending memory store");
            preload(60,321);
            dut.imem[0] = addi(1,0,99);
            dut.imem[1] = sw(1,0,240);
            dut.imem[2] = addi(31,0,99);
            repeat (3) @(negedge clk);
            rst_n = 1;
            cycles = 0;
            observed_pending = 0;
            while (!observed_pending && cycles < 70+DATA_LATENCY*10) begin
                @(negedge clk);
                cycles = cycles+1;
                if (DATA_LATENCY > 1)
                    observed_pending = dut.mem_model.busy && dut.mem_model.saved_write;
                else
                    observed_pending = dut.mem_model.req_valid &&
                                       dut.mem_model.req_write &&
                                       dut.mem_model.req_ready;
            end
            if (!observed_pending)
                $fatal(1,"No pending store before reset, latency=%0d pc=%08h",
                       DATA_LATENCY,dut.pc);
            // We are on a falling edge with an accepted store still uncommitted.
            if (dut.mem_model.words[60] !== 321)
                $fatal(1,"Premature store before reset, latency=%0d",DATA_LATENCY);
            rst_n = 0;
            req_count = 0;
            rsp_count = 0;
            store_req_count = 0;
            store_rsp_count = 0;
            repeat (3) @(negedge clk);
            if (dut.mem_model.busy !== 1'b0)
                $fatal(1,"Memory busy survived reset, latency=%0d",DATA_LATENCY);
            if (dut.mem_model.words[60] !== 321)
                $fatal(1,"Canceled store wrote RAM after reset, latency=%0d",DATA_LATENCY);

            // Same RAM, fresh instruction stream. The old store and the old
            // completion marker must never reappear after reset deasserts.
            dut.imem[0] = lw(2,0,240);
            dut.imem[1] = addi(3,2,1);
            dut.imem[2] = sw(3,0,244);
            dut.imem[3] = lw(4,0,244);
            dut.imem[4] = addi(31,0,6);
            expect_reg(2,321); expect_reg(3,322);
            expect_reg(4,322); expect_reg(31,6);
            expect_mem(61,322);
            run_case(6,120+(DATA_LATENCY+DATA_MAX_EXTRA)*90,3,1);
        end
    endtask

    // RV32I little-endian byte/halfword loads and masked byte/halfword stores.
    task automatic test_subword;
        begin
            prepare("byte/halfword sign extension and lanes");
            preload(30,32'h80ff7f01);
            preload(31,32'h11223344);
            dut.imem[0]  = encode_i(120,0,3'b000,1,7'h03); // lb x1,120(x0)
            dut.imem[1]  = encode_i(121,0,3'b000,2,7'h03); // lb x2,121(x0)
            dut.imem[2]  = encode_i(122,0,3'b000,3,7'h03); // lb x3,122(x0)
            dut.imem[3]  = encode_i(123,0,3'b000,4,7'h03); // lb x4,123(x0)
            dut.imem[4]  = encode_i(122,0,3'b100,5,7'h03); // lbu x5,122(x0)
            dut.imem[5]  = encode_i(123,0,3'b100,6,7'h03); // lbu x6,123(x0)
            dut.imem[6]  = encode_i(120,0,3'b001,7,7'h03); // lh x7,120(x0)
            dut.imem[7]  = encode_i(122,0,3'b001,8,7'h03); // lh x8,122(x0)
            dut.imem[8]  = encode_i(122,0,3'b101,9,7'h03); // lhu x9,122(x0)
            dut.imem[9]  = addi(10,0,165);
            dut.imem[10] = encode_s(121,10,0,3'b000);      // sb x10,121(x0)
            dut.imem[11] = addi(11,0,-1);
            dut.imem[12] = encode_s(122,11,0,3'b001);      // sh x11,122(x0)
            dut.imem[13] = encode_i(121,0,3'b000,12,7'h03);// lb -91
            dut.imem[14] = encode_i(121,0,3'b100,13,7'h03);// lbu 165
            dut.imem[15] = encode_i(120,0,3'b001,14,7'h03);// lh signed
            dut.imem[16] = encode_i(120,0,3'b101,15,7'h03);// lhu unsigned
            dut.imem[17] = lw(16,0,120);                    // full merged word
            dut.imem[18] = encode_s(124,0,0,3'b000);       // sb x0,124(x0)
            dut.imem[19] = encode_s(126,10,0,3'b001);      // sh x10,126(x0)
            dut.imem[20] = lw(17,0,124);
            dut.imem[21] = addi(31,0,5);
            expect_reg(1,1); expect_reg(2,127);
            expect_reg(3,32'hffffffff); expect_reg(4,32'hffffff80);
            expect_reg(5,255); expect_reg(6,128);
            expect_reg(7,32'h7f01); expect_reg(8,32'hffff80ff);
            expect_reg(9,32'h80ff); expect_reg(10,165);
            expect_reg(11,32'hffffffff); expect_reg(12,32'hffffffa5);
            expect_reg(13,165); expect_reg(14,32'hffffa501);
            expect_reg(15,32'ha501); expect_reg(16,32'hffffa501);
            expect_reg(17,32'h00a53300); expect_reg(31,5);
            expect_mem(30,32'hffffa501); expect_mem(31,32'h00a53300);
            run_case(5,180+(DATA_LATENCY+DATA_MAX_EXTRA)*120,19,4);
        end
    endtask

    initial begin
        if (DATA_LATENCY != 1 && DATA_LATENCY != 2 && DATA_LATENCY != 4)
            $fatal(1,"TB expects DATA_LATENCY=1,2,4 (got %0d)",DATA_LATENCY);
        if (DATA_MAX_EXTRA < 0 || DATA_MAX_EXTRA > 16)
            $fatal(1,"TB expects DATA_MAX_EXTRA from 0 through 16");
        test_dense_memory();
        test_consecutive_loads();
        test_branch_flush();
        test_backward_branch();
        test_reset_pending_store();
        test_subword();
        $display("PASS latency-controlled memory RV32I: DATA_LATENCY=%0d DATA_MAX_EXTRA=%0d cases=%0d checks=%0d",
                 DATA_LATENCY,DATA_MAX_EXTRA,cases_passed,state_checks);
        $finish;
    end
endmodule
`default_nettype wire
