# ============================================================================
# uniqos Makefile
# ============================================================================

ASM       := nasm
QEMU      := qemu-system-i386

STAGE1    := stage1.asm
STAGE2    := stage2.asm

STAGE1_BIN := stage1.bin
STAGE2_BIN := stage2.bin
DISK_IMG   := disk.img

.PHONY: all run clean

all: $(DISK_IMG)

$(STAGE1_BIN): $(STAGE1)
	$(ASM) -f bin $< -o $@

$(STAGE2_BIN): $(STAGE2)
	$(ASM) -f bin $< -o $@
	truncate -s 16384 $@

$(DISK_IMG): $(STAGE1_BIN) $(STAGE2_BIN)
	cat $(STAGE1_BIN) $(STAGE2_BIN) > $(DISK_IMG)

run: $(DISK_IMG)
	$(QEMU) -drive format=raw,file=$(DISK_IMG)

clean:
	rm -f $(STAGE1_BIN) $(STAGE2_BIN) $(DISK_IMG)
