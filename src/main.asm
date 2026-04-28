org 0x7C00      ; The BIOS loads our bootloader to this exact memory address (0x7C00)
bits 16         ; We are writing 16-bit real-mode code

%define ENDL 0x0D, 0x0A     ; Define newline: Carriage Return (0x0D) + Line Feed (0x0A)

start:
    jmp main                ; Jump to the main label (skips over the puts function)

; =============================================================
; puts - Print a null-terminated string to the screen
; Input:  DS:SI = pointer to the string to print
; =============================================================
puts:
    push si                 ; Save SI register (we will modify it)
    push ax                 ; Save AX register (we will modify it)

.loop:
    lodsb                   ; Load byte from DS:SI into AL and increment SI
    or al, al               ; Check if AL == 0 (null terminator)
    jz .done                ; If it's the end of string, exit the function

    ; Call BIOS teletype function to print the character in AL
    mov ah, 0x0E            ; AH = 0x0E → BIOS "teletype" output function
    mov bh, 0               ; BH = 0 → video page number (usually 0)
    int 0x10                ; Call BIOS video interrupt

    jmp .loop               ; Repeat for next character

.done:
    pop ax                  ; Restore original AX
    pop si                  ; Restore original SI
    ret                     ; Return from function

; =============================================================
main:
    ; ------------------- Initialize Segment Registers -------------------
    ; In real mode, segment registers cannot be set directly with immediate values.
    mov ax, 0               ; AX = 0
    mov ds, ax              ; DS = 0  (Data Segment)
    mov es, ax              ; ES = 0  (Extra Segment)

    ; ------------------- Setup Stack -------------------
    ; Stack is needed for push/pop and function calls
    mov ss, ax              ; SS = 0  (Stack Segment)
    mov sp, 0x7C00          ; SP = 0x7C00 → Stack starts right below our bootloader
                            ; Stack grows downward, so this is safe.

    ; ------------------- Print Message -------------------
    mov si, msg_hello       ; SI = address of our message
    call puts               ; Call the puts function to print "Hello world!"

    ; ------------------- Halt the CPU -------------------
    hlt                     ; Halt the CPU (stops execution until an interrupt occurs)

.halt:
    jmp .halt               ; Infinite loop - safety net in case CPU wakes up from HLT


; =============================================================
; Data Section
; =============================================================
msg_hello: db 'Hello world!', ENDL, 0
; The string "Hello world!" followed by newline and null terminator (0)


; ------------------- Boot Sector Signature -------------------
times 510-($-$$) db 0   ; Pad with zeros up to byte 510
                        ; ($-$$) = current position - start of file

dw 0xAA55               ; Boot signature (must be at bytes 510-511)
                        ; On disk it appears as 55 AA
                        ; BIOS requires this to consider the sector bootable
                        