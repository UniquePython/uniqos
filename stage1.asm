; ============================================================================
; Stage 1 bootloader
; ============================================================================
;
; BIOS loads this file at physical address 0x7C00 and starts execution there.
;
; Stage 1 has one job:
;
;   1. Set up a small real-mode environment.
;   2. Remember which disk BIOS booted us from.
;   3. Read Stage 2 from the sectors immediately following this boot sector.
;   4. Jump to Stage 2.
;
; Disk layout:
;
;   sector 1  -> Stage 1 / this bootloader
;   sector 2+ -> Stage 2
;
; Stage 2 is loaded at physical address 0x10000.
;
; ============================================================================


bits 16
org 0x7C00


; ============================================================================
; REAL MODE ENTRY
; ============================================================================

start:
    ; Disable interrupts while we initialize the segment registers and stack.
    ; We want the CPU to have a predictable environment before doing anything
    ; else.
    cli

    ; Clear AX so we can use it to initialize DS, ES, and SS.
    xor ax, ax

    ; Set DS to zero.
    ; With ORG 0x7C00, labels in this file can be accessed using offsets
    ; relative to the zero-based segment.
    mov ds, ax

    ; Set ES to zero.
    ; ES will later be changed to 0x1000 when loading Stage 2.
    mov es, ax

    ; Set SS to zero.
    ; This places the stack in the first 64 KiB of physical memory.
    mov ss, ax

    ; Set the real-mode stack pointer.
    ; SS:SP = 0000:9000, so the stack grows downward from physical address
    ; 0x9000.
    mov sp, 0x9000

    ; Save the boot drive number provided by the BIOS.
    ; BIOS enters the boot sector with DL containing the drive number:
    ;
    ;   0x00 -> first floppy drive
    ;   0x80 -> first hard disk
    ;
    ; We must preserve this because BIOS disk services need the same drive
    ; number when we request Stage 2.
    mov [boot_drive], dl

    ; Display a short debugging message before attempting the disk read.
    mov si, loading_message
    call print_string

    ; Set ES:BX to the physical address where Stage 2 will be loaded.
    ;
    ; We want:
    ;
    ;   physical address = 0x10000
    ;
    ; A 16-bit real-mode segment can represent this as:
    ;
    ;   0x1000 * 16 + 0x0000 = 0x10000
    ;
    ; BX therefore starts at zero because ES already provides the high part
    ; of the physical address.
    mov ax, 0x1000
    mov es, ax
    xor bx, bx

    ; Read Stage 2 from disk.
    ; load_sectors uses a fixed starting CHS address of cylinder 0, head 0,
    ; sector 2 and reads 32 sectors (16 KiB).
    call load_sectors

    ; Stage 2 was loaded at 0x1000:0000.
    ; Transfer control there with a far jump.
    ;
    ; We use JMP instead of CALL because Stage 1 has finished its job and
    ; Stage 2 is not expected to return here.
    jmp 0x1000:0x0000


; ============================================================================
; BIOS STRING PRINTING
; ============================================================================

print_string:
    ; Load the next character from the string into AL.
    mov al, [si]

    ; Check whether AL is the null terminator.
    ; A zero byte marks the end of the string.
    test al, al

    ; Stop printing when the null terminator is reached.
    jz .done

    ; BIOS teletype output uses AH = 0x0E.
    mov ah, 0x0E

    ; Ask BIOS video services to print the character in AL.
    int 0x10

    ; Advance SI to the next character.
    inc si

    ; Process the next character.
    jmp print_string

.done:
    ; Return to the caller once the entire string has been printed.
    ret


; ============================================================================
; DISK LOADING
; ============================================================================

load_sectors:
    ; BIOS interrupt 0x13 function 0x02 reads sectors using CHS addressing.
    ; AH must contain 0x02 when the interrupt is called.
    mov ah, 0x02

    ; Read 32 sectors.
    ; Each sector is 512 bytes, so this loads:
    ;
    ;   32 * 512 = 16384 bytes = 16 KiB
    ;
    ; The caller has already prepared ES:BX with the destination address.
    mov al, 32

    ; Select cylinder 0.
    mov ch, 0

    ; Select sector 2.
    ; CHS sector numbering starts at 1, so sector 2 is immediately after the
    ; boot sector in the disk image.
    mov cl, 2

    ; Select head 0.
    mov dh, 0

    ; Restore the boot drive number supplied by BIOS.
    ; This is important because DL may have been changed by previous BIOS calls.
    mov dl, [boot_drive]

    ; Read the requested sectors into ES:BX.
    ;
    ; On success:
    ;   CF = 0
    ;
    ; On failure:
    ;   CF = 1
    ;
    ; BIOS may also return an error code in AH, but this bootloader only needs
    ; to distinguish success from failure for now.
    int 0x13

    ; Check the carry flag immediately after INT 0x13.
    ; BIOS sets CF when the disk operation failed.
    jc disk_error

    ; Return to the caller after successfully loading Stage 2.
    ret


; ============================================================================
; DISK ERROR
; ============================================================================

disk_error:
    ; Load the address of the disk-error message into SI.
    mov si, disk_error_message

    ; Print the error message using the BIOS teletype routine.
    call print_string

.disk_hang:
    ; Disable interrupts because there is no useful interrupt handling in this
    ; tiny bootloader.
    cli

    ; Halt the CPU until an interrupt occurs.
    ; Since interrupts are disabled, this effectively stops execution.
    hlt

    ; Keep the CPU here if HLT ever resumes for any reason.
    jmp .disk_hang


; ============================================================================
; DATA
; ============================================================================

loading_message:
    ; Message displayed while Stage 2 is being loaded.
    ; The final zero terminates the string for print_string.
    db "Loading Stage 2...", 0


disk_error_message:
    ; Message displayed when BIOS reports a disk-read failure.
    ; This makes a failed INT 0x13 operation immediately recognizable.
    db "DISK ERROR!", 0


boot_drive:
    ; One byte used to preserve the BIOS-provided boot drive number.
    db 0


; ============================================================================
; BOOT SECTOR PADDING AND SIGNATURE
; ============================================================================

; Fill the remaining space with zeroes until byte 510.
; The first stage must occupy exactly one 512-byte sector.
times 510 - ($ - $$) db 0

; Standard BIOS boot signature.
; BIOS expects the bytes 0x55 and 0xAA at offsets 510 and 511.
dw 0xAA55
