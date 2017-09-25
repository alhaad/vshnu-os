; Copyright 2017 Alhaad Gokhale. All rights reserved.
; Use of this source code is governed by a BSD-style license that can
; be found in the LICENSE file.

%ifndef __BOOTLOADER_UTIL_INC__
%define __BOOTLOADER_UTIL_INC__

%include "bootloader/include/mem.inc" 

[bits 16]

;------------------------------------------------------------
; Data
;------------------------------------------------------------

; Disk Address Packet
; (data structure used by int13 ah=42)
DAP:
          db    0x10      ; size of this packet
          db    0         ; always zero
numsect   dw    0         ; number of sectors to transfer
destoff   dw    0         ; segment and offset in mem
destseg   dw    0
lbanum    dd    0         ; lba to read
lbanum2   dd    0         ; extra space for lba offset

;------------------------------------------------------------
; Functions
;------------------------------------------------------------

; PutStr
; Prints a null terminated string to screen
; input:      string address to be in si
; output:     none
; destroyed:  ax, bx
PutStr:
        mov   ah, 0x0E    ; function for printing
        mov   bh, 0x00    ; page number
        mov   bl, 0x07    ; color 
        
.ldchr: lodsb             ; put a byte of the string into al
        cmp   al, 0
        je    .done       ; if it's null/zero, all done
        int   0x10        ; do the print
        jmp   .ldchr      ; go to next char 
  
.done:  ret

; StrCmp
; compares two strings (assumes equal length)
; input:      str length in cx
;             ptr to str1 in ds:si
;             ptr to str2 in es:di
; output:     ax=0 if equal, nonzero if unequal
; destroyed:  ax, cx
StrCmp:
.nxtchar: cmp   cx,0      ; while (cx > 0) 
          jz    .success  ; done w/o failing, match  
          cmpsb 
          jnz   .fail     ; not equal
          dec   cx        ; dec counter
          jmp   .nxtchar  ; move to next char 

.fail:    mov   ax, 1  
          jmp   .done
.success: mov   ax, 0
.done:    ret

; ReadSectors
; Read 1 or more 2048-byte sectors from the CDROM using int 13 function 42.
; input:	bx - starting sector lba (logical block address)
;		cx - number of sectors to read
;		dl - drive number
;		es:di - target buffer
; output:     ah - Return code from int 13 (42h) BIOS call
; destroyed:  ax, si
ReadSectors:
	mov word [numsect], cx
	mov word [destoff], di
	mov word [destseg], es
	mov word [lbanum], bx

	mov si, DAP

	mov ah, 0x42
	int 0x13
	ret

%endif ; __BOOTLOADER_UTIL_INC__
