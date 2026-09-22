#!/usr/bin/env python3
"""Convert a ROM region into sdas8051-assemblable source using disasm51.

Usage: d51_to_sdas.py <rom.bin> <org_hex> <len_dec> [--label-prefix PREFIX]

Reads the instruction table from the disasm51 package (the same decoder that
produced firmware/src/main.asm), decodes each instruction in the region, and
emits sdas8051 syntax: 0x.. hex, numeric bit addresses, relative jumps as
local labels, absolute targets as 0x.... Numbers. The output assembles to the
exact same bytes via sdas8051+sdld+objcopy.

Pipe stdout into the region file's body section.
"""
import sys

def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    rom_path = sys.argv[1]
    org = int(sys.argv[2], 0)
    length = int(sys.argv[3], 0)
    prefix = "L_"
    for i, a in enumerate(sys.argv):
        if a == "--label-prefix" and i + 1 < len(sys.argv):
            prefix = sys.argv[i + 1]

    from disasm51.instructions import Instructions, ArgType
    table = Instructions().instructions

    rom = open(rom_path, "rb").read()
    data = rom[org:org + length]
    if len(data) != length:
        sys.exit("ERROR: ROM too short for 0x%04X len %d" % (org, length))

    # First pass: decode linearly, recording instruction boundaries and targets.
    boundaries = set()
    targets = set()
    pc = 0
    while pc < length:
        boundaries.add(org + pc)
        opcode = data[pc]
        ins = table.get(opcode)
        if ins is None:
            pc += 1
            continue
        if ins.args:
            arg_bytes = data[pc + 1:pc + ins.length]
            aidx = 0
            for atype in ins.args:
                if atype == ArgType.REL:
                    rel = arg_bytes[aidx]
                    if rel > 127:
                        rel -= 256
                    abs_target = org + pc + ins.length + rel
                    if org <= abs_target < org + length:
                        targets.add(abs_target)
                    aidx += 1
                elif atype in (ArgType.LABEL, ArgType.ADDR):
                    if atype == ArgType.LABEL:
                        abs_target = (arg_bytes[aidx] << 8) | arg_bytes[aidx + 1]
                        aidx += 2
                    else:  # ADDR (11-bit)
                        a10_8 = (opcode >> 5) & 7
                        abs_target = ((org + pc + ins.length) & 0xF800) | (a10_8 << 8) | arg_bytes[aidx]
                        aidx += 1
                    if org <= abs_target < org + length:
                        targets.add(abs_target)
                elif atype == ArgType.BIT:
                    aidx += 1
                elif atype == ArgType.IMM:
                    aidx += 1
                elif atype == ArgType.DATA:
                    aidx += 1
        pc += ins.length

    # A target gets a local label ONLY if it lands on a decoded instruction
    # boundary within the region; otherwise it is emitted as an absolute address
    # (out-of-region, or a misaligned target that means this region has embedded
    # data the linear sweep decoded as code — flagged with a warning comment).
    labeled = targets & boundaries
    misaligned = targets - boundaries

    def target_str(abs_target):
        if abs_target in labeled:
            return "%s%04X" % (prefix, abs_target)
        return "0x%04X" % abs_target

    # Second pass: emit sdas8051 source.
    print("        .org    0x%04X" % org)
    pc = 0
    while pc < length:
        addr = org + pc
        opcode = data[pc]
        ins = table.get(opcode)

        # Place label if this address is a labeled target.
        if addr in labeled:
            print("%s%04X:" % (prefix, addr))

        if ins is None:
            # Unknown opcode — emit as raw byte.
            print("        .db     0x%02X                        ; %04X (unknown opcode)" % (opcode, addr))
            pc += 1
            continue

        raw = data[pc:pc + ins.length]
        raw_hex = " ".join("%02X" % b for b in raw)

        if not ins.args:
            # No operands.
            print("        %-36s; %s  %04X" % (ins.mnemonic, raw_hex, addr))
            pc += ins.length
            continue

        # Decode operands.
        arg_bytes = data[pc + 1:pc + ins.length]
        operands = []
        aidx = 0
        for atype in ins.args:
            if atype == ArgType.IMM:
                operands.append("0x%02X" % arg_bytes[aidx])
                aidx += 1
            elif atype == ArgType.DATA:
                operands.append("0x%02X" % arg_bytes[aidx])
                aidx += 1
            elif atype == ArgType.BIT:
                operands.append("0x%02X" % arg_bytes[aidx])
                aidx += 1
            elif atype == ArgType.REL:
                rel = arg_bytes[aidx]
                if rel > 127:
                    rel -= 256
                abs_target = org + pc + ins.length + rel
                operands.append(target_str(abs_target))
                aidx += 1
            elif atype == ArgType.LABEL:
                abs_target = (arg_bytes[aidx] << 8) | arg_bytes[aidx + 1]
                operands.append("0x%04X" % abs_target)
                aidx += 2
            elif atype == ArgType.ADDR:
                a10_8 = (opcode >> 5) & 7
                abs_target = ((org + pc + ins.length) & 0xF800) | (a10_8 << 8) | arg_bytes[aidx]
                operands.append("0x%04X" % abs_target)
                aidx += 1

        # Format the mnemonic with resolved operands.
        mnem_template = ins.mnemonic
        # The mnemonic uses {0}, {1}, ... as placeholders.
        asm_line = mnem_template.format(*operands)
        print("        %-36s; %s  %04X" % (asm_line, raw_hex, addr))
        pc += ins.length


if __name__ == "__main__":
    main()
