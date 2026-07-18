`timescale 1ns/1ps
module tb_cpu();
    logic clk = 0;
    logic reset = 1;

    // instantiate CPU
    cpu u_cpu(.clk(clk), .reset(reset));

    // clock
    always #5 clk = ~clk;

    initial begin
        $display("Starting CPU TB");
        // release reset after a few cycles
        repeat (2) @(posedge clk);
        reset = 0;

        // run for 12 cycles
        for (int i = 0; i < 12; i++) begin
            @(posedge clk);
            $display("Cycle %0d PC=%08x instr=%08x x1=%08x x2=%08x x3=%08x", i, u_cpu.pc, u_cpu.instr, u_cpu.u_regfile.regs[1], u_cpu.u_regfile.regs[2], u_cpu.u_regfile.regs[3]);
        end

        $display("TB finished");
        $finish;
    end
endmodule
