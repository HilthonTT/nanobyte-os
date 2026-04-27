org 0x7C00      ; ORG directive - where we expect our code to be loaded
bits 16         ; BITS directive - emit 16-bit code

main:
    hlt         ; HLT - stops CPU (resumable by interrupt)

.halt:
    jmp .halt   ; JMP - unconditional jump (like goto in C)

times 510-($-$$) db 0   ; pad to 510 bytes
dw 0xAA55               ; boot signature (little-endian: 55 AA on disk)