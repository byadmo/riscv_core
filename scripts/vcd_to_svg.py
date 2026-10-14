#!/usr/bin/env python3
"""Render a cycle-sampled diagram from an actual integrated Icarus VCD.

This is not a timing/FPGA diagram. Each column reflects actual signal values
after a rising clock edge settles in the final architectural program.
"""
import html
import re
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: python3 scripts/vcd_to_svg.py input.vcd output.svg")
source, target = map(Path, sys.argv[1:])
symbols, state, scopes, samples = {}, {}, [], []
in_header = True
time = None
for line in source.read_text().splitlines():
    s = line.strip()
    if in_header:
        if s.startswith("$scope "):
            scopes.append(s.split()[2])
        elif s.startswith("$upscope "):
            scopes.pop()
        elif s.startswith("$var "):
            p = s.split()
            full = ".".join(scopes + [p[4]])
            symbols[full] = p[3]
        elif s.startswith("$enddefinitions "):
            in_header = False
        continue
    if s.startswith("#"):
        if time is not None and time % 10000 == 5000:
            samples.append({name: state.get(symbol, "x") for name, symbol in symbols.items()
                            if name in {
                                "tb_integrated_rv32i.rst_n",
                                "tb_integrated_rv32i.dut.pc",
                                "tb_integrated_rv32i.dut.stall",
                                "tb_integrated_rv32i.dut.redirect",
                                "tb_integrated_rv32i.dut.if_id_instr",
                                "tb_integrated_rv32i.dut.rf_we",
                                "tb_integrated_rv32i.dut.rf_wr",
                            }})
        time = int(s[1:])
    elif s.startswith("b"):
        found = re.match(r"b([01xXzZ]+)\s+(\S+)", s)
        if found:
            state[found.group(2)] = found.group(1).lower()
    elif len(s) >= 2 and s[0] in "01xXzZ":
        state[s[1:]] = s[0].lower()

last = [row for row in samples if row.get("tb_integrated_rv32i.rst_n") == "1"][-27:]
if len(last) != 27:
    raise SystemExit("insufficient post-clock samples")
def number(value):
    if not value or any(ch not in "01" for ch in value):
        return None
    return int(value, 2)

if not any(number(row.get("tb_integrated_rv32i.dut.stall")) == 1 for row in last):
    raise SystemExit("expected a real load-use stall in selected excerpt")
if not any(number(row.get("tb_integrated_rv32i.dut.redirect")) == 1 for row in last):
    raise SystemExit("expected a real redirect in selected excerpt")

fields = [
    ("tb_integrated_rv32i.dut.pc", "fetch PC", "addr"),
    ("tb_integrated_rv32i.dut.if_id_instr", "decoded instr.", "hex"),
    ("tb_integrated_rv32i.dut.stall", "load stall", "bit"),
    ("tb_integrated_rv32i.dut.redirect", "redirect", "bit"),
    ("tb_integrated_rv32i.dut.rf_we", "WB enable", "bit"),
    ("tb_integrated_rv32i.dut.rf_wr", "WB dest", "reg"),
]
width, height, cell, left, row_height = 1500, 382, 48, 172, 43
parts = [
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
    '<title id="title">Integrated RV32I program waveform sample</title>',
    '<desc id="desc">Real Icarus Verilog data sampled after rising edges, from the final load-to-branch program. Each column is a clock cycle. Shows PC, decode instruction, stall, redirect, writeback enable and writeback register destination.</desc>',
    f'<rect width="{width}" height="{height}" rx="12" fill="#18332f"/>',
    '<text x="21" y="30" fill="#e6efe7" font-family="monospace" font-weight="700" font-size="13">RV32I PIPELINE / REAL VCD SAMPLE / FINAL DIRECTED PROGRAM</text>',
    '<text x="21" y="51" fill="#b3cebc" font-family="monospace" font-size="10">One settled sample after each rising edge / Icarus Verilog 12</text>',
]
for n in range(len(last)):
    x = left + n*cell + cell/2
    parts.append(f'<text x="{x}" y="82" text-anchor="middle" fill="#bcd1c5" font-family="monospace" font-size="10">{n+1:02d}</text>')
for idx, (name, label, fmt) in enumerate(fields):
    top = 91 + idx*row_height
    parts.append(f'<rect x="14" y="{top}" width="{width-28}" height="{row_height-2}" fill="{"#204239" if idx%2 else "#1c3b36"}"/>')
    parts.append(f'<text x="22" y="{top+26}" fill="#dfeadf" font-family="monospace" font-size="12">{html.escape(label)}</text>')
    for j, row in enumerate(last):
        val = number(row.get(name))
        if val is None:
            rendered = "?"
        elif fmt == "bit":
            rendered = str(val)
        elif fmt == "addr":
            rendered = f"{val:03x}"
        elif fmt == "hex":
            rendered = f"{val:08x}"
        else:
            rendered = f"x{val}"
        x = left + j*cell + cell/2
        color = "#f0ca93" if fmt=="bit" and val==1 and idx in (2,3) else "#dce9df"
        if fmt == "hex":
            # Render only 4 trailing hex digits at this compact scale.
            rendered = rendered[-4:]
        parts.append(f'<text x="{x}" y="{top+26}" text-anchor="middle" fill="{color}" font-family="monospace" font-size="10">{rendered}</text>')
parts.append(f'<text x="21" y="{height-13}" fill="#b9d2c2" font-family="monospace" font-size="10">A sampled logic trace, not physical timing/FPGA measurement. Full register transitions are available in the raw VCD.</text>')
parts.append("</svg>")
target.write_text("\n".join(parts) + "\n")
print(f"Rendered {len(last)} VCD samples, with stall and redirect, to {target}")
