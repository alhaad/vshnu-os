[org 0x7c00]

call clear_screen

mov ax, welcome_string
mov bx, welcome_string.len
call print_string

; Infinte loop. $ points to the address of this line.
jmp $

%include "bootloader/video_services.asm"

welcome_string db 'Welcome to VSHNU-OS!' 
welcome_string.len equ $-welcome_string

; Bootsector is 512 bytes. The last two bytes form the magic number. We pad the
; remaining bytes with zero. Calculation: 512 - 2 (magic) - $ (address of
; current line) + $$ (address of segment).
; 'times N I' repeats instruction I, N times.
times 510 - ($ - $$) db 0

; Magic number
dw 0xAA55
