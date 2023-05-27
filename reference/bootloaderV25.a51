$nomod51
$nolist
;****************************************************************************
; This is the disasembled source for V2.50 bootloader found in new CH55x chips.
; When setting StartAddress to 3800h and leaving all other options at 0 it
; produce exactly the same binary as stored in CH554 or newer CH552 devices.
;****************************************************************************
$include (..\inc\ch552_keil.h)

; <<< Use Configuration Wizard in Context Menu >>>
; <h> Configuration for WCH V2.31 Bootloader

; <o> StartAddress <0-0x3800:0x800>
; <i> Startaddress for bootloader should be on a 0x800 boundary
StartAddress       EQU  0x3800


; <o> ADD_USB_BUGFIX  <0=> off
;                     <1=> on
; <i> insert usb bugfix for Setup requests to clear possible STALL contitions
ADD_USB_BUGFIX     EQU  0

; <o> OPTIMIZE_CALLS     <0=> off
;                        <1=> on
; <i> use ACALL/ AJMP instead of LCALL/LJMP a macro will do the job
OPTIMIZE_CALLS     EQU  0

; <<< end of configuration section >>>


;these macros select the long or short versions for CALL and JMP
if (OPTIMIZE_CALLS=1)
  XCALL macro dest
    ACALL dest
  endm
  XJMP macro dest
    AJMP dest
  endm
else
  XCALL macro dest
    LCALL dest
  endm
  XJMP macro dest
    LJMP dest
  endm
endif

$list

dseg at 0x08
OverLay:           DS 10     ; Keil C Overlay Ram for local vars

bseg at 0
bWrProtect:        DBIT 1     ; 1 disables CodeFlash writing
bVerifyErr:        DBIT 1     ; 1 when verify failed new v2.40 
bSoftReset:        DBIT 1     ; 1 for executing software reset
bChipTyp:          DBIT 1     ; 1 if it is a CH551 or CH553
bReqError:         DBIT 1     ; 1 on request Errors

dseg at 0x21
wValueLo:          DS 1       ; 0x21
TimeOut:           DS 2       ; new in V2.5
BootKey:           DS 8       ;
Marker0:           DS 1       ;
rlen:              DS 1       ;
reqlen:            DS 1       ;
cmdbuffer:         DS 64      ;
                   DS 2       ; unused
bRequest:          DS 1       ;
SnSum:             DS 1       ;
DescAddr:          DS 2       ;
CAddr:             DS 2       ;
Marker1:           DS 1
STACK:

xseg at 0
EP0_BUFFER:        DS  8      ; 0x0000 the control endpoint
                   DS  4      ; spare
EP2_OUT_BUFFER:    DS 64      ; 0x000C bulk out
EP2_IN_BUFFER:     DS 64      ; 0x004C bulk in


cseg at StartAddress          ; bootloader start
    ljmp  C_C51STARTUP        ; the core need a ljmp here dont use a XJmp
    nop                       ; db LOADER_OPTIONS

; =============== S U B R O U T I N E =======================================

__MaxFunc  set 11                  ;11 functions by default

FunctionDispatcher:                ; 0x3804

__i        set R3                  ;
__result   set R1
__len      set OverLay+1
__addr     set OverLay+2
    mov    A, Marker1              ;remove this
    xrl    A, #0x5A
    jz     $+4
    sjmp   $                       ;
    clr    A                       ;
    mov    DPTR, #EP2_IN_BUFFER + 5;EP2_IN_BUFFER[5]=0; 
    movx   @DPTR, A                ;

    mov    rlen, #6                ;
    mov    TimeOut+0, A            ;v2.5
    mov    TimeOut+1, A            ;v2.5
    mov    __result, #0xFE         ;result = -2

    mov    A, cmdbuffer+4          ;v2.4
    mov    R6, A
    mov    A, cmdbuffer+3
    mov    R5, A
    mov    A, R6
    mov    __addr, A
    mov    A, R5
    mov    __addr+1, A

    mov    A, cmdbuffer+0          ;switch (cmdbuffer[0])
    add    A, #0x5F                ;
    cjne   A, #__MaxFunc, code_382D; 11 functions
code_382D:                         ;
    jc    ComandCodeValid
    Xjmp  FuncBreak                ; unknown cmd

ComandCodeValid:                   ;
    mov   DPTR, #JmpTable
if (OPTIMIZE_CALLS = 0)
    mov   B, #3                    ; size of ljmp
else
    mov   B, #2                    ; size of ajmp
endif
    mul   AB
    xch   A, DPH                   ; calc the offset into
    add   A, B                     ; table
    xch   A, DPH                   ;
    jmp   @A+DPTR                  ; vector jmp

JmpTable:                          ;
    Xjmp  JumpFunction0            ;a1 detect chip V2
    Xjmp  JumpFunction1            ;a2 BootControl
    Xjmp  JumpFunction2            ;a3 createkey
    Xjmp  JumpFunction3            ;a4 erase Code Flash  (1k pages)
    Xjmp  JumpFunction4            ;a5 write  encoded code flash
    Xjmp  JumpFunction5            ;a6 verify encoded code flash
    Xjmp  JumpFunction6            ;a7 read  Boot Options
    Xjmp  JumpFunction7            ;a8 write Boot Options
    Xjmp  JumpFunction8            ;a9 erase Data Flash
    Xjmp  JumpFunction9            ;aa write encoded data flash
    Xjmp  JumpFunction10           ;ab read data flash

;*****************************;
;identify
;send: <0xa1> <??> <??> <??> <??>  <String>
;resp: <0xa1> <??> <lo> <hi> <id> <0x11>
JumpFunction0:                     ;
    mov   __result, CHIP_ID        ;
    clr   A                        ;
    mov   __i, A                   ;for (i=0,i<16 i++)
Func0Loop:                         ;
    mov   A, __i                   ;{
    mov   DPTR, #CopyrightMsg
    movc  A, @A+DPTR               ;
    mov   R7, A
    mov   A, #cmdbuffer + 5        ;
    add   A, __i                   ;  if (CopyrightMsg[i] != cmdbuffer[5+i])
    mov   R0, A                    ;
    mov   A, @R0                   ;
    xrl   A, R7                    ;
    jz    Func0Next                ;  {
    mov   __result, #0xF1          ;     result = 0xF1
    Xjmp  FuncBreak                ;     break;
Func0Next:                         ;  }
    inc   __i
    cjne  __i, #16, Func0Loop      ;}

    mov   DPTR, #EP2_IN_BUFFER + 5 ; EP2_IN_BUFFER[5]=0x11;
    mov   A, #0x11                 ;
    movx  @DPTR, A                 ;
    Xjmp  FuncBreak                ;break;


;*****************************;
JumpFunction4:                ;
    jnb   bWrProtect, JumpFunction9;
    Xjmp  Dispatcher_Done          ;return
;*****************************
;<a5> <len> <x> <addrL> <addrH> <data[len+5]>
;<aa> <len> <x> <addrL> <addrH> <data[len+5]>
JumpFunction9:                     ;
    mov   A, cmdbuffer+1           ; len = cmdbuffer[1]-5
    add   A, #-5                   ;
    mov   __len, A                 ;

    mov   A, cmdbuffer+0           ; if (cmdbuffer[0] == 0xA5)
    xrl   A, #0xA5
    jnz   code_38E2                ; {

    mov   __i, A                   ;    for (i=0; i < len; i+=2)
code_3894:                         ;    {
    mov   A, __i
    clr   C
    subb  A, __len
    jc    code_389h
    Xjmp  FuncBreak
code_389h:
    mov   A, __i
    mov   R6, #0                   ;        R6/R7 = param +i
    add   A, __addr+1
    mov   R7, A
    mov   A, R6
    addc  A, __addr
    mov   R6, A
    mov   A, R6
    push  ACC                      ;         save it
    mov   A, R7
    push  ACC                      ;
    mov   A, __i
    anl   A, #7
    mov   R5, A                    ;         R5 = i & 0x07
    add   A, #BootKey+1            ;
    mov   R0, A
    mov   A, @R0
    mov   R7, A                    ;         R7 = Bootkey[1+i&7]
    mov   A, #cmdbuffer+9          ;
    add   A, __i
    mov   R0, A
    mov   A, @R0
    xrl   A, R7
    mov   R6, A                    ;          R6 = cmdbuffer[9+i] ^ Bootkey[1+i&7]
    mov   A, #BootKey+0            ;
    add   A, R5
    mov   R0, A
    mov   A, @R0
    mov   R5, A                    ;          R5 = Bootkey[0+i]
    mov   A, #cmdbuffer+8          ;
    add   A, __i
    mov   R0, A
    mov   A, @R0
    xrl   A, R5
    mov   R5, A
    mov   A, R6
    mov   R4, A                    ;          R4 =  cmdbuffer[8+i] ^ Bootkey[0+i]
    pop   ACC                      ;
    mov   R7, A
    pop   ACC                      ;
    mov   R6, A
    Xcall WriteFlashCode
    xch   A, __result
    mov   A, R7
    xch   A, __result
    mov   A, __result
    jz    code_38DE
    Xjmp  FuncBreak
code_38DE:                         ;
    inc   __i
    inc   __i
    sjmp  code_3894

code_38E2:                         ; else
    clr   A                        ; {
    mov   __i, A                   ;    i=0

code_38E4:                         ;    for (i=0; i < _len; i++)
    mov   A, __i                   ;
    clr   C
    subb  A, __len
    jc    code_38ED
    Xjmp  FuncBreak
code_38ED:                         ;    {
    mov   A, __addr+1
    add   A, __i
    mov   R7, A
    mov   A, __i
    anl   A, #7
    add   A, #BootKey+0            ;
    mov   R0, A
    mov   A, @R0
    mov   R6, A
    mov   A, #cmdbuffer+8          ;
    add   A, __i
    mov   R0, A
    mov   A, @R0
    xrl   A, R6

code_38FF:                         ;
    mov   R5, A
    Xcall WriteFlashData
    xch   A, __result
    mov   A, R7
    xch   A, __result
    mov   A, __result
    jz    code_390C
    Xjmp  FuncBreak

code_390C:                         ;
    inc   __i                      ; i ++
    sjmp  code_38E4                ; loop it

;****************************;
;verify: <a6> <len> <0> <adrl> <adrh> <data[len-5]>
JumpFunction5:                     ;
    mov   A, cmdbuffer+1           ;len= cmdbuffer[1]-5
    add   A, #-5                   ;
    mov   __len, A                 ;if (len & 0x07) break;
    anl   A, #7                    ;
    jz    code_391C
    Xjmp  FuncBreak
code_391C:                         ;
    mov    A, __addr+1
    anl    A, #7
    jz     ROM_3929
    Xjmp   FuncBreak
ROM_3929:       
    clr    C
    mov    A, __addr+0              ; check for >=0x3800
    subb   A, #high (0x3800)        ;
    jc     ROM_3933
    Xjmp   FuncBreak

ROM_3933:
    jnb   bVerifyErr, ROM_3939
    ljmp  FuncBreak

ROM_3939:       
    mov CAddr+0, __addr+0
    mov CAddr+1, __addr+1

A5_001:
    clr   A                        ;for (i=0,i < len i++)
    mov   __i, A
code_3929:                         ;{
    mov   A, __i
    clr   C
    subb  A, __len
    jnc   code_3959                ;
    mov   A, __i                   ;    if ( BootKey[i & 0x07]
    anl   A, #7
    add   A, #BootKey+0            ;
    mov   R0, A
    mov   A, @R0                   ;
    mov   R7, A
    mov   A, #cmdbuffer+8          ;       ^ cmdbuffer[8+i]
    add   A, __i
    mov   R0, A
    mov   A, @R0                   ;
    xrl   A, R7
    mov   R7, A                    ;       ^ CBYTE[flashaddr]
    mov   DPL, CAddr+1             ;
    mov   DPH, CAddr+0             ;
    clr   A
    movc  A, @A+DPTR
    xrl   A, R7                    ;        )
    jz    code_394E                ;        {
A5_err:
    mov   __result, #0xF5          ;           result = 0xF5:
    setb  bVerifyErr               ;           bVerifyErr = 1 //v2.40
    Xjmp  FuncBreak                ;           break;
code_394E:                         ;        }
    inc   CAddr+1                  ;
    mov   A, CAddr+1
    jnz   code_3956
    inc   CAddr+0
code_3956:                         ;loop ++
    inc   __i
    sjmp  code_3929
code_3959:                         ;
    clr   A                        ;
    mov   __result, A              ;result = 0
    Xjmp  FuncBreak
;****************************
;read dataflash
;<ab> <x> <x> <addrl> <addrh> <x> <x> <rlen> <data[rlen]>
JumpFunction10:                    ;
    mov   A, cmdbuffer+7           ;rlen+=Buffer[7]
    add   A, rlen
    mov   rlen, A
    mov   ROM_ADDR_H, #high DATA_FLASH_ADDR
    mov   __i, #6                  ;for (i= 6;i< rlen; i++)
code_3969:                         ;{
    mov   A, __i
    clr   C
    subb  A, rlen
    jnc   code_398B
    mov   A, cmdbuffer+3           ;    (cmdbuffer[3+i] - 6) << 1
    add   A, __i
    add   A, #-6
    add   A, ACC
    mov   ROM_ADDR_L, A
    mov   ROM_CTRL, #ROM_CMD_READ  ;
    mov   A, #low EP2_IN_BUFFER    ;    EP2_IN_BUFFER[i]
    add   A, __i
    mov   DPL, A
    clr   A
    addc  A, #high EP2_IN_BUFFER   ;
    mov   DPH, A                   ;
    mov   A, ROM_DATA_L            ;
    movx  @DPTR, A
    inc   __i
    sjmp  code_3969                ;}
code_398B:                         ;
    clr   A                        ; result = 0
    mov   __result, A
    Xjmp  FuncBreak                ; break

;****************************
;<a4> <x> <x> <0..7>
;This code does not work as expected
JumpFunction3:                     ;  delete rom page
    mov   A, cmdbuffer+3           ; if (cmdbuffer[3] > 8) break
    clr   C
    subb  A, #8
    jnc   code_399A
    Xjmp  FuncBreak

code_399A:                         ;
    mov   cmdbuffer+3, #8          ;v2.5
    clr   A
    mov   __addr+0, A              ;addr=0
    mov   __addr+1, A
Funk3Loop:                         ;
    mov   A, #0xFF                 ;do 
    mov   R5, A                    ;{
    mov   R4, A
    mov   R7, __addr+1
    mov   R6, __addr+0
    Xcall WriteFlashCode           ;    result=WriteFlashCode(addr,0xFFFF)
    xch   A, __result
    mov   A, R7
    xch   A, __result
    mov   A, #4
    add   A, __addr+1              ;    addr+=4;
    mov   __addr+1, A
    clr   A
    addc  A, __addr
    mov   __addr, A                ;    if (????) cmdbuffer[3]--;
    anl   A, #3
    orl   A, __addr+1
    jnz   code_39C3
    dec   cmdbuffer+3
code_39C3:                         ;
    mov   A, cmdbuffer+3           ;} while (cmdbuffer[3])
    jnz   Funk3Loop
    clr   bWrProtect
    clr   bVerifyErr               ;v2.40 
    Xjmp  FuncBreak
;*****************************
;<a9>
JumpFunction8:                     ;Erase FlashData
    clr   A
    mov   __i, A                   ;for (i=0;i<128;i++)

code_39CE:            ;
    xch   A, R7
    mov   A, __i
    xch   A, R7
    mov   R5, #0xFF
    Xcall WriteFlashData
    xch   A, __result
    mov   A, R7
    xch   A, __result
    inc   __i
    cjne  __i, #128, code_39CE ;
    Xjmp  FuncBreak

;*****************************
;new bootkey
;<a3> <len> <x> <>
JumpFunction2:                     ;
    mov   A, cmdbuffer+1           ;if(cmdbuffer[1] < 30) break;
    clr   C
    subb  A, #30
    jnc   JumpF2_001
    Xjmp  FuncBreak

JumpF2_001:
    mov   A, cmdbuffer+1           ;i= (Buffer[1] / 7)
    mov   B, #7                    ;
    div   AB
    mov   __i, A                   ;
    add   A, ACC                   ;cmdbuffer[3+i*4]
    add   A, ACC                   ;
    add   A, #cmdbuffer+3          ;
    mov   R0, A
    mov   A, @R0                   ;
    xrl   A, SnSum
    mov   BootKey+0, A             ;BootKey[0] = cmdbuffer[3+i*4] ^ SnSum;
    mov   A, #cmdbuffer+3          ;
    add   A, __i
    mov   R0, A
    mov   A, @R0
    xrl   A, SnSum
    mov   BootKey+2, A             ;BootKey[2] = cmdbuffer[3+i] ^ SnSum;
    mov   A, __i                   ;
    mov   B, #6                    ;
    mul   AB
    add   A, #cmdbuffer+3          ;cmdbuffer[3+i*6]
    mov   R0, A
    mov   A, @R0
    xrl   A, SnSum
    mov   BootKey+3, A             ;BootKey[3] = cmdbuffer[3+i*6] ^ SnSum;
    mov   A, __i
    mov   B, #3                    ;
    mul   AB
    add   A, #cmdbuffer+3          ;
    mov   R0, A
    mov   A, @R0
    xrl   A, SnSum
    mov   BootKey+4, A             ;BootKey[4] = cmdbuffer[3+i*3] ^ SnSum;
    mov   A, __i
    mov   B, #5                    ;
    mul   AB
    add   A, #cmdbuffer+3          ;
    mov   R0, A
    mov   A, @R0
    xrl   A, SnSum
    mov   BootKey+6, A             ;BootKey[6] = cmdbuffer[3+i*5] ^ SnSum;
    mov   A, cmdbuffer+1
    mov   B, #5                    ;
    div   AB
    mov   __i, A                   ;i = cmdbuffer[1] / 5
    add   A, #cmdbuffer+3          ;
    mov   R0, A
    mov   A, @R0
    xrl   A, SnSum
    mov   BootKey+1, A             ;BootKey[1] = cmdbuffer[3+i] ^ SnSum;
    mov   A, __i
    mov   B, #3                    ;
    mul   AB
    add   A, #cmdbuffer+3          ;
    mov   R0, A
    mov   A, @R0
    xrl   A, SnSum
    mov   BootKey+5, A             ;BootKey[5] = cmdbuffer[3+i*3] ^ SnSum;
    mov   A, CHIP_ID               ;
    add   A, BootKey+0
    mov   BootKey+7, A             ;BootKey[7] = CHIP_ID + BootKey[0];
    clr   A
    mov   __i, A                   ;i=0;
    mov   __result, A              ;result=0;

code_3A52:                         ;for ( i=0;i<8; i++)
    mov   A, #BootKey+0            ;
    add   A, __i                   ;
    mov   R0, A
    mov   A, @R0                   ;  result += Bootkey[i];
    add   A, __result
    mov   __result, A
    inc   __i
    cjne  __i, #8, code_3A52
    Xjmp  FuncBreak                ;
;*****************************
;  0   1   2    3     4    5   ... 
;<a8> <x> <x> <0x07> <x> <cfg data>
JumpFunction7:                     ;write Boot Options
    mov   A, cmdbuffer+3           ;if  (cmdbuffer[3] & 0x07 == 0x07)
    anl   A, #7
    xrl   A, #7
    jz    JumpF7_001               ;{
    Xjmp  FuncBreak
JumpF7_001:
    anl   cmdbuffer+14, #0x7F      ;   cmdbuffer[14] = (cmdbuffer[14] & 0x7F) | 0x40;
    orl   cmdbuffer+14, #0x40      ;     set always the NO_BOOT_LOAD bit

    mov   __i, A                   ;   for (i=0;i < 10; i +=2)
JumpF7_Loop1:                      ;   {
    mov   A, __i
    add   A, #low  (ROM_CFG_ADDR-8);      R6 R7 = BootOptions + i
    mov   R7, A
    clr   A
    addc  A, #high (ROM_CFG_ADDR-8);
    mov   R6, A
    mov   A, R6
    push  ACC                      ;      save it
    mov   A, R7
    push  ACC                      ;
    mov   A, #cmdbuffer+6          ;      value = cmdbuffer[6+i]<< 8 | cmdbuffer[5+i]
    add   A, __i
    mov   R0, A
    mov   A, @R0
    mov   R6, A
    mov   A, #cmdbuffer+5          ;
    add   A, __i
    mov   R0, A
    mov   A, @R0
    mov   R5, A                    ;      result = WriteFlashCode(addr,value)
    mov   A, R6
    mov   R4, A
    pop   ACC
    mov   R7, A
    pop   ACC
    mov   R6, A
    Xcall WriteFlashCode           ;
    xch   A, __result
    mov   A, R7
    xch   A, __result
    inc   __i
    inc   __i
    mov   A, __i
    clr   C
    subb  A, #10                   ;
    jc    JumpF7_Loop1
    Xjmp  FuncBreak                ;

;****************************
;read boot options
;<a7> <?> <?> <0x10> == read serial and calc snsum
;<a7> <?> <?> <0x08> == read loaderVer
;<a7> <?> <?> <0x07> == read cfgSpace
;<a7> <?> <?> <0x1F> == read all of the obove
JumpFunction6:                         ;read cfg
    mov   A, cmdbuffer+3               ;V2.4 result &= 0x1F;  
    anl   A, #0x1F 
    mov   __result,A
    mov   A, cmdbuffer+3               ;if (cmdbuffer[3] & 0x07 == 0x07)
    anl   A, #7
    xrl   A, #7
    jnz   code_3AEE                    ;{ 
    mov   CAddr+0, #high (ROM_CFG_ADDR-8);   CAddr = BootOptions
    mov   CAddr+1, #low  (ROM_CFG_ADDR-8)

    mov   __i, A                       ;   for (i=0;i<10 i++)
JumpF6_Loop1:                          ;   {
    mov   DPL, CAddr+1                 ;      R7=CBYTE[CAddr]
    mov   DPH, CAddr+0                 ;
    clr   A
    movc  A, @A+DPTR
    mov   R7, A
    mov   A, #low EP2_IN_BUFFER        ;     EP2_IN_BUFFER[rLen]=R7
    add   A, rlen
    mov   DPL, A                       ;
    clr   A
    addc  A, #high EP2_IN_BUFFER
    mov   DPH, A                       ;
    mov   A, R7
    movx  @DPTR, A
    inc   CAddr+1                      ;     CAddr++
    mov   A, CAddr+1
    jnz   code_3AD6
    inc   CAddr+0
code_3AD6:                             ;
    inc   rlen                         ;      rLen++
    inc   __i
    cjne  __i, #10, JumpF6_Loop1       ;   }
    inc   rlen                         ;   rLen+2
    inc   rlen
    mov   DPTR, #EP2_IN_BUFFER+10      ;   R7=EP2_IN_BUFFER[10] & ~bBOOT_LOAD
    movx  A, @DPTR
    anl   A, #not bBOOT_LOAD           ;
    mov   R7, A
    movx  @DPTR, A
    mov   A, GLOBAL_CFG                ;   A = GLOBAL_CFG & bBOOT_LOAD
    anl   A, #bBOOT_LOAD
    orl   A, R7                        ;   EP2_IN_BUFFER[10] = A | R7
    movx  @DPTR, A                     ;}

code_3AEE:                             ;
    mov   A, cmdbuffer+3               ;if (cmdbuffer[3] & 0x08)
    jnb   ACC.3, code_3B12             ;{
    clr   A                            ;   for (i=0;i<4;i++)
    mov   __i, A
JumpF6_Loop2:                          ;   {
    mov   A, __i
    mov   DPTR, #BLoaderVer            ;
    movc  A, @A+DPTR
    mov   R7, A
    mov   A, #low EP2_IN_BUFFER        ;      EP2_IN_BUFFER[rLen] = CBYTE[BLoaderVer+i];
    add   A, rlen
    mov   DPL, A                       ;
    clr   A
    addc  A, #high EP2_IN_BUFFER
    mov   DPH, A                       ;
    mov   A, R7
    movx  @DPTR, A
    inc   rlen                         ;      rLen++;
    inc   __i                          ;   }
    cjne  __i, #4, JumpF6_Loop2        ;}

code_3B12:                             ;
    mov   A, cmdbuffer+3               ;if (cmdbuffer[3] & 0x10)
    jnb   ACC.4, code_3B53             ;{

    mov   CAddr+0, #high ROM_CHIP_ID_LO
    mov   CAddr+1, #low  ROM_CHIP_ID_LO

    clr   A
    mov   SnSum, A                     ;   snSum=0;
    mov   __i, A                       ;   for (i=0; i<4 ;i ++)
JumpF6_Loop3:                          ;
    mov   DPL, CAddr+1                 ;   {
    mov   DPH, CAddr+0                 ;
    clr   A                            ;       R7=CBYTE[addr]
    movc  A, @A+DPTR
    mov   R7, A
    mov   A, #low EP2_IN_BUFFER        ;       EP2_IN_BUFFER[rLen] = R7
    add   A, rlen
    mov   DPL, A                       ;
    clr   A
    addc  A, #high EP2_IN_BUFFER
    mov   DPH, A                       ;
    mov   A, R7                        ;       SnSum+= EP2_IN_BUFFER[rLen];
    movx  @DPTR, A
    ;inc   rlen                         ;       rLen++;
    add   A, SnSum
    mov   SnSum, A
    inc   CAddr+1                      ;       addr ++;
    mov   A, CAddr+1
    jnz   code_3B49
    inc   CAddr+0
code_3B49:                             ;
    inc   rlen                         ;v2.5   rLen++;
    inc   __i
    cjne  __i, #4, JumpF6_Loop3        ;   }
;new in v2.5 
    clr     A                         ;   i=0; 
    mov   __i, A
code_3B64:
    mov   A, #low EP2_IN_BUFFER        ;  do 
    add   A, rlen
    mov   DPL, A                       ;  {
    clr   A
    addc  A, #high EP2_IN_BUFFER       ;   EP2_IN_BUFFER[rLen] = 0;
    mov   DPH, A
    clr   A
    movx  @DPTR, A
    inc   rlen                         ;   rlen --
    inc   __i                          ;   
    cjne  __i, #4, code_3B64           ;  } while (++i < 4)

code_3B53:                             ;
    mov   SAFE_MOD,   #0x55            ;  SAFE_MOD = 0x55;
    mov   SAFE_MOD,   #0xAA            ;  SAFE_MOD = 0xAA;
    mov   GLOBAL_CFG, #0xC             ;  GLOBAL_CFG = bCODE_WE | bDATA_WE
    clr   A                            ;
    mov   SAFE_MOD, A                  ;  SAFE_MOD=0;
    sjmp  FuncBreak                    ;  break
;****************************
;<a2> <x> <x> <param>
JumpFunction1:                         ;
    mov   A, cmdbuffer+3               ;if (cmdbuffer[3]==1)
    cjne  A, #1, code_3B6A
    setb  bSoftReset                   ;   bSoftReset=1;
    sjmp  code_3B6C

code_3B6A:                             ;
    setb  bWrProtect                   ;else bWrProtect=1;

code_3B6C:                             ;
    clr   A                            ;result=0
    mov   __result, A
;****************************
FuncBreak:                             ;
    mov   DPTR, #EP2_IN_BUFFER         ;
    mov   A, cmdbuffer+0               ;EP2_IN_BUFFER[0]= cmdbuffer[0]
    movx  @DPTR, A
    mov   A, rlen
    add   A, #-4                       ;0xFC
    mov   DPTR, #EP2_IN_BUFFER+2       ;EP2_IN_BUFFER[2]= rlen - 4
    movx  @DPTR, A
    clr   A
    inc   DPTR                         ;EP2_IN_BUFFER[3]= 0;
    movx  @DPTR, A
    inc   DPTR
    mov   A, __result                  ;EP2_IN_BUFFER[4]= result
    movx  @DPTR, A
    clr   A                            ;todo remove this
    mov   Marker1, A                   ;clear all markers
    mov   Marker0, A
Dispatcher_Done:
    ret

; ===========================================================================
; void main (void)
; ===========================================================================
main:
;local vars
__hwcont  set R5              ; hw contition
__pins    set R6              ; 
__cfg     set R7              ; romcfg
__i       set R7              ; reused for loop 

    mov   SAFE_MOD, #0x55     ; change to 12MHz
    mov   SAFE_MOD, #0xAA     ;
    mov   A, CLOCK_CFG        ;
    anl   A, #not MASK_SYS_CK_SEL
    orl   A, #4               ; 12MHz
    mov   CLOCK_CFG, A        ;

    mov   DPTR, #ROM_CFG_ADDR-4  
    clr   A                   ; get the boot config
    movc  A, @A+DPTR
    mov   __cfg, A            ;
    jnb   ACC.1, code_3BC6    ;
    anl   UDEV_CTRL, #not bUD_PD_DIS ; switch Pullups on
code_3BC6:
    setb  bSoftReset          ;
    setb  bWrProtect          ;
    clr   bVerifyErr          ;v2.4

    mov   A, CHIP_ID          ;odd numbers only have one serial
    rrc   A                   ;
    mov   bChipTyp, C         ;
    clr   EA
    clr   TR0                 ;
    clr   TF0

    clr   A
    mov   __pins, A
    orl   TMOD, #1            ; Timer0 Mode 1
    mov   TL0, #low (0x64C0)  ; 
    mov   TH0, #high(0x64C0)  ; 
    setb  TR0                 ; 
    mov   A, GLOBAL_CFG       ;if (GLOBAL_CFG & bBOOT_LOAD)
    jnb   ACC.5, code_3BF7    ;{
    mov   DPTR, #0x0000       ;   check if flash is empty
    clr   A
    movc  A, @A+DPTR
    cjne  A, #0xFF, code_3BFB
    inc   DPTR
    clr   A
    movc  A, @A+DPTR
    cjne  A, #0xFF, code_3BFB  ;}
code_3BF7:                     ;
    mov   __pins, #3
    sjmp  code_3C3A

code_3BFB:
    mov   A, __cfg            ;
    jnb   ACC.1, code_3C06    ;
    mov   C,UDP               ; Pin P3.6
    clr   A
    rlc   A
    mov   __hwcont, A         ;save it
    sjmp  code_3C0F

code_3C06:
    jnb   MOSI, code_3C0D     ; checl P1.5 cont
    mov   __hwcont, #0                  
    sjmp  code_3C0F               

code_3C0D:
    mov   __hwcont, #1                                

code_3C0F: 
    mov   A, __hwcont         ; strange wy they check 
    jz    code_3C2B           ; HW cont again?                 
    mov   A, __cfg                                 
    jnb   ACC.1, code_3C1D                       
    mov   C, UDP              ; Pin P3.6
    clr   A                                     
    rlc   A                                     
    mov   __hwcont, A                                 
    sjmp  code_3C26                             

code_3C1D:
    jnb   MOSI, code_3C24     ; Pin P1.5                             
    mov   __hwcont, #0                                               
    sjmp  code_3C26                                            

code_3C24:
    mov   __hwcont, #1                                               
                                                                             
code_3C26:
    mov   A, __hwcont
    jz    code_3C2B                                            
    mov   R6, #3                                               
                                                                           
code_3C2B:
    mov   A, R6                                                
    jnz   code_3C3A                                            
    mov   A, __cfg
    jnb   ACC.0, code_3C3A                                      
    mov   TimeOut+0, #high(0x05DB)                                        
    mov   TimeOut+1, #low (0x05DB) ; (1500 - 1)            
    mov   R6, #1                                               

code_3C3A:
    mov   A, R6                          
    jnb   ACC.0, code_3C5F                
;v2.5                     ;

;start boudrate generator for serial mode
;for ch551/ch553 use T1 with uart0 
;otherwise use the SBAUD1 with uart1
    jnb   bChipTyp, code_3CE7 ;if(bChipTyp) {
    mov   SCON, #0x50         ;  SCON=0x50;
    clr   A
    mov   T2CON, A            ;  T2CON=0;
    mov   PCON, #SMOD         ;  
    orl   TMOD, #0x20         ;  T1 mode 2 
    mov   T2MOD,#bTMR_CLK or bT1_CLK;  T2MOD = bTMR_CLK | bT1_CLK;
    mov   TH1,  #0xF3         ;  TH1   = 0xF3;
    setb  TR1                 ;  TR1   = 1;
    sjmp  code_3C5D           ;} else
code_3CE7:                    ;{
    mov   SCON1, #0x30        ;   SCON1 = 30;
    mov   SBAUD1,#0xF3        ;   SBAUD = 0xF3;

code_3C5D:
    clr     bSoftReset                            
                                                              
code_3C5F:
    mov     A, R6                                 
    jnb     ACC.1, code_3C84                       
    mov     TimeOut+0, #4                         
    mov     TimeOut+1, #0xE2  ; 'Ô' ; 0x4E2 (1250) 

init_usb:
    clr   A                   ;
    mov   USB_CTRL, A         ;USB_CTRL=0;
    mov   UEP2_3_MOD, # bUEP2_RX_EN or bUEP2_TX_EN;
    mov   UEP0_DMA_H, A       ;UEP0_DMA=0;
    mov   UEP0_DMA_L, A       ;
    mov   UEP2_DMA_H, A       ;UEP2_DMA=0x000C
    mov   UEP2_DMA_L, # low EP2_OUT_BUFFER;
    mov   USB_CTRL,   # bUC_DEV_PU_EN or bUC_INT_BUSY or bUC_DMA_EN
    mov   UDEV_CTRL,  # bUD_PD_DIS or bUD_PORT_EN
    mov   USB_INT_FG, # 0xFF   ;
    mov   USB_INT_EN, # bUIE_SUSPEND or bUIE_TRANSFER or bUIE_BUS_RST

code_3C84:
    clr   A                    ; for i=0;i<8; i++
    mov   R7, A

code_3C86:
    mov   A, #0x24 
    add   A, R7
    mov   R0, A
    mov   @R0, TL0 
    inc   R7
    cjne  R7, #8, code_3C86


mainloop:                    ;while(1) {

    jnb   bSoftReset, code_3C9C;  if (bSoftReset) {
    mov   SAFE_MOD, #0x55    ;      SAFE_MOD = 0x55
    mov   SAFE_MOD, #0xAA    ;      SAFE_MOD = 0xAA
    mov   GLOBAL_CFG, # bSW_RESET;  while(1);
    sjmp  $                  ;
code_3C9C:                   ;    }
    jb    U1RI, code_3CA4    ;
    jnb   RI, code_3CAA      ;    if ((U1RI) || (RI)) SerialDispatcher();
code_3CA4:                   ;
    mov   Marker0, #0x96     ;
    Xcall SerialDispatcher   ;

code_3CAA:                   ;
    mov   A, USB_INT_FG      ;    if (USB_INT_FG & 0x07) HandleUsbEvents();
    anl   A, #7              ;
    jz    code_3CB6
    mov   Marker0, #0x96     ;
    Xcall HandleUsbEvents    ;

code_3CB6:                   ;
    jnb   TF0, mainloop      ;    if (TF0)
    clr   TF0                ;        TF0=0
    ;clr   TR0                ;        TR0=0;
    mov   TL0, #0xC0         ;
    mov   TH0, #0x64         ; 
    inc   TimeOut+1          ;    Timeout ++
    mov   A, TimeOut+1
    jnz   code_3CC9
    inc   TimeOut+0

code_3CC9:
    clr   C
    subb  A, #0xDC ; '_'
    mov   A, TimeOut+0
    subb  A, #5
    jc    mainloop
    setb  bSoftReset
    sjmp  mainloop           ;}


; =============== S U B R O U T I N E =======================================
HandleUsbEvents:                       ; 0x3B88
;local vars
__len     set  OverLay+0
__ptr     set  OverLay+4
__size    set  OverLay+7
    jb    UIF_TRANSFER, code_3B8E      ;
    Xjmp  usb_reset

code_3B8E:                             ; get the UIF_TRANSFER source
    mov   A, USB_INT_ST                ;
    anl   A, #bUIS_TOKEN1 or bUIS_TOKEN0 or 0x0F;
    jnz   code_l1
    Xjmp  EP0OutTransfer               ;
code_l1:
    add   A, #0xE0                     ;
    jnz   code_l2
    Xjmp  Ep0InTransfer                ;UIS_TOKEN_IN | 0                          ;
code_l2:
    add   A, #0xFE                     ;
    jz    EP2InTransfer                ;UIS_TOKEN_IN | 2
    add   A, #0xF2                     ;
    jz    SetupPacket                  ;UIS_TOKEN_SETUP | 0
    add   A, #0x2E                     ;
    jz    Ep2OutTransfer               ;UIS_TOKEN_OUT | 2
    Xjmp  transfer_done
;**************************************
Ep2OutTransfer:                        ;3BAD
    jb    U_TOG_OK, code_3BB3          ;
    Xjmp  transfer_done
;**************************************
code_3BB3:                             ;
    mov   __len, USB_RX_LEN           ;
    mov   __ptr+0, #1                 ;source xdata
    mov   __ptr+1, #high EP2_OUT_BUFFER
    mov   __ptr+2, #low  EP2_OUT_BUFFER
    mov   __size, __len
    mov   R3, #0                       ;dest idata
    mov   R2, #high cmdbuffer
    mov   R1, #low  cmdbuffer          ;
    Xcall memcpy
    mov   Marker1, #0x5A               ;
    Xcall FunctionDispatcher
    mov   UEP2_T_LEN, rlen             ;len
    anl   UEP2_CTRL, #not MASK_UEP_T_RES; 0xFC
    Xjmp  transfer_done
;**************************************
EP2InTransfer:                         ;3BDA
    mov   A, UEP2_CTRL                 ;
    anl   A, #not MASK_UEP_T_RES       ;0xFC
    orl   A, #UEP_T_RES_NAK
    mov   UEP2_CTRL, A                 ;
    Xjmp  transfer_done
;**************************************
SetupPacket:                           ;3BE5
if (ADD_USB_BUGFIX=1)
    ANL     UEP0_CTRL,#0F2H            ;stallbug
endif
    mov   A, USB_RX_LEN                ;
    xrl   A, #8
    jnz   code_3C54
    mov   DPTR, #EP0_BUFFER+6          ;
    movx  A, @DPTR
    mov   reqlen, A                    ;
    clr   bReqError                    ;
    mov   DPTR, #EP0_BUFFER+0          ;if (brequesttype & typemask)
    movx  A, @DPTR
    anl   A, #0x60
    jz    StdRequest                   ;
    setb  bReqError
    sjmp  Setup_break                  ;break

StdRequest:                            ;3BFF
    mov   DPTR, #EP0_BUFFER+1          ;brequest= Ep0Buffer[1]
    movx  A, @DPTR
    mov   bRequest, A                  ;
    mov   A, bRequest
    add   A, #0xFB                     ;
    jz    Set_Address
    add   A, #0xFD                     ;
    jz    GetConfig
    dec   A
    jz    SetConfig
    add   A, #3
    jnz   Setup_default
    mov   DPTR, #EP0_BUFFER+3
    movx  A, @DPTR
    add   A, #0xFE                     ;
    jz    GetConfigDesc
    inc   A
    jnz   DescUnknown
GetDeviceDesc:
    mov   DescAddr+0, #HIGH DeviceDesc
    mov   DescAddr+1, #LOW  DeviceDesc
    mov   __len, #18                  ;sizeof(DeviceDesc)
    sjmp  Setup_break
GetConfigDesc:                         ;3C2C
    mov   DescAddr+0, #HIGH ConfigDesc
    mov   DescAddr+1, #LOW  ConfigDesc
    mov   __len, #32                  ;sizeof(ConfigDesc)
    sjmp  Setup_break
DescUnknown:                           ;3C37
    setb  bReqError
    sjmp  Setup_break

Set_Address:                           ;3C3B
    sjmp  SetConfig

GetConfig:                             ;3C3D
    mov   DPTR, #EP0_BUFFER+0
    mov   A, wValueLo
    movx  @DPTR, A
    mov   __len, #1
    sjmp  Setup_break

SetConfig:                             ;3C48
    mov   DPTR, #EP0_BUFFER+2
    movx  A, @DPTR
    mov   wValueLo, A
    sjmp  Setup_break

Setup_default:                         ;3C50
    setb  bReqError
    sjmp  Setup_break

code_3C54:        ;
    setb  bReqError

Setup_break:                           ;3C56:
    jnb   bReqError, next_packet
    mov   bRequest, #0xFF
    mov   UEP0_CTRL, #bUEP_R_TOG or bUEP_T_TOG or UEP_R_RES_STALL or UEP_T_RES_STALL; 0xCF ;
    sjmp  transfer_done

next_packet:                           ;3C61
    mov   A, reqlen
    setb  C
    subb  A, __len
    jc    code_3C6B
    mov   reqlen, __len
code_3C6B:                             ;
    Xcall PrepareDescPacket
    mov   UEP0_CTRL, # bUEP_R_TOG or bUEP_T_TOG;0xC0 ;
    sjmp  transfer_done

;**************************************
Ep0InTransfer:                         ;3C73
    mov   A, bRequest
    add   A, #0xFB                     ;
    jz    status_address
    dec   A
    jnz   ep0In_default
    Xcall PrepareDescPacket
    xrl   UEP0_CTRL, #0x40 ;
    sjmp  transfer_done

status_address:                        ;3C84
    mov   A, USB_DEV_AD                ;
    anl   A, #0x80
    orl   A, wValueLo
    mov   USB_DEV_AD, A                ;
    sjmp  EP0OutTransfer
ep0In_default:                         ;3C8E
    clr   A
    mov   UEP0_T_LEN, A                ;send a ZLP
    sjmp  EP0OutTransfer

;**************************************
EP0OutTransfer:                        ;3C93
    mov   UEP0_CTRL, #UEP_T_RES_NAK    ;

transfer_done:
    clr   UIF_TRANSFER                 ;
    ret

;check other Irqs
usb_reset:
    jnb   UIF_BUS_RST, usb_suspend
    mov   UEP0_CTRL, #UEP_T_RES_NAK    ;
    mov   UEP2_CTRL, #bUEP_AUTO_TOG or UEP_T_RES_NAK
    clr   A
    mov   USB_DEV_AD, A                ;
    sjmp  usb_done

usb_suspend:
    jnb   UIF_SUSPEND, usb_done        ;
    clr   UIF_SUSPEND                  ;
    ret
;we are done
usb_done:                              ;3CAD
    mov   USB_INT_FG, #0xFF            ;
    ret

; =============== S U B R O U T I N E =======================================

;uint8_t SerialDispatcher(void)
;  uint8_t ch
;  uint8_t chk;
;  uint8_t i;
SerialDispatcher:            ; 0x3D94
__ch      SET R7
__chk     SET R6
__i       SET R5

    Xcall SerialGetChar      ;
    mov   A, __ch            ; if (SerialGetChar()!=0x57) return ;
    xrl   A, #0x57
    jnz   Serial_done        ;
    Xcall SerialGetChar      ;
    mov   A, __ch            ; if (SerialGetChar()!=0xAB) return;
    xrl   A, #0xAB
    jnz   Serial_done        ;
    Xcall SerialGetChar      ; 3. char
    mov   cmdbuffer+0, __ch  ; buffer[0] = SerialGetChar();
    mov   __chk, cmdbuffer+0 ; chk = buffer[0]
    Xcall SerialGetChar      ; 4. char
    mov   cmdbuffer+1, __ch  ; buffer[1] = SerialGetChar();
    mov   A, cmdbuffer+1
    add   A, __chk           ; chk += buffer[1]
    mov   __chk, A
    Xcall SerialGetChar      ; 5. char
    mov   cmdbuffer+2, __ch  ; buffer[2] = SerialGetChar();
    clr   A
    mov   __i, A             ; for (i=0;i< buffer[1];i++)

code_3DBB:                   ;{
    mov   A, __i             ;   //recive loop
    xrl   A, cmdbuffer+1
    jz    code_3DCE
    Xcall SerialGetChar      ;   buffer[3+i] = SerialGetChar()
    mov   A, #cmdbuffer+3    ;
    add   A, __i             ;
    mov   R0, A
    mov   A, __ch
    mov   @R0, A
    add   A, __chk           ;   chk+= buffer[3+i];
    mov   __chk, A
    inc   __i                ;
    sjmp  code_3DBB          ;}

code_3DCE:                   ;
    Xcall SerialGetChar      ;if (SerialGetChar() != chk) exit
    mov   A, __ch
    xrl   A, __chk
    jnz   Serial_done        ; exit
code_3DF1:
    mov   Marker1, #0x5A     ;
    Xcall FunctionDispatcher ;
    clr   A
    mov   __chk, A           ; chk=0;
    mov   __ch, #0x55        ; SerialWriteChar(0x55)
    Xcall SerialWriteChar
    mov   __ch, #0xAA        ; SerialWriteChar(0xAA)
    Xcall SerialWriteChar
    mov   __i, A             ;for (i=0;i<rLen;i++)

code_3DEC:                   ;{
    mov   A, __i             ;   //sendloop
    clr   C
    subb  A, rlen
    jnc   code_3E11
    mov   A, #low  EP2_IN_BUFFER; SerialWriteChar(EP2_IN_BUFFER[i])
    add   A, __i
    mov   DPL, A             ;
    clr   A
    addc  A, #high EP2_IN_BUFFER
    mov   DPH, A             ;
    movx  A, @DPTR
    mov   __ch, A
    Xcall SerialWriteChar
    mov   A, #low  EP2_IN_BUFFER;  chk+=EP2_IN_BUFFER[i];
    add   A, __i
    mov   DPL, A              ;
    clr   A
    addc  A, #high EP2_IN_BUFFER
    mov   DPH, A              ;
    movx  A, @DPTR 
    add   A, __chk
    mov   __chk, A
    inc   __i
    sjmp  code_3DEC           ;}

code_3E11:                    ;
    xch   A, __ch
    mov   A, __chk            ;SerialWriteChar(chk)
    xch   A, __ch
    Xcall SerialWriteChar     ;

Serial_done:
    ret


; ---------------------------------------------------------------------------
CopyrightMsg:                 ;0x3665
                db  'MCU ISP & WCH.CN',0 ;

DeviceDesc:                   ;0x3E76
                db    18
                db     1
                db  0x10,0x01 ; USB_bcd 1.1
                db  0xFF      ; class vendor defined
                db  0x80      ; subclass ??
                db  0x55      ; protocol ??
                db     8      ; EP0 Size
                db  0x48,0x43 ; Vendor ID 0x4843
                db  0xE0,0x55
                db  0x50,0x02 ; V2.40 

                db     0
                db     0
                db     0
                db     1

ConfigDesc:                  ;0x3E88
                db     9
                db     2
                db  0x20,0x00;
                db     1     ; 1 interface
                db     1     ; config
                db     0     ; no string
                db  0x80     ; buspower
                db  100/2    ; 100 mA

InterfaceDesc:  db     9
                db     4
                db     0
                db     0
                db     2     ; 2 EndPoints
                db  0xFF     ; vendor
                db  0x80     ; subclass
                db  0x55     ; protocoll
                db     0

EndPointDesc:                 ;0x3E9A
                db     7
                db     5
                db  0x82      ; EP2 IN
                db     2      ; bulk
                db  0x40,0x00 ; size
                db     0

                db     7
                db     5
                db     2      ; EP2 Out
                db     2      ; bulk
                db  0x40,0x00 ; size
                db     0

BLoaderVer:                   ;3EA8
                db     0      ;version 02.31 in BCD
                db     2
                db     5
                db     0


; =============== S U B R O U T I N E =======================================
;uint8_t WriteFlashCode(uint16_t Address uint16_t Data)
WriteFlashCode:            ;0x3EAC:
    mov   A, Marker0       ;Todo remove this
    xrl   A, #0x96
    jz    $+4
    sjmp  $
;if ( (Address < BOOT_LOAD_ADDR) || ((Address >= BootOptions ) && (Address < ROM_CFG_ADDR)))
    clr   C                ;
    mov   A, R6
    subb  A, #high BOOT_LOAD_ADDR  ;
    jc    code_3ECB        ;
    mov   A, R7            ;
    subb  A, #low  (ROM_CFG_ADDR-8);
    mov   A, R6
    subb  A, #high (ROM_CFG_ADDR-8);
    jc    code_3EE1        ;
    setb  C
    mov   A, R7            ;
    subb  A, #low  ROM_CFG_ADDR  ;
    mov   A, R6
    subb  A, #high ROM_CFG_ADDR  ;
    jnc   code_3EE1

code_3ECB:                 ; AddressRange ok
    mov   ROM_ADDR_H, R6   ; ROM_ADDR = Address
    mov   ROM_ADDR_L, R7   ;
    mov   ROM_DATA_H, R4   ; ROM_DATA = Data
    mov   ROM_DATA_L, R5   ;
    mov   A, ROM_CTRL      ;
    jnb   ACC.6, code_3EE1  ;
    mov   ROM_CTRL, #ROM_CMD_WRITE
    mov   A, ROM_CTRL      ;
    xrl   A, #0x40
    mov   R7, A
    ret
code_3EE1:                 ; return error
    mov   R7, #0x40        ;
    ret

; =============== S U B R O U T I N E =======================================
PrepareDescPacket:          ;
__src     set  OverLay+4
__len     set  OverLay+7
    mov   A, reqlen
    clr   C
    subb  A, #8
    jc    code_3F09
    mov   R7, #8
    sjmp  code_3F0B

code_3F09:                  ;
    mov   R7, reqlen        ; len

code_3F0B:                  ;
    xch   A, R6
    mov   A, R7
    xch   A, R6
    mov   __src+0, #0xFF      ; code
    mov   __src+1, DescAddr+0 ; addr
    mov   __src+2, DescAddr+1
    mov   __len, R6
    mov   R3, # 1             ; xdata
    mov   R2, # high(EP0_BUFFER) 
    mov   R1, # low (EP0_BUFFER)
    Xcall memcpy
    clr   C
    mov   A, reqlen
    subb  A, R6
    mov   reqlen, A
    mov   A, R6
    add   A, DescAddr+1
    mov   DescAddr+1, A
    clr   A
    addc  A, DescAddr+0
    mov   DescAddr+0, A
    mov   UEP0_T_LEN, R6    ;
    ret

; =============== S U B R O U T I N E =======================================
; c runtime memcpy
;void mem_cpy (uint8_t *dest,uint8_t *src,uint8_t len)
;{
;   while(len--) *dest++ = *src++;
;}
memcpy:         
__dest    set  OverLay+1
__src     set  OverLay+4
__len     set  OverLay+7

    mov   __dest+0, R3       ; save dest ptr
    mov   __dest+1, R2
    mov   __dest+2, R1

code_3F21:                   ; while (len--)
    mov   R7, __len
    dec   __len
    mov   A, R7
    jz    code_3F4E          ; done

    mov   R3, __src+0       ; 
    inc   __src+2
    mov   A, __src+2        ;RamE/F++
    mov   R2, __src+1
    jnz   code_3F34
    inc   __src+1
code_3F34:                   ;
    dec   A
    mov   R1, A
    Xcall loadFromPtr        ;
    mov   R7, A
    mov   R3, __dest+0
    inc   __dest+2
    mov   A, __dest+2
    mov   R2, __dest+1
    jnz   code_3F46
    inc   __dest+1

code_3F46:                   ;
    dec   A
    mov   R1, A
    mov   A, R7
    Xcall storeToPtr
    sjmp  code_3F21          ; goto loop

code_3F4E:                   ; done
    ret

; =============== S U B R O U T I N E =======================================
;c runtime  loadFromPtr
loadFromPtr:                  ; 0x3F4F
    cjne  R3, #1, code_3F58
    mov   DPL, R1             ;
    mov   DPH, R2             ;
    movx  A, @DPTR
    ret
code_3F58:                    ; from idata
    jnc   code_3F5C
    mov   A, @R1
    ret
code_3F5C:                    ; from xdata
    cjne  R3, #0xFE, code_3F61;
    movx  A, @R1
    ret
code_3F61:                    ; from code
    mov   DPL, R1             ;
    mov   DPH, R2             ;
    clr   A
    movc  A, @A+DPTR
    ret

; =============== S U B R O U T I N E =======================================
;c runtime
storeToPtr:                   ;0x3F68
    cjne  R3, #1, code_3F71   ;
    mov   DPL, R1             ;
    mov   DPH, R2             ;
    movx  @DPTR, A
    ret
code_3F71:                    ; to idata
    jnc   code_3F75
    mov   @R1, A
    ret
code_3F75:                    ;
    cjne  R3, #0xFE, code_3F79;
    movx  @R1, A
code_3F79:                    ;
    ret
; =============== S U B R O U T I N E =======================================
;uint8_t WriteFlashData(uint8_t Address,unt8_t value);
WriteFlashData:               ; 0x3F7A
    mov   A, Marker0          ;Todo remove this
    xrl   A, #0x96
    jz    code_3F82
    sjmp  $
code_3F82:                    ;
    mov   ROM_ADDR_H, #high DATA_FLASH_ADDR
    mov   A, R7
    add   A, ACC              ;
    mov   ROM_ADDR_L, A       ;
    mov   ROM_DATA_L, R5      ;
    mov   A, ROM_CTRL         ;
    jnb   ACC.6, code_3F9A    ;
    mov   ROM_CTRL, #0x9A     ;
    mov   A, ROM_CTRL         ;
    xrl   A, #0x40
    mov   R7, A
    ret
code_3F9A:                    ;
    mov R7, #0x40             ;
    ret
; =============== S U B R O U T I N E =======================================

;void SerialWriteChar(uint8_t Send);
SerialWriteChar:              ;0x3F9D
    jnb  bChipTyp, code_3FAA
    clr  TI                   ;
    mov  SBUF, R7             ; send the char
    jnb  TI, $                ; wait until send
    clr  TI                   ;
    ret
code_3FAA:                    ;
    clr  U1TI                 ;
    mov  SBUF1, R7            ; Send the char
    jnb  U1TI,$               ; wait until send
    clr  U1TI                 ;
    ret
; =============== S U B R O U T I N E =======================================
;uint8_t SerialGetChar (void)
SerialGetChar:                ;0x3FB4
    jnb  bChipTyp, code_3FBF
    jnb  RI, $                ; wait for a char
    clr  RI                   ;
    mov  R7, SBUF             ; and return it
    ret
code_3FBF:                    ;
    jnb   U1RI, $             ; wait for a char
    clr   U1RI                ;
    mov   R7, SBUF1           ; and return it
    ret

; =============== S U B R O U T I N E =======================================
C_C51STARTUP:                 ;
    mov   R0, # 127           ;
    clr   A
IDATALOOP:                    ;Init idata
    mov   @R0, A
    djnz  R0, IDATALOOP
    mov   SP, #STACK-1        ;Stack Pointer
    Xjmp  main                ;start with main
;***************************************
$NOLIST
;fill the rest with 0xFF
rept ((StartAddress or  07F0h) - $)
    DB    0FFh
endM

end

