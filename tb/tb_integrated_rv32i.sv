`timescale 1ns/1ps

// Architectural tests for pipeline_core: every case runs a small real RV32I
// program, then checks *all* general-purpose registers and data-memory words.
// No pipeline-stage implementation details are inspected or forced.
module tb_integrated_rv32i;
    localparam logic [31:0] NOP = 32'h00000013;  // addi x0, x0, 0
    localparam integer MEM_WORDS = 1024;

    logic clk = 1'b0;
    logic rst_n = 1'b1;
    always #5 clk = ~clk;

    pipeline_core dut (.clk(clk), .rst_n(rst_n));

    logic [31:0] expected_regs [0:31];
    logic [31:0] expected_mem [0:MEM_WORDS-1];
    reg [8*128-1:0] active_case;
    reg [8*256-1:0] wave_path;
    integer cases_passed = 0;
    integer checks_passed = 0;
    integer load_stalls_seen = 0;
    integer redirects_seen = 0;
    integer i;
    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.stall) load_stalls_seen = load_stalls_seen + 1;
            if (dut.redirect) redirects_seen = redirects_seen + 1;
        end
    end

    // These encoders enforce RV32I bit placement, including negative branch
    // displacements and the split store/branch immediates.
    function automatic [31:0] r_type(
        input [6:0] funct7,
        input [4:0] rs2, rs1,
        input [2:0] funct3,
        input [4:0] rd
    );
        r_type = {funct7, rs2, rs1, funct3, rd, 7'h33};
    endfunction

    function automatic [31:0] i_type(
        input integer imm,
        input [4:0] rs1,
        input [2:0] funct3,
        input [4:0] rd,
        input [6:0] opcode
    );
        reg [11:0] bits;
        begin
            bits = imm[11:0];
            i_type = {bits, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] s_type(
        input integer imm,
        input [4:0] rs2, rs1
    );
        reg [11:0] bits;
        begin
            bits = imm[11:0];
            s_type = {bits[11:5], rs2, rs1, 3'b010, bits[4:0], 7'h23};
        end
    endfunction

    function automatic [31:0] b_type(
        input integer offset,
        input [4:0] rs2, rs1,
        input [2:0] funct3
    );
        reg [12:0] bits;
        begin
            if (offset[0] !== 1'b0) begin
                $fatal(1, "Branch offset must be even: %0d", offset);
            end
            bits = offset[12:0];
            b_type = {bits[12], bits[10:5], rs2, rs1, funct3,
                      bits[4:1], bits[11], 7'h63};
        end
    endfunction

    function automatic [31:0] addi(input [4:0] rd, rs1, input integer imm);
        addi = i_type(imm, rs1, 3'b000, rd, 7'h13);
    endfunction
    function automatic [31:0] alu_i(input [2:0] funct3,
                                     input [4:0] rd, rs1, input integer imm);
        alu_i = i_type(imm, rs1, funct3, rd, 7'h13);
    endfunction
    function automatic [31:0] shifti(input [2:0] funct3,
                                      input [6:0] funct7,
                                      input [4:0] rd, rs1, shamt);
        shifti = {funct7, shamt, rs1, funct3, rd, 7'h13};
    endfunction
    function automatic [31:0] lw(input [4:0] rd, rs1, input integer imm);
        lw = i_type(imm, rs1, 3'b010, rd, 7'h03);
    endfunction
    function automatic [31:0] sw(input [4:0] rs2, rs1, input integer imm);
        sw = s_type(imm, rs2, rs1);
    endfunction
    function automatic [31:0] branch(input [2:0] funct3,
                                      input [4:0] rs1, rs2,
                                      input integer offset);
        branch = b_type(offset, rs2, rs1, funct3);
    endfunction

    // Keep reset asserted until each program and its expected state are ready.
    // Initializing the whole memory prevents X-valued unused instructions from
    // masking a missing branch flush or an incorrect PC redirect.
    task automatic prepare(input [8*128-1:0] label);
        integer n;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            active_case = label;
            for (n = 0; n < MEM_WORDS; n = n + 1) begin
                dut.imem[n] = NOP;
                dut.dmem[n] = 32'd0;
                expected_mem[n] = 32'd0;
            end
            for (n = 0; n < 32; n = n + 1) expected_regs[n] = 32'd0;
        end
    endtask

    task automatic expect_reg(input integer regnum, input [31:0] value);
        begin
            if ((regnum < 0) || (regnum > 31))
                $fatal(1, "Testbench error: register index %0d", regnum);
            expected_regs[regnum] = value;
        end
    endtask

    task automatic expect_mem(input integer wordnum, input [31:0] value);
        begin
            if ((wordnum < 0) || (wordnum >= MEM_WORDS))
                $fatal(1, "Testbench error: memory index %0d", wordnum);
            expected_mem[wordnum] = value;
        end
    endtask

    task automatic preload_mem(input integer wordnum, input [31:0] value);
        begin
            dut.dmem[wordnum] = value;
            expect_mem(wordnum, value);
        end
    endtask

    task automatic check_state;
        integer n;
        begin
            for (n = 0; n < 32; n = n + 1) begin
                if (dut.rf.regs[n] !== expected_regs[n]) begin
                    $display("FAIL %0s: x%0d expected=0x%08h actual=0x%08h pc=0x%08h at %0t",
                             active_case, n, expected_regs[n], dut.rf.regs[n], dut.pc, $time);
                    $fatal(1, "Architectural register mismatch");
                end
                checks_passed = checks_passed + 1;
            end
            for (n = 0; n < MEM_WORDS; n = n + 1) begin
                if (dut.dmem[n] !== expected_mem[n]) begin
                    $display("FAIL %0s: dmem[%0d] expected=0x%08h actual=0x%08h pc=0x%08h at %0t",
                             active_case, n, expected_mem[n], dut.dmem[n], dut.pc, $time);
                    $fatal(1, "Architectural memory mismatch");
                end
                checks_passed = checks_passed + 1;
            end
        end
    endtask

    // The PC passing the program's end guarantees fetch progress, and the
    // drain cycles allow all fetched instructions to retire. A finite cycle
    // budget catches permanent stalls and incorrect backward-branch loops.
    task automatic execute_and_check(input integer instruction_count,
                                      input integer max_cycles);
        integer cycles;
        begin
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
            cycles = 0;
            while ((dut.pc < instruction_count * 4 + 16) && (cycles < max_cycles)) begin
                @(negedge clk);
                cycles = cycles + 1;
                if (^dut.pc === 1'bx)
                    $fatal(1, "FAIL %0s: PC became X at cycle %0d", active_case, cycles);
            end
            if (cycles >= max_cycles)
                $fatal(1, "FAIL %0s: PC failed to progress after %0d cycles (pc=%08h)",
                       active_case, max_cycles, dut.pc);
            repeat (6) @(negedge clk);
            check_state();
            cases_passed = cases_passed + 1;
            $display("PASS %-24s (%0d cycles to PC past end, 32 regs and %0d memory words checked)",
                     active_case, cycles, MEM_WORDS);
        end
    endtask

    task automatic test_arithmetic;
        begin
            prepare("ALU, immediates, forwarding");
            dut.imem[0]  = addi(1, 0, 7);
            dut.imem[1]  = addi(2, 0, -3);
            dut.imem[2]  = r_type(0, 2, 1, 3'b000, 3);       // add  x3,x1,x2
            dut.imem[3]  = r_type(0, 1, 3, 3'b000, 4);       // add  x4,x3,x1
            dut.imem[4]  = r_type(7'h20, 2, 4, 3'b000, 5);   // sub  x5,x4,x2
            dut.imem[5]  = r_type(0, 1, 5, 3'b111, 6);       // and
            dut.imem[6]  = r_type(0, 1, 2, 3'b110, 7);       // or
            dut.imem[7]  = r_type(0, 1, 7, 3'b100, 8);       // xor
            dut.imem[8]  = r_type(0, 3, 1, 3'b001, 9);       // sll
            dut.imem[9]  = r_type(0, 3, 9, 3'b101, 10);      // srl
            dut.imem[10] = r_type(7'h20, 3, 2, 3'b101, 11);  // sra
            dut.imem[11] = r_type(0, 1, 2, 3'b010, 12);      // slt
            dut.imem[12] = r_type(0, 1, 2, 3'b011, 13);      // sltu
            dut.imem[13] = addi(14, 1, 0);                   // zero imm must still use immediate
            dut.imem[14] = addi(15, 0, -2048);               // sign extension
            dut.imem[15] = alu_i(3'b010, 16, 2, 0);          // slti
            dut.imem[16] = alu_i(3'b011, 17, 2, -1);         // sltiu
            dut.imem[17] = alu_i(3'b111, 18, 7, 255);        // andi
            dut.imem[18] = alu_i(3'b110, 19, 1, -2048);      // ori
            dut.imem[19] = alu_i(3'b100, 20, 1, -1);         // xori
            dut.imem[20] = shifti(3'b001, 0, 21, 1, 3);      // slli
            dut.imem[21] = shifti(3'b101, 0, 22, 21, 3);     // srli
            dut.imem[22] = shifti(3'b101, 7'h20, 23, 2, 1);  // srai
            dut.imem[23] = addi(0, 0, 123);                  // x0 must never change
            dut.imem[24] = addi(24, 0, 0);                   // zero immediate
            dut.imem[25] = r_type(0, 0, 21, 3'b000, 25);     // x0 as source
            dut.imem[26] = alu_i(3'b111, 26, 1, 0);
            dut.imem[27] = addi(27, 0, 1);
            dut.imem[28] = addi(27, 27, 2);
            dut.imem[29] = addi(28, 27, 4);                  // newest producer must win

            expect_reg(1, 7);
            expect_reg(2, 32'hfffffffd);
            expect_reg(3, 4);
            expect_reg(4, 11);
            expect_reg(5, 14);
            expect_reg(6, 6);
            expect_reg(7, 32'hffffffff);
            expect_reg(8, 32'hfffffff8);
            expect_reg(9, 112);
            expect_reg(10, 7);
            expect_reg(11, 32'hffffffff);
            expect_reg(12, 1);
            expect_reg(13, 0);
            expect_reg(14, 7);
            expect_reg(15, 32'hfffff800);
            expect_reg(16, 1);
            expect_reg(17, 1);
            expect_reg(18, 255);
            expect_reg(19, 32'hfffff807);
            expect_reg(20, 32'hfffffff8);
            expect_reg(21, 56);
            expect_reg(22, 7);
            expect_reg(23, 32'hfffffffe);
            expect_reg(24, 0);
            expect_reg(25, 56);
            expect_reg(26, 0);
            expect_reg(27, 3);
            expect_reg(28, 7);
            execute_and_check(30, 120);
        end
    endtask

    task automatic test_memory;
        begin
            prepare("loads, stores, RAW stalls");
            dut.imem[0]  = addi(1, 0, 100);
            dut.imem[1]  = sw(1, 0, 0);    // store consumes result of preceding ADDI
            dut.imem[2]  = lw(2, 0, 0);
            dut.imem[3]  = addi(3, 2, 1);  // immediate load-use stall
            dut.imem[4]  = r_type(0, 2, 3, 3'b000, 4);
            dut.imem[5]  = sw(4, 0, 4);
            dut.imem[6]  = lw(5, 0, 4);
            dut.imem[7]  = r_type(0, 3, 5, 3'b000, 6);
            dut.imem[8]  = addi(7, 0, 16);
            dut.imem[9]  = sw(6, 7, -4);   // sign-extended store address
            dut.imem[10] = lw(8, 7, -4);
            dut.imem[11] = r_type(0, 1, 8, 3'b000, 9);
            dut.imem[12] = lw(10, 0, 0);
            dut.imem[13] = sw(10, 0, 8);  // load followed immediately by store
            dut.imem[14] = lw(11, 0, 8);
            dut.imem[15] = lw(12, 0, 0);  // consecutive loads from different addresses
            dut.imem[16] = lw(13, 0, 4);
            dut.imem[17] = r_type(0, 13, 12, 3'b000, 14);
            dut.imem[18] = addi(15, 0, 9);
            dut.imem[19] = addi(16, 0, 1);
            dut.imem[20] = addi(17, 0, 2);
            dut.imem[21] = addi(18, 15, 4); // WB/ID same-edge dependency, not EX/MEM

            expect_reg(1, 100);
            expect_reg(2, 100);
            expect_reg(3, 101);
            expect_reg(4, 201);
            expect_reg(5, 201);
            expect_reg(6, 302);
            expect_reg(7, 16);
            expect_reg(8, 302);
            expect_reg(9, 402);
            expect_reg(10, 100);
            expect_reg(11, 100);
            expect_reg(12, 100);
            expect_reg(13, 201);
            expect_reg(14, 301);
            expect_reg(15, 9);
            expect_reg(16, 1);
            expect_reg(17, 2);
            expect_reg(18, 13);
            expect_mem(0, 100);
            expect_mem(1, 201);
            expect_mem(2, 100);
            expect_mem(3, 302);
            execute_and_check(22, 120);
        end
    endtask

    task automatic test_branches;
        begin
            prepare("branches, redirects, flush");
            preload_mem(0, 32'hcafe55aa);
            preload_mem(1, 32'h55aafeca);
            dut.imem[0]  = addi(1, 0, 3);
            dut.imem[1]  = addi(2, 0, 3);
            dut.imem[2]  = branch(3'b000, 1, 2, 16);   // beq taken to 6
            dut.imem[3]  = addi(10, 0, 99);            // wrong path
            dut.imem[4]  = sw(1, 0, 0);                // wrong path store
            dut.imem[5]  = addi(11, 0, 88);            // wrong path
            dut.imem[6]  = addi(3, 0, 8);
            dut.imem[7]  = branch(3'b001, 1, 2, 8);    // bne not taken
            dut.imem[8]  = addi(4, 0, 4);
            dut.imem[9]  = branch(3'b001, 1, 4, 12);   // bne taken to 12
            dut.imem[10] = addi(12, 0, 77);
            dut.imem[11] = sw(1, 0, 4);
            dut.imem[12] = addi(5, 0, -1);
            dut.imem[13] = branch(3'b100, 5, 4, 8);    // blt signed taken
            dut.imem[14] = addi(13, 0, 55);
            dut.imem[15] = branch(3'b101, 4, 5, 8);    // bge signed taken
            dut.imem[16] = addi(14, 0, 44);
            dut.imem[17] = branch(3'b110, 5, 4, 8);    // bltu unsigned not taken
            dut.imem[18] = addi(6, 0, 6);
            dut.imem[19] = branch(3'b111, 5, 4, 8);    // bgeu unsigned taken
            dut.imem[20] = addi(15, 0, 33);
            dut.imem[21] = branch(3'b101, 5, 4, 8);    // bge signed not taken
            dut.imem[22] = addi(7, 0, 7);
            dut.imem[23] = branch(3'b110, 4, 5, 8);    // bltu unsigned taken
            dut.imem[24] = addi(16, 0, 22);
            dut.imem[25] = branch(3'b000, 4, 5, 8);    // beq not taken
            dut.imem[26] = addi(8, 0, 8);
            dut.imem[27] = branch(3'b000, 8, 8, 8);    // beq taken
            dut.imem[28] = addi(17, 0, 11);
            dut.imem[29] = addi(9, 0, 9);
            dut.imem[30] = addi(18, 0, 0);
            dut.imem[31] = addi(18, 18, 1);            // count up through backward branch
            dut.imem[32] = alu_i(3'b010, 19, 18, 3);   // slti x19,x18,3
            dut.imem[33] = branch(3'b001, 19, 0, -8);  // bne backward to 31
            dut.imem[34] = addi(20, 18, 10);

            expect_reg(1, 3);
            expect_reg(2, 3);
            expect_reg(3, 8);
            expect_reg(4, 4);
            expect_reg(5, 32'hffffffff);
            expect_reg(6, 6);
            expect_reg(7, 7);
            expect_reg(8, 8);
            expect_reg(9, 9);
            expect_reg(18, 3);
            expect_reg(19, 0);
            expect_reg(20, 13);
            execute_and_check(35, 170);
        end
    endtask

    task automatic test_load_to_branch;
        begin
            prepare("load to branch / flush");
            preload_mem(1, 32'hdecafbad);
            dut.imem[0]  = addi(1, 0, 8);
            dut.imem[1]  = sw(1, 0, 0);
            dut.imem[2]  = lw(2, 0, 0);
            dut.imem[3]  = branch(3'b000, 2, 1, 12);   // compare loaded value; taken to 6
            dut.imem[4]  = addi(10, 0, 70);
            dut.imem[5]  = sw(2, 0, 4);                // must not corrupt sentinel
            dut.imem[6]  = addi(3, 2, 1);
            dut.imem[7]  = sw(3, 0, 8);
            dut.imem[8]  = lw(4, 0, 8);
            dut.imem[9]  = branch(3'b001, 4, 3, 8);    // bne not taken
            dut.imem[10] = addi(5, 4, 1);
            dut.imem[11] = branch(3'b000, 3, 3, 8);    // taken to 13
            dut.imem[12] = addi(6, 0, 1);
            dut.imem[13] = addi(7, 5, 1);

            expect_reg(1, 8);
            expect_reg(2, 8);
            expect_reg(3, 9);
            expect_reg(4, 9);
            expect_reg(5, 10);
            expect_reg(7, 11);
            expect_mem(0, 8);
            expect_mem(2, 9);
            execute_and_check(14, 120);
        end
    endtask

    initial begin
        if ($value$plusargs("vcd=%s", wave_path)) begin
            $display("Writing integrated RV32I waveform to %0s", wave_path);
            $dumpfile(wave_path);
            $dumpvars(0, tb_integrated_rv32i);
        end
        test_arithmetic();
        test_memory();
        test_branches();
        test_load_to_branch();
        if (load_stalls_seen < 3 || redirects_seen < 8)
            $fatal(1, "Control-event coverage low: %0d stalls and %0d redirects",
                   load_stalls_seen, redirects_seen);
        $display("PASS ALL: %0d integrated RV32I programs, %0d architectural state checks",
                 cases_passed, checks_passed);
        $display("Observed: %0d load-use stalls, %0d taken branch redirects",
                 load_stalls_seen, redirects_seen);
        $finish;
    end
endmodule
