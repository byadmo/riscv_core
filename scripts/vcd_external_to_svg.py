#!/usr/bin/env python3
"""Render actual I/D bus handshakes from VCD without inventing a timing trace."""
from pathlib import Path
from html import escape
import re
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: vcd_external_to_svg.py input.vcd output.svg")
inp, out = map(Path, sys.argv[1:])
symbols, state, samples = {}, {}, []
scope = []
header = True
time = None
names = ["rst_n","i_req_valid","i_req_ready","i_req_addr","i_req_tag",
         "i_rsp_valid","i_rsp_ready","i_rsp_tag","d_req_valid","d_req_ready",
         "d_rsp_valid","d_rsp_ready","d_req_tag","d_rsp_tag"]
for raw in inp.read_text().splitlines():
    s=raw.strip()
    if header:
        if s.startswith("$scope "):
            scope.append(s.split()[2])
        elif s.startswith("$upscope "):
            scope.pop()
        elif s.startswith("$var ") and scope==["tb_external_bus_rv32i"]:
            parts=s.split()
            if parts[4] in names:
                symbols[parts[4]]=parts[3]
        elif s.startswith("$enddefinitions "):
            header=False
        continue
    if s.startswith("#"):
        if time is not None and time%10000==5000:
            samples.append({n:state.get(k,"x") for n,k in symbols.items()})
        time=int(s[1:])
    elif s.startswith("b"):
        m=re.match(r"b([01xXzZ]+)\s+(\S+)",s)
        if m: state[m.group(2)]=m.group(1).lower()
    elif len(s)>1 and s[0] in "01xXzZ":
        state[s[1:]]=s[0].lower()
def val(row,name):
    raw=row.get(name,"x")
    return int(raw,2) if raw and set(raw)<=set("01") else None
first=next((i for i,r in enumerate(samples) if
            val(r,"rst_n")==1 and val(r,"d_rsp_valid")==1 and
            val(r,"d_rsp_ready")==0),None)
if first is None:
    raise SystemExit("VCD has no proven data response backpressure event")
start=max(0,first-13)
rows=samples[start:start+36]
if len(rows)<20 or not any(val(r,"i_req_valid")==1 for r in rows):
    raise SystemExit("Selected VCD sample missing independently active fetch")
tracks=[
    ("i_req_valid","I request","bit"),
    ("i_req_ready","I ready","bit"),
    ("i_req_tag","I req tag","tag"),
    ("i_rsp_valid","I response","bit"),
    ("i_rsp_ready","I rsp ready","bit"),
    ("d_req_valid","D request","bit"),
    ("d_req_ready","D ready","bit"),
    ("d_req_tag","D req tag","tag"),
    ("d_rsp_valid","D response","bit"),
    ("d_rsp_ready","D rsp ready","bit"),
]
left=156; cw=37; rh=33; width=left+cw*len(rows)+16; height=110+rh*len(tracks)+31
parts=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
       '<title id="title">Actual independent instruction and data memory request response trace</title>',
       '<desc id="desc">Cycle-sampled VCD showing separate instruction and data request/ready and response/ready with tags; includes an observed held data response.</desc>',
       f'<rect width="{width}" height="{height}" rx="12" fill="#16352e"/>',
       '<text x="18" y="30" fill="#e6ede6" font-family="monospace" font-size="14" font-weight="700">INDEPENDENT I / D BUS — CAPTURED SIMULATION</text>',
       '<text x="18" y="52" fill="#c5d5c8" font-family="monospace" font-size="10">Ready/valid handshakes, 8-bit tags and held data response</text>',
       '<text x="18" y="74" fill="#b4ccb9" font-family="monospace" font-size="10">One settled sample per rising edge, not synthesized hardware timing</text>']
for j in range(len(rows)):
    x=left+j*cw+cw//2
    parts.append(f'<text x="{x}" y="99" text-anchor="middle" fill="#b1c6b5" font-family="monospace" font-size="9">{start+j+1:03d}</text>')
for i,(key,label,kind) in enumerate(tracks):
    y=105+i*rh
    parts.append(f'<rect x="12" y="{y}" width="{width-24}" height="{rh-1}" fill="{"#20483a" if i%2 else "#1d4035"}"/>')
    parts.append(f'<text x="20" y="{y+22}" fill="#e0efe3" font-family="monospace" font-size="11">{escape(label)}</text>')
    for j,row in enumerate(rows):
        v=val(row,key)
        cell="?" if v is None else str(v)
        is_hold=(key=="d_rsp_valid" and v==1 and val(row,"d_rsp_ready")==0)
        color="#f1ca9a" if is_hold or key.endswith("valid") and v==1 else "#e3efe4"
        parts.append(f'<text x="{left+j*cw+cw//2}" y="{y+22}" text-anchor="middle" fill="{color}" font-family="monospace" font-size="10">{cell}</text>')
parts.append(f'<text x="18" y="{height-13}" fill="#bed5c4" font-family="monospace" font-size="10">Orange highlights are live requests, responses and a held D response. View the linked raw VCD for full signal timing.</text>')
parts.append("</svg>")
out.write_text("\n".join(parts)+"\n")
print(f"PASS: {len(rows)} real clock samples with I activity and D response backpressure")
