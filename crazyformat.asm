
org #C000

defb 1 ; expansion ROM
;----- bullshit -----------
defb 0 ; mark number
defb 1 ; version
defb 0 ; modification level

defw rsxnames

jp rominit
jp format

rsxnames
str 'init' ; lower case makes an hidden RSX
str 'FORMAT'
defb 0

; Not really initialisation, only displaying a message
rominit
push af,bc,de,hl
ld hl,disclaimer
.loop ld a,(hl) : and #7F : call #BB5A
bit 7,(hl) : jr nz,rominitend
inc hl
jr .loop
rominitend
pop hl,de,bc,af
scf
ret

disclaimer defb 'Forma-tatatata Ultra ROM',13,13,10+#80

; RSX copy code+sample to RAM for decrunch
format
ld hl,format_begin
ld de,#4000
ld bc,format_end-format_begin
ldir
call #6000
ret


format_begin

org #4000,$

incbin 'atata.smp',0,8192 ; sample data from #4000 to #5FFF can loop easily

init_sample
; cut interrupts, backup register and stack to quit from anywhere if needed
di : exx : exa : push af,bc,de,hl,ix,iy : ld (restore_registers.backsp+1),sp

ld a,1 : ld bc,#FA7E : out (c),a ; motor ON

; decrunch intro sample and end sample
ld hl,ataaa
ld de,freespace
call dzx0_turbo
ld hl,rhooo
ld de,freespace+3294 ; 6356
call dzx0_turbo

ld de,#C080 ; acknowledge values

ld hl,#0700+%00111101 ; Audio channel B only
call .sendpsg
ld hl,#0900 ; default volume to zero and init register 9 usage
call .sendpsg
jr .endinit

.sendpsg
ld bc,#F4F6
out (c),h ; reg
ld b,c
out (c),d
out (c),0
ld b,#F4
out (c),l ; valeur
ld b,c
out (c),e
out (c),0
ret
.endinit

; play intro sample
ld hl,freespace+3294
exx
ld bc,6356+256
call play_sm4

exx
ld hl,#4000 ; set looping sample for next operations
exx


;****************************************************
;       main loop from track 0 to 41
;****************************************************

ld bc,#FB7E
xor a : ld (track),a

.alltrack
call get_state    ; enforce drive and floppy ready to format
call seek_track   ; go to track
call format_track ; format DATA
ld a,(track) : inc a : ld (track),a
cp 42
jr nz,.alltrack
xor a : ld (track),a
call calibrate   ; get back to track zero

; play end sample
exx
ld hl,freespace
exx
ld bc,3294+256
call play_sm4

;pop iy,ix,hl,de,bc,af : exx : exa
call restore_registers
back2system
; mixer OFF
ld bc,#F4F6 : ld de,#80C0 : ld a,7 : out (c),a
ld b,c : out (c),e : out (c),0
ld b,#F4 : ld a,%00111111 : out (c),a
ld b,c : out (c),d : out (c),0
ld bc,#FA7E : out (c),0
ei
ret

nbresult defb 0
result defs 7

;****************************

macro LOOP_HL
res 5,h ; loop from #4000 to #6000
mend

; GET ET3 / FDC function 4
get_state
ld a,4 : call pushfdc
xor a  : call pushfdc
call getresult
ld a,(nbresult) : cp 1 : jp nz,error_et3
ld a,(result)
bit 7,a : jp nz,error_outoforder
bit 5,a : jp z,error_ready
bit 6,a : jp nz,error_protected
call play_64
ret

; CALIBRATION / FDC function 7
calibrate
call play_64
ld a,7 : call pushfdc
ld a,0 : call pushfdc
jr seek_track.waitseek

; SEEK TRACK / FDC function 15
seek_track
ld a,15 : call pushfdc
ld a,0  : call pushfdc
ld a,(track) : call pushfdc
.waitseek
call play_64
call get_int
ld a,(nbresult) : cp 2 : jr nz,.waitseek
ld a,(result) : cp 32 : jr nz,.waitseek
ld a,(result+1)
track=$+1 : cp #12 : jr nz,calibrate
call play_sample
ret

idlist defb #C1,#C6,#C2,#C7,#C3,#C8,#C4,#C9,#C5,0

; FORMAT TRACK / FDC function #4D
format_track
ld hl,idlist
ld a,(track) : ld e,a
ld a,#4D : call pushfdc
ld a,0   : call pushfdc ; drive
ld a,2   : call pushfdc ; taillesect
ld a,9   : call pushfdc ; nbsect
ld a,#50 : call pushfdc ; GAP
ld a,#E5 : call pushfdc ; filler
jr .ready

; we must continue to play 15Khz sample while we are waiting FDC to give him sector informations
.ready : in a,(c) : jp m,.send ; 1st wait
exx
dec b ; #F6->#F5
outi
exx
in a,(c) : jp m,.send
exx
ld b,c
out (c),e
exx
in a,(c) : jp m,.send
exx
out (c),0
exx
in a,(c) : jp m,.send
exx
LOOP_HL (void)
exx
in a,(c) : jp m,.send
in a,(c) : jp p,.ready

; when we have to send DATA to FDC in execution phase, we wont wait so we can avoid managing sample replay
.send
; piste/tete/ID/SS
inc c : out (c),e : dec c
.wparam2 in a,(c) : jp p,.wparam2
xor a : inc c : out (c),a : dec c
.wparam3 in a,(c) : jp p,.wparam3
inc b : inc c : outi : dec c 
.wparam4 in a,(c) : jp p,.wparam4
ld a,2 : inc c : out (c),a : dec c
exx
LOOP_HL (void)
ld b,#F5
outi
LOOP_HL (void)
ld b,c
out (c),e
out (c),0
exx
; is there any sector left? Yes, go back to WAIT+REPLAY routine
ld a,(hl) : or a : jr nz,.ready ; again!

call play_64
call getresult

; Error check
ld a,(nbresult) : cp 7 : jp nz,error_format_result
ld a,(result+0) ; ET0
and 128+64+16+8 ; => ERROR (no disk, calib faile, head unavailable)
jp nz,error_format_et0
ld a,(result+0) ; ET0
and 32 ; terminated
jp nz,error_format_et0
ld a,(result+1) ; ET1
and 16+2 ; => ERROR (overrun or protected) => DO NOT CHECK END OF TRACK because we want to deformat some ;)
jp nz,error_protected_or

call play_64

ret


; GET INT STATE / FDC function 8
get_int
ld a,8 : call pushfdc
call getresult
ret

; play 64 samples
play_64
ld a,64
.loop
push af
ld a,8
dec a : jr nz,$-1
pop af
call play_sample ; 16
dec a
jr nz,.loop
ret

play_sample
exx
dec b ; #F6->#F5
outi
LOOP_HL
ld b,c
out (c),e
out (c),0
exx
ret

; HL'=sample
; BC =length
;
; SM4 sample is a data format when RASM import WAV samples
; each sample is on 2 bit representing levels 0,13,14,15
; this method has a very good quality regarding the data
;
play_sm4
.rhooo
exx
ld b,#F4
ld a,(hl)
rlca : rlca : rlca : rlca : and %1100 : jr z,.outi
or %11
.outi
out (c),a
ld b,c
out (c),e
out (c),0
ld a,8 : dec a : jr nz,$-1
;
ld b,#F4
ld a,(hl)
nop : nop : rrca : rrca : and %1100 : jr z,.outi2
or %11
.outi2
out (c),a
ld b,c
out (c),e
out (c),0
ld a,8 : dec a : jr nz,$-1
;
ld b,#F4
ld a,(hl)
nop 4 : and %1100 : jr z,.outi3
or %11
.outi3
out (c),a
ld b,c
out (c),e
out (c),0
ld a,7 : dec a : jr nz,$-1
;
ld b,#F4
ld a,(hl) : inc hl
nop : nop : rlca : rlca : and %1100 : jr z,.outi4
or %11
.outi4
out (c),a
ld b,c
out (c),e
out (c),0
ld a,7 : dec a : jr nz,$-1
;
exx
dec c
jr nz,.rhooo
djnz .rhooo
ret

pushfdc
exa
.ready in a,(c) : add a : jr nc,.ready : add a : ret c
exa
inc c
out (c),a
dec c
ret

; compact version for GetResult
getresult
push de,hl
ld d,7 ; nombre MAX de valeurs a recuperer
ld hl,result
.wait_ready in a,(c) : jp p,.wait_ready ; attente du READY
and 64 : jr z,.done                ; doit-on recuperer quelque chose?
inc c : in a,(c) : dec c
ld (hl),a : inc hl ; store!
dec d
jr nz,.wait_ready
.done
ld a,7
sub d
ld (nbresult),a
pop hl,de
ret

error_et3
call restore_registers
ld hl,.errstr : call printstr : jp back2system
.errstr defb 'Error getting drive state',13,10,0

error_outoforder
call restore_registers
ld hl,.errstr : call printstr : jp back2system
.errstr defb 'Drive out of order',13,10,0

error_ready
call restore_registers
ld hl,.errstr : call printstr : jp back2system
.errstr defb 'Drive is not ready / floppy not inserted',13,10,0

error_protected
call restore_registers
ld hl,.errstr : call printstr : jp back2system
.errstr defb 'Floppy is protected',13,10,0


error_format_result
call restore_registers
ld hl,.errstr : call printstr : jp back2system
.errstr defb 'Error getting format result',13,10,0

error_format_et0
call restore_registers
ld hl,.errstr : call printstr : jp back2system
.errstr defb 'Format gone wrong',13,10,0

error_protected_or
call restore_registers
ld hl,.errstr : call printstr : jp back2system
.errstr defb 'Floppy protected or buffer overrun during format',13,10,0


printstr
.reloop ld a,(hl) : or a : ret z : inc hl : call #BB5A : jr .reloop

restore_registers pop hl ; retour
exx
.backsp ld sp,#1234
pop iy,ix,hl,de,bc,af : exx : exa : push hl : ret

rhooo inczx0 'rhooo.sm4'
ataaa inczx0 'ataaa.sm4'

include 'dzx0_turbo.asm'

freespace

org $

format_end


save "crazyformat.rom",#C000,#4000


