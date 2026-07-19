`timescale 1ns/1ps
module pipeline_directed_tb;
    logic clk=0; logic rst_n=0;
    always #5 clk = ~clk;
    core_top uut(.clk(clk), .rst_n(rst_n));
    initial begin
        rst_n=0; #20; rst_n=1;
        // Program: LW x1,0(x0); ADDI x2,x1,1; ADD x3,x2,x1; SW x3,4(x0)
        // Encode minimal opcodes for simulation memory directly
        // LW x1,0(x0) -> 0x00002083 (imm=0, rs1=0, funct3=010, rd=1, opcode=0000011)
        uut.imem[0] = 32'h00002083; // lw x1,0(x0)
        // ADDI x2,x1,1 -> opcode 0010011 funct3 000 rd=2 rs1=1 imm=1 => 0x00110113
        uut.imem[1] = 32'h00110113;
        // ADD x3,x2,x1 -> R-type 0x002081B3 (funct7=0000000 rs2=2 rs1=1 funct3=000 rd=3 opcode=0110011)
        uut.imem[2] = 32'h002081B3;
        // SW x3,4(x0) -> S-type imm=4 rs1=0 rs2=3 funct3=010 opcode=0100011 => 0x00302023
        uut.imem[3] = 32'h00302023;
        // Place data in dmem[0]=100
        uut.dmem[0] = 32'd100;
        repeat (20) @(posedge clk);
        // Check results: x1 should be 100, x2=101, x3=201, dmem[1]=201 (store at addr 4 -> index 1)
        if (uut.rf.regs[1] !== 32'd100) $display("FAIL x1 %0d", uut.rf.regs[1]);
        if (uut.rf.regs[2] !== 32'd101) $display("FAIL x2 %0d", uut.rf.regs[2]);
        if (uut.rf.regs[3] !== 32'd201) $display("FAIL x3 %0d", uut.rf.regs[3]);
        if (uut.dmem[1] !== 32'd201) $display("FAIL mem %0d", uut.dmem[1]);
        $display("pipeline_directed_tb: DONE"); $finish;
    end
endmodule