`timescale 1ns/1ps
module alu_tb;
    logic [3:0] op; logic [31:0] a,b; logic [31:0] res;
    alu uut(.alu_op(op), .a(a), .b(b), .result(res));
    initial begin
        a=10; b=5; op=0; #1; if (res!==15) $fatal(1, "ALU ADD fail");
        op=1; #1; if (res!==5) $fatal(1, "ALU SUB fail");
        op=2; a=8; b=3; #1; if (res!==(8^3)) $fatal(1, "ALU XOR fail");
        op=3; a=1; b=3; #1; if (res!==(1<<3)) $fatal(1, "ALU SLL fail");
        $display("alu_tb: PASS"); $finish;
    end
endmodule