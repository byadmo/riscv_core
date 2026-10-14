# Explicit instruction/data memory ports — verification contract

## Two independent channels

`pipeline_core #(.EXTERNAL_PORTS(1))` exposes **separate instruction and data transactions**. The previous educational mode `EXTERNAL_PORTS=0` remains for backward-compatible regressions. External mode does not read the core's internal `imem` or `mem_model.words` arrays; integration environments supply both memories. The model is a minimal in-order teaching bus, **not AXI, AHB, an SRAM macro, a cache, or a measured hardware interface**.

| Channel | Request | Response | Identity |
| --- | --- | --- | --- |
| Instruction | `i_req_valid/i_req_ready`, `i_req_addr`, `i_req_tag[7:0]` | `i_rsp_valid/i_rsp_ready`, `i_rsp_addr`, `i_rsp_tag`, `i_rsp_data` | Both address and 8-bit tag must echo the outstanding request |
| Data | `d_req_valid/d_req_ready`, `d_req_write`, `d_req_addr`, `d_req_tag[7:0]`, `d_req_wdata`, `d_req_wstrb[3:0]` | `d_rsp_valid/d_rsp_ready`, `d_rsp_tag`, `d_rsp_rdata` | 8-bit tag must echo the outstanding request |

Transfer occurs only on rising edges with **valid AND ready**. Each producer must keep its transaction metadata and response payload stable while valid is asserted and ready is low. There is **at most one outstanding request per channel**, but instruction fetch and data accesses can overlap. Completion is exactly one response handshake; data stores commit at most once. Response data for stores is ignored. All requests are ordered (no interleaving or out-of-order completions within a channel). The 8-bit tags increment after accepted requests; they wrap only after 256, which is safe here because no channel has multiple outstanding requests.

**Timing restriction:** the supported external adapters may present the response *no earlier than the clock edge following request acceptance*. Same-edge accept-and-respond (zero-cycle external response) is **not supported** by this external mode. The legacy internal `DATA_LATENCY=1` model still passes its original same-edge completion regression in `EXTERNAL_PORTS=0`.

## Fetch buffering, redirects and reset

The fetch unit issues requests for the next PC, holds the accepted address and tag while awaiting response, and has a **one-instruction response buffer**. Fetch PC advances only when that buffered instruction enters IF/ID; a fetch wait or blocked downstream stage cannot discard an instruction. If a branch or jump redirects while an instruction transaction is outstanding, the fetch epoch advances and the old response is *drained and discarded*. Neither its data nor its PC is allowed into ID/EX; the new target is requested after the obsolete response is accepted. A fetch response can be backpressured while older data memory is stalled.

An instruction request that has asserted `i_req_valid` but has not been accepted (`!i_req_ready`) **cannot be silently canceled**. It keeps its PC/tag stable even if a younger branch resolves; after eventual acceptance its stale response is drained and dropped. This imposes a throughput cost but preserves request/response protocol correctness without requiring cancellation messages.

The data side retains EX/MEM address, store payload, destination and control until the matching response handshake. While an older data access is pending, younger pipeline stages hold, but preceding MEM/WB can retire once; held ID/EX operands are refreshed when a writeback occurs. A branch/jump redirect cannot overtake an older memory operation. A configurable `DATA_RESPONSE_DELAY` deliberately deasserts `d_rsp_ready` for bounded cycles after request acceptance to verify that the external model holds a valid response until it can be consumed.

**Reset requirement:** both external adapters must be reset with the core to cancel every outstanding request/response. The core's tags reset to zero; without synchronized memory cancellation, a stale pre-reset response could be confused with a post-reset transaction. This test environment does not support reset-isolated or persistent out-of-order memory systems.

## Errors and unsupported features

- Instruction requests must be word-aligned within the supported modeled fetch address space. A physical instruction access-fault handler, privileged traps, CSRs and ISA exception recovery are not implemented.
- The data interface preserves little-endian `LB/LBU/LH/LHU/LW/SB/SH/SW` semantics. With default `FAULT_HALT=0`, invalid data alignment/range causes a simulator `$fatal`. Opt-in `FAULT_HALT=1` provides **precise, sticky fault-stop outputs** before an invalid request is issued; this is not a recoverable RISC-V trap. See [fault diagnostics](fault_halt.md).
- Memory mapping, MMIO, external bus arbitration, multi-beat accesses, atomics, fences, cache coherence and two or more outstanding requests per channel are unsupported.
- A valid response must eventually be presented by the memory. No deadlock-free guarantee can be made when the external environment withholds response forever.
- There is no synthesis/FPGA, physical SRAM timing, area, power, maximum clock or full RV32I compliance claim.

The actual tests, measured transaction counts and waveform evidence are described in the expanded coverage documentation. Do not interpret protocol tests as formal proof of all possible interleavings.
