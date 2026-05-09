# nanobyte-os

A tiny x86 hobby operating system written by following the
[**nanobyte** "Building an OS" YouTube series](https://www.youtube.com/playlist?list=PLFjM7v6KGMpiH2G-kT781ByCNC_0pKpPN).
Everything in this repository is from that tutorial — this repo is a
learning project, not an original OS.

## What it does so far

The system is still at the very beginning of the tutorial:

1. The PC's BIOS loads our **bootloader** (`src/bootloader/boot.asm`) from
   sector 0 of the floppy image into memory at `0x7C00` and jumps to it.
2. The bootloader sets up segment registers and a stack, then uses BIOS
   disk services (`INT 13h`) to walk the **FAT12** filesystem on the
   floppy, find `KERNEL.BIN`, and load it into memory at `0x2000:0x0000`.
3. It hands control to the **kernel** (`src/kernel/main.asm`), which
   prints a hello message and halts.

If something goes wrong during boot (disk error, missing kernel) the
bootloader prints a message and waits for a keypress before rebooting.

## Repository layout

```
.
├── src/
│   ├── bootloader/
│   │   └── boot.asm      # 512-byte FAT12 boot sector
│   └── kernel/
│       └── main.asm      # stage-2 kernel (hello world for now)
├── tools/
│   └── fat/
│       └── fat.c         # host-side FAT12 image reader (debug helper)
├── Makefile              # builds the bootloader, kernel, floppy image
├── run.sh                # boots the floppy image in QEMU
├── debug.sh              # boots in Bochs with the debugger attached
├── bochs_config          # Bochs configuration
└── bx_enh_dbg.ini        # Bochs enhanced-debugger settings
```

## Building

You'll need:

- `nasm` — the Netwide Assembler
- `gcc` — for the host-side `fat` tool
- `mtools` (`mcopy`) — to copy files into the FAT12 image
- `dosfstools` (`mkfs.fat`) — to format the floppy image
- `make`

Then:

```sh
make
```

The build produces:

- `build/bootloader.bin` — the raw 512-byte boot sector
- `build/kernel.bin`     — the kernel binary
- `build/main_floppy.img` — a 1.44 MB FAT12 floppy image with the
  bootloader written to sector 0 and `kernel.bin` + `test.txt` copied
  into the filesystem
- `build/tools/fat`      — host-side helper for inspecting FAT12 images

## Running

In QEMU:

```sh
./run.sh
```

In Bochs (with the debugger):

```sh
./debug.sh
```

You should see:

```
Loading...
Hello world from KERNEL!
```

…and then the system halts.

## Cleaning

```sh
make clean
```

## Reading the source

Both assembly files have been heavily commented for readers who have
never written assembly before — they walk through what each instruction
does, why the BIOS calls are arranged the way they are, and how FAT12
fits into the boot process. Start with `src/bootloader/boot.asm`, then
move on to `src/kernel/main.asm`.

## Credits

All design and code come from the
[nanobyte "Building an OS" tutorial series](https://www.youtube.com/playlist?list=PLFjM7v6KGMpiH2G-kT781ByCNC_0pKpPN).
This repository is just one viewer's checkpoint as they follow along.
