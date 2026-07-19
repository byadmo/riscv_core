`timescale 1ns/1ps
module full_pipeline_tb;
    logic clk=0; logic rst_n=0;
    always #5 clk = ~clk;
    pipeline_core uut(.clk(clk), .rst_n(rst_n));
    initial begin
        rst_n=0; #20; rst_n=1;
        // Simple program: initialize memory, test ADDI, ADD, LW, SW, BEQ
        // imm/encoding examples simplified and aligned with earlier tests
        uut.imem[0] = 32'h00000013; // NOP (ADDI x0,x0,0)
        uut.imem[1] = 32'h00400093; // ADDI x1,x0,4 -> x1=4 (imm=4 rd=1)
        uut.imem[2] = 32'h001080b3; // ADD x1,x1,x1 -> x1 = 8 (example)
        // store x1 to dmem[1]
        // SW x1,4(x0) -> 0x00102023 (example)
        uut.imem[3] = 32'h00102023;
        // load back
        uut.imem[4] = 32'h00002103; // LW x2,4(x0)
        // branch if x2==x1 (BEQ) -> if equal watch PC change
        uut.imem[5] = 32'h00218263; // BEQ x3,x2,offset (crafted example)
        // run
        repeat (100) @(posedge clk);
        $display("full_pipeline_tb: done"); $finish;
    end
endmodule