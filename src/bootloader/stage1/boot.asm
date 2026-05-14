; =============================================================================
; nanobyte-os bootloader
; =============================================================================
; A 512-byte FAT12 boot sector for x86 real mode. The BIOS loads this from
; sector 0 of the boot device into physical address 0x7C00 and jumps to it
; with CS:IP = 0000:7C00 (or equivalent), DL = boot drive number, and very
; little else guaranteed. We have to set up our own segments and stack
; before we can do anything useful.
;
; Real-mode memory map (the parts that matter to us):
;   0x00000 - 0x003FF   Interrupt Vector Table
;   0x00400 - 0x004FF   BIOS Data Area
;   0x00500 - 0x07BFF   Free — our stack lives at the top of this region
;   0x07C00 - 0x07DFF   Us (512 bytes)
;   0x07E00 - 0x9FBFF   Free — where we'll eventually load the kernel
; =============================================================================

org 0x7C00              ; Tell NASM the code will be loaded at 0x7C00 so that
                        ; label addresses are computed correctly. Without
                        ; this, every `mov si, msg_hello` would point into
                        ; the wrong part of memory.
bits 16                 ; Emit 16-bit instruction encodings (real mode).

%define ENDL 0x0D, 0x0A ; CRLF. The BIOS teletype service handles 0x0D
                        ; (carriage return) and 0x0A (line feed) the way
                        ; you'd expect a serial terminal to.

; =============================================================================
; FAT12 BIOS Parameter Block (BPB)
; =============================================================================
; This is data, not code. The FAT12 spec requires these fields to live at
; specific offsets inside the boot sector so that filesystem tools and OS
; drivers can read the disk's geometry. The CPU must NOT execute this — the
; first instruction below jumps over it to the real entry point.
; =============================================================================

jmp short start         ; 2-byte short jump to skip the BPB.
nop                     ; FAT requires the initial jump to occupy exactly
                        ; 3 bytes (`jmp short` is 2 bytes, so pad with NOP).

bdb_oem:                    db 'MSWIN4.1'   ; 8-byte OEM identifier. 'MSWIN4.1'
                                            ; is the conventional value; some
                                            ; tools misbehave with anything else.
bdb_bytes_per_sector:       dw 512          ; Bytes per logical sector.
bdb_sectors_per_cluster:    db 1            ; Sectors per allocation unit.
bdb_reserved_sectors:       dw 1            ; Sectors before the first FAT
                                            ; (just the boot sector itself).
bdb_fat_count:              db 2            ; Two FATs (the second is a backup).
bdb_dir_entries_count:      dw 0E0h         ; 224 root-directory entries.
bdb_total_sectors:          dw 2880         ; 2880 * 512 B = 1.44 MB.
bdb_media_descriptor_type:  db 0F0h         ; 0xF0 = 3.5" 1.44 MB floppy.
bdb_sectors_per_fat:        dw 9            ; 9 sectors per FAT.
bdb_sectors_per_track:      dw 18           ; Floppy geometry: 18 sectors/track.
bdb_heads:                  dw 2            ; Double-sided floppy.
bdb_hidden_sectors:         dd 0            ; No hidden sectors before us.
bdb_large_sector_count:     dd 0            ; Used only when total_sectors == 0.

; --- Extended Boot Record (FAT12/16 variant) ---------------------------------
ebr_drive_number:           db 0            ; 0x00 = floppy, 0x80 = first HDD.
                                            ; This is informational; the BIOS
                                            ; passes the real drive number in
                                            ; DL on entry.
                            db 0            ; Reserved (Windows NT flags).
ebr_signature:              db 29h          ; 0x29 indicates that the next
                                            ; three fields are present.
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; Arbitrary serial number.
ebr_volume_label:           db 'NANOBYTE OS'        ; 11 bytes, space-padded.
ebr_system_id:              db 'FAT12   '           ; 8 bytes, space-padded.

; =============================================================================
; Code
; =============================================================================

; -----------------------------------------------------------------------------
; main — bootloader entry point.
; -----------------------------------------------------------------------------
start:
    ; --- Initialise the data segments ----------------------------------------
    ; Real-mode segment registers can't take immediates, so we route through
    ; AX. Zeroing DS and ES means any `[label]` access uses 0000:offset, and
    ; `offset` is already biased by `org 0x7C00`, so addresses Just Work.
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; --- Set up the stack ----------------------------------------------------
    ; The stack grows *downward*. Putting SP at 0x7C00 means the first push
    ; lands at 0x7BFE — i.e. just below us, in the free region from 0x500
    ; to 0x7BFF. We won't accidentally overwrite our own code unless the
    ; stack uses more than ~30 KB, which it won't.
    mov ss, ax
    mov sp, 0x7C00

    ; --- Normalise CS:IP -----------------------------------------------------
    ; A physical address like 0x07C00 can be expressed as either 0000:7C00
    ; or 07C0:0000 (segment * 16 + offset is the same). Some buggy BIOSes
    ; pick the latter, which would break our `org 0x7C00` assumption. We
    ; force the canonical form by doing a far return: pushing ES (0) as
    ; the new CS, and the address of `.after` as the new IP, then `retf`
    ; pops both into CS:IP at once. After this, we're guaranteed to be
    ; running with CS=0.
    push es
    push word .after
    retf

.after:

    ; --- Read something from the floppy --------------------------------------
    ; BIOS sets DL to the boot drive number on entry; stash it for later use
    ; (and so disk_reset can find it via [ebr_drive_number] if we ever pass
    ; the drive number through memory instead of DL).
    mov [ebr_drive_number], dl

    ; --- Print greeting ------------------------------------------------------
    mov si, msg_loading
    call puts

    ; --- Ask the BIOS for the real disk geometry -----------------------------
    ; The BPB above contains the geometry the disk was *formatted* with,
    ; but a USB stick or a disk image emulated as a floppy might have
    ; different real geometry. INT 13h / AH=08h returns the actual values:
    ;   on success: CL[0..5]=sectors/track, CL[6..7]+CH=cylinders,
    ;               DH=last head index (i.e. heads-1), DL=drive count
    ; The call also clobbers ES:DI, so we save ES on the stack first.
    push es
    mov ah, 08h
    int 13h
    jc floppy_error                     ; CF set on error → bail out.
    pop es

    and cl, 0x3F                        ; Mask off the top 2 cylinder bits;
                                        ; the bottom 6 are the sectors/track.
    xor ch, ch                          ; Zero CH so CX = sectors/track.
    mov [bdb_sectors_per_track], cx     ; Patch the BPB with the real value.

    inc dh                              ; DH was max-head-index → heads = DH+1.
    mov [bdb_heads], dh                 ; Patch the BPB with the real value.

    ; --- Find the FAT12 root directory ---------------------------------------
    ; FAT12 disk layout:
    ;     [reserved sectors] [FAT #1] [FAT #2] [root dir] [data area]
    ; So the LBA (linear sector index) of the root directory is:
    ;     reserved_sectors + (fat_count * sectors_per_fat)
    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh                          ; BX = fat_count (zero-extended).
    mul bx                              ; DX:AX = fat_count * sectors_per_fat.
    add ax, [bdb_reserved_sectors]      ; AX = LBA of root directory.
    push ax                             ; Stash it; we need it again later.

    ; --- How many sectors does the root directory occupy? --------------------
    ; Each directory entry is exactly 32 bytes. Total bytes = 32 * entries.
    ; Then divide by bytes/sector (rounding *up*) to get the sector count.
    mov ax, [bdb_dir_entries_count]
    shl ax, 5                           ; AX *= 32 (shift left 5 = multiply by 32).
    xor dx, dx                          ; Zero DX for the 32-bit dividend DX:AX.
    div word [bdb_bytes_per_sector]     ; AX = total / bytes_per_sector,
                                        ; DX = remainder.

    test dx, dx                         ; If the division wasn't exact …
    jz .root_dir_after
    inc ax                              ; … round up so we read the partial
                                        ; final sector too.

.root_dir_after:

    ; --- Read the root directory into our scratch buffer ---------------------
    mov cl, al                          ; CL = sectors to read (computed above).
    pop ax                              ; AX = LBA of root directory (saved earlier).
    mov dl, [ebr_drive_number]          ; DL = drive number we stashed at entry.
    mov bx, buffer                      ; ES:BX = where to put the data
                                        ; (`buffer` lives just past our 512 bytes).
    call disk_read

    ; --- Walk the directory looking for "KERNEL  BIN" ------------------------
    ; FAT-style directory entries store the filename as 8 chars + 3 chars,
    ; space-padded, with no dot. So "kernel.bin" is the 11 bytes
    ; 'K','E','R','N','E','L',' ',' ','B','I','N'. We compare each entry's
    ; first 11 bytes against `file_kernel_bin` until we find a match.
    xor bx, bx                          ; BX = entry counter (0, 1, 2, …).
    mov di, buffer                      ; DI = pointer into the directory.

.search_kernel:
    mov si, file_kernel_bin             ; SI = expected filename.
    mov cx, 11                          ; Compare up to 11 bytes.
    push di                             ; `cmpsb` advances DI; save it so we
                                        ; can recover the entry start address.
    repe cmpsb                          ; "Repeat while equal, compare bytes":
                                        ; compares [DS:SI] vs [ES:DI], advancing
                                        ; both, until either CX=0 or the bytes
                                        ; differ. ZF=1 means all 11 matched.
    pop di
    je .found_kernel                    ; ZF=1 → we found it.

    add di, 32                          ; Otherwise step to the next 32-byte entry.
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_kernel                   ; Keep looking until we run out of entries.

    ; Fell through the loop without finding the file.
    jmp kernel_not_found_error

.found_kernel:
    ; DI points at the matching directory entry. Inside a FAT directory
    ; entry, byte offset 26 is a 16-bit field giving the *first cluster*
    ; of the file's data — the head of a linked list we'll walk through
    ; the FAT to find every cluster the file occupies.
    mov ax, [di + 26]
    mov [kernel_cluster], ax

    ; --- Load the FAT itself into our scratch buffer -------------------------
    ; The FAT lives right after the reserved sectors (one of which is us).
    ; We load it so we can chase the kernel's cluster chain.
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    ; --- Read each cluster of kernel.bin into 0x2000:0000 --------------------
    ; ES:BX is where the next cluster will land. We start at
    ; KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET (= 0x2000:0000) and bump BX
    ; by one sector after each read so successive clusters are contiguous
    ; in memory.
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    ; Convert cluster number → LBA. For FAT12, the data area starts after
    ; the reserved sectors + both FATs + the root directory, and clusters
    ; are numbered starting from 2 (clusters 0 and 1 are reserved). For
    ; this specific 1.44 MB layout that simplifies to LBA = cluster + 31.
    ; (Yes, this is hardcoded — fine for a tutorial bootloader.)
    mov ax, [kernel_cluster]
    add ax, 31                          ; cluster N → LBA N+31.

    mov cl, 1                           ; Read exactly one sector (=1 cluster here).
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]      ; Advance the destination pointer.

    ; --- Look up the next cluster in the FAT ---------------------------------
    ; FAT12 packs two 12-bit entries into every 3 bytes. To find the byte
    ; offset of entry N inside the FAT, we compute N * 3 / 2.
    ;   * The quotient is the byte offset to the pair of entries.
    ;   * The remainder tells us which of the two we want:
    ;       0 → the "even" (low) 12 bits of the 16-bit word at that offset
    ;       1 → the "odd"  (high) 12 bits — i.e. shift right by 4.
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx                              ; AX = cluster * 3.
    mov cx, 2
    div cx                              ; AX = (cluster*3)/2, DX = (cluster*3)%2.

    mov si, buffer
    add si, ax                          ; SI = address of the 16-bit word
                                        ; covering our 12-bit entry.
    mov ax, [ds:si]

.odd:
    shr ax, 4                           ; Odd entry: take the upper 12 bits.

.even:
    and ax, 0x0FFF                      ; Even entry: take the lower 12 bits.
                                        ; (Both labels run unconditionally —
                                        ; the original tutorial keeps it this
                                        ; way; the upper-12-then-lower-12 mask
                                        ; happens to be a no-op for an odd
                                        ; entry once shifted, and the AND
                                        ; trims the unused 4 bits for even
                                        ; entries.)

.next_cluster_after:
    cmp ax, 0x0FF8                      ; FAT12 end-of-chain markers are
                                        ; 0x0FF8..0x0FFF. If we hit one,
                                        ; we've read the whole file.
    jae .read_finish

    mov [kernel_cluster], ax            ; Otherwise loop with the next cluster.

.read_finish:
    ; --- Hand control to the kernel ------------------------------------------
    mov dl, [ebr_drive_number]          ; Convention: pass boot device in DL.

    ; Point DS and ES at the kernel's segment so its `org 0x0` data
    ; references resolve correctly.
    mov ax, KERNEL_LOAD_SEGMENT
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET
                                        ; Far jump: sets CS:IP to
                                        ; 0x2000:0x0000 and starts executing
                                        ; the kernel we just loaded.

    jmp wait_key_and_reboot             ; (Defensive — we never get here if
                                        ; the kernel jump succeeded.)


    ; --- Halt ----------------------------------------------------------------
    cli                     ; Disable interrupts so we can't get woken out of
    hlt                     ; the halt state.

; =============================================================================
; Error handlers
; =============================================================================
; Each handler prints a message and then waits for the user to press a key
; before rebooting the machine. We can't really recover from a disk error
; here — there's nowhere to log to and no other code to fall back on.
; =============================================================================

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

kernel_not_found_error:
    mov si, msg_kernel_not_found
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0               ; INT 16h / AH=00h: wait for a keystroke.
    int 16h
    jmp 0FFFFh:0            ; Far jump to physical address 0xFFFF0, which
                            ; is the CPU's reset vector. The BIOS sits there
                            ; with the same code it ran at power-on, so this
                            ; effectively warm-reboots the machine.

.halt:
    cli                     ; Disable interrupts so nothing can wake us …
    hlt                     ; … from the halt state.

; -----------------------------------------------------------------------------
; puts — print a NUL-terminated string via BIOS INT 10h, AH=0Eh.
;
;   In:    DS:SI -> string
;   Out:   nothing
;   Saves: SI, AX, BX
; -----------------------------------------------------------------------------
puts:
    push si             ; Preserve caller's registers — we clobber SI, AX, BX.
    push ax
    push bx

.loop:
    lodsb               ; AL = [DS:SI]; SI++. (Assumes DF is clear, which the
                        ; BIOS guarantees on entry.)
    or al, al           ; Test for the NUL terminator. `or al, al` is one byte
                        ; shorter than `cmp al, 0` and sets ZF the same way.
    jz .done

    mov ah, 0x0E        ; INT 10h / AH=0Eh: teletype output. Prints the
                        ; character in AL and advances the cursor; honours
                        ; CR (0x0D), LF (0x0A), BS (0x08), and BEL (0x07).
    mov bh, 0           ; BH = video page number (page 0).
    int 0x10            ; Call BIOS video service.

    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret

;
; Disk routines
;

; -----------------------------------------------------------------------------
; lba_to_chs — convert an LBA address to a CHS triple.
;
;   In:    AX = LBA address
;   Out:   CX[0..5]  = sector number
;          CX[6..15] = cylinder
;          DH        = head
;          DL        = drive number (preserved)
; -----------------------------------------------------------------------------
lba_to_chs:
    push ax
    push dx

    xor dx, dx                          ; DX = 0 for the 32-bit dividend.
    div word [bdb_sectors_per_track]    ; AX = LBA / SectorsPerTrack
                                        ; DX = LBA % SectorsPerTrack
    inc dx                              ; Sector numbers are 1-based.
    mov cx, dx                          ; CX[0..5] = sector.

    xor dx, dx                          ; DX = 0 again.
    div word [bdb_heads]                ; AX = (LBA / SPT) / Heads = cylinder
                                        ; DX = (LBA / SPT) % Heads = head
    mov dh, dl                          ; DH = head.
    mov ch, al                          ; CH = low 8 bits of cylinder.
    shl ah, 6
    or cl, ah                           ; CL[6..7] = high 2 bits of cylinder.

    pop ax                              ; AX = original DX (saved earlier).
    mov dl, al                          ; Restore DL (drive number); DH stays.
    pop ax                              ; Restore the original AX.
    ret

; -----------------------------------------------------------------------------
; disk_read — read sectors from a disk via INT 13h / AH=02h.
;
;   In:    AX     = LBA address
;          CL     = number of sectors to read (up to 128)
;          DL     = drive number
;          ES:BX  = destination buffer
;   Out:   carry clear on success; jumps to floppy_error on failure.
; -----------------------------------------------------------------------------
disk_read:
    push ax                             ; Save registers we'll modify.
    push bx
    push cx
    push dx
    push di

    push cx                             ; Stash CL (sector count) — lba_to_chs
                                        ; will overwrite CX with CHS data.
    call lba_to_chs                     ; Compute CHS from LBA in AX.
    pop ax                              ; AL = number of sectors to read.

    mov ah, 02h                         ; INT 13h / AH=02h: read sectors.
    mov di, 3                           ; Retry up to 3 times.

.retry:
    pusha                               ; BIOS may clobber anything; save all.
    stc                                 ; Some buggy BIOSes don't set CF on
                                        ; failure — pre-set it so JNC works.
    int 13h
    jnc .done                           ; CF clear = success.

    ; Read failed — reset the controller and retry.
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    ; All attempts exhausted.
    jmp floppy_error

.done:
    popa                                ; Match the pusha at .retry.

    pop di                              ; Restore registers modified above.
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; -----------------------------------------------------------------------------
; disk_reset — reset the disk controller via INT 13h / AH=00h.
;
; If a read fails, the controller may be in a confused state and need a
; reset before a retry has any chance of succeeding. This routine performs
; that reset for the drive in DL.
;
;   In:    DL = drive number
; -----------------------------------------------------------------------------
disk_reset:
    pusha               ; Save every general-purpose register; the BIOS
                        ; can clobber them.
    mov ah, 0           ; Function 0 = reset disk system.
    stc                 ; Pre-set CF (some BIOSes don't clear it on success
                        ; reliably, so we don't trust its initial value).
    int 13h
    jc floppy_error     ; Couldn't even reset → give up.
    popa
    ret

; =============================================================================
; Data
; =============================================================================
msg_loading:            db 'Loading...', ENDL, 0
msg_read_failed:        db 'Read from disk fail!', ENDL, 0
file_kernel_bin:        db 'STAGE2  BIN'
msg_kernel_not_found:   db 'STAGE2.BIN file not found!', ENDL, 0
kernel_cluster:         dw 0

KERNEL_LOAD_SEGMENT     equ 0x2000
KERNEL_LOAD_OFFSET      equ 0

; =============================================================================
; Boot signature
; =============================================================================
; The BIOS only treats a sector as bootable if its final two bytes are
; 0x55 0xAA. We pad with zeros up to offset 510, then emit the signature
; as a little-endian word so the on-disk bytes are 55 AA.
; =============================================================================

times 510-($-$$) db 0   ; Zero-fill up to byte 510. ($-$$) = current offset
                        ; from the start of the section.
dw 0xAA55               ; Boot sector signature.

buffer: