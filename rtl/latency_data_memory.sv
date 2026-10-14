`timescale 1ns/1ps
`default_nettype none
// Single-outstanding, ordered synchronous request/response word memory.
// req_valid/req_ready handshake accepts one request on a rising clock edge.
// rsp_valid is asserted during the final response cycle; its value is consumed
// at the rising edge. Stores update byte lanes at that edge, exactly once.
// LATENCY=1 responds during the first request cycle (edge completes operation).
// Additional bounded deterministic delay may vary per accepted request.
// Address alignment/range validation is done by the core, not this RAM model.
module latency_data_memory #(
    parameter integer LATENCY = 1,
    parameter integer MAX_EXTRA = 0,
    parameter integer WORDS = 1024
) (
    input wire clk, rst_n,
    input wire req_valid,
    output wire req_ready,
    input wire req_write,
    input wire [31:0] req_addr,
    input wire [31:0] req_wdata,
    input wire [3:0] req_wstrb,
    output wire rsp_valid,
    output wire [31:0] rsp_rdata
);
    reg [31:0] words [0:WORDS-1];
    reg busy;
    localparam integer CW = LATENCY+MAX_EXTRA > 1 ? $clog2(LATENCY+MAX_EXTRA+1) : 1;
    reg [CW-1:0] remaining;
    reg saved_write;
    reg [31:0] saved_addr, saved_wdata;
    reg [3:0] saved_wstrb;
    reg [7:0] request_number;
    wire [31:0] variation = MAX_EXTRA==0 ? 0 :
             ((req_addr[4:2] ^ request_number[2:0]) % (MAX_EXTRA+1));
    wire [31:0] request_latency = LATENCY + variation;
    wire instant_req = request_latency == 1;
    assign req_ready = !busy;
    assign rsp_valid = (req_valid && req_ready && instant_req) || (busy && remaining == 1);
    wire instant_response = !busy;
    wire response_write = instant_response ? req_write : saved_write;
    wire [31:0] response_addr = instant_response ? req_addr : saved_addr;
    wire [31:0] response_wdata = instant_response ? req_wdata : saved_wdata;
    wire [3:0] response_strobe = instant_response ? req_wstrb : saved_wstrb;
    assign rsp_rdata = words[response_addr[11:2]];

    initial begin
        if (LATENCY < 1 || MAX_EXTRA < 0 || WORDS < 1 || WORDS > 1024)
            $fatal(1, "LATENCY must be >=1 and 1<=WORDS<=1024");
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0;
            remaining <= 0;
            saved_write <= 0;
            saved_addr <= 0;
            saved_wdata <= 0;
            saved_wstrb <= 0;
            request_number <= 0;
        end else begin
            if (!busy && req_valid) begin
                request_number <= request_number + 1'b1;
                if (!instant_req) begin
                    busy <= 1;
                    remaining <= request_latency - 1;
                    saved_write <= req_write;
                    saved_addr <= req_addr;
                    saved_wdata <= req_wdata;
                    saved_wstrb <= req_wstrb;
                end
            end else if (busy) begin
                if (remaining == 1) begin
                    busy <= 0;
                    remaining <= 0;
                end else
                    remaining <= remaining - 1'b1;
            end
        end
    end
    // Byte enables allow SB/SH/SW through one aligned 32-bit memory port.
    // Memory contents deliberately survive reset, like typical synchronous RAM.
    always @(posedge clk) begin
        if (rst_n && rsp_valid && response_write) begin
            for (integer lane=0; lane<4; lane=lane+1)
                if (response_strobe[lane])
                    words[response_addr[11:2]][lane*8 +: 8] <= response_wdata[lane*8 +: 8];
        end
    end
endmodule
`default_nettype wire
