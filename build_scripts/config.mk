# Cross-toolchain configuration.
# Override any of these on the command line, e.g. `make JOBS=4 GCC_VER=14.2.0`.

TARGET       ?= i686-elf
BINUTILS_VER ?= 2.37
GCC_VER      ?= 14.4.0

# Build parallelism.
JOBS ?= $(shell nproc)

# Install layout. PREFIX must be absolute — GCC's configure rejects a relative one.
ROOT   ?= $(CURDIR)/toolchain
PREFIX ?= $(ROOT)/$(TARGET)

# Download mirrors. Swap these if ftp.gnu.org is slow for you.
BINUTILS_URL ?= https://ftp.gnu.org/gnu/binutils/binutils-$(BINUTILS_VER).tar.xz
GCC_URL      ?= https://ftp.gnu.org/gnu/gcc/gcc-$(GCC_VER)/gcc-$(GCC_VER).tar.xz
