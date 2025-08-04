.include "sys_macros.inc"

.section .text

.global mm_init
.global mm_deinit
.global mm_malloc
.global mm_free

// Initializes the memory manager.
mm_init:
    ret

// De-initializes the memory manager.
mm_deinit:
    ret

// Allocates a block with at least size bytes of payload.
mm_malloc:
    ret

// Frees a block
mm_free:
    ret
