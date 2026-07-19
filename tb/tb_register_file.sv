`timescale 1ns/1ps

module tb_register_file;
    logic        clk;
    logic        rst_n;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [4:0]  rd_addr;
    logic [31:0] rd_data;
    logic        reg_write;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    int errors;

    register_file dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (rs1_addr),
        .rs2_addr  (rs2_addr),
        .rd_addr   (rd_addr),
        .rd_data   (rd_data),
        .reg_write (reg_write),
        .rs1_data  (rs1_data),
        .rs2_data  (rs2_data)
    );

    always #5 clk = ~clk;

    task automatic write_reg(
        input logic [4:0]  addr,
        input logic [31:0] data
    );
        begin
            rd_addr = addr;
            rd_data = data;
            reg_write = 1'b1;
            @(posedge clk);
            #1;
            reg_write = 1'b0;
        end
    endtask

    task automatic check_read(
        input logic [4:0]  addr1,
        input logic [31:0] expected1,
        input logic [4:0]  addr2,
        input logic [31:0] expected2,
        input string       test_name
    );
        begin
            rs1_addr = addr1;
            rs2_addr = addr2;
            #1;

            if (rs1_data !== expected1) begin
                $error("%s rs1 failed: addr=%0d expected=%h got=%h",
                       test_name, addr1, expected1, rs1_data);
                errors++;
            end

            if (rs2_data !== expected2) begin
                $error("%s rs2 failed: addr=%0d expected=%h got=%h",
                       test_name, addr2, expected2, rs2_data);
                errors++;
            end
        end
    endtask

    initial begin
        $dumpfile("register_file_sim.vcd");
        $dumpvars(0, tb_register_file);

        clk = 1'b0;
        rst_n = 1'b0;
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        rd_addr = 5'd0;
        rd_data = 32'd0;
        reg_write = 1'b0;
        errors = 0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;

        check_read(5'd0, 32'd0, 5'd1, 32'd0, "reset values");

        write_reg(5'd1, 32'h1234_5678);
        write_reg(5'd2, 32'hcafe_beef);
        check_read(5'd1, 32'h1234_5678, 5'd2, 32'hcafe_beef, "basic write/read");

        write_reg(5'd0, 32'hffff_ffff);
        check_read(5'd0, 32'd0, 5'd1, 32'h1234_5678, "x0 hardwired zero");

        rd_addr = 5'd3;
        rd_data = 32'hdead_beef;
        reg_write = 1'b0;
        @(posedge clk);
        #1;
        check_read(5'd3, 32'd0, 5'd2, 32'hcafe_beef, "write disabled");

        rst_n = 1'b0;
        @(posedge clk);
        #1;
        rst_n = 1'b1;
        check_read(5'd1, 32'd0, 5'd2, 32'd0, "async reset clears registers");

        if (errors == 0) begin
            $display("tb_register_file PASS");
        end else begin
            $fatal(1, "tb_register_file FAIL: %0d error(s)", errors);
        end

        $finish;
    end
endmodule
