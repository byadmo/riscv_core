`timescale 1ns/1ps
`default_nettype none
// Deterministic independent instruction/data buses for external pipeline tests.
// Single outstanding request on each channel. Responses remain valid, with
// stable payload, until accepted by the core. Memory survives reset; all
// outstanding transactions are canceled by reset.
module dual_port_bus_adapter #(
    parameter integer I_LATENCY=2,
    parameter integer D_LATENCY=3,
    parameter integer I_JITTER=2,
    parameter integer D_JITTER=3,
    parameter integer READY_MODE=1
) (
    input wire clk, rst_n,
    input wire i_req_valid,
    output wire i_req_ready,
    input wire [31:0] i_req_addr,
    input wire [7:0] i_req_tag,
    output reg i_rsp_valid,
    input wire i_rsp_ready,
    output reg [31:0] i_rsp_addr,
    output reg [7:0] i_rsp_tag,
    output reg [31:0] i_rsp_data,
    input wire d_req_valid,
    output wire d_req_ready,
    input wire d_req_write,
    input wire [31:0] d_req_addr,
    input wire [7:0] d_req_tag,
    input wire [31:0] d_req_wdata,
    input wire [3:0] d_req_wstrb,
    output reg d_rsp_valid,
    input wire d_rsp_ready,
    output reg [7:0] d_rsp_tag,
    output reg [31:0] d_rsp_rdata
);
    reg [31:0] imem [0:1023];
    reg [31:0] dmem [0:1023];
    integer cycle_count=0;
    reg i_busy=0, d_busy=0;
    integer i_remaining=0,d_remaining=0;
    reg d_saved_write=0;
    reg [31:0] d_saved_addr=0, d_saved_wdata=0;
    reg [3:0] d_saved_wstrb=0;

    integer i_requests=0, i_responses=0;
    integer d_requests=0, d_responses=0, d_stores=0;
    integer i_tag_wraps=0;
    reg [7:0] last_i_tag=0;
    reg [31:0] last_i_addr=0;
    reg have_i_tag=0;
    reg [7:0] last_d_tag=0;
    reg have_d_tag=0;
    integer i_wait_cycles=0,d_wait_cycles=0;
    integer i_rsp_held_cycles=0,d_rsp_held_cycles=0;

    // Different throttle sequences for I and D, to expose cross-channel bugs.
    assign i_req_ready = rst_n && !i_busy && !i_rsp_valid &&
                         (READY_MODE==0 || (cycle_count%4 != 1));
    assign d_req_ready = rst_n && !d_busy && !d_rsp_valid &&
                         (READY_MODE==0 || (cycle_count%5 != 0 && cycle_count%5 != 1));
    wire i_fire = i_req_valid && i_req_ready;
    wire d_fire = d_req_valid && d_req_ready;
    wire i_done = i_rsp_valid && i_rsp_ready;
    wire d_done = d_rsp_valid && d_rsp_ready;

    initial begin
        if (I_LATENCY < 1 || D_LATENCY < 1 || I_JITTER < 0 || D_JITTER < 0)
            $fatal(1,"Bad dual-port adapter latency parameters");
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count<=0;
            i_busy<=0; d_busy<=0;
            i_remaining<=0; d_remaining<=0;
            i_rsp_valid<=0; d_rsp_valid<=0;
            i_rsp_addr<=0; i_rsp_tag<=0; i_rsp_data<=0;
            d_rsp_rdata<=0; d_rsp_tag<=0;
            d_saved_write<=0; d_saved_addr<=0;
            d_saved_wdata<=0; d_saved_wstrb<=0;
            i_requests<=0; i_responses<=0;
            d_requests<=0; d_responses<=0; d_stores<=0;
            i_tag_wraps<=0;last_i_tag<=0;last_i_addr<=0;have_i_tag<=0;
            last_d_tag<=0;have_d_tag<=0;
            i_wait_cycles<=0;d_wait_cycles<=0;
            i_rsp_held_cycles<=0;d_rsp_held_cycles<=0;
        end else begin
            cycle_count<=cycle_count+1;
            if (i_req_valid && !i_req_ready) i_wait_cycles<=i_wait_cycles+1;
            if (d_req_valid && !d_req_ready) d_wait_cycles<=d_wait_cycles+1;
            if (i_rsp_valid && !i_rsp_ready) i_rsp_held_cycles<=i_rsp_held_cycles+1;
            if (d_rsp_valid && !d_rsp_ready) d_rsp_held_cycles<=d_rsp_held_cycles+1;

            if (i_fire) begin
                if (i_req_addr[1:0]!=0 || |i_req_addr[31:12])
                    $fatal(1,"Invalid instruction bus fetch address %08h",i_req_addr);
                if (i_busy || i_rsp_valid)
                    $fatal(1,"Overlapping accepted instruction requests");
                i_requests<=i_requests+1;
                if (have_i_tag && i_req_tag < last_i_tag)
                    i_tag_wraps<=i_tag_wraps+1;
                if (have_i_tag && i_req_tag==last_i_tag && i_req_addr==last_i_addr)
                    $fatal(1,"Duplicate accepted instruction request: PC=%08h tag=%0d",
                           i_req_addr,i_req_tag);
                last_i_tag<=i_req_tag;
                last_i_addr<=i_req_addr;
                have_i_tag<=1;
                i_busy<=1;
                i_remaining<=I_LATENCY+((i_req_addr[5:2]^i_req_tag[3:0])%(I_JITTER+1));
                i_rsp_addr<=i_req_addr;
                i_rsp_tag<=i_req_tag;
                i_rsp_data<=imem[i_req_addr[11:2]];
            end else if (i_busy && !i_rsp_valid) begin
                if (i_remaining<=1) begin
                    i_remaining<=0;
                    i_rsp_valid<=1;
                end else i_remaining<=i_remaining-1;
            end
            if (i_done) begin
                if (!i_busy) $fatal(1,"Instruction response without request");
                i_responses<=i_responses+1;
                i_rsp_valid<=0;
                i_busy<=0;
            end

            if (d_fire) begin
                if (|d_req_addr[31:12])
                    $fatal(1,"Data bus address out of range: %08h",d_req_addr);
                if (d_busy || d_rsp_valid)
                    $fatal(1,"Overlapping accepted data requests");
                if (d_req_write && d_req_wstrb==0)
                    $fatal(1,"Store with no enabled byte lanes at %08h",d_req_addr);
                if (have_d_tag && d_req_tag !== (last_d_tag+8'd1))
                    $fatal(1,"Duplicated or skipped data transaction tag: last=%0d now=%0d",
                           last_d_tag,d_req_tag);
                last_d_tag<=d_req_tag;
                have_d_tag<=1;
                d_requests<=d_requests+1;
                d_busy<=1;
                d_remaining<=D_LATENCY+((d_req_addr[5:2]^d_requests)%(D_JITTER+1));
                d_saved_addr<=d_req_addr;
                d_saved_write<=d_req_write;
                d_saved_wdata<=d_req_wdata;
                d_saved_wstrb<=d_req_wstrb;
                d_rsp_tag<=d_req_tag;
                d_rsp_rdata<=dmem[d_req_addr[11:2]];
            end else if (d_busy && !d_rsp_valid) begin
                if (d_remaining<=1) begin
                    d_remaining<=0;
                    d_rsp_valid<=1;
                end else d_remaining<=d_remaining-1;
            end
            if (d_done) begin
                if (!d_busy) $fatal(1,"Data response without request");
                d_responses<=d_responses+1;
                d_rsp_valid<=0;
                d_busy<=0;
                if (d_saved_write) begin
                    d_stores<=d_stores+1;
                    for (integer lane=0;lane<4;lane=lane+1)
                        if (d_saved_wstrb[lane])
                            dmem[d_saved_addr[11:2]][8*lane+:8] <= d_saved_wdata[8*lane+:8];
                end
            end
        end
    end
endmodule
`default_nettype wire
