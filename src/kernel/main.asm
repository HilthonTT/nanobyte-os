org 0x0
bits 16

%define ENDL 0x0D, 0x0A ; CRLF. The BIOS teletype service handles 0x0D

start:
    ; print hello world message
    mov si, msg_hello
    call puts

.halt:
    cli
    hlt

;
; Print a string to the screen
; Params:
; - ds:si points to a string
;
puts:
    ; save reigsters we will modify
    push si
    push ax
    push bx

.loop:
    lodsb           ; load next character in al
    or al, al       ; verify if next character is null?
    jz .done

    mov ah, 0x0E    ; call bios interrupt
    mov bh, 0
    int 0x10
    
    jmp .loop

.done:
    pop BX
    pop ax
    pop si
    ret

msg_hello: db 'Hello world from KERNEL!', ENDL, 0
