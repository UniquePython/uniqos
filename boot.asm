; ============================================================================
; Simple 16-bit boot sector -> 32-bit protected mode code
; ============================================================================
;
; This program is exactly one 512-byte boot sector.
;
; The BIOS loads the sector at physical address 0x7C00 and jumps to it.
; We begin in 16-bit real mode, print a message using the BIOS, then switch
; the CPU into 32-bit protected mode and write directly to VGA text memory.
;
; Memory layout:
;
;   0x7C00  -> boot sector loaded by the BIOS
;   0x90000 -> stack used while in real mode
;   0xB8000 -> VGA text-mode video memory
;
; The GDT contains:
;
;   selector 0x00 -> null descriptor
;   selector 0x08 -> 32-bit code segment
;   selector 0x10 -> 32-bit data segment
;
; ============================================================================


bits 16
org 0x7C00


; ============================================================================
; REAL MODE
; ============================================================================

start:
    ; Clear AX so we can use it to initialize the segment registers.
    xor ax, ax

    ; Point DS at physical address 0x00000.
    ; This lets labels in our boot sector resolve normally with ORG 0x7C00.
    mov ds, ax

    ; Point ES at physical address 0x00000 as well.
    ; We are not using ES yet, but initializing it keeps the environment sane.
    mov es, ax

    ; Set the real-mode stack segment to zero.
    ; The stack will therefore live in the first 64 KiB of memory.
    mov ss, ax

    ; Set SP to 0x9000.
    ; With SS = 0, the stack begins around physical address 0x9000.
    mov sp, 0x9000

    ; Disable interrupts while we finish setting up the boot environment.
    ; We do not want an interrupt occurring while the stack or CPU state is
    ; being changed.
    cli

    ; Save the BIOS-provided boot drive number.
    ; BIOS places the boot drive in DL when it enters the boot sector.
    mov [boot_drive], dl

    ; Enable the A20 address line.
    ; Without A20, addresses above 1 MiB can wrap around on old hardware.
    call enable_a20

    ; Put the address of our message into SI.
    ; print_string will use SI to walk through the string one byte at a time.
    mov si, message

    ; Print the message while we are still in real mode.
    ; BIOS interrupt 0x10 is only being used before protected mode is enabled.
    call print_string

    ; Load the Global Descriptor Table.
    ; The CPU needs a GDT before protected-mode segment selectors can be used.
    lgdt [gdt_descriptor]

    ; Disable interrupts before changing CR0.
    ; Once protected mode is enabled, the existing real-mode interrupt handlers
    ; are no longer safe to call.
    cli

    ; Read the current value of CR0 into EAX.
    ; CR0 contains the CPU's control flags, including the protection-enable bit.
    mov eax, cr0

    ; Set bit 0 of CR0.
    ; Bit 0 is PE (Protection Enable), which tells the CPU to enter protected
    ; mode after the next far control transfer.
    or eax, 1

    ; Write the modified control register back to CR0.
    ; Protected mode is now enabled.
    mov cr0, eax

    ; Perform a far jump using our 32-bit code-segment selector.
    ; This does two important things:
    ;
    ;   1. Loads CS with the protected-mode code selector.
    ;   2. Flushes the CPU's instruction prefetch queue.
    ;
    ; The target label is assembled as 32-bit code because of "bits 32" below.
    jmp CODE_SEG:protected_mode_start


; ============================================================================
; BIOS STRING PRINTING
; ============================================================================

print_string:
    ; Load the next character from the string into AL.
    mov al, [si]

    ; Check whether AL contains the null terminator.
    ; A zero byte marks the end of our string.
    test al, al

    ; If AL is zero, the complete string has been printed.
    jz .done

    ; BIOS video services use AH = 0x0E for teletype output.
    mov ah, 0x0E

    ; Ask the BIOS to display the character currently stored in AL.
    int 0x10

    ; Move SI to the next character in the string.
    inc si

    ; Go back and process the next character.
    jmp print_string

.done:
    ; Return to the caller once the null terminator is reached.
    ret


; ============================================================================
; A20 LINE
; ============================================================================

enable_a20:
    ; Read the current value of the keyboard-controller "Fast A20" port.
    ; Port 0x92 is commonly supported by PC-compatible systems and emulators.
    in al, 0x92

    ; Check bit 1.
    ; If bit 1 is already set, the A20 line is already enabled.
    test al, 00000010b

    ; Skip the rest if A20 is already enabled.
    jnz .done

    ; Set bit 1 to enable the A20 line.
    or al, 00000010b

    ; Clear bit 0.
    ; On many systems bit 0 is the system reset control, so we must avoid
    ; accidentally triggering a reset.
    and al, 11111110b

    ; Write the modified value back to port 0x92.
    out 0x92, al

.done:
    ; Return to the caller.
    ret


; ============================================================================
; GLOBAL DESCRIPTOR TABLE
; ============================================================================

gdt_start:

gdt_null:
    ; The first GDT entry must be completely zero.
    ; A selector pointing to this descriptor is considered the null selector.
    times 8 db 0


gdt_code:
    ; Limit bits 0-15.
    ; The final limit is 0xFFFFF, giving us a 4 GiB segment when combined
    ; with 4 KiB granularity.
    dw 0xFFFF

    ; Base bits 0-15.
    ; Our protected-mode code segment starts at physical address 0.
    dw 0x0000

    ; Base bits 16-23.
    ; The base address is still zero.
    db 0x00

    ; Access byte:
    ;
    ;   1  = segment is present
    ;   00 = descriptor privilege level 0
    ;   1  = descriptor is executable/code
    ;   0  = descriptor type is code/data
    ;   1  = code segment can be read
    ;   0  = accessed bit initially clear
    ;
    ; This gives us 0x9A.
    db 10011010b

    ; Flags and limit bits 16-19:
    ;
    ;   1100 = 4 KiB granularity + 32-bit default operand size
    ;   1111 = upper four bits of the segment limit
    ;
    ; This gives us 0xCF.
    db 11001111b

    ; Base bits 24-31.
    ; The base address remains zero.
    db 0x00


gdt_data:
    ; Limit bits 0-15.
    dw 0xFFFF

    ; Base bits 0-15.
    dw 0x0000

    ; Base bits 16-23.
    db 0x00

    ; Access byte for a normal writable data segment.
    ;
    ; 0x92 means:
    ;   present + ring 0 + data segment + writable
    db 10010010b

    ; 32-bit segment + 4 KiB granularity + upper limit bits.
    db 11001111b

    ; Base bits 24-31.
    db 0x00


gdt_end:


; ============================================================================
; GDT DESCRIPTOR
; ============================================================================

gdt_descriptor:
    ; GDTR.limit contains the size of the GDT minus one.
    ; The CPU expects the last valid byte offset here, not the total size.
    dw gdt_end - gdt_start - 1

    ; GDTR.base contains the linear address of the first byte of the GDT.
    dd gdt_start


; ============================================================================
; 32-BIT PROTECTED MODE
; ============================================================================

bits 32

protected_mode_start:

    ; Load the data-segment selector into AX.
    ; Segment-register loads cannot directly use an immediate value, so we
    ; first place the selector into a general-purpose register.
    mov ax, DATA_SEG

    ; Load the protected-mode data segment into DS.
    mov ds, ax

    ; Load the same data segment into ES.
    mov es, ax

    ; Load the same data segment into FS.
    mov fs, ax

    ; Load the same data segment into GS.
    mov gs, ax

    ; Load the same data segment into SS.
    ; SS must also refer to a valid protected-mode data segment before using
    ; the protected-mode stack.
    mov ss, ax

    ; Set up a 32-bit stack.
    ; ESP points somewhere safely below the boot sector and GDT.
    mov esp, 0x90000

    ; Clear the direction flag.
    ; This makes string instructions such as MOVSB increment their pointers.
    cld

    ; Write the character 'P' directly into VGA text memory.
    ;
    ; VGA text memory starts at physical address 0xB8000.
    ; The first screen character occupies two bytes:
    ;
    ;   byte 0 = character
    ;   byte 1 = color attribute
    ;
    ; Because our data segment has a base of zero, [0xB8000] refers directly
    ; to physical address 0xB8000.
    mov byte [0xB8000], 'P'

    ; Set the character's color attribute.
    ;
    ; 0x0F = bright white foreground on a black background.
    mov byte [0xB8001], 0x0F

    ; Write another character to the second screen position.
    mov byte [0xB8002], 'M'

    ; Give the second character the same color.
    mov byte [0xB8003], 0x0F

    ; Write a third character to the screen.
    mov byte [0xB8004], '!'
    
    ; Give the third character the same color.
    mov byte [0xB8005], 0x0F

    ; Disable interrupts permanently.
    ; We have no protected-mode interrupt descriptor table (IDT), so handling
    ; interrupts here would not be safe.
    cli

.hang:
    ; Halt the CPU until an interrupt occurs.
    ; Interrupts are disabled, so this effectively stops execution.
    hlt

    ; Keep the CPU here even on systems where HLT unexpectedly resumes.
    jmp .hang


; ============================================================================
; CONSTANTS
; ============================================================================

; A GDT selector is simply the byte offset of a descriptor inside the GDT.
;
; gdt_code - gdt_start = 8, so CODE_SEG = 0x08.
CODE_SEG equ gdt_code - gdt_start

; gdt_data - gdt_start = 16, so DATA_SEG = 0x10.
DATA_SEG equ gdt_data - gdt_start


; ============================================================================
; DATA
; ============================================================================

message:
    ; String printed by the BIOS before entering protected mode.
    ; The final zero is the null terminator used by print_string.
    db "Entering protected mode...", 0

boot_drive:
    ; One byte reserved for the BIOS boot-drive number.
    ; We save DL here even though this code does not need the value later.
    db 0


; ============================================================================
; BOOT SECTOR SIGNATURE
; ============================================================================

; Fill all remaining bytes with zero until byte 510.
; The BIOS requires the boot signature to occupy bytes 510-511.
times 510 - ($ - $$) db 0

; Standard boot-sector signature.
; BIOS recognizes 0xAA55 as a valid bootable sector signature.
dw 0xAA55
