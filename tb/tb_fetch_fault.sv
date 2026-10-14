`timescale 1ns/1ps
`default_nettype none
// Independent, self-checking FAULT_HALT=1 instruction-fetch local range tests.
// A PC at 0x00001000 is a modeled instruction-access fault, NOT a valid
// instruction word and NOT a legal external instruction request.
// Intentionally checks only architectural state, fault outputs and bus
// handshakes: no implementation-specific fetch-fault pipeline signal needed.
module tb_fetch_fault #(
    parameter integer EXTERNAL_MODE=0,
    parameter integer DATA_LATENCY=2,
    parameter integer DATA_MAX_EXTRA=2,
    parameter integer I_LATENCY=2,
    parameter integer I_JITTER=2,
    parameter integer D_LATENCY=3,
    parameter integer D_JITTER=2,
    parameter integer READY_MODE=1,
    parameter integer DATA_RESPONSE_DELAY=3
);
    localparam [31:0] NOP=32'h00000013;
    localparam [31:0] FETCH_BAD=32'h00001000;
    reg clk=0,rst_n=0;
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
        .d_req_tag(d_req_tag),.d_req_wdata(d_req_wdata),.d_req_wstrb(d_req_wstrb),
        .d_rsp_valid(d_rsp_valid),.d_rsp_ready(d_rsp_ready),
        .d_rsp_tag(d_rsp_tag),.d_rsp_rdata(d_rsp_rdata)
    );
    // Separate instruction and data arrays; no reads from the DUT's
    // disconnected internal imem or mem_model in EXTERNAL_MODE=1.
    dual_port_bus_adapter #(
        .I_LATENCY(I_LATENCY),.I_JITTER(I_JITTER),
        .D_LATENCY(D_LATENCY),.D_JITTER(D_JITTER),
        .READY_MODE(READY_MODE)
    ) bus(
        .clk(clk),.rst_n(rst_n),
        .i_req_valid(i_req_valid),.i_req_ready(i_req_ready),
        .i_req_addr(i_req_addr),.i_req_tag(i_req_tag),
        .i_rsp_valid(i_rsp_valid),.i_rsp_ready(i_rsp_ready),
        .i_rsp_addr(i_rsp_addr),.i_rsp_tag(i_rsp_tag),.i_rsp_data(i_rsp_data),
        .d_req_valid(d_req_valid),.d_req_ready(d_req_ready),
        .d_req_write(d_req_write),.d_req_addr(d_req_addr),
        .d_req_tag(d_req_tag),.d_req_wdata(d_req_wdata),.d_req_wstrb(d_req_wstrb),
        .d_rsp_valid(d_rsp_valid),.d_rsp_ready(d_rsp_ready),
        .d_rsp_tag(d_rsp_tag),.d_rsp_rdata(d_rsp_rdata)
    );

    reg [31:0] expected_regs[0:31];
    reg [31:0] expected_mem[0:1023];
    reg [8*88-1:0] case_name;
    integer cases_passed=0, fault_cases=0, valid_cases=0, comparisons=0;
    integer accepted_i=0,accepted_d=0,completed_d=0;
    integer internal_req=0,internal_rsp=0;
    integer fetch_last_word=0, held_i=0,held_d=0;
    integer provisional_if_tokens=0;
    reg [8*512-1:0] vcd_file;
    reg fault_seen=0, i_held_prev=0,d_held_prev=0;
    reg [31:0] sticky_cause=0,sticky_pc=0,sticky_tval=0;
    reg [71:0] i_held_payload=0;
    reg [39:0] d_held_payload=0;
    reg [39:0] i_req_payload=0;
    reg [76:0] d_req_payload=0;
    reg i_req_waited=0,d_req_waited=0;

    always @(posedge clk) begin
        if (!rst_n) begin
            fault_seen<=0;sticky_cause<=0;sticky_pc<=0;sticky_tval<=0;
            accepted_i<=0;accepted_d<=0;completed_d<=0;
            internal_req<=0;internal_rsp<=0;fetch_last_word<=0;
            held_i<=0;held_d<=0;
            provisional_if_tokens<=0;
            i_held_prev<=0;d_held_prev<=0;
            i_req_waited<=0;d_req_waited<=0;
        end else begin
            // Coverage observation only: the architectural oracle below
            // remains independent of the DUT's implementation. Require the
            // boundary token to be genuinely present in the three squash tests.
            if (dut.if_id_valid && dut.if_id_fetch_fault) begin
                if (dut.if_id_pc !== FETCH_BAD)
                    $fatal(1,"%0s unexpected IF fault-token PC=%08h",
                           case_name,dut.if_id_pc);
                provisional_if_tokens<=provisional_if_tokens+1;
            end
            if (fault_seen && (fault_valid !== 1'b1 ||
                {fault_cause,fault_pc,fault_tval} !==
                {sticky_cause,sticky_pc,sticky_tval}))
                $fatal(1,"%0s sticky fetch-fault metadata changed",case_name);
            if (!fault_seen && fault_valid) begin
                if (EXTERNAL_MODE && accepted_d !== completed_d)
                    $fatal(1,"%0s fetch fault overtook accepted older D request: %0d/%0d",
                           case_name,accepted_d,completed_d);
                fault_seen<=1;
                sticky_cause<=fault_cause;
                sticky_pc<=fault_pc;
                sticky_tval<=fault_tval;
            end
            if (EXTERNAL_MODE) begin
                // Check offers, not merely accepted transactions. This detects
                // a malformed request hidden by a deasserted i_req_ready.
                if (i_req_valid && (i_req_addr[1:0] !== 2'b00 ||
                    i_req_addr[31:12] !== 20'b0))
                    $fatal(1,"%0s out-of-range/misaligned external I offer %08h ready=%b",
                           case_name,i_req_addr,i_req_ready);
                if (i_req_waited &&
                    (!i_req_valid || {i_req_addr,i_req_tag} !== i_req_payload))
                    $fatal(1,"%0s I request changed while !ready",case_name);
                if (d_req_waited &&
                    (!d_req_valid ||
                     {d_req_tag,d_req_write,d_req_addr,d_req_wdata,d_req_wstrb}
                      !== d_req_payload))
                    $fatal(1,"%0s D request changed while !ready",case_name);
                if (i_held_prev &&
                    (!i_rsp_valid ||
                      {i_rsp_addr,i_rsp_tag,i_rsp_data} !== i_held_payload))
                    $fatal(1,"%0s I response changed while !ready",case_name);
                if (d_held_prev &&
                    (!d_rsp_valid ||
                      {d_rsp_tag,d_rsp_rdata} !== d_held_payload))
                    $fatal(1,"%0s D response changed while !ready",case_name);
                i_req_waited<=i_req_valid && !i_req_ready;
                d_req_waited<=d_req_valid && !d_req_ready;
                i_req_payload<={i_req_addr,i_req_tag};
                d_req_payload<={d_req_tag,d_req_write,d_req_addr,d_req_wdata,d_req_wstrb};
                i_held_prev<=i_rsp_valid && !i_rsp_ready;
                d_held_prev<=d_rsp_valid && !d_rsp_ready;
                i_held_payload<={i_rsp_addr,i_rsp_tag,i_rsp_data};
                d_held_payload<={d_rsp_tag,d_rsp_rdata};
                if (i_rsp_valid && !i_rsp_ready) held_i<=held_i+1;
                if (d_rsp_valid && !d_rsp_ready) held_d<=held_d+1;
                if (i_req_valid && i_req_ready) begin
                    accepted_i<=accepted_i+1;
                    if (i_req_addr==32'hffc) fetch_last_word<=fetch_last_word+1;
                end
                if (d_req_valid && d_req_ready) accepted_d<=accepted_d+1;
                if (d_rsp_valid && d_rsp_ready) completed_d<=completed_d+1;
            end else begin
                if (dut.mem_req_valid && dut.mem_req_ready)
                    internal_req<=internal_req+1;
                if (dut.mem_rsp_valid) internal_rsp<=internal_rsp+1;
            end
        end
    end

    function automatic [31:0] ai(input [4:0] rd,rs1,input integer imm);
        ai={imm[11:0],rs1,3'b000,rd,7'h13};
    endfunction
    function automatic [31:0] lui(input [4:0] rd,input [19:0] imm);
        lui={imm,rd,7'h37};
    endfunction
    function automatic [31:0] sw(input [4:0] rs2,rs1,input integer imm);
        sw={imm[11:5],rs2,rs1,3'b010,imm[4:0],7'h23};
    endfunction
    function automatic [31:0] lw(input [4:0] rd,rs1,input integer imm);
        lw={imm[11:0],rs1,3'b010,rd,7'h03};
    endfunction
    function automatic [31:0] branch(input [4:0] rs1,rs2,
                                      input [2:0] funct3,input integer off);
        branch={off[12],off[10:5],rs2,rs1,funct3,off[4:1],off[11],7'h63};
    endfunction
    function automatic [31:0] jal(input [4:0] rd,input integer off);
        jal={off[20],off[10:1],off[11],off[19:12],rd,7'h6f};
    endfunction
    function automatic [31:0] jalr(input [4:0] rd,rs1,input integer imm);
        jalr={imm[11:0],rs1,3'b000,rd,7'h67};
    endfunction

    task automatic put(input integer index,input [31:0] ins);
        begin
            dut.imem[index]=ins;
            bus.imem[index]=ins;
        end
    endtask
    task automatic prepare(input [8*88-1:0] label);
        integer k;
        begin
            @(negedge clk);
            rst_n=0;
            case_name=label;
            for (k=0;k<1024;k=k+1) begin
                put(k,NOP);
                dut.mem_model.words[k]=0;
                bus.dmem[k]=0;
                expected_mem[k]=0;
            end
            for (k=0;k<32;k=k+1) expected_regs[k]=0;
            repeat(3) @(negedge clk);
            if (fault_valid !== 1'b0 ||
                {fault_cause,fault_pc,fault_tval} !== 96'b0)
                $fatal(1,"%0s reset failed to clear fault state",case_name);
        end
    endtask
    task automatic preload(input integer index,input [31:0] value);
        begin
            dut.mem_model.words[index]=value;
            bus.dmem[index]=value;
            expected_mem[index]=value;
        end
    endtask
    task automatic expect_reg(input integer index,input [31:0] value);
        expected_regs[index]=value;
    endtask
    task automatic expect_mem(input integer index,input [31:0] value);
        expected_mem[index]=value;
    endtask
    task automatic check_arch;
        integer k;
        reg [31:0] actual;
        begin
            for (k=0;k<32;k=k+1) begin
                actual=dut.rf.regs[k];
                if (actual !== expected_regs[k])
                    $fatal(1,"%0s x%0d expected=%08h got=%08h external=%0d",
                           case_name,k,expected_regs[k],actual,EXTERNAL_MODE);
                comparisons=comparisons+1;
            end
            for (k=0;k<1024;k=k+1) begin
                actual=EXTERNAL_MODE ? bus.dmem[k] : dut.mem_model.words[k];
                if (actual !== expected_mem[k])
                    $fatal(1,"%0s memory[%0d] expected=%08h got=%08h external=%0d",
                           case_name,k,expected_mem[k],actual,EXTERNAL_MODE);
                comparisons=comparisons+1;
            end
        end
    endtask

    task automatic check_transactions(input integer dcount,input integer last_fetch);
        begin
            if (EXTERNAL_MODE) begin
                if (accepted_d!==dcount || completed_d!==dcount ||
                    bus.d_requests!==dcount || bus.d_responses!==dcount)
                    $fatal(1,"%0s data transactions expected=%0d accepted=%0d returned=%0d model=%0d/%0d",
                           case_name,dcount,accepted_d,completed_d,
                           bus.d_requests,bus.d_responses);
                if (last_fetch && fetch_last_word<1)
                    $fatal(1,"%0s external last legal fetch @0xffc never accepted",case_name);
                if (bus.i_responses>bus.i_requests || bus.i_requests-bus.i_responses>1)
                    $fatal(1,"%0s external fetch requests/responses unbalanced %0d/%0d",
                           case_name,bus.i_requests,bus.i_responses);
            end else if (internal_req!==dcount || internal_rsp!==dcount)
                $fatal(1,"%0s internal D expected=%0d req=%0d rsp=%0d",
                       case_name,dcount,internal_req,internal_rsp);
        end
    endtask
    task automatic run_fault(input integer dcount);
        integer cycles,budget;
        begin
            @(negedge clk);
            rst_n=1;
            cycles=0;
            budget=15000+250*(I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+
                                DATA_LATENCY+DATA_MAX_EXTRA+DATA_RESPONSE_DELAY);
            while (fault_valid!==1'b1 && cycles<budget) begin
                @(negedge clk);
                cycles=cycles+1;
            end
            if (fault_valid!==1'b1)
                $fatal(1,"%0s fetch fault timeout after %0d cycles PC=%08h",
                       case_name,cycles,dut.pc);
            if ({fault_cause,fault_pc,fault_tval} !==
                {32'd1,FETCH_BAD,FETCH_BAD})
                $fatal(1,"%0s expected cause=1 pc=tval=00001000, got %0d/%08h/%08h",
                       case_name,fault_cause,fault_pc,fault_tval);
            repeat(48+I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+
                   DATA_LATENCY+DATA_MAX_EXTRA+DATA_RESPONSE_DELAY*3) @(negedge clk);
            if ({fault_valid,fault_cause,fault_pc,fault_tval} !==
                {1'b1,32'd1,FETCH_BAD,FETCH_BAD})
                $fatal(1,"%0s fault was not sticky after drain",case_name);
            check_arch();
            check_transactions(dcount,1);
            if (EXTERNAL_MODE && dcount>0 &&
                DATA_RESPONSE_DELAY>=D_LATENCY+D_JITTER+2 && held_d<1)
                $fatal(1,"%0s expected a held external D response, observed none",
                       case_name);
            if (EXTERNAL_MODE && d_req_valid)
                $fatal(1,"%0s new D request after sticky halt",case_name);
            cases_passed=cases_passed+1; fault_cases=fault_cases+1;
            $display("PASS fetch-fault ext=%0d %-42s cause=1 pc=tval=00001000 cycles=%0d D=%0d Iheld=%0d Dheld=%0d",
                     EXTERNAL_MODE,case_name,cycles,dcount,held_i,held_d);
        end
    endtask
    task automatic run_valid(input integer marker,input integer dcount,
                             input integer require_squash_token);
        integer cycles,budget;
        begin
            @(negedge clk);
            rst_n=1;
            cycles=0;
            budget=15000+250*(I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+
                                DATA_LATENCY+DATA_MAX_EXTRA+DATA_RESPONSE_DELAY);
            while (dut.rf.regs[31]!==marker && cycles<budget) begin
                @(negedge clk);
                cycles=cycles+1;
                if (fault_valid!==1'b0)
                    $fatal(1,"%0s premature wrong-path fault cause=%0d pc=%08h",
                           case_name,fault_cause,fault_pc);
            end
            if (cycles>=budget)
                $fatal(1,"%0s did not reach completion marker %0d",case_name,marker);
            repeat(50+I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+
                   DATA_RESPONSE_DELAY*3) @(negedge clk);
            if (fault_valid!==1'b0)
                $fatal(1,"%0s wrong-path/local-range fault not squashed",case_name);
            if (require_squash_token && provisional_if_tokens<1)
                $fatal(1,"%0s redirected before any provisional IF range-fault token existed",
                       case_name);
            check_arch();
            check_transactions(dcount,1);
            if (EXTERNAL_MODE && dcount>0 &&
                DATA_RESPONSE_DELAY>=D_LATENCY+D_JITTER+2 && held_d<1)
                $fatal(1,"%0s expected a held external D response, observed none",
                       case_name);
            cases_passed=cases_passed+1; valid_cases=valid_cases+1;
            $display("PASS fetch-valid ext=%0d %-42s marker=%0d cycles=%0d Iheld=%0d Dheld=%0d",
                     EXTERNAL_MODE,case_name,marker,cycles,held_i,held_d);
        end
    endtask

    task automatic test_sequential_full_boundary;
        begin
            prepare("1024 sequential words then fetch at 0x1000");
            put(0,ai(1,0,7));
            put(1023,ai(2,0,9));
            expect_reg(1,7);expect_reg(2,9);
            run_fault(0);
        end
    endtask
    task automatic test_sequential_after_jump;
        begin
            prepare("last legal ADDI retires before sequential fault");
            put(0,jal(0,4092)); // from 0 to 0xffc
            put(1023,ai(2,0,25));
            expect_reg(2,25);
            run_fault(0);
        end
    endtask
    task automatic test_boundary_store_then_load;
        begin
            prepare("SW+LW directly before invalid fetch drain older");
            preload(3,32'hdeadc0de);
            preload(4,32'hcafebabe); // nearby sentinel unaffected
            put(0,jal(0,4084)); // 0xff4
            put(1021,ai(1,0,55));
            put(1022,sw(1,0,12));
            put(1023,lw(2,0,12));
            expect_reg(1,55);expect_reg(2,55);expect_mem(3,55);
            run_fault(2);
        end
    endtask
    task automatic test_boundary_load_dependency;
        begin
            prepare("delayed LW/load-use/SW drain before invalid fetch");
            preload(4,77);
            preload(5,32'h12345678);
            put(0,jal(0,4084));
            put(1021,lw(1,0,16));
            put(1022,ai(2,1,1));
            put(1023,sw(2,0,20));
            expect_reg(1,77);expect_reg(2,78);expect_mem(5,78);
            run_fault(2);
        end
    endtask
    task automatic test_jal_to_invalid;
        begin
            prepare("JAL at 0xffc to 0x1000 links then fetch faults");
            put(0,jal(0,4092));
            put(1023,jal(5,4));
            expect_reg(5,32'h00001000);
            run_fault(0);
        end
    endtask
    task automatic test_jalr_to_invalid;
        begin
            prepare("JALR at 0xffc to 0x1000 links then faults");
            put(0,lui(1,20'h1));
            put(1,jal(0,4088));
            put(1023,jalr(6,1,0));
            expect_reg(1,32'h00001000);
            expect_reg(6,32'h00001000);
            run_fault(0);
        end
    endtask
    task automatic test_not_taken_branch;
        begin
            prepare("not-taken BEQ at 0xffc falls through and faults");
            put(0,ai(1,0,1));
            put(1,jal(0,4088));
            put(1023,branch(0,1,3'b000,-4088));
            expect_reg(1,1);
            run_fault(0);
        end
    endtask
    task automatic test_taken_branch_squash;
        begin
            prepare("taken BEQ at 0xffc redirects and squashes fault");
            put(0,jal(0,4092));
            put(1,ai(31,0,41));
            put(2,jal(0,0)); // in-range stable loop for drain period
            put(1023,branch(0,0,3'b000,-4088)); // target 0x4
            expect_reg(31,41);
            run_valid(41,0,1);
        end
    endtask
    task automatic test_jal_redirect_squash;
        begin
            prepare("JAL at 0xffc redirects inward; link survives");
            put(0,jal(0,4092));
            put(1,ai(31,0,42));
            put(2,jal(0,0));
            put(1023,jal(5,-4088)); // target 0x4
            expect_reg(5,32'h00001000); expect_reg(31,42);
            run_valid(42,0,1);
        end
    endtask
    task automatic test_jalr_redirect_squash;
        begin
            prepare("JALR at 0xffc redirects inward; link survives");
            put(0,ai(1,0,8));      // target byte address 0x8
            put(1,jal(0,4088));    // branch into last instruction
            put(2,ai(31,0,43));
            put(3,jal(0,0));       // stable loop at 0xc after return
            put(1023,jalr(6,1,0));
            expect_reg(1,8);expect_reg(6,32'h00001000);expect_reg(31,43);
            run_valid(43,0,1);
        end
    endtask
    task automatic test_reset_clears_sticky;
        integer k;
        begin
            prepare("reset cancels sticky fetch fault and restarts core");
            preload(8,32'hcafe900d);
            put(0,jal(0,4092));
            put(1023,ai(7,0,28));
            expect_reg(7,28);
            run_fault(0);
            @(negedge clk);
            rst_n=0;
            for (k=0;k<1024;k=k+1) put(k,NOP);
            for (k=0;k<32;k=k+1) expected_regs[k]=0;
            put(0,ai(31,0,44));
            put(1,jal(0,0));
            repeat(4) @(negedge clk);
            if (fault_valid!==1'b0 ||
                {fault_cause,fault_pc,fault_tval}!==96'b0)
                $fatal(1,"Sticky fetch-fault metadata persisted across reset");
            // Reset leaves data RAM contents intact, including seeded sentinel.
            @(negedge clk);rst_n=1;
            begin : check_restart
                integer cycles;
                cycles=0;
                while (dut.rf.regs[31]!==44 && cycles<2000) begin
                    @(negedge clk);cycles=cycles+1;
                end
                if (cycles>=2000) $fatal(1,"Reset restart timed out");
            end
            repeat(28) @(negedge clk);
            if (fault_valid!==1'b0)
                $fatal(1,"Spurious stale fetch fault after reset");
            expect_reg(31,44);
            check_arch();
            check_transactions(0,0);
            cases_passed=cases_passed+1;valid_cases=valid_cases+1;
            $display("PASS fetch-reset ext=%0d sticky clear and fresh execution",EXTERNAL_MODE);
        end
    endtask

    initial begin
        if ($value$plusargs("vcd=%s",vcd_file)) begin
            $dumpfile(vcd_file);
            // Selected, actual bus/pipeline/fault signals; do not dump 1024
            // RAM words and inflate or fabricate evidence.
            $dumpvars(0,clk,rst_n,fault_valid,fault_cause,fault_pc,fault_tval,
                      dut.pc,dut.if_id_valid,dut.id_ex_valid,dut.ex_mem_valid,
                      i_req_valid,i_req_ready,i_req_addr,i_req_tag,
                      i_rsp_valid,i_rsp_ready,i_rsp_addr,i_rsp_tag,
                      d_req_valid,d_req_ready,d_req_addr,d_req_tag,
                      d_rsp_valid,d_rsp_ready,d_rsp_tag,
                      bus.i_requests,bus.i_responses,bus.d_requests,
                      bus.d_responses,accepted_i,accepted_d,completed_d);
        end
        test_sequential_full_boundary();
        test_sequential_after_jump();
        test_boundary_store_then_load();
        test_boundary_load_dependency();
        test_jal_to_invalid();
        test_jalr_to_invalid();
        test_not_taken_branch();
        test_taken_branch_squash();
        test_jal_redirect_squash();
        test_jalr_redirect_squash();
        test_reset_clears_sticky();
        $display("PASS fetch-fault suite ext=%0d cases=%0d fault=%0d valid=%0d architectural-checks=%0d",
                 EXTERNAL_MODE,cases_passed,fault_cases,valid_cases,comparisons);
        $finish;
    end
endmodule
`default_nettype wire
