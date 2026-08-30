bits 16
org 0x7C00

start:
    ; set up segment registers
    xor ax, ax ; zero out a general-purpose register
    mov ds, ax ; zero out ds
    mov es, ax ; zero out es

    mov si, message   ; SI will walk through the string, byte by byte

print_loop:
    mov al, [si] ; load the byte SI points to into al
    cmp al, 0 ; is it the null terminator (0)?
    jz hang ;  if so, jump to the hang label

    ; otherwise, print al
    mov ah, 0x0e
    int 0x10

    ; advance si to the next byte
    inc si
    ; jump back to print_loop
    jmp print_loop

hang:
    jmp $

message: db "Hello, World!", 0

times 510-($-$$) db 0
dw 0xAA55
