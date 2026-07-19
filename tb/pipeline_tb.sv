`timescale 1ns/1ps
module pipeline_tb;
    logic clk=0; logic rst_n=0;
    always #5 clk = ~clk;
    core_top uut(.clk(clk), .rst_n(rst_n));
    initial begin
        rst_n=0; #20; rst_n=1;
        // This baseline test checks power-up and a few cycles of the core top
        repeat (20) @(posedge clk);
        $display("pipeline_tb: completed smoke cycles (manual inspection may be needed)"); $finish;
    end
endmodule