#!/usr/bin/env python3
"""Make a readable sampled memory-handshake figure from an actual Icarus VCD.

Only declared VCD values are used. No physical waveforms or metrics invented.
"""
import html
import re
import sys
from pathlib import Path

if len(sys.argv)!=3:
    raise SystemExit("usage: python3 scripts/vcd_memory_to_svg.py INPUT.vcd OUTPUT.svg")
src,dst=map(Path,sys.argv[1:])
symbols={}
state={}
rows=[]
header=True
time=None
for line in src.read_text().splitlines():
    line=line.strip()
    if header:
        if line.startswith("$var "):
            parts=line.split()
            symbols[parts[4]]=parts[3]
        if line.startswith("$enddefinitions "):header=False
        continue
    if line.startswith("#"):
        if time is not None and time%10000==5000:
            rows.append({key:state.get(symbol,"x") for key,symbol in symbols.items()})
        time=int(line[1:])
    elif line.startswith("b"):
        m=re.match(r"b([01xXzZ]+)\s+(\S+)",line)
        if m:state[m.group(2)]=m.group(1).lower()
    elif len(line)>1 and line[0] in "01xXzZ":
        state[line[1:]]=line[0].lower()
def val(row,key):
    raw=row.get(key,"x")
    return int(raw,2) if raw and set(raw)<=set("01") else None
first=next((i for i,row in enumerate(rows) if val(row,"mem_req_valid")==1 and
            val(row,"rst_n")==1),None)
if first is None:raise SystemExit("no memory request found in capture")
sample=rows[max(0,first-4):max(0,first-4)+27]
if len(sample)<20 or not any(val(x,"mem_rsp_valid")==1 for x in sample):
    raise SystemExit("selected excerpt lacks a completed response")
fields=[("pc","PC","addr"),("mem_req_valid","request","bit"),
        ("mem_req_ready","ready","bit"),("busy","busy","bit"),
        ("mem_rsp_valid","response","bit"),("mem_hold","hold","bit"),
        ("ex_mem_alu_res","address","addr")]
cell=46;left=146; width=left+cell*len(sample)+21
rh=38;height=105+rh*len(fields)+36
parts=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
 '<title id="title">Latency-aware RISC-V memory transaction, captured from Icarus Verilog VCD</title>',
 '<desc id="desc">Actual clock-sampled PC and memory request, ready, busy, response, pipeline-hold and address values. The memory response is delayed and the pipeline holds until it finishes.</desc>',
 f'<rect width="{width}" height="{height}" fill="#16322e" rx="13"/>',
 '<text x="18" y="29" fill="#e6f1e6" font-family="monospace" font-size="13" font-weight="700">MEMORY HANDSHAKE / REAL INTEGRATED VCD</text>',
 '<text x="18" y="50" fill="#aaccbd" font-family="monospace" font-size="10">BASE LATENCY 4 + UP TO 3 DETERMINISTIC EXTRA CYCLES</text>',
 '<text x="18" y="72" fill="#b4d2be" font-family="monospace" font-size="10">One settled sample per rising edge (simulation, not hardware timing)</text>']
for j in range(len(sample)):
    x=left+j*cell+cell/2
    parts.append(f'<text x="{x}" y="100" text-anchor="middle" fill="#bcd8c8" font-family="monospace" font-size="10">{j+1:02d}</text>')
for i,(name,label,kind) in enumerate(fields):
    top=108+rh*i
    parts.append(f'<rect x="12" y="{top}" width="{width-24}" height="{rh-1}" fill="{"#1d3d37" if i%2 else "#20443b"}"/>')
    parts.append(f'<text x="20" y="{top+24}" fill="#e2eee4" font-family="monospace" font-size="11">{html.escape(label)}</text>')
    for j,row in enumerate(sample):
        value=val(row,name)
        txt="?" if value is None else f"{value:04x}" if kind=="addr" else str(value)
        color="#efca94" if kind=="bit" and value==1 and name in ("mem_req_valid","mem_rsp_valid") else "#deebe2"
        parts.append(f'<text x="{left+j*cell+cell/2}" y="{top+24}" text-anchor="middle" fill="{color}" font-family="monospace" font-size="11">{txt}</text>')
parts.append(f'<text x="18" y="{height-14}" fill="#bcd4c6" font-family="monospace" font-size="10">Raw waveform contains original signal transitions and timestamps; table selects real sampled values.</text>')
parts.append("</svg>")
dst.write_text("\n".join(parts)+"\n")
print(f"PASS real memory trace: {len(sample)} sampled cycles, req/rsp observed; wrote {dst}")
