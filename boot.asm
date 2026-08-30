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

gdt_start:

gdt_null:
    ; 8 bytes, all zero (the null descriptor)
    times 8 db 0

gdt_code:
    dw 0xFFFF       ; limit bits 0-15  (limit is 0xFFFFF, low 16 bits = 0xFFFF)
    dw 0x0000       ; base bits 0-15   (base is 0, so this is 0)
    db 0x00         ; base bits 16-23  (still 0)
    db 0x9A         ; access byte
    db 0xCF         ; flags (top nibble 0xC) + limit bits 16-19 (bottom nibble 0xF)
    db 0x00         ; base bits 24-31  (still 0)

gdt_data:
    ; same as gdt_code but access byte 0x92
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92
    db 0xCF
    db 0x00

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1   ; size of GDT, always one less than true size
    dd gdt_start                 ; start address of the GDT

hang:
    jmp $

message: db "Hello, World!", 0

times 510-($-$$) db 0
dw 0xAA55
