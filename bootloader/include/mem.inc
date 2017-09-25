; Copyright 2017 Alhaad Gokhale. All rights reserved.
; Use of this source code is governed by a BSD-style license that can
; be found in the LICENSE file.

%ifndef __BOOTLOADER_MEM_INC__
%define __BOOTLOADER_MEM_INC__

;=============================================================================
; Memory layout
;=============================================================================

Mem.BIOS.IVT                        equ     0x00000000
Mem.BIOS.Data                       equ     0x00000400
Mem.Sector.Buffer                   equ     0x00000500
Mem.Stack.Bottom                    equ     0x00004000
Mem.Stack.Top                       equ     0x00007c00
Mem.Stage1                          equ     0x00007c00
Mem.Stage2                          equ     0x00008400
Mem.Stage2.KernLBA                  equ     0x00008408
Mem.Stage2.KernSize                 equ     0x0000840c
Mem.Stack32.Temp.Bottom             equ     0x0006f000
Mem.Stack32.Temp.Top                equ     0x00070000
Mem.Kernel.LoadBuffer               equ     0x00070000
Mem.Kernel.Image                    equ     0x00100000

; Layout region sizes
Mem.Sector.Buffer.Size              equ     0x00000800
Mem.Kernel.LoadBuffer.Size          equ     0x00010000

%endif ; __BOOTLOADER_MEM_INC__
