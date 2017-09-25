; Copyright 2017 Alhaad Gokhale. All rights reserved.
; Use of this source code is governed by a BSD-style license that can
; be found in the LICENSE file.

%include "bootloader/include/gdt.inc"
%include "bootloader/include/mem.inc"

; The second-stage bootloader starts in 16-bit real mode.
[bits 16]
[org Mem.Stage2]

start:
	jmp real_start

	; Create an 8-byte padding.
	times 8-($-$$) db 0

Stage2.KernLBA dd 0
Stage2.KernSize dd 0

real_start:

	; Check kernel info.
	mov si, String.Chkkern
	call PutStr
	cmp dword [Stage2.KernLBA], 0
	jz .fail
	cmp dword [Stage2.KernSize], 0
	jz .fail
	mov si, String.Success
	call PutStr

	; Enable A20 so we can access > 1mb of ram
	mov si, String.A20
	call PutStr
	call EnableA20
	cmp ax, 0
	jnz .fail
	mov si, String.Success
	call PutStr

	; Load Kernel into memory.
	; Enable interrupts while loading the kernel.
	sti
	; Use a temporary GDT while loading the kernel.
	lgdt    [GDT32.Table.Pointer]
	mov si, String.Ldkern
	call PutStr
	mov bx, [Stage2.KernLBA]
	mov eax, [Stage2.KernSize]
	call LoadKernel
	jc .fail
	mov si, String.Success
	call PutStr
	cli

        ; Switch to 32-bit protected mode.
	mov   eax, cr0
	or    al, (1 << 0) 
	mov   cr0, eax
	jmp   GDT32.Selector.Code32:start_pmode ; jump to clear pipeline of non-32b inst

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

; EnableA20
; function to enable the a20 gate on a processor
; (allows access to greater range of memory)
; assumes:    none
; input:      none
; output:     ax=0 on success, nonzero on failure
; destroyed:  ax
EnableA20:
	  cli
          call  wait_for_kbd_in   ; wait for kbd to clear

          mov   al, 0xD0          ; command to read status
          out   0x64, al

          call  wait_for_kbd_out  ; wait for kbd to have data

          xor   ax, ax            ; clear ax 
          in    al, 0x60          ; get data from kbd
          push  ax                ; save value
          
          call  wait_for_kbd_in   ; wait for keyboard to clear
          mov   al, 0xD1          ; command to write status
          out   0x64, al
          call  wait_for_kbd_in   ; wait for keyboard to clear
          pop   ax                ; get the old value 
          or    al, 00000010b     ; flip A20 bit
          out   0x60, al          ; write it back

          call  wait_for_kbd_in   ; double check that it worked
          mov   al, 0xD0          ; same process as above to read 
          out   0x64, al
          
          call  wait_for_kbd_out
          xor   ax,ax
          in    al, 0x60
          bt    ax, 1             ; is the A20 bit enabled?
          jc    .success
          
          mov   ax, 1             ; code that we failed
          jmp   .return 
         
.success: mov   ax, 0             ; code that we succeeded
.return:  sti
	  ret


; wait_for_kbd_in
; 16 bit, real mode
; checks to see whether keyboard controller can be written to
; assumes:    none
; input:      none
; output:     none
; destroyed:  ax
wait_for_kbd_in:
          in    al, 0x64         ; read the port
          bt    ax, 1            ; see if bit 1 is 0 or not
          jc    wait_for_kbd_in  ; if it isn't, loop
          ret   


; wait_for_kbd_out
; 16 bit, real mode
; checks to see whether keyboard controller has data to read
; assumes:    none
; input:      none
; output:     none
; destroyed:  ax
wait_for_kbd_out:
          in    al, 0x64         ; read the port
          bt    ax, 0            ; see if bit 0 is 1 or not
          jnc   wait_for_kbd_out ; if it isn't, loop
          ret

;=============================================================================
; LoadKernel
;
; Load the kernel into upper memory.
;
; There are two problems we need to solve:
;
;   1. In real mode, we have access to the BIOS but can only access the
;      first megabyte of system memory.
;   2. In protected mode, we can access memory above the first megabyte but
;      don't have access to the BIOS.
;
; Since we need the BIOS to read the kernel from the CDROM and we need to load
; it into upper memory, we'll have to switch back and forth between real mode
; and protected mode to do it.
;
; This code repeats the following steps until the kernel is fully copied into
; upper memory:
;
;     1. Use BIOS to read the next 64KiB of the kernel file into a lower
;        memory buffer.
;     2. Switch to 32-bit protected mode.
;     3. Copy the 64KiB chunk from the lower memory buffer into the
;        appropriate upper memory location.
;     4. Switch back to real mode.
;
; Input registers:
;   EAX     Size of the kernel file (in bytes)
;   BX      Start sector of the kernel file
;
; Return flags:
;   CF      Set on error
;
; Killed registers:
;   None
;=============================================================================
LoadKernel:
    ; Preserve registers.
    push    es
    pusha

    ; Preserve the real mode stack pointer.
    mov     [LoadKernel.StackPointer],  sp

    ; Retrieve the cdrom disk number.
    ;mov     dl,     [Globals.DriveNumber]

    ; Save the kernel size.
    ;mov     [Globals.KernelSize],       eax

    ; Convert kernel size from bytes to sectors (after rounding up).
    add     eax,    Mem.Sector.Buffer.Size - 1
    shr     eax,    11

    ; Store status in code memory, since it's hard to use the stack while
    ; switching between real and protected modes.
    mov     [LoadKernel.CurrentSector], bx
    add     ax,                         bx
    mov     [LoadKernel.LastSector],    ax

    .loadChunk:

        ; Set target buffer for the read.
	mov     cx,     Mem.Kernel.LoadBuffer >> 4
	mov     es,     cx
	xor     di,     di

        ; Set the number of sectors to read (buffersize / 2048).
        mov     cx,     Mem.Kernel.LoadBuffer.Size >> 11

        ; Calculate the number of remaining sectors.
        ; (ax = LastSector, bx = CurrentSector)
        sub     ax,     bx

        ; Are there fewer sectors to read than will fit in the buffer?
        cmp     cx,     ax
        jb      .proceed

        ; Don't read more sectors than are left.
        mov     cx,     ax

    .proceed:

        ; Store the number of sectors being loaded, so we can access it in
        ; protected mode when we do the copy to upper memory.
        mov     [LoadKernel.SectorsToCopy],     cx

        ; Read a chunk of the kernel into the buffer.
        call    ReadSectors
        jc      .errorReal

    .prepareProtected32Mode:

        ; Disable interrupts until we're out of protected mode and back into
        ; real mode, since we're not setting up a new interrupt table.
        cli

        ; Enable protected mode.
        mov     eax,    cr0
        or      eax,    (1 << 0)    ; CR.PE
        mov     cr0,    eax

        ; Do a far jump to switch to 32-bit protected mode.
        jmp     GDT32.Selector.Code32 : .switchToProtected32Mode

[bits 32]

    .switchToProtected32Mode:

        ; Initialize all data segment registers with the 32-bit protected mode
        ; data segment selector.
        mov     ax,     GDT32.Selector.Data32
        mov     ds,     ax
        mov     es,     ax
        mov     ss,     ax

        ; Create a temporary stack used only while in protected mode.
        ; (probably not necessary since interrupts are disabled)
        mov     esp,    Mem.Stack32.Temp.Top

    .copyChunk:

        ; Set up a copy from lower memory to upper memory using the number of
        ; sectors.
        xor     ecx,    ecx
        xor     esi,    esi
        xor     edi,    edi
        mov     bx,     [LoadKernel.SectorsToCopy]
        mov     cx,     bx
        shl     ecx,    11       ; multiply by sector size (2048)
        mov     esi,    Mem.Kernel.LoadBuffer
        mov     edi,    [LoadKernel.TargetPointer]

        ; Advance counters and pointers.
        add     [LoadKernel.TargetPointer],     ecx
        add     [LoadKernel.CurrentSector],     bx

        ; Copy the chunk.
        cld
        shr     ecx,    2       ; divide by 4 since we're copying dwords.
        rep     movsd

    .prepareProtected16Mode:

        ; Before we can switch back to real mode, we have to switch to
        ; 16-bit protected mode.
        jmp     GDT32.Selector.Code16 : .switchToProtected16Mode

[bits 16]

    .switchToProtected16Mode:

        ; Initialize all data segment registers with the 16-bit protected mode
        ; data segment selector.
        mov     ax,     GDT32.Selector.Data16
        mov     ds,     ax
        mov     es,     ax
        mov     ss,     ax

    .prepareRealMode:

        ; Disable protected mode.
        mov     eax,    cr0
        and     eax,    ~(1 << 0)   ; CR0.PE
        mov     cr0,    eax

        ; Do a far jump to switch back to real mode.
        jmp     0x0000 : .switchToRealMode

    .switchToRealMode:

        ; Restore real mode data segment registers.
        xor     ax,     ax
        mov     ds,     ax
        mov     es,     ax
        mov     ss,     ax

        ; Restore the real mode stack pointer.
        xor     esp,    esp
        mov     sp,     [LoadKernel.StackPointer]

        ; Enable interrupts again.
        sti

    .checkCompletion:

        ; Check if the copy is complete.
        mov     ax,     [LoadKernel.LastSector]
        mov     bx,     [LoadKernel.CurrentSector]
        cmp     ax,     bx
        je      .success

        ; Proceed to the next chunk.
        jmp     .loadChunk

    .errorReal:

        ; Set carry flag on error.
        stc
        jmp     .done

    .success:

        ; Clear carry on success.
        clc

    .done:

        ; Wipe the sector load buffer.
        mov     ax,     Mem.Kernel.LoadBuffer >> 4
        mov     es,     ax
        xor     ax,     ax
        xor     di,     di
        mov     cx,     Mem.Kernel.LoadBuffer.Size - 1
        rep     stosb
        inc     cx
        stosb

        ; Clear upper word of 32-bit registers we used.
        xor     eax,    eax
        xor     ecx,    ecx
        xor     esi,    esi
        xor     edi,    edi

        ; Restore registers.
        popa
        pop     es

        ret

;-----------------------------------------------------------------------------
; LoadKernel state variables
;-----------------------------------------------------------------------------
align 4
LoadKernel.TargetPointer        dd      Mem.Kernel.Image
LoadKernel.CurrentSector        dw      0
LoadKernel.LastSector           dw      0
LoadKernel.SectorsToCopy        dw      0
LoadKernel.StackPointer         dw      0

; start_pmode
; label in 32bit assembly used in the far jump to clear pipeline for switching from
; real16bit to protected32bit mode
[BITS 32]
start_pmode:
            mov ax, GDT32.Selector.Data32    ; need to load data segment into ds/ss
            mov ds, ax
            mov es, ax 
            mov ss, ax
            jmp Mem.Kernel.Image     ; jmp to kernel!

;=============================================================================
; Global data
;=============================================================================

;-----------------------------------------------------------------------------
; Global Descriptor Table used (temporarily) in 32-bit protected mode
;-----------------------------------------------------------------------------
align 4
GDT32.Table:

    ; Null descriptor
    istruc GDT.Descriptor
        at GDT.Descriptor.LimitLow,            dw      0x0000
        at GDT.Descriptor.BaseLow,             dw      0x0000
        at GDT.Descriptor.BaseMiddle,          db      0x00
        at GDT.Descriptor.Access,              db      0x00
        at GDT.Descriptor.LimitHighFlags,      db      0x00
        at GDT.Descriptor.BaseHigh,            db      0x00
    iend

    ; 32-bit protected mode - code segment descriptor (selector = 0x08)
    ; (Base=0, Limit=4GiB-1, RW=1, DC=0, EX=1, PR=1, Priv=0, SZ=1, GR=1)
    istruc GDT.Descriptor
        at GDT.Descriptor.LimitLow,            dw      0xffff
        at GDT.Descriptor.BaseLow,             dw      0x0000
        at GDT.Descriptor.BaseMiddle,          db      0x00
        at GDT.Descriptor.Access,              db      10011010b
        at GDT.Descriptor.LimitHighFlags,      db      11001111b
        at GDT.Descriptor.BaseHigh,            db      0x00
    iend

    ; 32-bit protected mode - data segment descriptor (selector = 0x10)
    ; (Base=0, Limit=4GiB-1, RW=1, DC=0, EX=0, PR=1, Priv=0, SZ=1, GR=1)
    istruc GDT.Descriptor
        at GDT.Descriptor.LimitLow,            dw      0xffff
        at GDT.Descriptor.BaseLow,             dw      0x0000
        at GDT.Descriptor.BaseMiddle,          db      0x00
        at GDT.Descriptor.Access,              db      10010010b
        at GDT.Descriptor.LimitHighFlags,      db      11001111b
        at GDT.Descriptor.BaseHigh,            db      0x00
    iend

    ; 16-bit protected mode - code segment descriptor (selector = 0x18)
    ; (Base=0, Limit=1MiB-1, RW=1, DC=0, EX=1, PR=1, Priv=0, SZ=0, GR=0)
    istruc GDT.Descriptor
        at GDT.Descriptor.LimitLow,            dw      0xffff
        at GDT.Descriptor.BaseLow,             dw      0x0000
        at GDT.Descriptor.BaseMiddle,          db      0x00
        at GDT.Descriptor.Access,              db      10011010b
        at GDT.Descriptor.LimitHighFlags,      db      00000001b
        at GDT.Descriptor.BaseHigh,            db      0x00
    iend

    ; 16-bit protected mode - data segment descriptor (selector = 0x20)
    ; (Base=0, Limit=1MiB-1, RW=1, DC=0, EX=0, PR=1, Priv=0, SZ=0, GR=0)
    istruc GDT.Descriptor
        at GDT.Descriptor.LimitLow,            dw      0xffff
        at GDT.Descriptor.BaseLow,             dw      0x0000
        at GDT.Descriptor.BaseMiddle,          db      0x00
        at GDT.Descriptor.Access,              db      10010010b
        at GDT.Descriptor.LimitHighFlags,      db      00000001b
        at GDT.Descriptor.BaseHigh,            db      0x00
    iend

GDT32.Table.Size    equ     ($ - GDT32.Table)

GDT32.Table.Pointer:
    dw  GDT32.Table.Size - 1    ; Limit = offset of last byte in table
    dd  GDT32.Table

; Strings for printing status
String.Chkkern        db  'Checking Kernel Info................',0
String.A20            db  'Enabling A20........................',0
String.Ldkern         db  'Loading Kernel......................',0
String.Rnkern          db  'Starting VSHNU-OS kernel..................',0

; Success and fail strings;
String.Success           db  'Done',13,10,0
String.Fail              db  'Fail',13,10,0
