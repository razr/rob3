# ROB3 firmware — assemble & verify the annotated init sequence
#
# Toolchain (SDCC suite + ucSim):
#   sdas8051   assembler   (.a51 -> .rel)
#   sdld       linker      (.rel -> .ihx)
#   objcopy    ihex->bin   (binutils)
#   s51        8051 sim    (ucSim) for behavioral tests
#
# The init region is a BYTE-EXACT transcription of the real ROM. The golden
# test proves the assembled bytes equal the ROM; the sim tests prove the
# runtime behavior matches firmware/src/main.annotated.asm.

# ---- Layout ------------------------------------------------------------------
BIN        := bin/M2764A@DIP28.BIN
HEX        := hex/M2764A@DIP28.HEX
SIMDIR     := sim
BUILD      := $(SIMDIR)/build
SRC        := $(SIMDIR)/init.a51

# Init region within the ROM (reset init: 0x0600 .. 0x074C inclusive)
INIT_ORG   := 0x0600
INIT_LEN   := 333            # 0x074D - 0x0600
INIT_SKIP  := 1536           # 0x0600 in decimal

# sdld base: place ABS CODE area at the init origin
LDBASE     := CODE=$(INIT_ORG)

# ---- Tools -------------------------------------------------------------------
AS         := sdas8051
LD         := sdld
OBJCOPY    := objcopy
SIM        := s51
SIMFLAGS   := -t 51 -X 11.0592M

# A hex copy with a shell-safe name (the shipped .hex has an '@' in its name)
SAFEHEX    := $(BUILD)/rob3.hex

# ---- Artifacts ---------------------------------------------------------------
REL        := $(BUILD)/init.rel
IHX        := $(BUILD)/init.ihx
OUTBIN     := $(BUILD)/init.bin
ROMSLICE   := $(BUILD)/rom_init.bin

.PHONY: all assemble link bin verify sim-init sim-run test gen clean help

all: verify ## Default: assemble the init and prove it matches the ROM

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		sort | awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n", $$1, $$2}'

$(BUILD):
	@mkdir -p $(BUILD)

# ---- Assemble ----------------------------------------------------------------
$(REL): $(SRC) | $(BUILD)
	$(AS) -o -l -s $(BUILD)/init.rel $(SRC)

assemble: $(REL) ## Assemble sim/init.a51 -> .rel

# ---- Link --------------------------------------------------------------------
$(IHX): $(REL)
	$(LD) -i -m -b $(LDBASE) $(IHX) $(REL)

link: $(IHX) ## Link .rel -> Intel HEX

# ---- Binary ------------------------------------------------------------------
$(OUTBIN): $(IHX)
	$(OBJCOPY) -I ihex -O binary $(IHX) $(OUTBIN)

bin: $(OUTBIN) ## Produce raw binary of the assembled init

# ---- Golden byte-match test --------------------------------------------------
$(ROMSLICE): $(BIN) | $(BUILD)
	dd if="$(BIN)" of=$(ROMSLICE) bs=1 skip=$(INIT_SKIP) count=$(INIT_LEN) status=none

verify: $(OUTBIN) $(ROMSLICE) ## GOLDEN: assembled init must equal ROM bytes
	@if cmp -s $(OUTBIN) $(ROMSLICE); then \
		echo "PASS  golden: assembled init == ROM[$(INIT_ORG)..] ($(INIT_LEN) bytes)"; \
		sha256sum $(OUTBIN) $(ROMSLICE); \
	else \
		echo "FAIL  golden: assembled init differs from ROM"; \
		cmp $(OUTBIN) $(ROMSLICE) || true; \
		exit 1; \
	fi

# ---- Simulator plumbing ------------------------------------------------------
$(SAFEHEX): $(HEX) | $(BUILD)
	cp "$(HEX)" $(SAFEHEX)

sim-init: $(SAFEHEX) ## Behavioral test: run init in s51, assert annotated behavior
	@SAFEHEX=$(SAFEHEX) SIM="$(SIM)" SIMFLAGS="$(SIMFLAGS)" \
		$(SIMDIR)/tests/sim_init.sh

sim-run: $(SAFEHEX) ## Run init past the ADC/INT1 gate (inject EOC) to main loop
	@SAFEHEX=$(SAFEHEX) SIM="$(SIM)" SIMFLAGS="$(SIMFLAGS)" \
		$(SIMDIR)/tests/sim_run.sh

# ---- Aggregate ---------------------------------------------------------------
test: verify sim-init sim-run ## Run all tests (golden + behavioral)
	@echo "ALL TESTS PASSED"

# ---- Regenerate the byte-exact source from the ROM ---------------------------
gen: ## Regenerate sim/init.a51 from the ROM (byte-exact)
	@python3 $(SIMDIR)/gen_init.py "$(BIN)" $(SRC) $(INIT_ORG) $(INIT_LEN)
	@echo "regenerated $(SRC)"

clean: ## Remove build artifacts
	rm -rf $(BUILD)
