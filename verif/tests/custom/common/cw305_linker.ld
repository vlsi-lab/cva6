OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 0x00010400
}

PHDRS
{
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
}

SECTIONS
{
  . = ORIGIN(RAM);

  .text.init : {
    KEEP(*(.text.init))
    KEEP(*(.text.start))
  } > RAM :text

  .text : {
    *(.text.unlikely .text.unlikely.*)
    *(.text.startup .text.startup.*)
    *(.text.hot .text.hot.*)
    *(.text .text.*)
    *(.gnu.linkonce.t.*)
  } > RAM :text

  .rodata : {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
    *(.srodata.cst*)
  } > RAM :text

  . = ALIGN(8);
  .tohost : {
    KEEP(*(.tohost))
  } > RAM :data

  .data : {
    *(.data .data.*)
    *(.sdata .sdata.*)
    *(.gnu.linkonce.d.*)
    *(.gnu.linkonce.s.*)
  } > RAM :data

  . = ALIGN(8);
  __global_pointer$ = . + 0x800;

  __bss_start = .;
  .sbss : {
    *(.sbss .sbss.*)
    *(.scommon)
  } > RAM :data

  .bss : {
    *(.bss .bss.*)
    *(COMMON)
  } > RAM :data
  __bss_end = .;

  .tdata : {
    _tdata_begin = .;
    *(.tdata .tdata.*)
    _tdata_end = .;
  } > RAM :data

  .tbss : {
    *(.tbss .tbss.*)
    _tbss_end = .;
  } > RAM :data

  . = ALIGN(64);
  .uvmif : {
    KEEP(*(.uvmif))
  } > RAM :data

  . = ALIGN(16);
  __stack_start = .;
  _sp = ORIGIN(RAM) + LENGTH(RAM);
  PROVIDE(__stack_top = _sp);
  __stack_end = _sp;

  _end = _sp;
  PROVIDE(end = _end);

  ASSERT(_end <= ORIGIN(RAM) + LENGTH(RAM), "RAM overflow")

  /DISCARD/ : {
    *(.comment)
    *(.riscv.attributes)
    *(.eh_frame .eh_frame.*)
    *(.debug_frame)
  }
}
