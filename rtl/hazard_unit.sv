// Simple hazard unit: detects load-use hazards and requests a single-cycle stall
module hazard_unit(
    input logic id_ex_is_load,
    input logic [4:0] id_ex_rd,
    input logic [4:0] if_id_rs1,
    input logic [4:0] if_id_rs2,
    output logic stall,
    output logic flush_if_id
);
    always_comb begin
        stall = 1'b0;
        flush_if_id = 1'b0;
        if (id_ex_is_load && ( (id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2) ) && (id_ex_rd != 5'd0)) begin
            stall = 1'b1; // insert bubble
            flush_if_id = 1'b0; // we hold IF/ID; ID/EX gets bubble by clearing controls
        end
    end
endmodule