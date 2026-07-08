# Makefile
ASM   = nasm
CC    = gcc
CC16  = /usr/bin/watcom/binl/wcc
LD16  = /usr/bin/watcom/binl/wlink

SRC_DIR   = src
TOOLS_DIR = tools

include build_scripts/config.mk

# Absolute build dir, computed once and passed to every sub-make.
ABS_BUILD_DIR := $(abspath $(BUILD_DIR))

# Recursive-make helper:  $(call submake,<dir>[,<goal>])
submake = $(MAKE) -C $(1) BUILD_DIR=$(ABS_BUILD_DIR) $(2)

# Deliverables
FLOPPY   := $(BUILD_DIR)/main_floppy.img
DISK_FILE = test.txt

.PHONY: all floppy_image bootloader stage1 stage2 kernel tools_fat clean always
.DELETE_ON_ERROR:

all: floppy_image tools_fat

include build_scripts/toolchain.mk

#
# Floppy image
#
floppy_image: $(FLOPPY)

$(FLOPPY): bootloader kernel
	dd if=/dev/zero of=$@ bs=512 count=2880
	mkfs.fat -F 12 -n "NBOS" $@
	dd if=$(BUILD_DIR)/stage1.bin of=$@ conv=notrunc
	mcopy -i $@ $(BUILD_DIR)/stage2.bin "::stage2.bin"
	mcopy -i $@ $(BUILD_DIR)/kernel.bin "::kernel.bin"
	mcopy -i $@ $(DISK_FILE) "::test.txt"
	mmd   -i $@ "::mydir"
	mcopy -i $@ $(DISK_FILE) "::mydir/test.txt"

#
# Bootloader
#
bootloader: stage1 stage2

stage1: $(BUILD_DIR)/stage1.bin
$(BUILD_DIR)/stage1.bin: always
	$(call submake,$(SRC_DIR)/bootloader/stage1)

stage2: $(BUILD_DIR)/stage2.bin
$(BUILD_DIR)/stage2.bin: always
	$(call submake,$(SRC_DIR)/bootloader/stage2)

#
# Kernel
#
kernel: $(BUILD_DIR)/kernel.bin
$(BUILD_DIR)/kernel.bin: always
	$(call submake,$(SRC_DIR)/kernel)

#
# Tools
#
tools_fat: $(BUILD_DIR)/tools/fat
$(BUILD_DIR)/tools/fat: always $(TOOLS_DIR)/fat/fat.c
	mkdir -p $(BUILD_DIR)/tools
	$(call submake,$(TOOLS_DIR)/fat)

#
# Always — forces the recursive sub-makes to run every time
# (incrementality is delegated to each sub-Makefile).
#
always:
	mkdir -p $(BUILD_DIR)

#
# Clean
#
clean:
	$(call submake,$(SRC_DIR)/bootloader/stage1,clean)
	$(call submake,$(SRC_DIR)/bootloader/stage2,clean)
	$(call submake,$(SRC_DIR)/kernel,clean)
	$(call submake,$(TOOLS_DIR)/fat,clean)
	rm -rf $(BUILD_DIR)
