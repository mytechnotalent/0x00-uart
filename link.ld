/* ==============================================================================
 * Project:       0x00-uart
 * File:          link.ld
 * Target Device: CH32V003 (QingKe RV32EC): 16 KB flash, 2 KB SRAM
 * Description:   Places the reset vector table at 0x00000000, code/rodata in
 *                flash, initialised data copied to RAM at boot, bss + stack in
 *                RAM. Mirrors the official WCH CH32V003 layout.
 * ============================================================================== */

/* ------------------------------------------------------------------------------
 * Entry point and stack configuration
 * ------------------------------------------------------------------------------ */
ENTRY( _start )

__stack_size = 512;
PROVIDE( _stack_size = __stack_size );

/* ==============================================================================
 * SECTION:     MEMORY  (address space layout)
 * ============================================================================== */
MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 16K
    RAM (xrw)  : ORIGIN = 0x20000000, LENGTH = 2K
}

/* ==============================================================================
 * SECTION:     SECTIONS  (flash and RAM placement)
 * ============================================================================== */
SECTIONS
{
    /* --------------------------------------------------------------------------
     * .init — reset vector table (must be first in flash at 0x00000000)
     * -------------------------------------------------------------------------- */
    .init :
    {
        _sinit = .;
        . = ALIGN(4);
        KEEP(*(SORT_NONE(.init)))
        . = ALIGN(4);
        _einit = .;
    } >FLASH AT>FLASH

    /* --------------------------------------------------------------------------
     * .text + .rodata — code and read-only data in flash
     * --------------------------------------------------------------------------
     * handle_reset is placed first so it lands at the reset vector.
     * default_handlers follows to keep the ISR table contiguous.
     * -------------------------------------------------------------------------- */
    .text :
    {
        . = ALIGN(4);
        *(.text.handle_reset)
        *(.text.default_handlers)
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata*)
        *(.gnu.linkonce.t.*)
        . = ALIGN(4);
    } >FLASH AT>FLASH

    /* --------------------------------------------------------------------------
     * _etext — end of flash-resident code/rodata
     * -------------------------------------------------------------------------- */
    . = ALIGN(4);
    PROVIDE( _etext = . );

    /* --------------------------------------------------------------------------
     * .dalign — RAM VMA base for initialised data (4-byte aligned)
     * -------------------------------------------------------------------------- */
    .dalign :
    {
        . = ALIGN(4);
        PROVIDE(_data_vma = .);
    } >RAM AT>FLASH

    /* --------------------------------------------------------------------------
     * .dlalign — LMA (load address) for .data, placed right after .text
     * -------------------------------------------------------------------------- */
    .dlalign :
    {
        . = ALIGN(4);
        PROVIDE(_data_lma = .);
    } >FLASH AT>FLASH

    /* --------------------------------------------------------------------------
     * .data — initialised global/static variables (copied from flash at boot)
     * -------------------------------------------------------------------------- */
    .data :
    {
        . = ALIGN(4);
        *(.gnu.linkonce.r.*)
        *(.data .data.*)
        *(.gnu.linkonce.d.*)
        . = ALIGN(8);
        PROVIDE( __global_pointer$ = . + 0x800 );
        *(.sdata .sdata.*)
        *(.sdata2*)
        *(.gnu.linkonce.s.*)
        . = ALIGN(4);
        PROVIDE( _edata = . );
    } >RAM AT>FLASH

    /* --------------------------------------------------------------------------
     * .bss — zero-initialised globals/statics + COMMON symbols
     * -------------------------------------------------------------------------- */
    .bss :
    {
        . = ALIGN(4);
        PROVIDE( _sbss = .);
        *(.sbss*)
        *(.gnu.linkonce.sb.*)
        *(.bss .bss.*)
        *(.gnu.linkonce.b.*)
        *(COMMON*)
        . = ALIGN(4);
        PROVIDE( _ebss = .);
    } >RAM AT>FLASH

    /* --------------------------------------------------------------------------
     * _end / end — heap start (no malloc in this firmware, but conventional)
     * -------------------------------------------------------------------------- */
    PROVIDE( _end = _ebss);
    PROVIDE( end = . );

    /* --------------------------------------------------------------------------
     * .stack — top of SRAM, grows downward; 512-byte kernel stack
     * -------------------------------------------------------------------------- */
    .stack ORIGIN(RAM) + LENGTH(RAM) - __stack_size :
    {
        . = ALIGN(4);
        PROVIDE(_susrstack = . );
        . = . + __stack_size;
        PROVIDE( _eusrstack = . );
    } >RAM

    /* --------------------------------------------------------------------------
     * Safety check — abort link if .bss + .data + stack exceed 2 KB SRAM
     * -------------------------------------------------------------------------- */
    ASSERT(_ebss <= ORIGIN(RAM) + LENGTH(RAM) - __stack_size,
           "RAM overflow: .bss/.data overruns the reserved stack region")
}
