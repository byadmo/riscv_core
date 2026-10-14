#!/usr/bin/env python3
"""Deterministic RV32I-subset program generator and independent sequential oracle.

Instruction bit encoders and reference execution are separate routines. The
oracle decodes actual emitted hex, interprets byte-addressed little-endian RAM,
and writes the expected *architectural* register and word-memory image.
"""
from pathlib import Path
import random
import sys

MASK = 0xffffffff
NOP = 0x00000013

def encode_i(imm, rs1, f3, rd, opcode=0x13):
    return ((imm & 0xfff) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opcode
def encode_r(f7, rs2, rs1, f3, rd):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33
def encode_s(imm, rs2, rs1, f3):
    return ((imm & 0xfe0) << 20) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 31) << 7) | 0x23
def encode_b(offset, rs1, rs2, f3):
    return (((offset >> 12) & 1) << 31) | (((offset >> 5) & 63) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (((offset >> 1) & 15) << 8) | (((offset >> 11) & 1) << 7) | 0x63
def encode_j(offset, rd):
    return (((offset >> 20)&1)<<31) | (((offset >> 1)&0x3ff)<<21) | (((offset>>11)&1)<<20) | (((offset>>12)&255)<<12) | (rd<<7) | 0x6f
def sx(x, n):
    return (x ^ (1 << (n - 1))) - (1 << (n - 1))
def u32(x):
    return x & MASK

def simulate(program, initial_words):
    regs = [0]*32
    data = bytearray().join(int(w).to_bytes(4, 'little') for w in initial_words)
    pc = 0
    steps = 0
    while pc < len(program)*4:
        if steps >= 4000 or pc & 3:
            raise ValueError(f"nonterminating or misaligned PC: {pc:08x}")
        ins = program[pc//4]
        op,rd,f3,rs1,rs2,f7 = ins&127,(ins>>7)&31,(ins>>12)&7,(ins>>15)&31,(ins>>20)&31,(ins>>25)&127
        a,b = regs[rs1],regs[rs2]
        nxt = pc+4
        wr = None
        if op == 0x13:
            imm=sx(ins>>20,12)
            if f3==0: wr=a+imm
            elif f3==7: wr=a&imm
            elif f3==6: wr=a|imm
            elif f3==4: wr=a^imm
            elif f3==2: wr=int(sx(a,32)<imm)
            elif f3==3: wr=int(a<u32(imm))
            elif f3==1: wr=a<<(imm&31)
            elif f3==5: wr=sx(a,32)>>(imm&31) if imm&0x400 else a>>(imm&31)
            else: raise ValueError(f"unsupported I opcode {ins:08x}")
        elif op == 0x33:
            if f3==0: wr=a-b if f7==0x20 else a+b
            elif f3==7: wr=a&b
            elif f3==6: wr=a|b
            elif f3==4: wr=a^b
            elif f3==2: wr=int(sx(a,32)<sx(b,32))
            elif f3==3: wr=int(a<b)
            elif f3==1: wr=a<<(b&31)
            elif f3==5: wr=sx(a,32)>>(b&31) if f7==0x20 else a>>(b&31)
            else: raise ValueError(f"unsupported R opcode {ins:08x}")
        elif op in (0x03,0x23):
            if op==0x03: off=sx(ins>>20,12)
            else: off=sx((((ins>>25)&0x7f)<<5)|((ins>>7)&31),12)
            addr=u32(a+off)
            size={0:1,1:2,2:4,4:1,5:2}[f3]
            if addr+size>len(data) or addr%size:
                raise ValueError(f"generated invalid access {addr}")
            if op==0x03:
                raw=int.from_bytes(data[addr:addr+size],'little')
                wr=sx(raw,size*8) if f3 in (0,1) else raw
            else:
                data[addr:addr+size]=(b & ((1<<(size*8))-1)).to_bytes(size,'little')
        elif op==0x63:
            off=sx((((ins>>31)&1)<<12)|(((ins>>7)&1)<<11)|(((ins>>25)&63)<<5)|(((ins>>8)&15)<<1),13)
            yes={0:a==b,1:a!=b,4:sx(a,32)<sx(b,32),5:sx(a,32)>=sx(b,32),6:a<b,7:a>=b}[f3]
            if yes: nxt=pc+off
        elif op==0x6f:
            off=sx((((ins>>31)&1)<<20)|(((ins>>12)&255)<<12)|(((ins>>20)&1)<<11)|(((ins>>21)&1023)<<1),21)
            wr=pc+4
            nxt=pc+off
        else:
            raise ValueError(f"unimplemented generator opcode {ins:08x}")
        if wr is not None and rd: regs[rd]=u32(wr)
        pc=nxt
        steps+=1
    return regs,[int.from_bytes(data[i:i+4],'little') for i in range(0,len(data),4)],steps

def main():
    if len(sys.argv)!=3:
        raise SystemExit("usage: generate_memory_stress.py OUTPUT_DIR SEED")
    out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
    seed=int(sys.argv[2]); rng=random.Random(seed)
    words=[rng.getrandbits(32) for _ in range(1024)]
    program=[]
    for n in range(1,17):
        program.append(encode_i(rng.randrange(-128,128),0,0,n))
    actions=['add','sub','xor','and','or','sll','srl','sra','slt','sltu',
             'addi','slti','xori','andi','ori','lb','lbu','lh','lhu','lw',
             'sb','sh','sw','branch','jump']
    for n in range(170):
        action=rng.choice(actions)
        rs1=rng.randrange(0,17)
        rs2=rng.randrange(0,17)
        rd=rng.randrange(1,17)
        if action in {'add','sub','xor','and','or','sll','srl','sra','slt','sltu'}:
            f3={'add':0,'sub':0,'xor':4,'and':7,'or':6,'sll':1,'srl':5,'sra':5,'slt':2,'sltu':3}[action]
            program.append(encode_r(0x20 if action in {'sub','sra'} else 0,rs2,rs1,f3,rd))
        elif action in {'addi','slti','xori','andi','ori'}:
            f3={'addi':0,'slti':2,'xori':4,'andi':7,'ori':6}[action]
            program.append(encode_i(rng.randrange(-128,128),rs1,f3,rd))
        elif action in {'lb','lbu','lh','lhu','lw','sb','sh','sw'}:
            f3={'lb':0,'lbu':4,'lh':1,'lhu':5,'lw':2,'sb':0,'sh':1,'sw':2}[action]
            size=2 if 'h' in action else 4 if 'w' in action else 1
            addr=rng.randrange(0,128//size)*size
            if action.startswith('l'):
                program.append(encode_i(addr,0,f3,rd,0x03))
            else:
                program.append(encode_s(addr,rs2,0,f3))
        elif action=='branch':
            # Forward-only branch, followed by a wrong-path store sentinel or ALU.
            f3=rng.choice([0,1,4,5,6,7])
            program.append(encode_b(8,rs1,rs2,f3))
            program.append(encode_s(192,rs2,0,2))
        else:
            program.append(encode_j(8,rd))
            program.append(encode_s(196,rs2,0,2))
    regs,expected,steps=simulate(program,words)
    for filename,values in [('program.hex',program + [NOP]*(1024-len(program))),('initial_mem.hex',words),
                             ('expected_regs.hex',regs),('expected_mem.hex',expected)]:
        (out/filename).write_text(''.join(f"{v:08x}\n" for v in values))
    (out/'manifest.txt').write_text(f"seed={seed} instructions={len(program)} oracle_steps={steps}\n")
    print(f"SEED {seed}: {len(program)} instructions, {steps} sequential reference steps")
if __name__ == '__main__':
    main()
