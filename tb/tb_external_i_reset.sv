`timescale 1ns/1ps
`default_nettype none
// Independent test of shared reset during three distinct external I-channel
// states. The existing external regression checks reset of an older D store;
// these tests specifically check that no queued, outstanding or held I
// transaction survives into a fresh program.
module tb_external_i_reset #(
    parameter integer FAULT_HALT=1,
    parameter integer I_LATENCY=2,
    parameter integer D_LATENCY=25
);
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
    pipeline_core #(.EXTERNAL_PORTS(1),.FAULT_HALT(FAULT_HALT)) dut(
        .clk(clk),.rst_n(rst_n),.fault_valid(fault_valid),
        .fault_cause(fault_cause),.fault_pc(fault_pc),.fault_tval(fault_tval),
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
        .I_LATENCY(I_LATENCY),.I_JITTER(0),
        .D_LATENCY(D_LATENCY),.D_JITTER(0),.READY_MODE(1)
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
    localparam [31:0] NOP=32'h00000013;
    integer checks=0;
    reg req_held=0,rsp_held=0;
    reg [39:0] last_req=0;
    reg [71:0] last_rsp=0;
    reg [8*64-1:0] current_case;
    always @(posedge clk) begin
        if (!rst_n) begin
            req_held<=0;rsp_held<=0;
        end else begin
            if (i_req_valid && (|i_req_addr[31:12] || |i_req_addr[1:0]))
                $fatal(1,"%0s invalid I request %08h",current_case,i_req_addr);
            if (req_held && (!i_req_valid ||
                {i_req_addr,i_req_tag} !== last_req))
                $fatal(1,"%0s unaccepted I request canceled/changed",current_case);
            if (rsp_held && (!i_rsp_valid ||
                {i_rsp_addr,i_rsp_tag,i_rsp_data} !== last_rsp))
                $fatal(1,"%0s held I response canceled/changed",current_case);
            req_held<=i_req_valid && !i_req_ready;
            rsp_held<=i_rsp_valid && !i_rsp_ready;
            last_req<={i_req_addr,i_req_tag};
            last_rsp<={i_rsp_addr,i_rsp_tag,i_rsp_data};
        end
    end
    function automatic [31:0] addi(input [4:0] rd,rs1,input integer imm);
        addi={imm[11:0],rs1,3'b000,rd,7'h13};
    endfunction
    function automatic [31:0] lw(input [4:0] rd,rs1,input integer imm);
        lw={imm[11:0],rs1,3'b010,rd,7'h03};
    endfunction
    task automatic load_program(input integer kind);
        integer k;
        begin
            @(negedge clk);
            rst_n=0;
            for(k=0;k<1024;k=k+1) bus.imem[k]=NOP;
            bus.dmem[0]=32'h12345678;
            if (kind==3) begin
                bus.imem[0]=lw(1,0,0);
                bus.imem[1]=addi(2,0,52);
            end else begin
                bus.imem[0]=addi(1,0,99);
                bus.imem[1]=addi(2,0,98);
            end
            repeat(4) @(negedge clk);
            rst_n=1;
        end
    endtask
    task automatic reset_and_restart;
        integer k,cycles;
        begin
            // Called at negedge while an I-channel condition is observed.
            rst_n=0;
            for(k=0;k<1024;k=k+1) bus.imem[k]=NOP;
            bus.imem[0]=addi(5,0,21);
            bus.imem[1]=addi(31,0,61);
            bus.imem[2]=32'h0000006f; // JAL x0,0, stable loop
            repeat(4) @(negedge clk);
            if (i_req_valid!==0 || i_rsp_valid!==0 ||
                d_req_valid!==0 || d_rsp_valid!==0 ||
                dut.if_pending!==0 || dut.if_request_waiting!==0 ||
                dut.if_buffer_valid!==0 || bus.i_busy!==0 || bus.d_busy!==0 ||
                fault_valid!==0 || dut.pc!==0 || dut.rf.regs[1]!==0 ||
                bus.i_requests!==0 || bus.d_requests!==0)
                $fatal(1,"%0s reset did not cancel pending work and clear architectural state",
                       current_case);
            rst_n=1;
            cycles=0;
            while (dut.rf.regs[31]!==61 && cycles<1000) begin
                @(negedge clk);cycles=cycles+1;
            end
            if (cycles>=1000)
                $fatal(1,"%0s restart timed out after canceled I transaction",current_case);
            repeat(15) @(negedge clk);
            if (dut.rf.regs[1]!==0 || dut.rf.regs[2]!==0 ||
                dut.rf.regs[5]!==21 || dut.rf.regs[31]!==61 ||
                bus.dmem[0]!==32'h12345678 || bus.d_requests!==0 ||
                bus.d_responses!==0 || fault_valid!==0)
                $fatal(1,"%0s stale I/D work contaminated restart",current_case);
            checks=checks+1;
            $display("PASS external-I reset %0s cycles=%0d",current_case,cycles);
        end
    endtask
    task automatic scenario(input integer kind);
        integer cycles;
        reg found;
        begin
            case(kind)
                1: current_case="queued unaccepted instruction request";
                2: current_case="accepted unanswered instruction request";
                3: current_case="held I response while older D load waits";
                default: $fatal(1,"Invalid external reset test index");
            endcase
            load_program(kind);
            cycles=0;found=0;
            while (!found && cycles<1000) begin
                @(negedge clk);cycles=cycles+1;
                case(kind)
                    1: found=i_req_valid && !i_req_ready && bus.i_requests==0;
                    2: found=bus.i_busy && !i_rsp_valid && bus.i_requests==1;
                    3: found=i_rsp_valid && !i_rsp_ready && bus.d_busy;
                endcase
            end
            if (!found)
                $fatal(1,"%0s targeted bus state never occurred",current_case);
            $display("COVER external-I reset %0s old I=%0d/%0d D=%0d/%0d",
                     current_case,bus.i_requests,bus.i_responses,
                     bus.d_requests,bus.d_responses);
            reset_and_restart();
        end
    endtask
    initial begin
        scenario(1);
        scenario(2);
        scenario(3);
        if (checks!==3) $fatal(1,"missing external I reset scenarios");
        $display("PASS external-I reset suite fault_halt=%0d: 3 distinct in-flight reset conditions",
                 FAULT_HALT);
        $finish;
    end
endmodule
`default_nettype wire
