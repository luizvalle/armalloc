.include "sys_macros.s"

.section .data
not_implemented_txt: .asciz "Not implemented.\n"
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
