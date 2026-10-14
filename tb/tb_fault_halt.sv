`timescale 1ns/1ps
`default_nettype none
// Independent architectural tests for the opt-in *halt-on-fault* model.
// No handler/CSR/MRET is assumed. A fault must be sticky until reset,
// precise with respect to registers and memory, and terminate younger work.
// Compile with core RTL plus the existing independent dual_port_bus_adapter.
module tb_fault_halt #(
    parameter integer EXTERNAL_MODE = 0,
    parameter integer DATA_LATENCY = 2,
    parameter integer DATA_MAX_EXTRA = 1,
    parameter integer I_LATENCY = 2,
    parameter integer D_LATENCY = 3,
    parameter integer I_JITTER = 2,
    parameter integer D_JITTER = 2,
    parameter integer READY_MODE = 1,
    parameter integer DATA_RESPONSE_DELAY = 3
);
    localparam [31:0] NOP=32'h00000013;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    wire fault_valid;
    wire [31:0] fault_cause,fault_pc,fault_tval;
    wire i_req_valid,i_req_ready,i_rsp_valid,i_rsp_ready;
    wire [31:0] i_req_addr,i_rsp_addr,i_rsp_data;
    wire [7:0] i_req_tag,i_rsp_tag;
    wire d_req_valid,d_req_ready,d_req_write,d_rsp_valid,d_rsp_ready;
    wire [31:0] d_req_addr,d_req_wdata,d_rsp_rdata;
    wire [3:0] d_req_wstrb;
    wire [7:0] d_req_tag,d_rsp_tag;

    pipeline_core #(
        .FAULT_HALT(1),.EXTERNAL_PORTS(EXTERNAL_MODE),
        .DATA_LATENCY(DATA_LATENCY),.DATA_MAX_EXTRA(DATA_MAX_EXTRA),
        .DATA_RESPONSE_DELAY(DATA_RESPONSE_DELAY)
    ) dut(
        .clk(clk),.rst_n(rst_n),
        .fault_valid(fault_valid),.fault_cause(fault_cause),
        .fault_pc(fault_pc),.fault_tval(fault_tval),
        .i_req_valid(i_req_valid),.i_req_ready(i_req_ready),
        .i_req_addr(i_req_addr),.i_req_tag(i_req_tag),
        .i_rsp_valid(i_rsp_valid),.i_rsp_ready(i_rsp_ready),
        .i_rsp_addr(i_rsp_addr),.i_rsp_tag(i_rsp_tag),.i_rsp_data(i_rsp_data),
        .d_req_valid(d_req_valid),.d_req_ready(d_req_ready),
        .d_req_write(d_req_write),.d_req_addr(d_req_addr),
        .d_req_wdata(d_req_wdata),.d_req_wstrb(d_req_wstrb),
        .d_req_tag(d_req_tag),
        .d_rsp_valid(d_rsp_valid),.d_rsp_ready(d_rsp_ready),
        .d_rsp_tag(d_rsp_tag),.d_rsp_rdata(d_rsp_rdata)
    );
    dual_port_bus_adapter #(
        .I_LATENCY(I_LATENCY),.D_LATENCY(D_LATENCY),
        .I_JITTER(I_JITTER),.D_JITTER(D_JITTER),
        .READY_MODE(READY_MODE)
    ) bus (
        .clk(clk),.rst_n(rst_n),
        .i_req_valid(i_req_valid),.i_req_ready(i_req_ready),
        .i_req_addr(i_req_addr),.i_req_tag(i_req_tag),
        .i_rsp_valid(i_rsp_valid),.i_rsp_ready(i_rsp_ready),
        .i_rsp_addr(i_rsp_addr),.i_rsp_tag(i_rsp_tag),.i_rsp_data(i_rsp_data),
        .d_req_valid(d_req_valid),.d_req_ready(d_req_ready),
        .d_req_write(d_req_write),.d_req_addr(d_req_addr),
        .d_req_wdata(d_req_wdata),.d_req_wstrb(d_req_wstrb),
        .d_req_tag(d_req_tag),
        .d_rsp_valid(d_rsp_valid),.d_rsp_ready(d_rsp_ready),
        .d_rsp_tag(d_rsp_tag),.d_rsp_rdata(d_rsp_rdata)
    );

    reg [31:0] golden_regs[0:31];
    reg [31:0] golden_mem[0:1023];
    reg [8*96-1:0] scenario;
    integer scenarios_passed=0, state_checks=0, fault_cases_passed=0;
    reg check_forbidden_d=0;
    reg [31:0] forbidden_addr=0;
    integer internal_requests=0;
    reg seen_fault=0;
    reg [31:0] old_cause=0,old_pc=0,old_tval=0;
    // This monitor is independent of the DUT pipeline-state implementation.
    always @(posedge clk) begin
        if (!rst_n) begin
            seen_fault<=0;
            old_cause<=0;old_pc<=0;old_tval<=0;
            internal_requests<=0;
        end else begin
            if (EXTERNAL_MODE==0 && dut.mem_req_valid && dut.mem_req_ready)
                internal_requests<=internal_requests+1;
            if (EXTERNAL_MODE!=0 && check_forbidden_d &&
                d_req_valid && d_req_addr===forbidden_addr)
                $fatal(1,"Forbidden external data request: %0s addr=%08h",scenario,d_req_addr);
            if (seen_fault && (fault_valid!==1'b1 ||
                 {fault_cause,fault_pc,fault_tval} !== {old_cause,old_pc,old_tval}))
                $fatal(1,"Fault not sticky after asserted in %0s",scenario);
            if (fault_valid && !seen_fault) begin
                seen_fault<=1;
                old_cause<=fault_cause;
                old_pc<=fault_pc;
                old_tval<=fault_tval;
            end
        end
    end

    function automatic [31:0] inst_i(input integer imm,input [4:0] rs1,
                                     input [2:0] f3,input [4:0] rd,input [6:0] op);
        inst_i={imm[11:0],rs1,f3,rd,op};
    endfunction
    function automatic [31:0] inst_s(input integer imm,input [4:0] rs2,rs1,input [2:0] f3);
        inst_s={imm[11:5],rs2,rs1,f3,imm[4:0],7'h23};
    endfunction
    function automatic [31:0] inst_b(input integer offset,input [4:0] rs1,rs2,input [2:0] f3);
        inst_b={offset[12],offset[10:5],rs2,rs1,f3,offset[4:1],offset[11],7'h63};
    endfunction
    function automatic [31:0] addi(input [4:0] rd,rs1,input integer value);
        addi=inst_i(value,rs1,3'b000,rd,7'h13);
    endfunction
    function automatic [31:0] load(input [2:0] f3,input [4:0] rd,rs1,input integer off);
        load=inst_i(off,rs1,f3,rd,7'h03);
    endfunction
    function automatic [31:0] store(input [2:0] f3,input [4:0] rs2,rs1,input integer off);
        store=inst_s(off,rs2,rs1,f3);
    endfunction
    function automatic [31:0] lui(input [4:0] rd,input [19:0] imm);
        lui={imm,rd,7'h37};
    endfunction
    function automatic [31:0] beq(input [4:0] rs1,rs2,input integer off);
        beq=inst_b(off,rs1,rs2,3'b000);
    endfunction
    function automatic [31:0] jal(input [4:0] rd,input integer off);
        jal={off[20],off[10:1],off[11],off[19:12],rd,7'h6f};
    endfunction
    function automatic [31:0] jalr(input [4:0] rd,rs1,input integer off);
        jalr=inst_i(off,rs1,0,rd,7'h67);
    endfunction

    // Load both memories regardless of mode; only the selected I/D hierarchy
    // supplies execution. This prevents a test from passing due to the
    // disconnected internal RAM accidentally executing its own program.
    task automatic instruction(input integer index,input [31:0] value);
        begin
            dut.imem[index]=value;
            bus.imem[index]=value;
        end
    endtask
    task automatic reset_program(input [8*96-1:0] name);
        integer k;
        begin
            @(negedge clk);
            rst_n=0;
            scenario=name;
            check_forbidden_d=0;
            forbidden_addr=0;
            for (k=0;k<1024;k=k+1) begin
                instruction(k,NOP);
                dut.mem_model.words[k]=0;
                bus.dmem[k]=0;
                golden_mem[k]=0;
            end
            for (k=0;k<32;k=k+1) golden_regs[k]=0;
            repeat(3) @(negedge clk);
            if (fault_valid!==1'b0)
                $fatal(1,"Fault sticky output did not reset before %0s",scenario);
        end
    endtask
    task automatic seed_word(input integer idx,input [31:0] value);
        begin
            dut.mem_model.words[idx]=value;
            bus.dmem[idx]=value;
            golden_mem[idx]=value;
        end
    endtask
    task automatic expect_reg(input integer idx,input [31:0] value);
        golden_regs[idx]=value;
    endtask
    task automatic expect_word(input integer idx,input [31:0] value);
        golden_mem[idx]=value;
    endtask
    task automatic check_all_state;
        integer k;
        reg [31:0] actual;
        begin
            for (k=0;k<32;k=k+1) begin
                if (dut.rf.regs[k] !== golden_regs[k])
                    $fatal(1,"%0s x%0d expected=%08h got=%08h external=%0d",
                           scenario,k,golden_regs[k],dut.rf.regs[k],EXTERNAL_MODE);
                state_checks=state_checks+1;
            end
            for (k=0;k<1024;k=k+1) begin
                actual = EXTERNAL_MODE ? bus.dmem[k] : dut.mem_model.words[k];
                if (actual !== golden_mem[k])
                    $fatal(1,"%0s RAM[%0d] expected=%08h got=%08h external=%0d",
                           scenario,k,golden_mem[k],actual,EXTERNAL_MODE);
                state_checks=state_checks+1;
            end
        end
    endtask
    task automatic append_forbidden_younger;
        begin
            // The faulting instruction is always at PC=8 in setup_memory_fault.
            instruction(3,addi(20,0,99));
            instruction(4,store(3'b010,20,0,8)); // must not modify sentinel
            instruction(5,addi(31,0,88));       // must never retire
        end
    endtask
    task automatic setup_memory_fault(input [31:0] bad_ins,
                                      input [31:0] bad_addr);
        begin
            instruction(0,addi(1,0,47));
            instruction(1,store(3'b010,1,0,0)); // older operation must retire
            instruction(2,bad_ins);
            append_forbidden_younger();
            expect_reg(1,47);
            expect_word(0,47);
            seed_word(2,32'hca7ebabe);
            check_forbidden_d=1;
            forbidden_addr=bad_addr;
        end
    endtask

    // Bounds accommodate both slow independent buses and variable internal RAM.
    // The post-fault drain period additionally tests that no younger write
    // appears after the metadata has become visible.
    task automatic run_fault(input [31:0] cause,pc,tval,input integer expected_d);
        integer cycles,deadline;
        reg [31:0] frozen_cause,frozen_pc,frozen_tval;
        begin
            @(negedge clk);
            rst_n=1;
            cycles=0;
            deadline=2600+200*(I_LATENCY+D_LATENCY+I_JITTER+D_JITTER+
                                DATA_LATENCY+DATA_MAX_EXTRA+DATA_RESPONSE_DELAY);
            while (fault_valid!==1'b1 && cycles<deadline) begin
                @(negedge clk);
                cycles=cycles+1;
            end
            if (fault_valid!==1'b1)
                $fatal(1,"%0s never faulted after %0d cycles PC=%08h",scenario,cycles,dut.pc);
            if ({fault_cause,fault_pc,fault_tval} !== {cause,pc,tval})
                $fatal(1,"%0s wrong fault got cause=%0d pc=%08h tval=%08h expected=%0d/%08h/%08h",
                       scenario,fault_cause,fault_pc,fault_tval,cause,pc,tval);
            frozen_cause=fault_cause;
            frozen_pc=fault_pc;
            frozen_tval=fault_tval;
            repeat(45+I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+
                   3*(DATA_LATENCY+DATA_MAX_EXTRA+DATA_RESPONSE_DELAY)) @(negedge clk);
            if (fault_valid!==1'b1 ||
                {fault_cause,fault_pc,fault_tval} !== {frozen_cause,frozen_pc,frozen_tval})
                $fatal(1,"%0s fault metadata was not sticky",scenario);
            check_all_state();
            if (EXTERNAL_MODE) begin
                if (bus.d_requests!==expected_d || bus.d_responses!==expected_d)
                    $fatal(1,"%0s external D req/rsp expected=%0d observed=%0d/%0d",
                           scenario,expected_d,bus.d_requests,bus.d_responses);
                if (d_req_valid)
                    $fatal(1,"%0s external data request still issued after halt",scenario);
            end else if (internal_requests!==expected_d) begin
                $fatal(1,"%0s internal memory request count expected=%0d observed=%0d",
                       scenario,expected_d,internal_requests);
            end
            scenarios_passed=scenarios_passed+1;
            fault_cases_passed=fault_cases_passed+1;
            $display("PASS fault halt ext=%0d %-39s cause=%0d pc=%08h tval=%08h D=%0d cycles=%0d",
                     EXTERNAL_MODE,scenario,cause,pc,tval,expected_d,cycles);
        end
    endtask
    task automatic run_valid(input [31:0] marker,input integer expected_d);
        integer cycles,deadline;
        begin
            @(negedge clk);
            rst_n=1;
            cycles=0;
            deadline=2600+200*(I_LATENCY+D_LATENCY+I_JITTER+D_JITTER+
                                DATA_LATENCY+DATA_MAX_EXTRA+DATA_RESPONSE_DELAY);
            while (dut.rf.regs[31]!==marker && cycles<deadline) begin
                @(negedge clk);
                cycles=cycles+1;
                if (fault_valid!==1'b0)
                    $fatal(1,"%0s unexpectedly faulted cause=%0d pc=%08h tval=%08h",
                           scenario,fault_cause,fault_pc,fault_tval);
            end
            if (cycles>=deadline)
                $fatal(1,"%0s valid program timed out PC=%08h",scenario,dut.pc);
            repeat(25+I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+
                   DATA_LATENCY+DATA_MAX_EXTRA+DATA_RESPONSE_DELAY) @(negedge clk);
            if (fault_valid!==1'b0)
                $fatal(1,"%0s produced a delayed spurious fault",scenario);
            check_all_state();
            if (EXTERNAL_MODE) begin
                if (bus.d_requests!==expected_d || bus.d_responses!==expected_d)
                    $fatal(1,"%0s valid external D count expected=%0d got=%0d/%0d",
                           scenario,expected_d,bus.d_requests,bus.d_responses);
            end else if (internal_requests!==expected_d)
                $fatal(1,"%0s valid internal D count expected=%0d got=%0d",
                       scenario,expected_d,internal_requests);
            scenarios_passed=scenarios_passed+1;
            $display("PASS no-fault ext=%0d %-37s marker=%0d D=%0d cycles=%0d",
                     EXTERNAL_MODE,scenario,marker,expected_d,cycles);
        end
    endtask

    task automatic illegal_after_older_ops;
        begin
            reset_program("illegal opcode after older SW/LW");
            instruction(0,addi(1,0,77));
            instruction(1,store(3'b010,1,0,0));
            instruction(2,load(3'b010,2,0,0));
            instruction(3,32'hffffffff);
            instruction(4,addi(20,0,18));
            instruction(5,store(3'b010,20,0,4));
            seed_word(1,32'haabbccdd);
            expect_reg(1,77); expect_reg(2,77); expect_word(0,77);
            run_fault(2,12,32'hffffffff,2);
        end
    endtask
    task automatic illegal_reserved_encoding;
        begin
            reset_program("illegal reserved shift encoding");
            instruction(0,addi(1,0,3));
            instruction(1,32'h40009093); // SLLI with reserved funct7=0100000
            instruction(2,addi(21,0,11));
            expect_reg(1,3);
            run_fault(2,4,32'h40009093,0);
        end
    endtask
    task automatic illegal_load_encoding;
        begin
            reset_program("illegal reserved load funct3");
            instruction(0,addi(1,0,3));
            instruction(1,32'h00003103); // load with reserved funct3=011 -> x2
            instruction(2,addi(22,0,11));
            expect_reg(1,3);
            run_fault(2,4,32'h00003103,0);
        end
    endtask
    task automatic misaligned_load_half;
        begin
            reset_program("misaligned LH byte address 1");
            setup_memory_fault(load(3'b001,2,0,1),1);
            run_fault(4,8,1,1);
        end
    endtask
    task automatic misaligned_load_word;
        begin
            reset_program("misaligned LW byte address 2");
            setup_memory_fault(load(3'b010,2,0,2),2);
            run_fault(4,8,2,1);
        end
    endtask
    task automatic misaligned_store_half;
        begin
            reset_program("misaligned SH byte address 3");
            setup_memory_fault(store(3'b001,1,0,3),3);
            run_fault(6,8,3,1);
        end
    endtask
    task automatic misaligned_store_word;
        begin
            reset_program("misaligned SW byte address 2");
            setup_memory_fault(store(3'b010,1,0,2),2);
            run_fault(6,8,2,1);
        end
    endtask
    task automatic access_fault_load;
        begin
            reset_program("LW beyond modeled 4KiB RAM");
            instruction(0,lui(1,20'h00001)); // x1=4096
            instruction(1,load(3'b010,2,1,0));
            instruction(2,addi(20,0,13));
            instruction(3,store(3'b010,20,0,4));
            seed_word(1,32'hd00dcafe);
            expect_reg(1,4096);
            check_forbidden_d=1; forbidden_addr=4096;
            run_fault(5,4,4096,0);
        end
    endtask
    task automatic access_fault_store;
        begin
            reset_program("SW beyond modeled 4KiB RAM");
            instruction(0,lui(1,20'h00001)); // x1=4096
            instruction(1,addi(2,0,77));
            instruction(2,store(3'b010,2,1,0));
            instruction(3,addi(20,0,13));
            instruction(4,store(3'b010,20,0,4));
            seed_word(1,32'hf00d1234);
            expect_reg(1,4096);expect_reg(2,77);
            check_forbidden_d=1; forbidden_addr=4096;
            run_fault(7,8,4096,0);
        end
    endtask
    task automatic misaligned_jalr_target;
        begin
            reset_program("JALR resolved target not 4-byte aligned");
            instruction(0,addi(1,0,6));
            instruction(1,jalr(5,1,0)); // target=(6&~1)=6, not 4-byte aligned
            instruction(2,addi(20,0,99));
            instruction(3,store(3'b010,20,0,4));
            seed_word(1,32'hc0decafe);
            expect_reg(1,6); // faulting JALR must not write link x5
            run_fault(0,4,6,0);
        end
    endtask
    task automatic misaligned_jal_target;
        begin
            reset_program("JAL target not 4-byte aligned");
            instruction(0,jal(5,2));
            instruction(1,addi(20,0,99));
            seed_word(1,32'hc0decafe);
            run_fault(0,0,2,0);
        end
    endtask
    task automatic misaligned_taken_branch;
        begin
            reset_program("taken BEQ target not 4-byte aligned");
            instruction(0,addi(1,0,1));
            instruction(1,beq(1,1,2)); // target=6
            instruction(2,addi(20,0,99));
            seed_word(1,32'hc0decafe);
            expect_reg(1,1);
            run_fault(0,4,6,0);
        end
    endtask
    task automatic wrong_path_illegal_and_memory;
        begin
            reset_program("wrong-path illegal and bad memory ignored");
            instruction(0,addi(1,0,7));
            instruction(1,beq(1,1,16)); // skip indices 2,3,4
            instruction(2,32'hffffffff);
            instruction(3,load(3'b010,2,0,2)); // misaligned speculative LW
            instruction(4,store(3'b010,1,0,8));
            instruction(5,store(3'b010,1,0,12));
            instruction(6,load(3'b010,3,0,12));
            instruction(7,addi(31,0,42));
            seed_word(2,32'hf00df00d);
            expect_reg(1,7);expect_reg(3,7);expect_reg(31,42);
            expect_word(3,7);
            run_valid(42,2);
        end
    endtask
    task automatic wrong_path_jalr_and_bad_store;
        begin
            reset_program("wrong-path misaligned JALR and SW ignored");
            instruction(0,addi(1,0,6));
            instruction(1,beq(1,1,16));
            instruction(2,jalr(5,1,0)); // would raise cause 0
            instruction(3,store(3'b010,1,0,2)); // would raise cause 6
            instruction(4,addi(20,0,99));
            instruction(5,addi(6,0,15));
            instruction(6,addi(31,0,43));
            seed_word(2,32'hfeed1234);
            expect_reg(1,6);expect_reg(6,15);expect_reg(31,43);
            run_valid(43,0);
        end
    endtask
    task automatic valid_end_of_ram;
        begin
            reset_program("valid last-word/half/byte memory boundaries");
            seed_word(1023,32'h80ff7f01);
            instruction(0,lui(1,20'h00001));
            instruction(1,load(3'b010,2,1,-4));  // LW at 4092
            instruction(2,load(3'b100,3,1,-1));  // LBU at 4095
            instruction(3,load(3'b001,4,1,-2));  // LH at 4094
            instruction(4,addi(5,0,42));
            instruction(5,store(3'b000,5,1,-1)); // SB at 4095
            instruction(6,load(3'b101,6,1,-2));  // LHU at 4094
            instruction(7,addi(31,0,44));
            expect_reg(1,4096);expect_reg(2,32'h80ff7f01);
            expect_reg(3,128);expect_reg(4,32'hffff80ff);
            expect_reg(5,42);expect_reg(6,32'h2aff);expect_reg(31,44);
            expect_word(1023,32'h2aff7f01);
            run_valid(44,5);
        end
    endtask

    initial begin
        illegal_after_older_ops();
        illegal_reserved_encoding();
        illegal_load_encoding();
        misaligned_load_half();
        misaligned_load_word();
        misaligned_store_half();
        misaligned_store_word();
        access_fault_load();
        access_fault_store();
        misaligned_jalr_target();
        misaligned_jal_target();
        misaligned_taken_branch();
        wrong_path_illegal_and_memory();
        wrong_path_jalr_and_bad_store();
        valid_end_of_ram();
        $display("PASS fault-halt regression ext=%0d scenarios=%0d fault-cases=%0d state-checks=%0d",
                 EXTERNAL_MODE,scenarios_passed,fault_cases_passed,state_checks);
        $finish;
    end
endmodule
`default_nettype wire
