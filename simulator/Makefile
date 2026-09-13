# ROB3 firmware — assemble & verify the annotated ROM regions
#
# Toolchain (SDCC suite + ucSim):
#   sdas8051   assembler   (.a51 -> .rel)
#   sdld       linker      (.rel -> .ihx)
#   objcopy    ihex->bin   (binutils)
#   s51        8051 sim    (ucSim) for behavioral tests
#
# Each annotated region is a BYTE-EXACT transcription of the real ROM. The
# golden tests prove the assembled bytes equal the ROM; the sim tests prove the
# runtime behavior matches the annotated .asm files.
#
# Regions:
#   init      0x0600..0x074C  -> ../firmware/src/annotated/main.annotated.asm
#   teachbox  0x0C00..0x0C6B  -> ../firmware/src/annotated/teachbox.annotated.asm (keypad scanner)
#
# This Makefile lives in the top-level simulator/ directory. The firmware
# artifacts (ROM image + annotated sources) live in ../firmware/; the
# simulator sources, tests and build output are local to this directory.

# ---- Layout ------------------------------------------------------------------
FWDIR      := ../firmware
BIN        := $(FWDIR)/bin/M2764A@DIP28.BIN
HEX        := $(FWDIR)/hex/M2764A@DIP28.HEX
SIMDIR     := .
BUILD      := $(SIMDIR)/build

# Init region (reset init: 0x0600 .. 0x074C inclusive)
INIT_SRC   := $(SIMDIR)/init.a51
INIT_ORG   := 0x0600
INIT_LEN   := 333            # 0x074D - 0x0600
INIT_SKIP  := 1536           # 0x0600 in decimal

# Teachbox keypad scanner region (0x0C00 .. 0x0C6B inclusive)
TB_SRC     := $(SIMDIR)/teachbox_scan.a51
TB_ORG     := 0x0C00
TB_LEN     := 108            # 0x0C6C - 0x0C00
TB_SKIP    := 3072           # 0x0C00 in decimal

# ---- Tools -------------------------------------------------------------------
AS         := sdas8051
LD         := sdld
OBJCOPY    := objcopy
SIM        := s51
SIMFLAGS   := -t 51 -X 11.0592M

# A hex copy with a shell-safe name (the shipped .hex has an '@' in its name)
SAFEHEX    := $(BUILD)/rob3.hex

.PHONY: all verify verify-init verify-teachbox \
        sim-init sim-run sim-teachbox sim-teachbox-module sim-adc \
        sim-teachbox-axis demo-teachbox test gen clean help

all: verify ## Default: assemble all regions and prove they match the ROM

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		sort | awk 'BEGIN{FS=":.*?## "}{printf "  %-16s %s\n", $$1, $$2}'

$(BUILD):
	@mkdir -p $(BUILD)

# ---- Generic assemble+link+bin+golden ----------------------------------------
# $(1)=name  $(2)=src .a51  $(3)=org  $(4)=len(bytes)  $(5)=skip(dec)
define GOLDEN_template
$$(BUILD)/$(1).bin: $(2) | $$(BUILD)
	$$(AS) -o -l -s $$(BUILD)/$(1).rel $(2)
	$$(LD) -i -m -b CODE=$(3) $$(BUILD)/$(1).ihx $$(BUILD)/$(1).rel
	$$(OBJCOPY) -I ihex -O binary $$(BUILD)/$(1).ihx $$(BUILD)/$(1).bin

$$(BUILD)/rom_$(1).bin: $$(BIN) | $$(BUILD)
	dd if="$$(BIN)" of=$$(BUILD)/rom_$(1).bin bs=1 skip=$(5) count=$(4) status=none

verify-$(1): $$(BUILD)/$(1).bin $$(BUILD)/rom_$(1).bin
	@if cmp -s $$(BUILD)/$(1).bin $$(BUILD)/rom_$(1).bin; then \
		echo "PASS  golden[$(1)]: assembled == ROM[$(3)..] ($(4) bytes)"; \
		sha256sum $$(BUILD)/$(1).bin $$(BUILD)/rom_$(1).bin; \
	else \
		echo "FAIL  golden[$(1)]: assembled differs from ROM"; \
		cmp $$(BUILD)/$(1).bin $$(BUILD)/rom_$(1).bin || true; \
		exit 1; \
	fi
endef

$(eval $(call GOLDEN_template,init,$(INIT_SRC),$(INIT_ORG),$(INIT_LEN),$(INIT_SKIP)))
$(eval $(call GOLDEN_template,teachbox,$(TB_SRC),$(TB_ORG),$(TB_LEN),$(TB_SKIP)))

verify: verify-init verify-teachbox ## GOLDEN: all regions must equal the ROM

# ---- Simulator plumbing ------------------------------------------------------
$(SAFEHEX): $(HEX) | $(BUILD)
	cp "$(HEX)" $(SAFEHEX)

sim-init: $(SAFEHEX) ## Behavioral: run init in s51, assert annotated behavior
	@SAFEHEX=$(SAFEHEX) SIM="$(SIM)" SIMFLAGS="$(SIMFLAGS)" \
		$(SIMDIR)/tests/sim_init.sh

sim-run: $(SAFEHEX) ## Run init past the ADC/INT1 gate (inject EOC) to main loop
	@SAFEHEX=$(SAFEHEX) SIM="$(SIM)" SIMFLAGS="$(SIMFLAGS)" \
		$(SIMDIR)/tests/sim_run.sh

sim-teachbox: $(SAFEHEX) ## Behavioral: run the keypad scanner, assert key decode
	@SAFEHEX=$(SAFEHEX) SIM="$(SIM)" SIMFLAGS="$(SIMFLAGS)" \
		$(SIMDIR)/tests/sim_teachbox.sh

sim-teachbox-module: $(SAFEHEX) ## Behavioral: exercise the compiled teachbox cl_hw module (opt-in; skips w/o ucsim_51)
	@SAFEHEX=$(SAFEHEX) SIMFLAGS="$(SIMFLAGS)" \
		$(SIMDIR)/tests/sim_teachbox_module.sh

sim-adc: $(SAFEHEX) ## Behavioral: free-run past the ADC/INT1 gate via the compiled adc cl_hw module (opt-in; skips w/o ucsim_51)
	@SAFEHEX=$(SAFEHEX) SIMFLAGS="$(SIMFLAGS)" \
		$(SIMDIR)/tests/sim_adc.sh

sim-teachbox-axis: $(SAFEHEX) ## Black-box: real keypad axis-select -> POSITION mode (needs teachbox+loopback cl_hw; skips w/o them)
	@UCSIM_51="$(UCSIM_51)" python3 $(SIMDIR)/tests/test_teachbox_axis_select.py

demo-teachbox: $(SAFEHEX) ## Demo: teachbox key press -> axis-select -> jog -> axis position moves (needs custom ucsim_51)
	@SAFEHEX=$(SAFEHEX) SIMFLAGS="$(SIMFLAGS)" \
		$(SIMDIR)/tests/demo_teachbox_axis.sh

# ---- Aggregate ---------------------------------------------------------------
test: verify sim-init sim-run sim-teachbox sim-teachbox-module sim-adc sim-teachbox-axis ## Run all tests (golden + behavioral)
	@echo "ALL TESTS PASSED"

# ---- Regenerate the byte-exact sources from the ROM --------------------------
gen: ## Regenerate the .a51 region sources from the ROM (byte-exact)
	@python3 $(SIMDIR)/gen_init.py "$(BIN)" $(INIT_SRC) $(INIT_ORG) $(INIT_LEN) \
		init_start $(FWDIR)/src/annotated/main.annotated.asm
	@python3 $(SIMDIR)/gen_init.py "$(BIN)" $(TB_SRC) $(TB_ORG) $(TB_LEN) \
		kbd_scan_region $(FWDIR)/src/annotated/teachbox.annotated.asm
	@echo "regenerated $(INIT_SRC) and $(TB_SRC)"

clean: ## Remove build artifacts
	rm -rf $(BUILD)
