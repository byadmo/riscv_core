// 32x32 Register File with x0 hardwired to zero
module regfile(
    input logic clk,
    input logic we,                 // write enable
    input logic [4:0] ra1,
    input logic [4:0] ra2,
    input logic [4:0] wa,
    input logic [31:0] wd,
    output logic [31:0] rd1,
    output logic [31:0] rd2
);
    logic [31:0] regs [31:0];

    assign rd1 = (ra1 == 5'd0) ? 32'd0 : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'd0 : regs[ra2];

    always_ff @(posedge clk) begin
        if (we && (wa != 5'd0))
            regs[wa] <= wd;
        regs[0] <= 32'd0;
    end

endmodule
