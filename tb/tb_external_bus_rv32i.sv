`timescale 1ns/1ps
`default_nettype none
// External-ports architectural regression, independent of internal instruction
// and data memories. Compile together with tb/dual_port_bus_adapter.sv, the
// pipeline's RTL dependencies, and select parameters with -Ptb_external_bus_rv32i.X.
module tb_external_bus_rv32i #(
    parameter integer I_LATENCY = 2,
    parameter integer D_LATENCY = 3,
    parameter integer I_JITTER = 2,
    parameter integer D_JITTER = 3,
    parameter integer READY_MODE = 1,
    parameter integer DATA_RESPONSE_DELAY = 0
);
    localparam [31:0] NOP=32'h00000013;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    wire i_req_valid,i_req_ready;
    wire [31:0] i_req_addr;
    wire [7:0] i_req_tag;
    wire i_rsp_valid,i_rsp_ready;
    wire [31:0] i_rsp_addr,i_rsp_data;
    wire [7:0] i_rsp_tag;
    wire [7:0] i_rsp_tag_to_core;
    wire d_req_valid,d_req_ready,d_req_write;
    wire [31:0] d_req_addr,d_req_wdata;
    wire [3:0] d_req_wstrb;
    wire [7:0] d_req_tag,d_rsp_tag;
    wire [7:0] d_rsp_tag_to_core;
    wire d_rsp_valid,d_rsp_ready;
    wire [31:0] d_rsp_rdata;
    reg corrupt_i_tag=0,corrupt_d_tag=0;
    assign i_rsp_tag_to_core=i_rsp_tag ^ (corrupt_i_tag ? 8'h80 : 8'h00);
    assign d_rsp_tag_to_core=d_rsp_tag ^ (corrupt_d_tag ? 8'h80 : 8'h00);

    pipeline_core #(.EXTERNAL_PORTS(1),.DATA_RESPONSE_DELAY(DATA_RESPONSE_DELAY)) dut(
        .clk(clk),.rst_n(rst_n),
        .i_req_valid(i_req_valid),.i_req_ready(i_req_ready),
        .i_req_addr(i_req_addr),.i_req_tag(i_req_tag),
        .i_rsp_valid(i_rsp_valid),.i_rsp_ready(i_rsp_ready),
        .i_rsp_addr(i_rsp_addr),.i_rsp_tag(i_rsp_tag_to_core),.i_rsp_data(i_rsp_data),
        .d_req_valid(d_req_valid),.d_req_ready(d_req_ready),
        .d_req_write(d_req_write),.d_req_addr(d_req_addr),
        .d_req_tag(d_req_tag),.d_req_wdata(d_req_wdata),.d_req_wstrb(d_req_wstrb),
        .d_rsp_valid(d_rsp_valid),.d_rsp_ready(d_rsp_ready),
        .d_rsp_tag(d_rsp_tag_to_core),.d_rsp_rdata(d_rsp_rdata)
    );
    dual_port_bus_adapter #(
        .I_LATENCY(I_LATENCY),.D_LATENCY(D_LATENCY),
        .I_JITTER(I_JITTER),.D_JITTER(D_JITTER),.READY_MODE(READY_MODE)
    ) bus (
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
    reg [8*80-1:0] case_name;
    integer passed=0,arch_checks=0;
    reg [8*256-1:0] wave_path;
    reg i_previously_held=0,d_previously_held=0;
    reg [71:0] old_i_response=0;
    reg [39:0] old_d_response=0;
    reg i_request_waited=0,d_request_waited=0;
    reg [39:0] old_i_request=0;
    reg [76:0] old_d_request=0;
    // The adapter promises stable response under backpressure. Check that
    // property at the core interface as well (independent of adapter logic).
    always @(posedge clk) begin
        if (!rst_n) begin
            i_previously_held<=0;
            d_previously_held<=0;
            i_request_waited<=0;
            d_request_waited<=0;
        end else begin
            if (i_request_waited &&
                (!i_req_valid || {i_req_addr,i_req_tag} !== old_i_request))
                $fatal(1,"I request changed before ready in %0s",case_name);
            if (d_request_waited &&
                (!d_req_valid || {d_req_tag,d_req_write,d_req_addr,d_req_wdata,d_req_wstrb}
                 !== old_d_request))
                $fatal(1,"D request changed before ready in %0s",case_name);
            if (i_previously_held &&
                (!i_rsp_valid || {i_rsp_addr,i_rsp_tag,i_rsp_data} !== old_i_response))
                $fatal(1,"I response changed while backpressured in %0s",case_name);
            if (d_previously_held &&
                (!d_rsp_valid || {d_rsp_tag,d_rsp_rdata} !== old_d_response))
                $fatal(1,"D response changed while backpressured in %0s",case_name);
            i_previously_held <= i_rsp_valid && !i_rsp_ready;
            d_previously_held <= d_rsp_valid && !d_rsp_ready;
            i_request_waited <= i_req_valid && !i_req_ready;
            d_request_waited <= d_req_valid && !d_req_ready;
            old_i_request <= {i_req_addr,i_req_tag};
            old_d_request <= {d_req_tag,d_req_write,d_req_addr,d_req_wdata,d_req_wstrb};
            old_i_response <= {i_rsp_addr,i_rsp_tag,i_rsp_data};
            old_d_response <= {d_rsp_tag,d_rsp_rdata};
        end
    end

    function automatic [31:0] encode_i(input integer imm,input [4:0] rs1,
                                       input [2:0] f3,input [4:0] rd,input [6:0] opcode);
        encode_i={imm[11:0],rs1,f3,rd,opcode};
    endfunction
    function automatic [31:0] encode_s(input integer imm,input [4:0] rs2,rs1,input [2:0] f3);
        encode_s={imm[11:5],rs2,rs1,f3,imm[4:0],7'h23};
    endfunction
    function automatic [31:0] encode_b(input integer offset,input [4:0] rs1,rs2,input [2:0] f3);
        begin
            if ((offset&1)!=0) $fatal(1,"Odd branch displacement %0d",offset);
            encode_b={offset[12],offset[10:5],rs2,rs1,f3,offset[4:1],offset[11],7'h63};
        end
    endfunction
    function automatic [31:0] addi(input [4:0] rd,rs1,input integer imm);
        addi=encode_i(imm,rs1,0,rd,7'h13);
    endfunction
    function automatic [31:0] add(input [4:0] rd,rs1,rs2);
        add={7'b0,rs2,rs1,3'b000,rd,7'h33};
    endfunction
    function automatic [31:0] load(input [2:0] f3,input [4:0] rd,rs1,input integer imm);
        load=encode_i(imm,rs1,f3,rd,7'h03);
    endfunction
    function automatic [31:0] store(input [2:0] f3,input [4:0] rs2,rs1,input integer imm);
        store=encode_s(imm,rs2,rs1,f3);
    endfunction
    function automatic [31:0] beq(input [4:0] rs1,rs2,input integer displacement);
        beq=encode_b(displacement,rs1,rs2,3'b000);
    endfunction
    function automatic [31:0] bne(input [4:0] rs1,rs2,input integer displacement);
        bne=encode_b(displacement,rs1,rs2,3'b001);
    endfunction

    task automatic prepare(input [8*80-1:0] title);
        integer k;
        begin
            @(negedge clk);
            rst_n=0;
            case_name=title;
            for (k=0;k<1024;k=k+1) begin
                bus.imem[k]=NOP;
                bus.dmem[k]=0;
                expected_mem[k]=0;
            end
            for (k=0;k<32;k=k+1) expected_regs[k]=0;
        end
    endtask
    task automatic preload(input integer word_index,input [31:0] value);
        begin
            bus.dmem[word_index]=value;
            expected_mem[word_index]=value;
        end
    endtask
    task automatic expect_reg(input integer index,input [31:0] value);
        expected_regs[index]=value;
    endtask
    task automatic expect_mem(input integer index,input [31:0] value);
        expected_mem[index]=value;
    endtask

    task automatic check_state;
        integer k;
        begin
            for (k=0;k<32;k=k+1) begin
                if (dut.rf.regs[k] !== expected_regs[k])
                    $fatal(1,"%0s x%0d expected=%08h actual=%08h I=%0d/%0d D=%0d/%0d",
                           case_name,k,expected_regs[k],dut.rf.regs[k],
                           bus.i_requests,bus.i_responses,bus.d_requests,bus.d_responses);
                arch_checks=arch_checks+1;
            end
            for (k=0;k<1024;k=k+1) begin
                if (bus.dmem[k] !== expected_mem[k])
                    $fatal(1,"%0s dmem[%0d] expected=%08h actual=%08h",
                           case_name,k,expected_mem[k],bus.dmem[k]);
                arch_checks=arch_checks+1;
            end
        end
    endtask
    task automatic run_case(input [31:0] marker,
                            input integer expected_d_transactions,
                            input integer expected_stores);
        integer n, budget;
        begin
            repeat(3) @(negedge clk);
            rst_n=1;
            budget=2200+160*(I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+DATA_RESPONSE_DELAY);
            if (marker==6 || marker==7)
                budget=25000+100*(I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+DATA_RESPONSE_DELAY);
            n=0;
            while (dut.rf.regs[31] !== marker && n<budget) begin
                @(negedge clk);
                n=n+1;
            end
            if (dut.rf.regs[31] !== marker)
                $fatal(1,"External CPU timeout %0s after %0d cycles, I=%0d/%0d D=%0d/%0d pc=%08h",
                       case_name,n,bus.i_requests,bus.i_responses,bus.d_requests,bus.d_responses,dut.pc);
            repeat(25+I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+DATA_RESPONSE_DELAY*4) @(negedge clk);
            check_state();
            if (bus.d_requests!==expected_d_transactions ||
                bus.d_responses!==expected_d_transactions ||
                bus.d_stores!==expected_stores)
                $fatal(1,"%0s duplicate/missing data request: expected d=%0d stores=%0d got req=%0d rsp=%0d stores=%0d",
                       case_name,expected_d_transactions,expected_stores,
                       bus.d_requests,bus.d_responses,bus.d_stores);
            if (bus.i_requests<1 || bus.i_requests-bus.i_responses>1 ||
                bus.i_responses>bus.i_requests)
                $fatal(1,"%0s instruction request/response imbalance %0d/%0d",
                       case_name,bus.i_requests,bus.i_responses);
            passed=passed+1;
            $display("PASS external %0s cycles=%0d I=%0d/%0d D=%0d/%0d stores=%0d Iwait=%0d Dwait=%0d Iheld=%0d Dheld=%0d",
                     case_name,n,bus.i_requests,bus.i_responses,bus.d_requests,
                     bus.d_responses,bus.d_stores,bus.i_wait_cycles,bus.d_wait_cycles,
                     bus.i_rsp_held_cycles,bus.d_rsp_held_cycles);
        end
    endtask

    task automatic test_mixed_memory;
        begin
            prepare("mixed stores, loads and byte lanes");
            preload(3,32'habcd0123);
            bus.imem[0]=addi(1,0,11);
            bus.imem[1]=store(3'b010,1,0,0);
            bus.imem[2]=store(3'b010,1,0,4);
            bus.imem[3]=load(3'b010,2,0,0);
            bus.imem[4]=load(3'b010,3,0,4);
            bus.imem[5]=add(4,2,3);
            bus.imem[6]=store(3'b010,4,0,8);
            bus.imem[7]=load(3'b010,5,0,8);
            bus.imem[8]=addi(6,5,1);
            bus.imem[9]=store(3'b000,6,0,13);
            bus.imem[10]=load(3'b100,7,0,13);
            bus.imem[11]=store(3'b001,4,0,14);
            bus.imem[12]=load(3'b010,8,0,12);
            bus.imem[13]=addi(31,0,1);
            expect_reg(1,11);expect_reg(2,11);expect_reg(3,11);
            expect_reg(4,22);expect_reg(5,22);expect_reg(6,23);
            expect_reg(7,23);expect_reg(8,32'h00161723);expect_reg(31,1);
            expect_mem(0,11);expect_mem(1,11);
            expect_mem(2,22);expect_mem(3,32'h00161723);
            run_case(1,10,5);
        end
    endtask

    task automatic test_redirects;
        begin
            prepare("branch redirects and wrong-path suppression");
            preload(10,9);preload(11,32'hdeadbeef);preload(14,32'h5abadead);
            bus.imem[0]=load(3'b010,1,0,40);
            bus.imem[1]=addi(2,0,9);
            bus.imem[2]=beq(1,2,16);
            bus.imem[3]=store(3'b010,1,0,44); // forbidden
            bus.imem[4]=load(3'b010,10,0,44); // forbidden
            bus.imem[5]=addi(11,0,42);       // forbidden
            bus.imem[6]=store(3'b010,1,0,48);
            bus.imem[7]=load(3'b010,3,0,48);
            bus.imem[8]=addi(4,3,1);
            bus.imem[9]=bne(4,2,12);
            bus.imem[10]=store(3'b010,4,0,44); // forbidden
            bus.imem[11]=addi(12,0,20);       // forbidden
            bus.imem[12]=store(3'b010,4,0,52);
            bus.imem[13]=load(3'b010,5,0,52);
            bus.imem[14]=beq(5,4,8);
            bus.imem[15]=store(3'b010,5,0,56); // forbidden
            bus.imem[16]=addi(31,0,2);
            expect_reg(1,9);expect_reg(2,9);expect_reg(3,9);
            expect_reg(4,10);expect_reg(5,10);expect_reg(31,2);
            expect_mem(12,9);expect_mem(13,10);
            run_case(2,5,2);
        end
    endtask

    task automatic test_backward_fetch;
        begin
            prepare("backward branch with delayed fetch");
            preload(16,4);preload(18,32'hfadedead);
            bus.imem[0]=load(3'b010,1,0,64);
            bus.imem[1]=addi(2,0,0);
            bus.imem[2]=addi(2,2,1);
            bus.imem[3]=bne(2,1,-4);
            bus.imem[4]=store(3'b010,2,0,68);
            bus.imem[5]=load(3'b010,3,0,68);
            bus.imem[6]=beq(3,1,12);
            bus.imem[7]=store(3'b010,3,0,72); // forbidden
            bus.imem[8]=addi(12,0,100); // forbidden
            bus.imem[9]=addi(31,0,3);
            expect_reg(1,4);expect_reg(2,4);expect_reg(3,4);expect_reg(31,3);
            expect_mem(17,4);
            run_case(3,3,1);
        end
    endtask

    task automatic test_sign_extension;
        begin
            prepare("signed subword loads and masked stores");
            preload(20,32'h80ff7f01);
            bus.imem[0]=load(3'b000,1,0,80);
            bus.imem[1]=load(3'b000,2,0,81);
            bus.imem[2]=load(3'b000,3,0,82);
            bus.imem[3]=load(3'b000,4,0,83);
            bus.imem[4]=load(3'b100,5,0,82);
            bus.imem[5]=load(3'b101,6,0,82);
            bus.imem[6]=load(3'b001,7,0,82);
            bus.imem[7]=addi(8,0,-1);
            bus.imem[8]=store(3'b000,8,0,81);
            bus.imem[9]=store(3'b001,8,0,82);
            bus.imem[10]=load(3'b010,9,0,80);
            bus.imem[11]=addi(31,0,4);
            expect_reg(1,1);expect_reg(2,127);
            expect_reg(3,32'hffffffff);expect_reg(4,32'hffffff80);
            expect_reg(5,255);expect_reg(6,32'h80ff);
            expect_reg(7,32'hffff80ff);expect_reg(8,32'hffffffff);
            expect_reg(9,32'hffffff01);expect_reg(31,4);
            expect_mem(20,32'hffffff01);
            run_case(4,10,2);
        end
    endtask

    task automatic test_reset_cancellation;
        integer cycles;
        begin
            prepare("reset aborts pending external store");
            preload(30,317);
            bus.imem[0]=addi(1,0,96);
            bus.imem[1]=store(3'b010,1,0,120);
            bus.imem[2]=addi(31,0,99);
            repeat(3) @(negedge clk);
            rst_n=1;
            cycles=0;
            // Stop after a request was accepted, before the response handshake.
            while (!(bus.d_busy && !bus.d_rsp_valid && bus.d_saved_write) &&
                   cycles<1000) begin
                @(negedge clk);
                cycles=cycles+1;
            end
            if (cycles>=1000)
                $fatal(1,"Reset test never found outstanding store");
            if (bus.dmem[30] !== 317)
                $fatal(1,"Store committed before acknowledgment");
            rst_n=0;
            repeat(3) @(negedge clk);
            if (bus.dmem[30] !== 317 || bus.d_busy !== 0 || bus.d_rsp_valid !== 0)
                $fatal(1,"Reset failed to cancel data transaction");
            bus.imem[0]=load(3'b010,2,0,120);
            bus.imem[1]=addi(3,2,1);
            bus.imem[2]=store(3'b010,3,0,124);
            bus.imem[3]=load(3'b010,4,0,124);
            bus.imem[4]=addi(31,0,5);
            expect_reg(2,317);expect_reg(3,318);
            expect_reg(4,318);expect_reg(31,5);
            expect_mem(31,318);
            run_case(5,3,1);
        end
    endtask

    task automatic test_fetch_tag_wrap;
        begin
            prepare("300 redirect loop, 8-bit epoch wrap");
            // Each taken backwards BNE redirects instruction fetch and changes
            // its epoch tag. Exactly 299 taken branches wrap the 8-bit tag.
            bus.imem[0]=addi(1,0,0);
            bus.imem[1]=addi(1,1,1);
            bus.imem[2]=encode_i(300,1,3'b010,2,7'h13); // slti x2,x1,300
            bus.imem[3]=bne(2,0,-8);
            bus.imem[4]=addi(31,0,6);
            expect_reg(1,300);expect_reg(2,0);expect_reg(31,6);
            run_case(6,0,0);
            if (bus.i_tag_wraps<1 || bus.i_requests<256)
                $fatal(1,"Fetch epoch did not wrap: wrap=%0d fetches=%0d",
                       bus.i_tag_wraps,bus.i_requests);
        end
    endtask

    task automatic test_long_straight_line;
        integer n;
        begin
            prepare("301 sequential instructions across fetch");
            // >256 static instructions with continuous RAW dependencies and
            // no branches. The fetch-epoch wrap is tested independently above.
            bus.imem[0]=addi(1,0,0);
            for (n=1;n<=300;n=n+1)
                bus.imem[n]=addi(1,1,1);
            bus.imem[301]=addi(31,0,7);
            expect_reg(1,300);expect_reg(31,7);
            run_case(7,0,0);
            if (bus.i_requests<302)
                $fatal(1,"Straight-line test fetched too few instructions: %0d",
                       bus.i_requests);
        end
    endtask

    task automatic test_python_reference;
        reg [8*512-1:0] program_file,initial_file,regs_file,mem_file;
        integer program_words,cycles,limit,k;
        begin
            prepare("independent Python sequential oracle");
            if (!$value$plusargs("program=%s",program_file) ||
                !$value$plusargs("initial_mem=%s",initial_file) ||
                !$value$plusargs("expected_regs=%s",regs_file) ||
                !$value$plusargs("expected_mem=%s",mem_file) ||
                !$value$plusargs("nins=%d",program_words))
                $fatal(1,"Reference mode requires +program +initial_mem +expected_regs +expected_mem +nins");
            if (program_words<1 || program_words>950)
                $fatal(1,"Bad independent reference program length %0d",program_words);
            $readmemh(program_file,bus.imem);
            $readmemh(initial_file,bus.dmem);
            $readmemh(regs_file,expected_regs);
            $readmemh(mem_file,expected_mem);
            repeat(3) @(negedge clk);
            rst_n=1;
            cycles=0;
            limit=25000+200*(I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+DATA_RESPONSE_DELAY);
            // Generated program is forward-only apart from simple skipped
            // instructions. Its sequential oracle stops at program_words*4.
            while (dut.pc < program_words*4+32 && cycles<limit) begin
                @(negedge clk);
                cycles=cycles+1;
            end
            if (cycles>=limit)
                $fatal(1,"Python reference program timed out pc=%08h after %0d cycles",
                       dut.pc,cycles);
            repeat(45+I_LATENCY+I_JITTER+D_LATENCY+D_JITTER+DATA_RESPONSE_DELAY*3) @(negedge clk);
            check_state();
            if (bus.d_requests!==bus.d_responses)
                $fatal(1,"Python reference mismatched D request/response %0d/%0d",
                       bus.d_requests,bus.d_responses);
            if (bus.i_requests-bus.i_responses>1 || bus.i_responses>bus.i_requests)
                $fatal(1,"Python reference I request/response mismatch %0d/%0d",
                       bus.i_requests,bus.i_responses);
            passed=passed+1;
            $display("PASS external Python oracle nins=%0d cycles=%0d checks=%0d I=%0d/%0d D=%0d/%0d writes=%0d",
                     program_words,cycles,arch_checks,bus.i_requests,bus.i_responses,
                     bus.d_requests,bus.d_responses,bus.d_stores);
        end
    endtask

    initial begin
        corrupt_i_tag=$test$plusargs("corrupt_i_tag");
        corrupt_d_tag=$test$plusargs("corrupt_d_tag");
        if ($value$plusargs("vcd=%s",wave_path)) begin
            $dumpfile(wave_path);
            $dumpvars(0,tb_external_bus_rv32i);
        end
        if ($test$plusargs("reference")) begin
            test_python_reference();
        end else begin
            test_mixed_memory();
            test_redirects();
            test_backward_fetch();
            test_sign_extension();
            test_reset_cancellation();
            test_fetch_tag_wrap();
            test_long_straight_line();
        end
        $display("PASS external-bus RV32I cases=%0d state-checks=%0d I(%0d+%0d) D(%0d+%0d) throttle=%0d response-delay=%0d",
                 passed,arch_checks,I_LATENCY,I_JITTER,D_LATENCY,D_JITTER,
                 READY_MODE,DATA_RESPONSE_DELAY);
        $finish;
    end
endmodule
`default_nettype wire
