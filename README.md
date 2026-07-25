# nanobyte-os

A tiny x86 hobby operating system written by following the
[**nanobyte** "Building an OS" YouTube series](https://www.youtube.com/playlist?list=PLFjM7v6KGMpiH2G-kT781ByCNC_0pKpPN).
Everything in this repository is from that tutorial — this repo is a
learning project, not an original OS.

## What it does so far

The project uses a **two-stage bootloader** that hands off to a 32-bit C
kernel. Stage 2 and the kernel are both written in C and built with a GCC
`i686-elf` cross-compiler. The boot sequence is:

1. The PC's BIOS loads **stage 1** (`src/bootloader/stage1/boot.asm`) —
   the 512-byte FAT12 boot sector — from sector 0 of the floppy image
   into memory at `0x7C00` and jumps to it.
2. Stage 1 sets up segment registers and a stack, then uses BIOS disk
   services (`INT 13h`) to walk the **FAT12** filesystem, find
   `STAGE2.BIN`, load it into memory, and jump to it.
3. **Stage 2** (`src/bootloader/stage2/`) begins in 16-bit real mode at
   its assembly entry point (`entry.asm`): it saves the boot drive, sets
   up a stack, enables the A20 line, loads a GDT, and **switches the CPU
   into 32-bit protected mode** before calling into the C entry point
   `start` (`main.c`). From there it:
   - initialises the disk (`disk.c`) and the FAT12 driver (`fat.c`),
   - opens `/kernel.bin`, reads it into memory in chunks, and
   - **jumps to the kernel entry point**.
4. **The kernel** (`src/kernel/`) starts at `start` (`main.c`): it zeroes
   the BSS, then calls `HAL_Initialize()` to bring up the hardware
   abstraction layer (`hal/`), which installs the kernel's own
   **GDT** and **IDT** (`arch/i686/`). It then clears the screen, prints
   a hello-world message, and halts.

If something goes wrong during boot (disk error, missing `STAGE2.BIN` or
`KERNEL.BIN`) the offending stage prints a message before halting; stage 1
waits for a keypress and reboots.

> **Note:** the IDT is loaded but no interrupt gates are enabled yet, so
> the kernel does not yet handle interrupts — the plumbing (GDT, IDT,
> port I/O helpers) is in place for the next steps in the series.

## Repository layout

```
.
├── src/
│   ├── bootloader/
│   │   ├── stage1/
│   │   │   └── boot.asm     # 512-byte FAT12 boot sector (loads stage 2)
│   │   └── stage2/          # C stage-2 loader (real mode → protected mode)
│   │       ├── entry.asm    # 16-bit entry, switches to protected mode, calls start()
│   │       ├── main.c       # start() — disk + FAT12 demo
│   │       ├── disk.c/.h    # disk read wrapper
│   │       ├── fat.c/.h     # FAT12 driver (open/read/readdir)
│   │       ├── ctype.c/.h   # character classification helpers
│   │       ├── memory.c/.h  # memcpy/memset etc.
│   │       ├── stdio.c/.h   # printf, putc, puts
│   │       ├── string.c/.h  # string helpers
│   │       ├── x86.asm/.h   # low-level asm helpers
│   │       ├── memdefs.h    # memory-layout constants
│   │       ├── minmax.h     # min/max macros
│   │       └── linker.ld    # GNU ld linker script
│   └── kernel/
│       ├── main.c           # kernel entry start(): HAL init + hello world
│       ├── stdio.c/.h       # printf, screen output
│       ├── memory.c/.h      # memcpy/memset etc.
│       ├── hal/             # hardware abstraction layer
│       │   └── hal.c/.h     # HAL_Initialize() — brings up GDT + IDT
│       ├── arch/i686/       # i686-specific low-level setup
│       │   ├── gdt.c/.h/.asm  # Global Descriptor Table
│       │   ├── idt.c/.h/.asm  # Interrupt Descriptor Table
│       │   └── io.asm/.h      # port I/O helpers (inb/outb)
│       ├── util/
│       │   └── binary.h     # bit-flag helper macros
│       └── linker.ld        # GNU ld linker script
├── tools/
│   └── fat/                 # host-side FAT12 image reader
│       ├── main.c           # CLI: read a file out of an image
│       ├── disk.c/.h
│       └── fat.c/.h
├── build_scripts/
│   ├── config.mk            # toolchain vars, target triple, versions
│   └── toolchain.mk         # builds the i686-elf binutils + GCC cross-compiler
├── Makefile                 # builds stages, kernel, floppy image, tools
├── run.sh                   # boots the floppy image in QEMU
├── debug.sh                 # boots in Bochs with the debugger attached
├── bochs_config             # Bochs configuration
└── bx_enh_dbg.ini           # Bochs enhanced-debugger settings
```

## Building

You'll need:

- `nasm` — the Netwide Assembler (stage 1, stage 2 entry, asm helpers)
- an **`i686-elf` GCC cross-compiler** (`i686-elf-gcc`) — used to compile
  stage 2 and the kernel. If you don't have one, the Makefile can build
  it for you (see below).
- `gcc` — for the host-side `fat` tool
- `mtools` (`mcopy`, `mmd`) — to copy files into the FAT12 image
- `dosfstools` (`mkfs.fat`) — to format the floppy image
- `make`

### Building the cross-compiler

The cross-compiler is built from binutils and GCC sources (versions are
pinned in `build_scripts/config.mk`) and installed under `toolchain/`:

```sh
make toolchain
```

This downloads and compiles binutils and GCC, so it takes a while and
needs the usual GCC build dependencies (`wget`, `tar`, a host C/C++
compiler, `gmp`, `mpfr`, `mpc`, etc.). The Makefile prepends
`toolchain/i686-elf/bin` to `PATH`, so once built the `i686-elf-*` tools
are found automatically.

### Building the OS

```sh
make
```

The build produces:

- `build/stage1.bin`      — the raw 512-byte boot sector
- `build/stage2.bin`      — the C stage-2 loader
- `build/kernel.bin`      — the kernel binary
- `build/main_floppy.img` — a 1.44 MB FAT12 floppy image with stage 1
  written to sector 0 and `stage2.bin`, `kernel.bin`, `test.txt`, and a
  `mydir/` subdirectory (containing `test.txt`) copied into the
  filesystem
- `build/tools/fat.out`   — host-side helper for inspecting FAT12 images

## Running

In QEMU:

```sh
./run.sh
```

In Bochs (with the debugger):

```sh
./debug.sh
```

You should see the bootloader load stage 2, stage 2 load the kernel, and
then the kernel print `Hello world from kernel!!!`, after which the
system halts.

## Inspecting an image on the host

The `fat` tool reads a file straight out of a FAT12 image, which is handy
for debugging the on-disk layout:

```sh
build/tools/fat.out build/main_floppy.img mydir/test.txt
```

## Cleaning

```sh
make clean
```

To also remove the built cross-compiler:

```sh
make clean-toolchain      # remove the build/source dirs
make clean-toolchain-all  # wipe everything under toolchain/
```

## Reading the source

The assembly files are heavily commented for readers who have never
written assembly before — they walk through what each instruction does,
why the BIOS calls are arranged the way they are, and how FAT12 fits into
the boot process. A good reading order follows the boot flow:

1. `src/bootloader/stage1/boot.asm` — the boot sector
2. `src/bootloader/stage2/` — the C loader (`entry.asm` → `main.c` →
   `fat.c` → `disk.c`)
3. `src/kernel/` — the kernel (`main.c` → `hal/hal.c` →
   `arch/i686/gdt.c` → `arch/i686/idt.c`)

## Continuous integration

A GitHub Actions workflow (`.github/workflows/build.yml`) builds the OS on
every push and pull request. It caches the `i686-elf` cross-compiler
(keyed on `build_scripts/config.mk`, so it only rebuilds when the pinned
versions change) and uploads `main_floppy.img` as a build artifact.

## Credits

All design and code come from the
[nanobyte "Building an OS" tutorial series](https://www.youtube.com/playlist?list=PLFjM7v6KGMpiH2G-kT781ByCNC_0pKpPN).
This repository is just one viewer's checkpoint as they follow along.
