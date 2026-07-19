`timescale 1ns/1ps

module tb_alu;
    logic [31:0] a;
    logic [31:0] b;
    logic [3:0]  alu_control;
    logic [31:0] result;
    logic        zero;

    int errors;

    alu dut (
        .a           (a),
        .b           (b),
        .alu_control (alu_control),
        .result      (result),
        .zero        (zero)
    );

    task automatic check_alu(
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [3:0]  test_control,
        input logic [31:0] expected_result,
        input string       test_name
    );
        begin
            a = test_a;
            b = test_b;
            alu_control = test_control;
            #1;

            if (result !== expected_result) begin
                $error("%s failed: a=%h b=%h ctrl=%b expected=%h got=%h",
                       test_name, test_a, test_b, test_control, expected_result, result);
                errors++;
            end

            if (zero !== (expected_result == 32'd0)) begin
                $error("%s zero flag failed: expected=%b got=%b",
                       test_name, (expected_result == 32'd0), zero);
                errors++;
            end
        end
    endtask

    initial begin
        $dumpfile("alu_sim.vcd");
        $dumpvars(0, tb_alu);

        errors = 0;

        check_alu(32'd15,       32'd10,       4'b0000, 32'd25,       "ADD");
        check_alu(32'd15,       32'd10,       4'b1000, 32'd5,        "SUB");
        check_alu(32'hf0f0_00ff, 32'h0ff0_ff00, 4'b0100, 32'hff00_ffff, "XOR");
        check_alu(32'h0000_0003, 32'd4,        4'b0001, 32'h0000_0030, "SLL");
        check_alu(32'hffff_0000, 32'h00ff_0000, 4'b0111, 32'h00ff_0000, "AND");
        check_alu(32'hffff_0000, 32'h00ff_00ff, 4'b0110, 32'hffff_00ff, "OR");
        check_alu(32'h8000_0000, 32'd4,        4'b0101, 32'h0800_0000, "SRL");
        check_alu(32'h8000_0000, 32'd4,        4'b1101, 32'hf800_0000, "SRA");
        check_alu(32'hffff_ffff, 32'd1,        4'b0010, 32'd1,        "SLT signed");
        check_alu(32'hffff_ffff, 32'd1,        4'b0011, 32'd0,        "SLTU unsigned");
        check_alu(32'd42,       32'd42,       4'b1000, 32'd0,        "ZERO flag");

        if (errors == 0) begin
            $display("tb_alu PASS");
        end else begin
            $fatal(1, "tb_alu FAIL: %0d error(s)", errors);
        end

        $finish;
    end
endmodule
