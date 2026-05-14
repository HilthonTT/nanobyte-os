; =============================================================================
; nanobyte-os kernel (stage 2)
; =============================================================================
; This file is the second program that runs on the machine. The bootloader
; (src/bootloader/boot.asm) reads this binary off the floppy disk and jumps
; to it. By the time we get here:
;
;   * The CPU is still in 16-bit real mode.
;   * The bootloader has already initialised DS, ES, SS and SP for us, and
;     loaded this kernel at segment KERNEL_LOAD_SEGMENT (0x2000), offset 0.
;   * BIOS interrupts (INT 10h for video, INT 16h for keyboard, etc.) are
;     still available because we have not switched to protected mode yet.
;
; This stage is intentionally tiny: it just prints a "hello" message and
; halts. It exists so we can confirm the bootloader → kernel handoff works
; before we start adding real functionality.
; =============================================================================

org 0x0                 ; The bootloader jumps to KERNEL_LOAD_SEGMENT:0x0000,
                        ; meaning the *offset* part of every label inside this
                        ; file should start counting from zero. `org 0x0`
                        ; tells NASM to compute label addresses with that
                        ; assumption — so `mov si, msg_hello` will produce
                        ; the right offset relative to our segment.

bits 16                 ; Generate 16-bit machine code. We're in real mode,
                        ; so registers are 16-bit and pointers are seg:offset.

%define ENDL 0x0D, 0x0A ; A handy macro for "end of line". 0x0D is carriage
                        ; return, 0x0A is line feed. The BIOS teletype
                        ; service treats this pair the same way a classic
                        ; serial terminal would: move to column 0, then
                        ; move down one line.

; -----------------------------------------------------------------------------
; start — kernel entry point. Execution begins here because this is the very
; first byte of the file (and the bootloader jumps to offset 0).
; -----------------------------------------------------------------------------
start:
    ; Print our greeting. By convention `puts` expects DS:SI to point at a
    ; NUL-terminated string, so we load the address of msg_hello into SI
    ; and then call the routine.
    mov si, msg_hello
    call puts

.halt:
    cli                 ; Clear the Interrupt Flag — from now on the CPU
                        ; will ignore maskable hardware interrupts. Without
                        ; this, a stray timer tick could wake us up.
    hlt                 ; Halt the CPU. It will sit in a low-power state
                        ; until the next interrupt — and because we just
                        ; disabled interrupts, that effectively means
                        ; "forever".

; -----------------------------------------------------------------------------
; puts — print a NUL-terminated string using the BIOS teletype service.
;
;   Inputs:   DS:SI -> first character of the string
;   Outputs:  none
;   Clobbers: nothing visible to the caller (we save and restore everything
;             we touch)
;
; This is the same routine as in the bootloader. We duplicate it here
; because the kernel is a separate binary and can't call into the
; bootloader's code once we've jumped away from it.
; -----------------------------------------------------------------------------
puts:
    ; Save the registers we are about to overwrite. The caller doesn't
    ; expect us to change them, so we push their current values onto the
    ; stack and pop them back at the end.
    push si
    push ax
    push bx

.loop:
    lodsb               ; "Load string byte": copies the byte at DS:SI into
                        ; AL, then increments SI. Equivalent to:
                        ;     mov al, [ds:si]
                        ;     inc si
                        ; (The CPU's Direction Flag controls whether SI is
                        ; incremented or decremented; the BIOS guarantees
                        ; DF=0 on entry, so we get the increment we want.)

    or al, al           ; Bitwise-OR a register with itself doesn't change
                        ; its value, but it *does* update the flags — in
                        ; particular, ZF (Zero Flag) gets set when AL is 0.
                        ; This is a one-byte-shorter way of writing
                        ; `cmp al, 0`.
    jz .done            ; If AL is zero, we hit the NUL terminator — stop.

    ; --- Print the character in AL via INT 10h, AH=0Eh -----------------------
    ; The BIOS exposes a "video services" interrupt at vector 0x10. With
    ; AH=0x0E, it acts like a teletype: it prints the character in AL and
    ; advances the cursor, handling CR (0x0D), LF (0x0A), backspace (0x08),
    ; and bell (0x07) on the way.
    mov ah, 0x0E        ; Function number: teletype output.
    mov bh, 0           ; Video page number — 0 is the active page.
    int 0x10            ; Trigger the BIOS video service.

    jmp .loop           ; Move on to the next character.

.done:
    ; Restore the caller's registers in reverse order from how we saved
    ; them — stacks are LIFO, so the last push is the first pop.
    pop bx
    pop ax
    pop si
    ret                 ; Return to whoever called us.

; -----------------------------------------------------------------------------
; Data
; -----------------------------------------------------------------------------
msg_hello: db 'Hello world from KERNEL!', ENDL, 0
                        ; `db` = "define byte(s)". This emits the literal
                        ; text, followed by CR/LF, followed by a 0 byte
                        ; that acts as the NUL terminator `puts` looks for.
