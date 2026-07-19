// Pipeline register structs (simple flops)
module if_id(
    input logic clk, rst_n,
    input logic [31:0] pc_in, instr_in,
    output logic [31:0] pc_out, instr_out
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out <= 32'b0; instr_out <= 32'b0;
        end else begin
            pc_out <= pc_in; instr_out <= instr_in;
        end
    end
endmodule

module id_ex(
    input logic clk,rst_n,
    input logic [31:0] pc_in, imm_in, rs1_in, rs2_in,
    input logic [4:0] rd_in,
    output logic [31:0] pc_out, imm_out, rs1_out, rs2_out,
    output logic [4:0] rd_out
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out<=0; imm_out<=0; rs1_out<=0; rs2_out<=0; rd_out<=0;
        end else begin
            pc_out<=pc_in; imm_out<=imm_in; rs1_out<=rs1_in; rs2_out<=rs2_in; rd_out<=rd_in;
        end
    end
endmodule

module ex_mem(/* similar – omitted for brevity in this baseline */);
endmodule

module mem_wb(/* similar – omitted for brevity in this baseline */);
endmodule