# i686-elf cross-toolchain for OS development.
# Builds binutils + a freestanding GCC into $(PREFIX).
# Usage: make -f toolchain.mk

include $(dir $(lastword $(MAKEFILE_LIST)))config.mk

# Derived paths (internal — edit config.mk, not these).
SRC   := $(ROOT)/src
BUILD := $(ROOT)/build

# The freshly built binutils must be on PATH before GCC is configured,
# or the GCC build won't find $(TARGET)-as and the target libs fail.
export PATH := $(PREFIX)/bin:$(PATH)

BINUTILS_TAR := $(SRC)/binutils-$(BINUTILS_VER).tar.xz
GCC_TAR      := $(SRC)/gcc-$(GCC_VER).tar.xz

BINUTILS_SRC := $(SRC)/binutils-$(BINUTILS_VER)
GCC_SRC      := $(SRC)/gcc-$(GCC_VER)

BINUTILS_BUILD := $(BUILD)/binutils-$(BINUTILS_VER)
GCC_BUILD      := $(BUILD)/gcc-$(GCC_VER)

# Install markers: the presence of the compiled binary == that stage is done.
AS  := $(PREFIX)/bin/$(TARGET)-as
GCC := $(PREFIX)/bin/$(TARGET)-gcc

.PHONY: toolchain binutils gcc toolchain-clean toolchain-distclean

toolchain: gcc
binutils:  $(AS)
gcc:       $(GCC)

# ---- download ----
$(BINUTILS_TAR):
	mkdir -p $(SRC)
	wget -O $@ $(BINUTILS_URL)

$(GCC_TAR):
	mkdir -p $(SRC)
	wget -O $@ $(GCC_URL)

# ---- extract ----
$(BINUTILS_SRC): $(BINUTILS_TAR)
	tar -xf $< -C $(SRC)
	touch $@

$(GCC_SRC): $(GCC_TAR)
	tar -xf $< -C $(SRC)
	cd $(GCC_SRC) && ./contrib/download_prerequisites
	touch $@

# ---- binutils ----
$(AS): $(BINUTILS_SRC)
	mkdir -p $(BINUTILS_BUILD)
	cd $(BINUTILS_BUILD) && $(BINUTILS_SRC)/configure \
		--target=$(TARGET) \
		--prefix=$(PREFIX) \
		--with-sysroot \
		--disable-nls \
		--disable-werror
	$(MAKE) -j$(JOBS) -C $(BINUTILS_BUILD)
	$(MAKE) -C $(BINUTILS_BUILD) install

# ---- gcc (freestanding) ----
$(GCC): $(GCC_SRC) $(AS)
	mkdir -p $(GCC_BUILD)
	cd $(GCC_BUILD) && $(GCC_SRC)/configure \
		--target=$(TARGET) \
		--prefix=$(PREFIX) \
		--enable-languages=c,c++ \
		--disable-nls \
		--without-headers
	$(MAKE) -j$(JOBS) -C $(GCC_BUILD) all-gcc all-target-libgcc
	$(MAKE) -C $(GCC_BUILD) install-gcc install-target-libgcc

toolchain-clean:
	rm -rf $(BUILD)

toolchain-distclean:
	rm -rf $(ROOT)
