MEMORY {
    RAM (rwx) : ORIGIN = 0x00000400, LENGTH = 0x8000 - 0x400
    ROM (rx)  : ORIGIN = 0x00008000, LENGTH = 0x8000
}

ENTRY(_start)

SECTIONS {
    .text {
        _stext = .;
        KEEP(*(.isr_vector))
        *(.text.entry)
        *(.text*)
	_etext = .;
    } > ROM

    .rodata {
        _srodata = .;
        *(.rodata*)
        *(.srodata*)
        _erodata = .;
    } > ROM

    .sdata : AT(LOADADDR(.rodata) + SIZEOF(.rodata)) {
	. = ALIGN(4);
        _ssdata = .;
        __global_pointer$ = . + 0x800;
    	*(.sdata*)
	. = ALIGN(4);
	_esdata = .;
    } > RAM

    .sbss (NOLOAD) : {
        . = ALIGN(4);
        _ssbss = .;
        *(.sbss*)
        . = ALIGN(4);
	_esbss = .;
    } > RAM

    .data : AT(LOADADDR(.sdata) + SIZEOF(.sdata)){
        . = ALIGN(4);
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM

    .bss (NOLOAD) : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
	_ebss = .;
    } > RAM

    PROVIDE(_stack_top = ORIGIN(RAM) + LENGTH(RAM));

    PROVIDE(_heap_start = _ebss);
    PROVIDE(_heap_end = ORIGIN(RAM) + LENGTH(RAM));

    _lma_sdata = LOADADDR(.sdata);
    _lma_data = LOADADDR(.data);
}
