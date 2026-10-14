# Data-memory interface and backpressure contract

## Scope

The educational `pipeline_core` contains a `latency_data_memory` instance named `mem_model`. This is a **cycle-controlled behavioural memory adapter**, not an external SRAM controller or a production bus. The core's instruction memory is still zero-wait-state and separate.

The memory interface exposes:

| Signal | Meaning |
| --- | --- |
| `req_valid`, `req_ready` | Request is accepted on a rising edge when both are 1 |
| `req_write` | 1 for stores; 0 for loads |
| `req_addr` | Byte address, restricted to 0..4095 in the supported model |
| `req_wdata` | Store data already shifted into little-endian byte lanes |
| `req_wstrb[3:0]` | Write enable for each of four bytes of a 32-bit word |
| `rsp_valid`, `rsp_rdata` | Response becomes valid for exactly one completion edge; data is meaningful for loads only when valid |

There is no `rsp_ready`: the pipeline **always accepts a valid response**. At most one request is outstanding. While busy, `req_ready=0`; the core holds the request address/payload stable, and the memory does **not** accept a duplicate. Stores modify RAM only on the response-completion edge, once per accepted store.

## Timing and pipeline handling

`DATA_LATENCY=N` means the transaction completes at the Nth rising edge following the first cycle in which its request is presented, with `N>=1`. `DATA_MAX_EXTRA=M` adds a bounded deterministic 0..M cycles based on request address and ordinal (not probabilistic network jitter). A base latency of 1 may complete at the request-acceptance edge. The model uses combinational RAM-word selection with synchronous request acceptance and edge-committed response/store: **it is not a physical synchronous SRAM macro**.

When EX/MEM contains a load or store, the pipeline holds PC, IF/ID and ID/EX throughout request issuance, wait, **and** the response-acceptance edge. An earlier MEM/WB instruction drains once during this hold. When the response arrives, its data and register destination move together into MEM/WB; EX/MEM becomes an invalid bubble. On the following cycle, execution resumes, forwarding the completed load through MEM/WB. This intentionally sacrifices throughput to keep hazards auditable.

A WB-to-held-ID/EX bypass refreshes source values when an older register result retires during the hold; otherwise a stalled younger instruction could resume with stale operands after the original MEM/WB forwarding source has disappeared. Taken branches/jumps in the younger EX stage cannot redirect until older memory completion; on release they flush younger stages before an incorrect store can enter memory. Ordinary one-cycle load-use interlocks remain in place.

## Byte lanes

The word array is little endian: address `4n` corresponds to bits 7:0 of `words[n]`, `4n+1` to 15:8, `4n+2` to 23:16, and `4n+3` to 31:24. SB writes one selected lane; SH writes a two-lane pair at byte offset 0 or 2; SW writes all four lanes at offset 0. Loads select the same lanes and apply correct sign extension (LB/LH) or zero extension (LBU/LHU).

Supported alignment: byte accesses at any byte offset, halfword accesses at offsets 0 or 2, and word accesses at offset 0. Invalid alignment or address outside `0..4095` triggers an explicit simulator `$fatal` at request acceptance. **No RV32I architectural exception, fault code, retry, or out-of-range bus response is implemented**; synthesis with invalid addresses is outside the supported contract.

## Evidence and reproducibility

Run `bash scripts/run_regression.sh /tmp/rv32i-regression`. Under `memory/`, the logs show request/response/store cardinalities for six directed programs over six fixed/variable latency combinations, twelve interpreter-generated program runs, and four expected invalid-address rejections. The VCD `memory_handshake.vcd` captures actual PC, request, ready, busy, hold and response signals, and `scripts/vcd_memory_to_svg.py` renders a sample of those captured values.

The independent Python interpreter decodes generated instruction words and updates a byte-addressed architectural memory image. RTL simulation is then compared against the predicted final state of all 32 integer registers and 1,024 RAM words. The oracle is independent of RTL state and pipeline timing but is **not** an official ISA compliance reference.
