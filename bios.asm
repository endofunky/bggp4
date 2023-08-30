;;
;;
;;     ┬                 ┬         ┌─┐  A self-replicating BIOS ROM
;;     │                 │         │ ┴
;;     │                 │         │    Submitted to Binary Golf Grand Prix #4
;;     │                 │         │
;;     │                 │         │    endofunky <ebbg (ng) shmmrq.bet>
;;     │                 │   ·     │
;;     ├─┐ ┌─┐ ┌─┐ ┌─┐   ├─┐ │ ┌─┐ └─┐  0x510F3BD00000DEAD
;;     │ │ │ │ │ │ │ │ ─ │ │ │ │ │ │ │
;;     └─┘ └─┤ └─┤ ├─┘   └─┘ ┴ └─┘ └─┘
;;           │   │ │
;;           │   │ │                    Social:
;;           │   │ │
;;           │   │ │                    t: @endofunky
;;           │   │ │
;;          ─┘  ─┘ ┴                    m: @aa55@mastodon.social
;;
;;
;; Overview
;; ---------------------------------------------------------------------------
;;
;; A BIOS ROM for Binary Gold Grand Prix 4 (https://binary.golf/) that:
;;
;; - Initialized VGA mode 0x13 and prints '4'
;; - Creates a FAT12 file system on disk 0
;; - Replicates itself to a file called '4'
;;
;; How it works:
;; ---------------------------------------------------------------------------
;;
;; Build with NASM as a flat binary:
;;
;;     % nasm -f bin -o bios.rom bios.asm
;;
;; Generate HDD disk image for QEMU. This needs to be equal to or larger than
;; 135 * 512 byte sectors - or 69120 bytes:
;;
;;     % qemu-img create hdd.img 69120
;;
;; Run QEMU with the BIOS ROM and disk attached:
;;
;;     % qemu-system-i386 -drive file=hdd.img,format=raw -bios bios.rom
;;
;; Mount the disk image:
;;
;;     % sudo mount -o loop hdd.img /mnt
;;
;; Compare the SHA hashes:
;;
;;     % sha256sum /mnt/4 bios.rom
;;
;; Anecdotes / "Write-Up"
;; ---------------------------------------------------------------------------
;;
;; This was quite a journey. Once BGGP was announced, I spent a more than the
;; first month trying to find something exploitable to write a file for.
;; Unfortunately, I either did not look hard enough or, more likely, need to
;; practice a bit more. Next time.
;;
;; It was time to come up with a plan B. Ideally I wanted to do something
;; low-level and with a bit of a retro touch. A legacy BIOS ROM seemed like a
;; good idea. No interrupts, no hand holding.
;;
;; The rules this year:
;;
;;     A valid submission will:
;;     - Produce exactly 1 copy of itself
;;     - Name the copy "4"
;;     - Not execute the copied file
;;     - Print, return, or display the number 4
;;
;; First, I had to figure out how they actually work. Intel x86 CPUs use a
;; eset vector at 0xFFFFFFF0. 16 bytes below 1 MB. That gives you 16 bytes to
;; jump to the main BIOS code. It took me a moment to figure out why QEMU
;; would not accept the first binaries I built until I found out that the ROM
;; size needs to be a multiple of 65536:
;;
;; qemu/hw/i386/x86.c:
;;
;;     if (bios_size <= 0 ||
;;         (bios_size % 65536) != 0) {
;;         goto bios_error;
;;     }
;;
;; I clearly won't win any size awards with this but in absence of a better
;; idea I decided to go with it anyway. I knew I will learn a bunch of new ...
;; stuff - and when do I win anything ever anyway? :)
;;
;; Once I got the ROM file to load I needed a debug setup. Turns out,
;; debugging real mode binaries in gdb kind of sucks. On the internet I found
;; a few gdbinit snippets that are supposed to make it more convenient but it
;; still wasn't ... great. At least general-purpose and segment registers as
;; well as flags were showing up more or less correctly, so I had to make due
;; with that.
;;
;; Since you can't really return '4' from the BIOS ROM I had to display it, so
;; I needed to learn how VGA hardware works. You have to write a bunch of
;; bytes to a set of different hardware registers to set the VGA mode. There
;; are different text and graphics modes to choose from, but it seems just
;; initializing the card and display is the same no matter which mode you
;; choose. I tried the text modes first, but nothing happened. Apparently you
;; need to set a palette and a font first. Setting a font ended up a lot of
;; assembly code - so much that in the end just initializing graphics mode
;; 0x13, setting a palette and rendering a sprite was less code than using a
;; text mode, so I went with that.
;;
;; Next, the file had to be replicated. Just using IDE would be the easiest
;; way to do that, I figured. I scoured the internet for some decent
;; documentation and the best one I found was the ATA-1 spec, which clocked in
;; at over 600 pages. At this point I felt I was already lagging behind
;; getting this done in time, so I looked at some osdev.org pages and old
;; Linux kernel source code instead. All I had to do was send the correct
;; sector count, starting sector, cylinder, head and track and then a write
;; command to the right I/O ports. In order to actually write the bytes you
;; have to wait for the IDE hardware to signal it's ready. There are two ways
;; to do that, one is to use interrupts and the other one is polling. I
;; decided on polling since I didn't want to deal with the PIC, too. It
;; worked and was easier than I anticipated.
;;
;; Now, my initial version would just replicate the 64K ROM to a 64K HDD
;; image. I re-read the rules once more to ensure I was actually done and
;; noticed that the output file should be named '4' as well. Well, there
;; wasn't really a way for me to control what someone would call their disk
;; image, so I had to find a way to deal with that. The easiest work around
;; would be to just create a file system on the disk image and then write the
;; ROM image to the correct place. The choice of file systems wasn't huge
;; since they needed to support small disk images. ext2 was out of the
;; questions since it seemed quite elaborate and the clock was ticking.
;;
;; Another option I considered was to use the SCO UnixWare Boot File System,
;; or BFS. That one does not support directories and all files need to be
;; written continuously, so I wouldn't have to deal with fragmentation.
;; However, I felt that wouldn't really fit the PC retro theme that well, so
;; in the end I settled on FAT12. This had the pleasant side-effect of always
;; having a boot loader at the start - remember putting a non-bootable floppy
;; in your 286? If someone tried to boot from the BIOS or disk image I could
;; show an error message! Most of the file system structures were pretty
;; straight-forward, except for the actual file allocation table, which uses
;; 12 bit entries. For hours I've tried to write a NASM macro to build these
;; somewhat dynamically using offsets, but in the end I just wrote them by
;; hand. It still bothers me! Anyhow, I got it working with a 135 sector disk
;; image and not a single byte to spare.
;;
;; Now all is done. I've learned a ton about antique hardware protocols and
;; had lots of fun. Now to counting the days until BGGP #5. See y'all next
;; year!
;;
;; Shout-outs
;; ---------------------------------------------------------------------------
;;
;; - The BGGP crew for putting these on every year.
;; - Skeletal Remains for keeping me motivated.
;;
;; ===========================================================================

cpu 686

ROM_SIZE:     equ 0x10000       ; Needs to be multiple of 0x10000 for QEMU
RESET_OFFSET: equ 0x10          ; Reset vector offset = 16 bytes

;; ===========================================================================
;; Macros
;; ===========================================================================

;; Right-pad string
;;
;; %1 = String to pad
;; %2 = Padding
%macro pdb 2
%strlen len %1
%define n %2-len
        db %1
%if n > 0
        times n db ' '
%endif
%endmacro

;; Write byte to I/O port
;;
;; %1 = Port
;; %2 = Byte to write
%macro outb 2
        mov dx, %1
        mov ax, %2
        out dx, al
%endmacro

;; ===========================================================================
;; FAT12 File System
;; ===========================================================================
FAT_NAME:      equ 11           ; Name entry length
FAT_ATTR_ARCH: equ 32           ; File "dirty", eg not backed up. This is the
                                ; default for newly created files.

FAT_SECTORS: equ (FAT_SIZE+ROM_SIZE)/512 ; Total number of filesystem sectors

;; Boot sector
;; ---------------------------------------------------------------------------
fat_start:
        jmp short .fat_boot
        nop
        pdb 'BGGP4.FS', 8       ; System ID

;; BIOS parameter block + Extended BIOS Parameter Block
;; ---------------------------------------------------------------------------
        dw 512                  ; Sector size
        db 4                    ; Cluster size
        dw 1                    ; Reserved sectors
        db 1                    ; Number of file allocation tables
        dw 16                   ; Max. root directory entries (min = 16)
        dw FAT_SECTORS          ; Total number of sectors
        db 0xF8                 ; Media type (0xF8 = fixed disk)
        dw 1                    ; Sectors/allocation table
        dw 16                   ; Sectors/track
        dw 2                    ; Number of heads
        dd 0                    ; Hidden sectors
        dd 0                    ; Total sectors if > 65535
        db 0x80                 ; Drive number
        db 0                    ; Reserved
        db 0x29                 ; Extended boot signature
        dd 0x44444444           ; Volume ID
        pdb 'BGGP4', FAT_NAME   ; Volume label
        pdb 'FAT12', 8          ; File system type

;; Boot code
;; ---------------------------------------------------------------------------
.fat_boot:
        xor ax, ax              ; Clear screen
        int 0x10

        mov bp, .fat_msg+0x7C00 ; Print message
        mov bl, 0x0D            ; Pink!
        mov cx, FAT_MSG_LEN
        mov ah, 0x13
        int 0x10

        mov ah, 1               ; Hide cursor
        mov ch, 0x3F
        int 0x10

.fat_halt:
        hlt
        jmp short .fat_halt
.fat_msg:
        db 'This is not how this works!'
FAT_MSG_LEN: equ $-.fat_msg

;; Boot sector magic
;; ---------------------------------------------------------------------------
        times 0x200-2-($-$$) db 0
        dw 0xAA55

;; File allocation table
;; ---------------------------------------------------------------------------
        db 0xF8, 0xFF, 0xFF, 0x00, 0x40, 0x00, 0x05, 0x60,
        db 0x00, 0x07, 0x80, 0x00, 0x09, 0xA0, 0x00, 0x0B,
        db 0xC0, 0x00, 0x0D, 0xE0, 0x00, 0x0F, 0x00, 0x01,
        db 0x11, 0x20, 0x01, 0x13, 0x40, 0x01, 0x15, 0x60,
        db 0x01, 0x17, 0x80, 0x01, 0x19, 0xA0, 0x01, 0x1B,
        db 0xC0, 0x01, 0x1D, 0xE0, 0x01, 0x1F, 0x00, 0x02,
        db 0x21, 0x20, 0x02, 0xFF, 0x0F

;; Directory entry
;; ---------------------------------------------------------------------------
        times 0x400-($-$$) db 0
        pdb '4', FAT_NAME         ; File name & extension
        db FAT_ATTR_ARCH          ; Attributes
        db 0                      ; Unused
        db 0                      ; Created ms
        dw 0                      ; Created secs/mins/hours (packed)
        dw 0                      ; Creation year/month/hours (packed)
        dw 0                      ; Last access year/month/hours (packed)
        dw 0                      ; EA Index
        dw 0                      ; Last modified time (same format as above)
        dw 0                      ; Last modified date (same format as above)
        dw 3                      ; First cluster
        dd ROM_SIZE               ; File size

        times 0x0E00-($-$$) db 0  ; Pad until file start

FAT_SIZE: equ $-fat_start

;; ===========================================================================
;; VGA DATA
;; ===========================================================================

VGA_BUF: equ 0xA000

;; Ports
VGA_AC_WRITE:    equ 0x3C0      ; Attribute Address/Data Register
VGA_MISC_WRITE:  equ 0x3C2      ; Miscellaneous Output Register
VGA_INSTAT_READ: equ 0x3DA      ; Input Status #1 Register
VGA_SEQ_INDEX:   equ 0x3C4      ; Sequencer Address Register
VGA_CRTC_INDEX:  equ 0x3D4      ; CRTC Controller Address Register
VGA_GC_INDEX:    equ 0x3CE      ; Graphics Controller Address Register
VGA_DAC_INDEX:   equ 0x3C8      ; DAC Address Write Mode Register

;; Sequencer register values
vga_regs_seq:
	db 0x03, 0x01, 0x0F, 0x00, 0x0E
VGA_REGS_SEQ_LEN: equ $-vga_regs_seq

;; CRT controller register values
vga_regs_crtc:
	db 0x5F, 0x4F, 0x50, 0x82, 0x54, 0x80, 0xBF, 0x1F,
	db 0x00, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	db 0x9C, 0x0E, 0x8F, 0x28, 0x40, 0x96, 0xB9, 0xA3,
	db 0xFF
VGA_REGS_CRTC_LEN: equ $-vga_regs_crtc

;; Graphics controller register values
vga_regs_gc:
	db 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x05, 0x0F,
	db 0xFF
VGA_REGS_GC_LEN: equ $-vga_regs_gc

;; Attributes controller register values
vga_regs_ac:
	db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
	db 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
	db 0x41, 0x00, 0x0F, 0x00, 0x00
VGA_REGS_AC_LEN: equ $-vga_regs_ac

;; '4' sprite based on HP 4195A Regular 8x13 font
sprite:
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00
        db 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00
        db 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00
        db 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00
        db 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00
        db 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00
        db 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00
        db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00
SPRITE_LEN:  equ $-sprite
SPRITE_COLS: equ 8

;; ===========================================================================
;; IDE PIO DATA
;;
;; - https://elixir.bootlin.com/linux/2.3.44pre8/source/include/linux/hdreg.h
;; ===========================================================================

;; I/O Ports
HD_DATA:         equ 0x1F0      ; Data Register
HD_COUNT:        equ 0x1F2      ; Sector Count Register
HD_SECTOR:       equ 0x1F3      ; Starting Sector
HD_CYL_LOW:      equ 0x1F4      ; Starting Cylinder
HD_CYL_HIGH:     equ 0x1F5      ; Starting Cylinder (high byte)
HD_HEAD_DRV_LBA: equ 0x1F6      ; Drive/Head Register
HD_CMD:          equ 0x1F7      ; Command Register
HD_STATUS:       equ 0x1F7      ; Status Register

;; Register values
HD_WRITE:        equ 0x30       ; Write command register value

;; Status flags
HD_DRQ_STAT:     equ 0x08       ; Status bit set when PIO ready

;; ===========================================================================
;; BIOS
;; ===========================================================================

;; Write VGA registers.
;;
;; cx = Number of bytes
;; dx = Port
;; si = Register bytes start address
wr_vga_regs:
        xor al, al              ; al = index byte
.l:
        mov ah, [si]            ; ah = data byte
        out dx, ax
        inc si
        inc al
        loop .l
        ret

;; Write words to HD_DATA I/O port. Called twice for writing file system
;; header and ROM data. Does not send the required write command beforehand.
;;
;; Polls the status register for readiness. This is a) faster than using
;; interrupts and b) much simpler.
;;
;; ax = Number of sectors to copy
;; es = Start address
;; si = Address offset
hd_copy:
        xor di, di
	mov dx, HD_DATA
.l_hd_write:
	push ax                 ; Save for polling
	push dx
	mov dx, HD_STATUS
.l_hd_poll:
	in al, dx               ; Poll DRQ ready
	and al, HD_DRQ_STAT
        jz .l_hd_poll
	pop dx
	pop ax

	mov cx, 256             ; Write 1 sector (256 words)
        rep outsw
	sub ax, 1
        jnz .l_hd_write         ; Next sector

        ret

;; BIOS main entry point
;;
;; This is where the reset vector at 0xFFFFFFF0 jumps to.
;; ---------------------------------------------------------------------------
bios_main:
        cli
        cld

        mov ax, cs
        mov ds, ax
        mov ax, 0x100
        mov ss, ax

;; Set VGA registers for mode 0x13 (320x200x256)
;; ---------------------------------------------------------------------------
        outb VGA_MISC_WRITE, 0x63 ; 7 6 5 4 3 2 1 0
                                  ; 0 1 1 0 0 0 1 1 (0x63)
                                  ; | | | | | | | +- I/O Address Select
                                  ; | | | | | | +--- Enable RAM
                                  ; | | | | +-+----- Clock Select
                                  ; | | +-+--------- Page Bit for Odd/Even?
                                  ; | +------------- Horizontal Sync Polarity
                                  ; =--------------- Vertical Sync Polarity

        mov dx, VGA_SEQ_INDEX   ; Initialize sequencer
        mov cx, VGA_REGS_SEQ_LEN
        mov si, vga_regs_seq
        call wr_vga_regs

        mov dx, VGA_CRTC_INDEX  ; Initialize CRT controller
        mov cx, VGA_REGS_CRTC_LEN
        mov si, vga_regs_crtc
        call wr_vga_regs

        mov dx, VGA_GC_INDEX    ; Initialize graphics controller
        mov cx, VGA_REGS_GC_LEN
        mov si, vga_regs_gc
        call wr_vga_regs

        mov si, vga_regs_ac     ; Initialize attribute controller
        mov dx, VGA_AC_WRITE
        mov cx, VGA_REGS_AC_LEN
        in ax, dx               ; Read once to enter index state
.l_vga_ac:
        mov al, cl
        out dx, al              ; Write index byte
        lodsb
        out dx, al              ; Write data byte
        inc al
        loop .l_vga_ac
        mov al, 0x20            ; Unblank display
        out dx, al              ; AC reg

;; Set palette
;; ---------------------------------------------------------------------------
        mov dx, VGA_DAC_INDEX
        xor ax, ax              ; Index 0x00 = Black
        out dx, al
        inc dx                  ; vga_dac_index+1 == DAC data port
        out dx, al
        out dx, al
        out dx, al

        mov dx, VGA_DAC_INDEX
        mov ax, 0xFF            ; Index 0xFF = White
        out dx, al
        inc dx
        out dx, al
        out dx, al
        out dx, al

;; Send write command
;; ---------------------------------------------------------------------------
        outb HD_COUNT, FAT_SECTORS ; Total number of sectors to write

        outb HD_SECTOR, 1       ; Set starting sector

        xor al, al              ; Except for the starting sector these all end
	mov dx, HD_CYL_LOW      ; up zero
	out dx, al
	mov dx, HD_CYL_HIGH
	out dx, al
	mov dx, HD_HEAD_DRV_LBA
	out dx, al

	mov al, HD_WRITE        ; Send write command
	mov dx, HD_CMD
	out dx, al

;; Create FAT12 file system
;; ---------------------------------------------------------------------------
        mov ax, FAT_SIZE/512    ; Sectors for FAT12 header to write
        mov si, fat_start
        call hd_copy

;; Copy ROM
;; ---------------------------------------------------------------------------
        mov ax, ROM_SIZE/512    ; Sectors for ROM to write
        xor si, si
        call hd_copy

;; Render sprite
;;
;; Done last so if this doesn't render it might indicate an error during
;; replication.
;; ---------------------------------------------------------------------------
        mov ax, VGA_BUF
        mov es, ax
        mov bx, (SPRITE_LEN/SPRITE_COLS) ; Rows
        mov si, sprite
        xor di, di
.l_sprite_next_row:
        mov cx, SPRITE_COLS
        rep movsb
        add di, 320-SPRITE_COLS ; Advance to next row
        dec bx
        jnz .l_sprite_next_row

.halt:
        hlt
        jmp .halt

;; ===========================================================================
;; RESET VECTOR (0xFFFFFFF0)
;; ===========================================================================
        times ROM_SIZE-RESET_OFFSET-($-$$) db 0x04
        jmp bios_main
align RESET_OFFSET, db 0x04
