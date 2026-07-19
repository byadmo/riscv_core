// register_file.sv - RV32I Standard Register File
// 32 registers, 32-bits wide. Register x0 is hardwired to 0.

module register_file (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [4:0]  rs1_addr,   // Read address 1
    input  logic [4:0]  rs2_addr,   // Read address 2
    input  logic [4:0]  rd_addr,    // Write address
    input  logic [31:0] rd_data,    // Write data
    input  logic        reg_write,  // Write enable
    output logic [31:0] rs1_data,   // Read data 1
    output logic [31:0] rs2_data    // Read data 2
);

    logic [31:0] rf [31:0];

    // Asynchronous read logic
    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : rf[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : rf[rs2_addr];

    // Synchronous write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers to 0 (optional for some FPGA targets but good for sim)
            for (int i = 0; i < 32; i++) begin
                rf[i] <= 32'h0;
            end
        end else if (reg_write && rd_addr != 5'd0) begin
            rf[rd_addr] <= rd_data;
        end
    end

endmodule
