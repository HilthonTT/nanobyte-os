# Cross-toolchain configuration.
# Override any of these on the command line, e.g. `make JOBS=4 GCC_VER=14.2.0`.

# Host tools. Not exported: sub-Makefiles set their own defaults with ?=,
# and an exported (even empty) value would override them.
CFLAGS = -std=c99 -g
GCC = gcc
CXX = g++
LD = gcc
ASM = nasm
ASMFLAGS =
LINKFLAGS =
LIBS =

export TARGET_CFLAGS = -std=c99 -g # -O2
export TARGET       ?= i686-elf
export TARGET_CC = $(TARGET)-gcc
export TARGET_CXX = $(TARGET)-g++
export TARGET_LD = $(TARGET)-gcc
export TARGET_ASM = nasm
export TARGET_ASM_FLAGS =
export TARGET_LINKFLAGS = 
export TARGET_LIBS = 

BUILD_DIR = $(abspath build)

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
