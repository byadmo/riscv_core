`timescale 1ns/1ps
`default_nettype none
// Separate adversarial FAULT_HALT=1 suite. Historical 90 fault-halt cases
// and 72 fetch-boundary cases remain unchanged and independently counted.
module tb_fault_priority #(
    parameter integer EXTERNAL_MODE=0,
    parameter integer DATA_LATENCY=2,
    parameter integer DATA_MAX_EXTRA=2,
    parameter integer I_LATENCY=2,
    parameter integer I_JITTER=2,
    parameter integer D_LATENCY=3,
    parameter integer D_JITTER=2,
    parameter integer READY_MODE=1,
    parameter integer DATA_RESPONSE_DELAY=0
);
    localparam [31:0] NOP=32'h00000013;
    localparam [31:0] ILLEGAL=32'hffffffff;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    wire fault_valid;
    wire [31:0] fault_cause,fault_pc,fault_tval;
    wire i_req_valid,i_req_ready,i_rsp_valid,i_rsp_ready;
    wire [31:0] i_req_addr,i_rsp_addr,i_rsp_data;
    wire [7:0] i_req_tag,i_rsp_tag;
    wire d_req_valid,d_req_ready,d_req_write,d_rsp_valid,d_rsp_ready;
    wire [31:0] d_req_addr,d_req_wdata,d_rsp_rdata;
    wire [7:0] d_req_tag,d_rsp_tag;
    wire [3:0] d_req_wstrb;

    pipeline_core #(
        .FAULT_HALT(1),.EXTERNAL_PORTS(EXTERNAL_MODE),
        .DATA_LATENCY(DATA_LATENCY),.DATA_MAX_EXTRA(DATA_MAX_EXTRA),
        .DATA_RESPONSE_DELAY(DATA_RESPONSE_DELAY)
    ) dut (
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
    dual_port_bus_adapter #(
        .I_LATENCY(I_LATENCY),.I_JITTER(I_JITTER),
        .D_LATENCY(D_LATENCY),.D_JITTER(D_JITTER),.READY_MODE(READY_MODE)
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

    integer passed=0,comparisons=0;
    integer offered_d=0,accepted_d=0,completed_d=0,held_d=0;
    integer internal_d=0,internal_completed=0;
    reg saw_fault=0;
    reg [31:0] saved_cause=0,saved_pc=0,saved_tval=0;
    reg d_rsp_was_held=0;
    reg [39:0] d_rsp_payload=0;
    reg [31:0] expected_regs [0:31];
    reg [31:0] expected_mem [0:1023];
    reg [8*80-1:0] case_name;

    always @(posedge clk) begin
        if (!rst_n) begin
            offered_d<=0;accepted_d<=0;completed_d<=0;held_d<=0;
            internal_d<=0;internal_completed<=0;
            saw_fault<=0;saved_cause<=0;saved_pc<=0;saved_tval<=0;
            d_rsp_was_held<=0;d_rsp_payload<=0;
        end else begin
            if (dut.mem_req_valid && dut.mem_req_ready && !EXTERNAL_MODE)
                internal_d<=internal_d+1;
            if (dut.mem_rsp_valid && !EXTERNAL_MODE)
                internal_completed<=internal_completed+1;
            if (EXTERNAL_MODE) begin
                if (d_req_valid) offered_d<=offered_d+1;
                if (d_req_valid && d_req_ready) accepted_d<=accepted_d+1;
                if (d_rsp_valid && d_rsp_ready) completed_d<=completed_d+1;
                if (d_rsp_valid && !d_rsp_ready) held_d<=held_d+1;
                if (d_rsp_was_held &&
                    (!d_rsp_valid || {d_rsp_tag,d_rsp_rdata} !== d_rsp_payload))
                    $fatal(1,"%0s external held D response changed",case_name);
                d_rsp_was_held<=d_rsp_valid && !d_rsp_ready;
                d_rsp_payload<={d_rsp_tag,d_rsp_rdata};
            end
            if (saw_fault &&
                ({fault_valid,fault_cause,fault_pc,fault_tval} !==
                 {1'b1,saved_cause,saved_pc,saved_tval}))
                $fatal(1,"%0s fault metadata changed after halt",case_name);
            if (fault_valid && !saw_fault) begin
                if (EXTERNAL_MODE && accepted_d !== completed_d)
                    $fatal(1,"%0s fault overtook older D response",case_name);
                if (!EXTERNAL_MODE && internal_d !== internal_completed)
                    $fatal(1,"%0s fault overtook unfinished internal D access %0d/%0d",
                           case_name,internal_d,internal_completed);
                saw_fault<=1;
                saved_cause<=fault_cause;saved_pc<=fault_pc;saved_tval<=fault_tval;
            end
        end
    end

    function automatic [31:0] iword(input integer imm,
        input [4:0] rs1,input [2:0] f3,input [4:0] rd,input [6:0] opcode);
        iword={imm[11:0],rs1,f3,rd,opcode};
    endfunction
    function automatic [31:0] sword(input integer imm,
        input [4:0] rs2,rs1,input [2:0] f3);
        sword={imm[11:5],rs2,rs1,f3,imm[4:0],7'h23};
    endfunction
    function automatic [31:0] rword(input [6:0] f7,
        input [4:0] rs2,rs1,input [2:0] f3,input [4:0] rd);
        rword={f7,rs2,rs1,f3,rd,7'h33};
    endfunction
    task automatic put(input integer index,input [31:0] ins);
        begin dut.imem[index]=ins;bus.imem[index]=ins;end
    endtask
    task automatic prepare(input [8*80-1:0] name);
        integer k;
        begin
            @(negedge clk);
            rst_n=0;
            case_name=name;
            for (k=0;k<1024;k=k+1) begin
                put(k,NOP);
                dut.mem_model.words[k]=0;bus.dmem[k]=0;expected_mem[k]=0;
            end
            for (k=0;k<32;k=k+1) expected_regs[k]=0;
            repeat(3) @(negedge clk);
            if ({fault_valid,fault_cause,fault_pc,fault_tval} !== 97'b0)
                $fatal(1,"%0s fault failed to reset",case_name);
        end
    endtask
    task automatic check_state;
        integer k;
        reg [31:0] observed;
        begin
            for (k=0;k<32;k=k+1) begin
                if (dut.rf.regs[k] !== expected_regs[k])
                    $fatal(1,"%0s x%0d wanted=%08h got=%08h",
                           case_name,k,expected_regs[k],dut.rf.regs[k]);
                comparisons=comparisons+1;
            end
            for (k=0;k<1024;k=k+1) begin
                observed=EXTERNAL_MODE ? bus.dmem[k] : dut.mem_model.words[k];
                if (observed !== expected_mem[k])
                    $fatal(1,"%0s RAM[%0d] wanted=%08h got=%08h",
                           case_name,k,expected_mem[k],observed);
                comparisons=comparisons+1;
            end
        end
    endtask
    task automatic finish_case(input integer want_cause,
        input [31:0] want_pc,want_tval,input integer want_d,input integer check_early_wb);
        integer cycles;
        begin
            @(negedge clk);
            rst_n=1;
            cycles=0;
            while (fault_valid!==1'b1 && cycles<1500) begin
                @(negedge clk);
                cycles=cycles+1;
            end
            if (cycles>=1500)
                $fatal(1,"%0s fault did not occur",case_name);
            if ({fault_cause,fault_pc,fault_tval} !==
                {32'(want_cause),want_pc,want_tval})
                $fatal(1,"%0s wrong cause/pc/tval actual=%0d/%08h/%08h expected=%0d/%08h/%08h",
                       case_name,fault_cause,fault_pc,fault_tval,want_cause,want_pc,want_tval);
            if (check_early_wb && !EXTERNAL_MODE && dut.rf.regs[2] !== 0)
                $fatal(1,"%0s expected older ALU writeback still pending at fault_valid",case_name);
            repeat(30+DATA_RESPONSE_DELAY+D_LATENCY+I_LATENCY) @(negedge clk);
            check_state();
            if (EXTERNAL_MODE) begin
                if (accepted_d!==want_d || completed_d!==want_d ||
                    bus.d_requests!==want_d || bus.d_responses!==want_d ||
                    (want_d==0 && offered_d!=0))
                    $fatal(1,"%0s D transactions expected=%0d got=%0d/%0d offered=%0d",
                           case_name,want_d,accepted_d,completed_d,offered_d);
                // Guaranteed by these matrix configurations: core response
                // hold delay exceeds the adapter's bounded response delay.
                if (want_d>0 && DATA_RESPONSE_DELAY>=D_LATENCY+D_JITTER+2 &&
                    held_d<1)
                    $fatal(1,"%0s expected held D response never exercised",case_name);
            end else if (internal_d!==want_d || internal_completed!==want_d)
                $fatal(1,"%0s internal D expected=%0d got requests=%0d responses=%0d",
                       case_name,want_d,internal_d,internal_completed);
            passed=passed+1;
            $display("PASS priority ext=%0d %-44s cause=%0d pc=%08h tval=%08h D=%0d heldD=%0d",
                     EXTERNAL_MODE,case_name,want_cause,want_pc,want_tval,want_d,held_d);
        end
    endtask
    task automatic invalid(input [8*80-1:0] name,
        input [31:0] first,bad,input integer cause,
        input [31:0] tval,reg1);
        begin
            prepare(name);
            put(0,first);put(1,bad);put(2,iword(99,0,0,6,7'h13));
            expected_regs[1]=reg1;
            finish_case(cause,4,tval,0,0);
        end
    endtask
    task automatic older_store;
        begin
            prepare("older delayed SW completes before reserved-R fault");
            put(0,iword(47,0,0,1,7'h13));
            put(1,sword(0,1,0,3'b010));
            put(2,rword(7'h20,1,1,3'b001,5));
            put(3,iword(99,0,0,6,7'h13));
            expected_regs[1]=47;expected_mem[0]=47;
            finish_case(2,8,rword(7'h20,1,1,3'b001,5),1,0);
        end
    endtask
    task automatic older_load;
        begin
            prepare("older delayed LW+dependent ALU retire before illegal");
            dut.mem_model.words[0]=33;bus.dmem[0]=33;expected_mem[0]=33;
            put(0,iword(0,0,3'b010,1,7'h03));
            put(1,iword(1,1,0,2,7'h13));
            put(2,ILLEGAL);put(3,iword(99,0,0,6,7'h13));
            expected_regs[1]=33;expected_regs[2]=34;
            finish_case(2,8,ILLEGAL,1,0);
        end
    endtask
    task automatic older_alu;
        begin
            prepare("older ALU register write retires after fault_valid");
            put(0,iword(7,0,0,1,7'h13));
            put(1,iword(1,1,0,2,7'h13));
            put(2,ILLEGAL);put(3,iword(99,0,0,6,7'h13));
            expected_regs[1]=7;expected_regs[2]=8;
            finish_case(2,8,ILLEGAL,0,1);
        end
    endtask

    initial begin
        invalid("negative LB -1 range",iword(-1,0,0,1,7'h13),iword(0,1,0,5,7'h03),5,32'hffffffff,32'hffffffff);
        invalid("negative LH -1 alignment wins over range",iword(-1,0,0,1,7'h13),iword(0,1,1,5,7'h03),4,32'hffffffff,32'hffffffff);
        invalid("negative LW -4 range",iword(-4,0,0,1,7'h13),iword(0,1,2,5,7'h03),5,32'hfffffffc,32'hfffffffc);
        invalid("negative SW -4 range",iword(-4,0,0,1,7'h13),sword(0,1,1,2),7,32'hfffffffc,32'hfffffffc);
        invalid("negative SW -1 alignment wins over range",iword(-1,0,0,1,7'h13),sword(0,1,1,2),6,32'hffffffff,32'hffffffff);
        invalid("last byte 4095 SH alignment",{20'd1,5'd1,7'h37},sword(-1,1,1,1),6,32'h00000fff,32'h00001000);
        invalid("past end 4097 SH alignment wins over range",{20'd1,5'd1,7'h37},sword(1,1,1,1),6,32'h00001001,32'h00001000);
        invalid("past end 4096 LW range",{20'd1,5'd1,7'h37},iword(0,1,2,5,7'h03),5,32'h00001000,32'h00001000);
        invalid("reserved SLL funct7=0x20",iword(4,0,0,1,7'h13),rword(7'h20,1,1,1,5),2,rword(7'h20,1,1,1,5),4);
        invalid("M extension MUL funct7=0x01",iword(4,0,0,1,7'h13),rword(7'h01,1,1,0,5),2,rword(7'h01,1,1,0,5),4);
        invalid("reserved AND funct7=0x20",iword(4,0,0,1,7'h13),rword(7'h20,1,1,7,5),2,rword(7'h20,1,1,7,5),4);
        invalid("reserved branch funct3=010",iword(4,0,0,1,7'h13),32'h0010a263,2,32'h0010a263,4);
        invalid("reserved JALR funct3=001",iword(5,0,0,1,7'h13),iword(1,1,1,5,7'h67),2,iword(1,1,1,5,7'h67),5);
        invalid("reserved LW funct3=011 outrange",iword(-1,0,0,1,7'h13),iword(0,1,3,5,7'h03),2,iword(0,1,3,5,7'h03),32'hffffffff);
        invalid("reserved SW funct3=011 outrange",iword(-1,0,0,1,7'h13),sword(0,1,1,3),2,sword(0,1,1,3),32'hffffffff);
        older_store();
        older_load();
        older_alu();
        $display("PASS fault-priority suite ext=%0d cases=%0d architectural-checks=%0d",
                 EXTERNAL_MODE,passed,comparisons);
        $finish;
    end
endmodule
`default_nettype wire
