.include "constants.s"
.include "sys_macros.s"

.section .bss

.align PTR_ALIGN

_mem_heap_start: .skip PTR_SIZE_BYTES  // Points to first byte of heap

_mem_brk: .skip PTR_SIZE_BYTES  // Points to last byte of heap plus 1

_mem_heap_end: .skip PTR_SIZE_BYTES  // Max legal heap addr plus 1

.section .data

not_implemented_txt: .asciz "Not implemented.\n"

// Compute the size of the string (including the null terminator)
// '.': current location counter
// '. - not_implemented_txt': difference between current address and label
// This sets 'not_implemented_txt_size' to the number of bytes in the string
.equ not_implemented_txt_size, . - not_implemented_txt

.section .text

.global mem_init
.global mem_sbrk
.global mem_deinit

// Allocates the arena
mem_init: 
    sys_write #1, not_implemented_txt, #not_implemented_txt_size
    ret

// Extends the heap
mem_sbrk:
    sys_write #1, not_implemented_txt, #not_implemented_txt_size
    ret

// Frees the arena
mem_deinit:
    sys_write #1, not_implemented_txt, #not_implemented_txt_size
    ret
