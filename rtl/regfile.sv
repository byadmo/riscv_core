// 32x32 Register File
module regfile(
    input logic clk,
    input logic rst_n,
    input logic we,
    input logic [4:0] rs1, rs2, rd,
    input logic [31:0] wd,
    output logic [31:0] rd1, rd2
);
    logic [31:0] regs [31:0];
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0;i<32;i++) regs[i] <= 32'b0;
        end else begin
            if (we && rd != 5'd0) regs[rd] <= wd;
        end
    end
    assign rd1 = (rs1==5'd0) ? 32'b0 : regs[rs1];
    assign rd2 = (rs2==5'd0) ? 32'b0 : regs[rs2];
endmodule