`timescale 1ns/1ps
module branch_tb;
    logic clk=0; logic rst_n=0;
    always #5 clk = ~clk;
    pipeline_core uut(.clk(clk), .rst_n(rst_n));
    initial begin
        rst_n=0; #20; rst_n=1;
        // Program to test BEQ: set x1=5, x2=5, then BEQ x1,x2, +8 (skip next instruction)
        // Using simplified encodings aligned to earlier tests
        uut.imem[0] = 32'h00500113; // ADDI x2,x0,5 -> x2=5
        uut.imem[1] = 32'h00500093; // ADDI x1,x0,5 -> x1=5
        // BEQ x1,x2, +8 -> encodings are illustrative
        uut.imem[2] = 32'h00208663; // BEQ x1,x2,offset
        uut.imem[3] = 32'h00110113; // ADDI x2,x2,1 (should be skipped if branch taken)
        uut.imem[4] = 32'h00000013; // NOP
        repeat (50) @(posedge clk);
        $display("branch_tb: done"); $finish;
    end
endmodule