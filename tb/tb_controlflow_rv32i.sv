`timescale 1ns/1ps
`default_nettype none
// Independent architectural program: U-type, signed/unsigned branches,
// JAL/JALR link+redirect, wrong-path suppression and x0 hardwiring.
module tb_controlflow_rv32i;
    reg clk=0, rst_n=0;
    always #5 clk = ~clk;
    pipeline_core uut(.clk(clk),.rst_n(rst_n));

    function automatic [31:0] i_type(input integer imm,input [4:0] rs1,
                                      input [2:0] f3,input [4:0] rd,input [6:0] opcode);
        i_type={imm[11:0],rs1,f3,rd,opcode};
    endfunction
    function automatic [31:0] b_type(input integer imm,input [4:0] rs1,input [4:0] rs2,input [2:0] f3);
        b_type={imm[12],imm[10:5],rs2,rs1,f3,imm[4:1],imm[11],7'h63};
    endfunction
    function automatic [31:0] j_type(input integer imm,input [4:0] rd);
        j_type={imm[20],imm[10:1],imm[11],imm[19:12],rd,7'h6f};
    endfunction
    task automatic check(input [4:0] regid,input [31:0] expected);
        begin
            if(uut.rf.regs[regid] !== expected)
                $fatal(1,"x%0d expected %08x actual %08x",regid,expected,uut.rf.regs[regid]);
        end
    endtask
    initial begin
        $dumpfile("rv32i_controlflow.vcd");
        $dumpvars(0,tb_controlflow_rv32i);
        for (integer n=0;n<1024;n=n+1) uut.imem[n]=32'h00000013;
        uut.imem[0]={20'h12345,5'd1,7'h37}; // lui x1,0x12345
        uut.imem[1]={20'h00001,5'd2,7'h17}; // auipc x2,0x1
        uut.imem[2]=i_type(-1,0,0,3,7'h13); // addi x3,x0,-1
        uut.imem[3]=i_type(2,0,0,4,7'h13); // addi x4,x0,2
        uut.imem[4]=b_type(8,3,4,3'b100); // blt signed, skip wrong path
        uut.imem[5]=i_type(91,0,0,5,7'h13); // forbidden write
        uut.imem[6]=b_type(8,3,4,3'b110); // bltu (false: 0xffffffff < 2? no)
        uut.imem[7]=b_type(8,3,4,3'b110); // bltu again false
        uut.imem[8]=b_type(8,3,4,3'b111); // bgeu true, skips next write
        uut.imem[9]=i_type(92,0,0,6,7'h13); // forbidden write
        uut.imem[10]=j_type(8,7); // jal x7,+8, link = 44
        uut.imem[11]=i_type(93,0,0,8,7'h13); // forbidden write
        uut.imem[12]=i_type(65,0,0,9,7'h13); // x9=65; JALR clears low bit ->64
        uut.imem[13]=i_type(0,9,0,10,7'h67); // jalr x10,0(x9), link=56, target=64
        uut.imem[14]=i_type(94,0,0,11,7'h13); // forbidden write
        uut.imem[15]=i_type(95,0,0,12,7'h13); // forbidden write
        uut.imem[16]=i_type(44,0,0,13,7'h13); // reached at pc=64
        uut.imem[17]=b_type(8,13,13,3'b000); // beq taken
        uut.imem[18]=i_type(96,0,0,14,7'h13); // forbidden write
        uut.imem[19]=i_type(42,0,0,15,7'h13); // pass marker
        uut.imem[20]=j_type(0,0); // idle forever at pc=80
        repeat(3) @(negedge clk);
        rst_n=1;
        repeat(90) @(negedge clk);
        check(0,0);check(1,32'h12345000);check(2,32'h00001004);
        check(3,32'hffffffff);check(4,2);check(5,0);check(6,0);
        check(7,44);check(8,0);check(9,65);check(10,56);
        check(11,0);check(12,0);check(13,44);check(14,0);check(15,42);
        if (uut.pc !== 32'd80) $fatal(1,"expected settled idle loop PC=80 got %0d",uut.pc);
        $display("PASS controlflow: U/J, signed/unsigned branches, redirect flush, JALR alignment, x0");
        $finish;
    end
    initial begin #3000; $fatal(1,"controlflow timeout"); end
endmodule
`default_nettype wire
