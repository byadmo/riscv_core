`timescale 1ns/1ps
`default_nettype none
// Negative test: simulation must reject invalid access, not silently alias.
// The regression runner expects $fatal with 'Unsupported memory access'.
module tb_memory_fault;
    parameter integer FAULT_CASE=0;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    pipeline_core dut(.clk(clk),.rst_n(rst_n));
    initial begin
        for(integer i=0;i<1024;i=i+1)begin
            dut.imem[i]=32'h00000013;
            dut.mem_model.words[i]=32'h11223344;
        end
        case(FAULT_CASE)
            0: dut.imem[0]=32'h00101083; // LH x1,1(x0) odd halfword
            1: dut.imem[0]=32'h00202083; // LW x1,2(x0) unaligned word
            2: dut.imem[0]=32'h001011a3; // SH x1,3(x0) unaligned halfword
            3: begin
                dut.imem[0]=32'h000010b7; // LUI x1,0x1 => 4096
                dut.imem[1]=32'h0000a103; // LW x2,0(x1)
            end
            default: $fatal(1,"invalid FAULT_CASE");
        endcase
        repeat(3) @(negedge clk);
        rst_n=1;
        repeat(50) @(negedge clk);
        $fatal(1,"fault missed; invalid memory access was silently accepted");
    end
endmodule
`default_nettype wire
