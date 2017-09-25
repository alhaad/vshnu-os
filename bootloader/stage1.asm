; Copyright 2017 Alhaad Gokhale. All rights reserved.
; Use of this source code is governed by a BSD-style license that can
; be found in the LICENSE file.

%include "bootloader/include/mem.inc"

; The first-stage boot loader starts in 16-bit real mode.
[bits 16]

[org Mem.Stage1]

start:
	; Enforces real-mode addressing model.
	jmp 0x00:real_start

real_start:
	; Disable interrupts while setting up stack pointer.
	cli

	; All data-segments are initalized to same as cs.
	mov ax, cs
	mov ds, ax
	mov fs, ax
	mov gs, ax
	mov es, ax

	; Setup stack which starts just below Mem.Stage1.
	xor ax, ax
	mov ss, ax
	mov sp, Mem.Stack.Top

	; Re-enable interrupts.
	sti

	; Print message.
	mov si, String.Started
	call PutStr

	; Find PVD on ISO9660. We assume support.
	mov si, String.Ldpvd
	call PutStr
	call LoadPVD
	cmp al, 0
	jne .fail
	mov si, String.Success
	call PutStr

	; Load Path table.
	mov si, String.Ldpt
	call PutStr
	call LoadPT
	cmp ax, 0
	jne .fail
	mov si, String.Success
	call PutStr

	; Load the boot directory.
	mov si, String.Ldboot
	call PutStr
	call LoadBoot
	cmp ax, 0
	jne .fail
	mov si, String.Success
	call PutStr

	; Load stage 2 bootloader.
	mov si, String.Ldstg2
	call PutStr
	call LoadStage2
	cmp ax, 0
	jne .fail
	mov si, String.Success
	call PutStr

	; Find kernel.
	mov si, String.Findkern
	call PutStr
	call FindKern
	cmp ax, 0
	jne .fail
	mov si, String.Success
	call PutStr

	; Jump to stage 2.
	jmp Mem.Stage2

.fail:
	mov si, String.Fail
	call PutStr
.end:
	hlt
	jmp .end

;=============================================================================
; Subroutines
;=============================================================================

%include "bootloader/include/utils.inc"

; LoadPVD
; Loads the Primary Volume Descriptor on an ISO 9660 Disc to Mem.Sector.Buffer.
; input: none
; output: al = 0 on success, nonzero on failure
; destroyed: ax, si
LoadPVD:
	mov bx, 0x10	; LBA offset to read.
	mov cx, 0x1	; Read a single sector.
	mov di, Mem.Sector.Buffer
	call ReadSectors
	jc .fail

	; The volume's first byte contains its type.
	mov al, [es:Mem.Sector.Buffer]

	; Type 1 is the primary volume descriptor.
	cmp al, 0x01
	je .success

	; Type 0xff is the volume list terminator.
	cmp al, 0xFF
	je .fail

	; Move on to next sector.
	inc bx
	jmp LoadPVD

.fail:
	mov al, 1
	jmp .done
.success:
	mov al, 0
.done:
	ret

; LoadPT
; Loads the path table to Mem.Sector.Buffer.
; Assumes the PVD is already loaded at this same spot
; (overrides PVD in memory, we don't need it)
; input:      none
; output:     ax=0 on success, nonzero on failure
; destroyed:  ax, si
LoadPT:
	mov eax, [es:Mem.Sector.Buffer + 132]	; PT size
	shr eax, 11				; bytes -> blocks (divide by 2k)
	add ax, 1				; cover less significant digits
	mov cx, ax
	mov di, Mem.Sector.Buffer
	mov bx, [es:Mem.Sector.Buffer + 140]	; LBA of PT
	call ReadSectors
	cmp ah, 0
	jnz .done
	mov ax, 0x00
.done:
	ret

; LoadBoot
; assumes:    PT is loaded at Mem.Sector.Buffer.
;             Boot directory is present on media.
; input:      none
; output:     /boot is loaded to Mem.Sector.Buffer.
; destroyed:  ax, bx, cx, si, di
LoadBoot:
	mov bx, Mem.Sector.Buffer
.parsedir:
	cmp byte [es:bx], 4 	; check length
	jz .strchk
.nextent:
	xor al, al			; build offset to next PT entry in al
	add al, 8			; offset to dir name
	add al, [es:bx]			; length of dir name
	bt word [es:bx], 0		; determine if name is even
	jnc .even
	add al, 1			; odd. there's one extra byte of padding
.even:
	add bl, al			; add the offset
	jmp .parsedir			; parse the new dir
.strchk:
	mov cx, 4
	mov si, boot_dir
	mov di, bx
	add di, 8
	call StrCmp
	cmp ax, 0
	jnz .nextent
.endLoop:
	mov cx, 0x01
	mov di, Mem.Sector.Buffer
	mov ax, [es:bx + 2]
	mov bx, ax
	call ReadSectors
	cmp ah, 0
	jnz .done
	mov ax, 0x00
.done:
	ret

; LoadStage2
; Loads second stage to STAGE2
; assumes:    boot directory loaded at DIR_LOC
;             stage2 filename is at stage2_name (and is correct)
; input:      none
; output:     ax=0 on success, nonzero on failure
; destroyed:  ax, bx, cx, si, di
LoadStage2:
	mov bx, Mem.Sector.Buffer
.parsedir:
	cmp byte [es:bx + 32], stage2_name_len+2	; check length
	jnz .nextdir
.strchk:
	mov cx, stage2_name_len
	mov si, stage2_name
	mov di, bx
	add di, 33
	call StrCmp
	cmp ax, 0
	jz .found
.nextdir:
	xor ax, ax
	mov al, byte [es:bx]
	add bx, ax
	jmp .parsedir
.found:
	mov eax, [es:bx + 10]		; size of stage2 in bytes
	shr eax, 11			; convert to sector
	add ax, 1			; in case of remainder
	mov cx, ax
	mov di, Mem.Stage2
	mov bx, [es:bx + 2]
	call ReadSectors
	cmp ah, 0
	jnz .done
	mov ax, 0x00
.done:
	ret

; FindKern
; Finds the LBA of kernel on disc and tells stage2 about it by
; writing size and #lbas to first and second dword in stage2.
; assumes:    boot directory loaded at DIR_LOC
;             kernel filename is at kernel_name (and is correct)
;             stage2 has already been loaded
;             first dword of stage2 = kernel loc
;             second dword of stage2 = kernel size
; input:      none
; output:     ax=0 on success, nonzero on failure
; destroyed:  ax, bx, cx, si, di
FindKern:
	mov bx, Mem.Sector.Buffer
.parsedir:
	cmp byte [es:bx + 32], kernel_name_len+2
	jnz .nextdir
.strchk:
	mov cx, kernel_name_len
	mov si, kernel_name
	mov di, bx
	add di, 33
	call StrCmp
	cmp ax, 0
	jz .found
.nextdir:
	xor ax, ax
	mov al, byte [es:bx]
	add bx, ax
	jmp .parsedir
.found:
	mov eax, [es:bx + 2]		; location
	mov [es:Mem.Stage2.KernLBA], eax
	mov eax, [es:bx + 10]		; size in bytes
	mov [es:Mem.Stage2.KernSize], eax
	mov ax, 0
.done:
	ret

;=============================================================================
; Data
;=============================================================================

; Strings for printing status.
String.Started db 'Started stage 1 bootloader.', 13, 10, 0
String.Ldpvd          db  'Loading Primary Volume Descriptor...',0
String.Ldpt           db  'Loading Path Table..................',0
String.Ldboot         db  'Loading /boot.......................',0
String.Ldstg2         db  'Loading stage2......................',0
String.Findkern       db  'Finding Kernel......................',0

String.Success           db  'Done',13,10,0
String.Fail              db  'Fail',13,10,0

; Strings for file names
boot_dir          db  'BOOT'
boot_dir_len      equ $-boot_dir
stage2_name       db  'STAGE2.' ; period due to ISO filename standards
stage2_name_len   equ $-stage2_name
kernel_name       db  'KERNEL.'       ; period due to ISO filename standards
kernel_name_len   equ $-kernel_name

;=============================================================================
; Padding & boot signature
;=============================================================================

end:

; Pad the boot record to 2 KiB (1 sector).
times 2046 - ($ - $$) db 0

; Add the boot signature AA55 at the very end.
signature dw 0xaa55
