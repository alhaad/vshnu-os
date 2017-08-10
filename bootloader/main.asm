; This is the absolute memory address offset where bios loads the bootloader at.
[org 0x7c00]
KERNEL_OFFSET equ 0x1000 

; set the stack
mov bp, 0x9000
mov sp, bp


call clear_screen

mov ax, welcome_string
mov bx, welcome_string.len
call print_string

call load_kernel ; read the kernel from disk
call switch_to_pm ; ; disable interrupts, load GDT. Finally jumps to 'BEGIN_PM'

; Infinte loop. $ points to the address of this line.
; This line would never get executed.
jmp $

%include "bootloader/boot_sect_disk.asm"
%include "bootloader/video_services.asm"
%include "bootloader/32bit-print.asm"
%include "bootloader/32bit-gdt.asm"
%include "bootloader/32bit-switch.asm"

[bits 16]
load_kernel:
    mov bx, KERNEL_OFFSET ; Read from disk and store in 0x1000
    mov dh, 2
    mov dl, [BOOT_DRIVE]
    call disk_load
    ret

[bits 32]
BEGIN_PM: ; after the switch we will get here
    mov ebx, MSG_PROT_MODE
    ;call print_string_pm
    call KERNEL_OFFSET ; Give control to the kernel
    jmp $ ; Stay here when the kernel returns control to us (if ever)


BOOT_DRIVE db 0 ; It is a good idea to store it in memory because 'dl' may get overwritten
welcome_string db 'Welcome to VSHNU-OS!' 
welcome_string.len equ $-welcome_string
MSG_PROT_MODE db "Landed in 32-bit Protected Mode", 0

; Bootsector is 512 bytes. The last two bytes form the magic number. We pad the
; remaining bytes with zero. Calculation: 512 - 2 (magic) - $ (address of
; current line) + $$ (address of segment).
; 'times N I' repeats instruction I, N times.
times 510 - ($ - $$) db 0

; Magic number
dw 0xAA55
