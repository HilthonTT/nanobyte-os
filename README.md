# nanobyte-os

A tiny x86 hobby operating system written by following the
[**nanobyte** "Building an OS" YouTube series](https://www.youtube.com/playlist?list=PLFjM7v6KGMpiH2G-kT781ByCNC_0pKpPN).
Everything in this repository is from that tutorial — this repo is a
learning project, not an original OS.

## What it does so far

The project now uses a **two-stage bootloader**, with stage 2 written in
C. The boot sequence is:

1. The PC's BIOS loads **stage 1** (`src/bootloader/stage1/boot.asm`) —
   the 512-byte FAT12 boot sector — from sector 0 of the floppy image
   into memory at `0x7C00` and jumps to it.
2. Stage 1 sets up segment registers and a stack, then uses BIOS disk
   services (`INT 13h`) to walk the **FAT12** filesystem, find
   `STAGE2.BIN`, load it into memory, and jump to it.
3. **Stage 2** (`src/bootloader/stage2/`, mostly C compiled for 16-bit
   real mode with Open Watcom) takes over. It:
   - initialises the disk (`disk.c`) and the FAT12 driver (`fat.c`),
   - opens the root directory and lists its first few entries,
   - opens a file inside a subdirectory (`mydir/test.txt`), reads it,
     and prints its contents,
   - then halts.

If something goes wrong during boot (disk error, missing `STAGE2.BIN`)
stage 1 prints a message and waits for a keypress before rebooting.

> **Note:** stage 2 currently demonstrates the FAT12 driver rather than
> handing off to the kernel. `KERNEL.BIN` (the tiny hello-world in
> `src/kernel/main.asm`) is built and copied onto the floppy image, but
> stage 2 does not yet load or jump to it.

## Repository layout

```
.
├── src/
│   ├── bootloader/
│   │   ├── stage1/
│   │   │   └── boot.asm     # 512-byte FAT12 boot sector (loads stage 2)
│   │   └── stage2/          # C stage-2 loader (16-bit real mode)
│   │       ├── main.asm     # entry stub, calls into C
│   │       ├── main.c       # cstart_ — disk + FAT12 demo
│   │       ├── disk.c/.h    # BIOS disk read wrapper
│   │       ├── fat.c/.h     # FAT12 driver (open/read/readdir)
│   │       ├── memory.c     # memcpy/memset etc.
│   │       ├── stdio.c      # printf, putc, puts
│   │       ├── string.c     # string helpers
│   │       ├── x86.asm/.h   # real-mode BIOS call thunks
│   │       └── linker.lnk   # Watcom linker script
│   └── kernel/
│       └── main.asm         # stage-2 kernel (hello world for now)
├── tools/
│   └── fat/                 # host-side FAT12 image reader
│       ├── main.c           # CLI: read a file out of an image
│       ├── disk.c/.h
│       └── fat.c/.h
├── Makefile                 # builds stages, kernel, floppy image, tools
├── run.sh                   # boots the floppy image in QEMU
├── debug.sh                 # boots in Bochs with the debugger attached
├── bochs_config             # Bochs configuration
└── bx_enh_dbg.ini           # Bochs enhanced-debugger settings
```

## Building

You'll need:

- `nasm` — the Netwide Assembler (stage 1, stage 2 thunks, kernel)
- [**Open Watcom**](https://open-watcom.github.io/) — `wcc` / `wlink`,
  used to compile stage 2's C for 16-bit real mode. The Makefile expects
  them at `/usr/bin/watcom/binl/wcc` and `.../wlink`; adjust `CC16` /
  `LD16` in the top-level `Makefile` if yours live elsewhere.
- `gcc` — for the host-side `fat` tool
- `mtools` (`mcopy`, `mmd`) — to copy files into the FAT12 image
- `dosfstools` (`mkfs.fat`) — to format the floppy image
- `make`

Then:

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

You should see the loading message, the first few root-directory
entries, and the contents of `mydir/test.txt` printed to the screen,
after which the system halts.

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

## Reading the source

The assembly files are heavily commented for readers who have never
written assembly before — they walk through what each instruction does,
why the BIOS calls are arranged the way they are, and how FAT12 fits into
the boot process. Start with `src/bootloader/stage1/boot.asm`, then read
the C stage 2 in `src/bootloader/stage2/` (`main.c` → `fat.c` →
`disk.c`).

## Credits

All design and code come from the
[nanobyte "Building an OS" tutorial series](https://www.youtube.com/playlist?list=PLFjM7v6KGMpiH2G-kT781ByCNC_0pKpPN).
This repository is just one viewer's checkpoint as they follow along.
