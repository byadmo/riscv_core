`timescale 1ns/1ps
module jal_jalr_tb;
    logic clk=0; logic rst_n=0;
    always #5 clk = ~clk;
    pipeline_core uut(.clk(clk), .rst_n(rst_n));
    initial begin
        rst_n=0; #20; rst_n=1;
        // Test JAL: write return address to x1 and jump forward
        uut.imem[0] = 32'h0000006f; // JAL x0,0 (noop) - placeholder
        uut.imem[1] = 32'h004000ef; // JAL x1,4 -> x1=pc+4; pc+=4
        uut.imem[2] = 32'h00000013; // NOP
        uut.imem[3] = 32'h00000013; // NOP
        repeat (50) @(posedge clk);
        $display("jal_jalr_tb: done"); $finish;
    end
endmodule