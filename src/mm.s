.include "sys_macros.inc"

.section .data

not_implemented_txt: .asciz "Not implemented.\n"

// Compute the size of the string (including the null terminator)
// '.': current location counter
// '. - not_implemented_txt': difference between current address and label
// This sets 'not_implemented_txt_size' to the number of bytes in the string
.equ not_implemented_txt_size, . - not_implemented_txt

.section .text

.global mm_init
.global mm_deinit
.global mm_malloc
.global mm_free

// Initializes the memory manager.
mm_init:
    sys_write #1, not_implemented_txt, #not_implemented_txt_size
    ret

// De-initializes the memory manager.
mm_deinit:
    sys_write #1, not_implemented_txt, #not_implemented_txt_size
    ret

// Allocates a block with at least size bytes of payload.
mm_malloc:
    sys_write #1, not_implemented_txt, #not_implemented_txt_size
    ret

// Frees a block
mm_free:
    sys_write #1, not_implemented_txt, #not_implemented_txt_size
    ret
