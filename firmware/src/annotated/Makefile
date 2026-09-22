# ROB3 firmware — assemble the annotated source into a 1:1 ROM image
#==============================================================================
# This directory holds the ANNOTATED, ASSEMBLING source for the ROB3 8031
# firmware. The top unit rob3.asm includes the symbolic equates (inc/*.inc) and
# every code region (vectors/ext0/timer0/ext1/rs232/init/main/program/teachbox/
# tables) in address order. The goal is a build whose 8 KB output is
# BYTE-IDENTICAL to the original EPROM image:
#
#     firmware/bin/M2764A@DIP28.BIN
#
# Toolchain (SDCC suite + binutils):
#     sdas8051   assembler  (.asm -> .rel)
#     sdld       linker     (.rel -> .ihx)
#     objcopy    ihex->bin  (binutils)
#
#   make            assemble + link + pad to 8 KB (_build/rob3.bin)
#   make verify     build, then cmp _build/rob3.bin against the ROM (the 1:1 test)
#   make regions    dump each region's ROM slice under _build/rom/ (conversion aid)
#   make status     report which region files still contain narrative gaps
#   make clean
#
# NOTE (reorg status): the region files were split out of the earlier
# *.annotated.asm listings and carry the full annotations, but they are NOT yet
# byte-complete (some bodies still have narrative gaps / pseudo-targets). Until
# each region is converted to exact opcodes, `make` / `make verify` are expected
# to FAIL — that is the follow-up work this layout enables, gated by `verify`.
#==============================================================================

# ---- Layout ------------------------------------------------------------------
FWDIR      := ../../..
ROM        := $(FWDIR)/firmware/bin/M2764A@DIP28.BIN
BUILD      := _build
ROMSIZE    := 8192

TOP        := rob3.asm
# Region sources (documented; the assembler pulls them via rob3.asm .include).
REGIONS    := vectors.asm ext0_estop.asm timer0_tick.asm ext1_servo.asm \
              rs232.asm init.asm main.asm program.asm teachbox.asm tables.asm
INCS       := $(wildcard inc/*.inc)

# Per-region ROM address / length (for the `regions` conversion aid).
# name:org:len(bytes)
REGION_MAP := vectors:0x0000:0x38 \
              ext0_estop:0x0040:0x32 \
              timer0_tick:0x0080:0x1E \
              ext1_servo:0x00C0:0x143 \
              rs232:0x0203:0x385 \
              init:0x0600:0x14D \
              main:0x074D:0xA5 \
              program:0x0800:0x242 \
              teachbox:0x0C00:0x3C5 \
              tables:0x0FC5:0x19

# ---- Tools -------------------------------------------------------------------
AS         := sdas8051
LD         := sdld
OBJCOPY    := objcopy

.PHONY: all build verify verify-regions regions status clean help

all: build ## Assemble + link + pad to an 8 KB image

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		sort | awk 'BEGIN{FS=":.*?## "}{printf "  %-10s %s\n", $$1, $$2}'

$(BUILD):
	@mkdir -p $(BUILD)

# ---- Assemble the whole annotated unit ---------------------------------------
build: $(BUILD)/rob3.bin ## Assemble rob3.asm into _build/rob3.bin (padded to 8 KB)

$(BUILD)/rob3.bin: $(TOP) $(REGIONS) $(INCS) | $(BUILD)
	$(AS) -l -s -o $(BUILD)/rob3.rel $(TOP)
	$(LD) -i -m $(BUILD)/rob3.ihx $(BUILD)/rob3.rel
	$(OBJCOPY) -I ihex -O binary --gap-fill=0xFF --pad-to=$(ROMSIZE) \
		$(BUILD)/rob3.ihx $(BUILD)/rob3.bin
	@echo "built $(BUILD)/rob3.bin ($$(stat -c%s $(BUILD)/rob3.bin) bytes)"

# ---- The 1:1 test ------------------------------------------------------------
verify: build ## GOLDEN: assembled image must equal the ROM, byte for byte
	@if cmp -s $(BUILD)/rob3.bin "$(ROM)"; then \
		echo "PASS  1:1 — assembled image == ROM ($(ROMSIZE) bytes)"; \
		sha256sum $(BUILD)/rob3.bin "$(ROM)"; \
	else \
		echo "FAIL  assembled image differs from the ROM:"; \
		cmp $(BUILD)/rob3.bin "$(ROM)" || true; \
		echo "(first differing byte above; see _build/rob3.rst for the listing)"; \
		exit 1; \
	fi

# ---- Per-region verify (assemble one region standalone, cmp its ROM slice) ---
# Each region file must assemble on its own (it .org's at its true address and
# needs the equates). We build it with the inc/ files prepended via a wrapper.
# Usage: make verify-region REGION=vectors
verify-region: | $(BUILD) ## Verify ONE region: make verify-region REGION=<name>
	@test -n "$(REGION)" || { echo "usage: make verify-region REGION=<name>"; exit 2; }
	@spec=""; for s in $(REGION_MAP); do case $$s in $(REGION):*) spec=$$s;; esac; done; \
	test -n "$$spec" || { echo "unknown region '$(REGION)'"; exit 2; }; \
	rest=$${spec#*:}; org=$${rest%%:*}; len=$${rest#*:}; \
	orgd=$$(printf '%d' $$org); lend=$$(printf '%d' $$len); \
	printf '        .area CODE (ABS)\n' > $(BUILD)/_r_$(REGION).asm; \
	for i in inc/sfr.inc inc/devices.inc inc/system.inc inc/servo.inc \
	         inc/teachbox.inc inc/serial.inc inc/program.inc; do \
	  printf '        .include "%s"\n' "$$PWD/$$i" >> $(BUILD)/_r_$(REGION).asm; done; \
	printf '        .include "%s"\n' "$$PWD/$(REGION).asm" >> $(BUILD)/_r_$(REGION).asm; \
	$(AS) -l -s -o $(BUILD)/_r_$(REGION).rel $(BUILD)/_r_$(REGION).asm || exit 1; \
	$(LD) -i -m $(BUILD)/_r_$(REGION).ihx $(BUILD)/_r_$(REGION).rel || exit 1; \
	$(OBJCOPY) -I ihex -O binary --gap-fill=0xFF --pad-to=$$((orgd + lend)) \
	  $(BUILD)/_r_$(REGION).ihx $(BUILD)/_r_$(REGION).full; \
	dd if=$(BUILD)/_r_$(REGION).full of=$(BUILD)/_r_$(REGION).bin bs=1 count=$$lend status=none; \
	dd if="$(ROM)" of=$(BUILD)/_rom_$(REGION).bin bs=1 skip=$$orgd count=$$lend status=none; \
	if cmp -s $(BUILD)/_r_$(REGION).bin $(BUILD)/_rom_$(REGION).bin; then \
	  echo "PASS  region[$(REGION)] $$org len=$$len — assembled == ROM"; \
	else \
	  echo "FAIL  region[$(REGION)] $$org — differs:"; \
	  cmp $(BUILD)/_r_$(REGION).bin $(BUILD)/_rom_$(REGION).bin || true; exit 1; \
	fi

# ---- Conversion aid: dump each region's exact ROM slice ----------------------
regions: | $(BUILD) ## Dump each region's ROM slice to _build/rom/<name>.bin (+hex)
	@mkdir -p $(BUILD)/rom
	@for spec in $(REGION_MAP); do \
		name=$${spec%%:*}; rest=$${spec#*:}; org=$${rest%%:*}; len=$${rest#*:}; \
		orgd=$$(printf '%d' $$org); lend=$$(printf '%d' $$len); \
		dd if="$(ROM)" of=$(BUILD)/rom/$$name.bin bs=1 skip=$$orgd count=$$lend status=none; \
		printf '%-12s org=%-6s len=%-5s -> %s\n' "$$name" "$$org" "$$len" "$(BUILD)/rom/$$name.bin"; \
		xxd -s $$orgd -l $$lend "$(ROM)" > $(BUILD)/rom/$$name.hex; \
	done

# ---- Report per-region byte-match status -------------------------------------
status: ## Verify every region individually and report PASS/FAIL
	@for spec in $(REGION_MAP); do \
		name=$${spec%%:*}; $(MAKE) --no-print-directory verify-region REGION=$$name || true; \
	done

clean: ## Remove build artifacts
	rm -rf $(BUILD)
