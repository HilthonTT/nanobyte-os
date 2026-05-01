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

start:
    jmp main            ; Skip the helper routines to the real entry point.

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

; -----------------------------------------------------------------------------
; main — bootloader entry point.
; -----------------------------------------------------------------------------
main:
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

    ; --- Read something from the floppy --------------------------------------
    ; BIOS sets DL to the boot drive number on entry; stash it for later use
    ; (and so disk_reset can find it via [ebr_drive_number] if we ever pass
    ; the drive number through memory instead of DL).
    mov [ebr_drive_number], dl

    mov ax, 1               ; LBA = 1, second sector from disk.
    mov cl, 1               ; 1 sector to read.
    mov bx, 0x7E00          ; Destination = right after the bootloader.
    call disk_read

    ; --- Print greeting ------------------------------------------------------
    mov si, msg_hello
    call puts

    ; --- Halt ----------------------------------------------------------------
    cli                     ; Disable interrupts so we can't get woken out of
    hlt                     ; the halt state.

;
; Error handlers
;
floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h                 ; Wait for keypress.
    jmp 0FFFFh:0            ; Far jump to BIOS reset vector — reboots.

.halt:
    cli                     ; Disable interrupts so we can't get woken out of
    hlt                     ; the halt state.

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
;   In:    DL = drive number
; -----------------------------------------------------------------------------
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

; =============================================================================
; Data
; =============================================================================
msg_hello:          db 'Hello world!', ENDL, 0
msg_read_failed:    db 'Read from disk fail!', ENDL, 0

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
