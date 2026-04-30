org 0x7C00              ; Tell NASM the code will be loaded at 0x7C00 so that
                        ; label addresses are computed correctly. Without
                        ; this, every `mov si, msg_hello` would point into
                        ; the wrong part of memory.
bits 16                 ; Emit 16-bit instruction encodings (real mode).

%define ENDL 0x0D, 0x0A ; CRLF. The BIOS teletype service handles 0x0D
                        ; (carriage return) and 0x0A (line feed) the way
                        ; you'd expect a serial terminal to.

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

    ; --- Print greeting ------------------------------------------------------
    mov si, msg_hello
    call puts

    ; --- Halt ----------------------------------------------------------------
    hlt                 ; Park the CPU until the next interrupt.

.halt:
    jmp .halt           ; If we *do* get woken (e.g. timer tick), loop here
                        ; forever instead of falling through into garbage.

; =============================================================================
; Data
; =============================================================================
msg_hello:  db 'Hello world!', ENDL, 0

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
