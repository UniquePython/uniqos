; ============================================================================
; Stage 2 bootloader
; ============================================================================
;
; Stage 1 loads this file into physical address 0x10000 and jumps to:
;
;   0x1000:0x0000
;
; Stage 2 is assembled with ORG 0 because its labels are offsets relative to
; the beginning of the Stage 2 image. The actual runtime address is supplied
; by the segment 0x1000 used by Stage 1.
;
; Therefore:
;
;   physical address = 0x1000 * 16 + label offset
;                    = 0x10000 + label offset
;
; Stage 2 is responsible for:
;
;   1. Establishing a known real-mode environment.
;   2. Enabling the A20 address line.
;   3. Loading the Global Descriptor Table.
;   4. Enabling 32-bit protected mode.
;   5. Reloading the segment registers.
;   6. Setting up a 32-bit stack.
;   7. Writing directly to VGA text memory as proof of life.
;
; Stage 2 does not need a boot signature because BIOS never loads this file
; directly. Stage 1 reads it from disk as ordinary data.
;
; ============================================================================


bits 16
org 0


; ============================================================================
; CONSTANTS
; ============================================================================

; Stage 1 loads the beginning of Stage 2 at physical address 0x10000.
; ORG is zero, so labels in this file are offsets from that address.
STAGE2_BASE equ 0x10000


; ============================================================================
; REAL MODE ENTRY
; ============================================================================

stage2_start:
    ; Disable interrupts while we establish the real-mode environment.
    ; Stage 1 already disabled interrupts, but doing it again here makes Stage 2
    ; independent of that assumption.
    cli

    ; Load the Stage 2 segment value into AX.
    ; Stage 1 entered us through 0x1000:0x0000, so Stage 2's data lives in the
    ; segment beginning at 0x1000.
    mov ax, 0x1000

    ; Set DS to 0x1000.
    ; With ORG 0, labels such as gdt_descriptor are offsets from the beginning
    ; of Stage 2, so DS:label points at their actual location.
    mov ds, ax

    ; Set ES to the same segment as DS.
    ; This keeps ordinary data accesses consistent throughout real mode.
    mov es, ax

    ; Set SS to 0x1000 as well.
    ; This keeps the stack in the same segment as Stage 2 while using a
    ; separate offset so it does not immediately overlap the loaded code.
    mov ss, ax

    ; Set the real-mode stack pointer.
    ;
    ; SS:SP = 1000:9000
    ;
    ; Physical address:
    ;
    ;   0x1000 * 16 + 0x9000 = 0x19000
    ;
    ; The stack grows downward from this address.
    mov sp, 0x9000

    ; Enable the A20 address line.
    ; This allows the CPU to access memory above the first 1 MiB without the
    ; legacy 20-bit address wraparound.
    call enable_a20

    ; Load the Global Descriptor Table.
    ; The CPU needs valid descriptors before protected-mode segment selectors
    ; can be loaded.
    lgdt [gdt_descriptor]

    ; Interrupts must remain disabled while changing CPU operating mode.
    cli

    ; Read CR0 into EAX.
    ; CR0 contains the Protection Enable (PE) bit that controls whether the
    ; CPU operates in real mode or protected mode.
    mov eax, cr0

    ; Set bit 0 of CR0.
    ; This enables protected mode.
    or eax, 1

    ; Write the updated value back to CR0.
    ; The CPU is now ready to enter protected mode.
    mov cr0, eax

    ; Perform a far jump to the protected-mode code segment.
    ;
    ; The jump:
    ;
    ;   1. Loads CS with CODE_SEG.
    ;   2. Loads EIP with the actual runtime address of protected_mode_start.
    ;   3. Flushes the CPU's prefetched real-mode instructions.
    ;
    ; Because ORG is zero, protected_mode_start is only an offset inside the
    ; Stage 2 image. Add STAGE2_BASE to turn that offset into its actual
    ; runtime linear address.
    ;
    ; The code-segment descriptor has a base of zero, so the resulting EIP is
    ; used directly as the linear address.
    jmp dword CODE_SEG:STAGE2_BASE + protected_mode_start


; ============================================================================
; A20 LINE
; ============================================================================

enable_a20:
    ; Read the current value of the Fast A20 Gate port.
    ; Port 0x92 is commonly available on PC-compatible hardware and emulators.
    in al, 0x92

    ; Test bit 1.
    ; Bit 1 controls the Fast A20 Gate.
    test al, 00000010b

    ; If bit 1 is already set, A20 is already enabled.
    jnz .done

    ; Set bit 1 to enable A20.
    or al, 00000010b

    ; Clear bit 0.
    ; Bit 0 can control system reset on compatible hardware, so we explicitly
    ; clear it to avoid accidentally requesting a reset.
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
    ; The first descriptor must be completely zero.
    ; It is used as the mandatory null descriptor.
    times 8 db 0


gdt_code:
    ; Limit bits 0-15.
    ; The complete limit is 0xFFFFF, which becomes a 4 GiB segment because
    ; the granularity flag below makes each limit unit 4096 bytes.
    dw 0xFFFF

    ; Base bits 0-15.
    ; The code segment starts at linear address 0.
    dw 0x0000

    ; Base bits 16-23.
    ; The base address is still zero.
    db 0x00

    ; Access byte:
    ;
    ;   1  = descriptor is present
    ;   00 = descriptor privilege level 0
    ;   1  = executable/code segment
    ;   0  = descriptor type is code/data
    ;   1  = code segment is readable
    ;   0  = accessed bit initially clear
    ;
    ; 0x9A represents a present, ring-0, readable code segment.
    db 10011010b

    ; Flags and limit bits 16-19:
    ;
    ;   1  = 4 KiB granularity
    ;   1  = 32-bit default operand size
    ;   0  = reserved
    ;   0  = reserved
    ;
    ; The lower four bits extend the segment limit to 0xFFFFF.
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

    ; 4 KiB granularity + 32-bit default operand size + upper limit bits.
    db 11001111b

    ; Base bits 24-31.
    ; The base address remains zero.
    db 0x00


gdt_end:


; ============================================================================
; GDT DESCRIPTOR
; ============================================================================

gdt_descriptor:
    ; GDTR.limit contains the size of the GDT minus one.
    ; The CPU expects the offset of the final valid byte rather than the total
    ; size of the GDT.
    dw gdt_end - gdt_start - 1

    ; GDTR.base contains the actual linear address of the first byte of the
    ; GDT.
    ;
    ; Because ORG is zero, gdt_start by itself is only an offset inside Stage 2.
    ; Add STAGE2_BASE to obtain the GDT's actual runtime address.
    dd STAGE2_BASE + gdt_start


; ============================================================================
; 32-BIT PROTECTED MODE
; ============================================================================

bits 32

protected_mode_start:

    ; Load the data-segment selector into AX.
    ; Segment registers cannot be loaded directly from an immediate value, so
    ; we first put DATA_SEG into a general-purpose register.
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
    ; SS must reference a valid protected-mode data descriptor before we use
    ; the protected-mode stack.
    mov ss, ax

    ; Set up the 32-bit stack.
    ; The stack grows downward from physical address 0x90000.
    mov esp, 0x90000

    ; Clear the direction flag.
    ; String instructions will therefore process memory in the forward
    ; direction if we use them later.
    cld

    ; Write the character 'P' directly to VGA text memory.
    ;
    ; VGA text memory begins at physical address 0xB8000.
    ; Each character uses two bytes:
    ;
    ;   byte 0 = ASCII character
    ;   byte 1 = color attribute
    ;
    ; Our data segment has a base of zero, so this linear address maps directly
    ; to physical address 0xB8000.
    mov byte [0xB8000], 'P'

    ; Set the color attribute for the character.
    ;
    ; 0x0F = bright white foreground on a black background.
    mov byte [0xB8001], 0x0F

    ; Write a second character immediately after the first one.
    mov byte [0xB8002], 'M'

    ; Give the second character the same color.
    mov byte [0xB8003], 0x0F

    ; Write a third character.
    mov byte [0xB8004], '!'

    ; Give the third character the same color.
    mov byte [0xB8005], 0x0F

    ; Disable interrupts.
    ; We have not created an IDT for protected mode, so there is no safe
    ; interrupt-handling environment yet.
    cli

.hang:
    ; Halt the CPU.
    ; With interrupts disabled, execution effectively stops here.
    hlt

    ; If HLT ever resumes for any reason, return to the same halt instruction.
    jmp .hang


; ============================================================================
; GDT SELECTORS
; ============================================================================

; A GDT selector is the byte offset of a descriptor within the GDT.
;
; gdt_code - gdt_start = 8, so CODE_SEG = 0x08.
CODE_SEG equ gdt_code - gdt_start

; gdt_data - gdt_start = 16, so DATA_SEG = 0x10.
DATA_SEG equ gdt_data - gdt_start
