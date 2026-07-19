`timescale 1ns/1ps

module tb_control_unit;
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic       reg_write;
    logic       alu_src_b;
    logic       mem_read;
    logic       mem_write;
    logic       mem_to_reg;
    logic       branch;
    logic [3:0] alu_control;

    int errors;

    control_unit dut (
        .opcode      (opcode),
        .funct3      (funct3),
        .funct7      (funct7),
        .reg_write   (reg_write),
        .alu_src_b   (alu_src_b),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .mem_to_reg  (mem_to_reg),
        .branch      (branch),
        .alu_control (alu_control)
    );

    task automatic check_decode(
        input logic [6:0] test_opcode,
        input logic [2:0] test_funct3,
        input logic [6:0] test_funct7,
        input logic       exp_reg_write,
        input logic       exp_alu_src_b,
        input logic       exp_mem_read,
        input logic       exp_mem_write,
        input logic       exp_mem_to_reg,
        input logic       exp_branch,
        input logic [3:0] exp_alu_control,
        input string      test_name
    );
        begin
            opcode = test_opcode;
            funct3 = test_funct3;
            funct7 = test_funct7;
            #1;

            if ({reg_write, alu_src_b, mem_read, mem_write, mem_to_reg, branch, alu_control} !==
                {exp_reg_write, exp_alu_src_b, exp_mem_read, exp_mem_write, exp_mem_to_reg, exp_branch, exp_alu_control}) begin
                $error("%s failed: got rw=%b asb=%b mr=%b mw=%b m2r=%b br=%b alu=%b",
                       test_name, reg_write, alu_src_b, mem_read, mem_write, mem_to_reg, branch, alu_control);
                $error("%s expected: rw=%b asb=%b mr=%b mw=%b m2r=%b br=%b alu=%b",
                       test_name, exp_reg_write, exp_alu_src_b, exp_mem_read, exp_mem_write, exp_mem_to_reg, exp_branch, exp_alu_control);
                errors++;
            end
        end
    endtask

    initial begin
        $dumpfile("control_unit_sim.vcd");
        $dumpvars(0, tb_control_unit);

        errors = 0;

        check_decode(7'h33, 3'b000, 7'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 4'b0000, "R ADD");
        check_decode(7'h33, 3'b000, 7'h20, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 4'b1000, "R SUB");
        check_decode(7'h33, 3'b100, 7'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 4'b0100, "R XOR");
        check_decode(7'h33, 3'b001, 7'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 4'b0001, "R SLL");
        check_decode(7'h13, 3'b000, 7'h00, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 4'b0000, "I ADDI");
        check_decode(7'h03, 3'b010, 7'h00, 1'b1, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 4'b0000, "LW");
        check_decode(7'h23, 3'b010, 7'h00, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 4'b0000, "SW");
        check_decode(7'h63, 3'b000, 7'h00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 4'b1000, "BEQ");
        check_decode(7'h7f, 3'b111, 7'h7f, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 4'b0000, "Illegal/default");

        if (errors == 0) begin
            $display("tb_control_unit PASS");
        end else begin
            $fatal(1, "tb_control_unit FAIL: %0d error(s)", errors);
        end

        $finish;
    end
endmodule
