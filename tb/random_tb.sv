`timescale 1ns/1ps
module random_tb;
    logic clk=0; logic rst_n=0;
    always #5 clk = ~clk;
    core_top uut(.clk(clk), .rst_n(rst_n));
    import "DPI-C" function int $urandom_range(int max);
    initial begin
        rst_n=0; #20; rst_n=1;
        // Fill imem with random ADD/ADDI sequences
        int i;
        for (i=0;i<64;i++) begin
            // create a random ADDI: opcode 0010011, funct3=000 rd=i%32 rs1=(i+1)%32 imm = i
            int rd = i % 32; int rs1 = (i+1) % 32; int imm = i & 12'hfff;
            uut.imem[i] = (imm << 20) | (rs1 << 15) | (3'b000 << 12) | (rd << 7) | 7'b0010011;
        end
        repeat (200) @(posedge clk);
        $display("random_tb: completed cycles"); $finish;
    end
endmodule