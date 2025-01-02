/* mm.s - A 64-bit implementation of a segregatted free list allocator.
 *
 * Simple allocator based on segregated free lists, lifo first-fit placement,
 * and boundary tag coalescing. Blocks must be aligned to doubleword (16 byte)
 * boundaries. Minimum block size is 32
 * bytes.
 */

.text


.include "linux_syscalls.s"

.equ   NUM_SEG_LISTS,  8
.equ   WORD_SIZE,      8
.equ   DWORD_SIZE,     2 * WORD_SIZE
.equ   PAGE_SIZE,      4096


/*
* Initializes the memory manager.
*
* Should be called before using the allocator.
*/
.global mm_init
mm_init:
    str lr, [sp, #-16]!

    sbrk 1024

    ldr lr, [sp], #16
    ret
