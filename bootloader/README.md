Two stage bootloader.

;=============================================================================
; Memory layout before this code starts running:
;
;   000c0000 - 000fffff      262,144 bytes     ROM
;   000a0000 - 000bffff      131,072 bytes     BIOS video memory
;   0009fc00 - 0009ffff        1,024 bytes     Extended BIOS data area (EBDA)
;   000083fe - 0009fbff      620,545 bytes     Free
;   00007c00 - 000083fd        2,046 bytes     First-stage boot loader (MBR)
;   00000500 - 00007bff       30,464 bytes     Free
;   00000400 - 000004ff          256 bytes     BIOS data area
;   00000000 - 000003ff        1,024 bytes     Real mode IVT
;
;   [ See http://wiki.osdev.org/Memory_Map_(x86) ]
;=============================================================================
