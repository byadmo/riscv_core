// Branch target adder: computes PC + immediate
module branch_adder(
    input logic [31:0] pc,
    input logic [31:0] imm,
    output logic [31:0] target
);
    assign target = pc + imm;
endmodule
