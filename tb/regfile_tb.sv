`timescale 1ns/1ps
module regfile_tb;
    logic clk=0; logic rst_n=0;
    logic we; logic [4:0] rs1, rs2, rd;
    logic [31:0] wd, rd1, rd2;
    regfile uut(.clk(clk), .rst_n(rst_n), .we(we), .rs1(rs1), .rs2(rs2), .rd(rd), .wd(wd), .rd1(rd1), .rd2(rd2));
    always #5 clk = ~clk;
    initial begin
        rst_n = 0; #20; rst_n = 1;
        // write x1 = 42
        we=1; rd=5'd1; wd=32'd42; rs1=5'd1; rs2=5'd0; #10;
        we=0; #10;
        if (rd1 !== 32'd42) begin $display("REGFILE FAIL: expected 42 got %0d", rd1); $finish; end
        // x0 stays zero
        rs1=5'd0; #10; if (rd1 !== 32'd0) begin $display("REGFILE FAIL: x0 not zero"); $finish; end
        $display("regfile_tb: PASS"); $finish;
    end
endmodule