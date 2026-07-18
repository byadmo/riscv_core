`timescale 1ns/1ps

module tb_alu;
    // Inputs
    logic [31:0] a;
    logic [31:0] b;
    logic [3:0]  alu_control;

    // Outputs
    logic [31:0] result;
    logic        zero;

    // Instantiate the ALU
    alu uut (
        .a(a),
        .b(b),
        .alu_control(alu_control),
        .result(result),
        .zero(zero)
    );

    initial begin
        // Setup waveform dumping
        $dumpfile("alu_sim.vcd");
        $dumpvars(0, tb_alu);

        // Test 1: Addition (15 + 10 = 25)
        a = 32'd15; b = 32'd10; alu_control = 4'b0000; #10;

        // Test 2: Subtraction (15 - 10 = 5)
        alu_control = 4'b1000; #10;

        // Test 3: Zero Flag Trigger (15 - 15 = 0)
        b = 32'd15; alu_control = 4'b1000; #10;

        // Test 4: Bitwise AND (Checking hex logic)
        a = 32'hFFFF0000; b = 32'h00FF0000; alu_control = 4'b0111; #10;

        $finish;
    end
endmodule