; print a string using BIOS's video services.
; the location of the string should be in register ax.
; the size of the string should be in register bx.
print_string:                                                                           
  pusha                                                                          
  mov bp, ax                                                                     
  mov cx, bx                                                                     
  mov ax, cs                                                                      
  mov es, ax                                                                      
  mov dx, 0                                                                      
  mov bl, 7                                                                       
  mov ax,0x1300                                                                  
  int 0x10                                                                           
  popa                                                                          
  ret

clear_screen:
  mov ax, 0
  int 0x10
  ret
