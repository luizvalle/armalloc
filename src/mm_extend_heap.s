.include "mm_list_traversal_macros.inc"

.section .text

.global _extend_heap


// Extends the heap with a free block and returns its payload pointer.
//
// Syntax:
//   bl extend_heap
//
// Parameters:
//   x0 [Register]
//      - Number of words to extend the heap by
//      - Will be rounded up to the nearest even number
//      - Each word is WORD_SIZE bytes (8 bytes)
//
// Return Value:
//   x0 [Register]
//      - On success: Pointer to the payload of the new coalesced free block
//      - On failure: NULL (0) if mem_sbrk fails
//
// Behavior:
//   - Rounds up word count to nearest even number for alignment
//   - Calls mem_sbrk to extend heap by (words * WORD_SIZE) bytes
//   - Sets up new free block with header and footer
//   - Creates new epilogue header at end of extended region
//   - Calls coalesce to merge with adjacent free blocks if possible
//   - Returns pointer to the resulting free block's payload
//
// Algorithm:
//   1. Round words up to even number: words = (words + 1) & ~1
//   2. Calculate size in bytes: size = words * WORD_SIZE
//   3. Extend heap with mem_sbrk(size)
//   4. Initialize new block as free with size
//   5. Create new epilogue header (size=0, allocated=1)
//   6. Coalesce with adjacent blocks
//   7. Return coalesced block payload
//
// Memory Layout After Extension:
//   [existing heap...]
//   [new block header]     <- mem_sbrk return pointer - WORD_SIZE
//   [new block payload]    <- mem_sbrk return pointer (function return value)
//   [new block data...]
//   [new block footer]
//   [new epilogue header]  <- size=0, allocated=1
//
// Example Usage:
//   mov x0, #64                    // Extend by 64 words (512 bytes)
//   bl extend_heap                 // x0 = new free block payload or NULL
//   cbz x0, heap_extension_failed  // Branch if extension failed
//   // x0 now points to usable free block payload
//
// Registers Modified:
//   x0  - Return value (payload pointer or NULL)
//   x1  - Used for header/footer values (overwritten)
//   x2  - Used for address calculations (overwritten)
//   x19 - Saved/restored (used to preserve size value)
//   lr  - Saved/restored (for function calls)
//
// Function Calls:
//   - mem_sbrk(size) - Extends heap memory
//   - coalesce(payload) - Merges adjacent free blocks
//
// Error Conditions:
//   - Returns NULL if mem_sbrk fails (heap cannot be extended)
_extend_heap:
    stp lr, x19, [sp, #-16]!

    // Make number of words even
    // words = words % 2 ? (words + 1) * WORD_SIZE : words * WORD_SIZE;
    // Works by adding 1 to the number and then clearing the last bit.
    // Leverages the fact that even numbers have a 0 in the last bit.
    add x0, x0, #1
    bic x0, x0, #1

    lsl x19, x0, #WORD_ALIGN  // size = words * WORD_SIZE (8)
    mov x0, x19
    bl mem_sbrk
    cmp x0, #-1
    b.eq .Lextend_heap_sbrk_failed

    // Set up the free block's header and footer
    SET_SIZE x1, x19
    SET_ALLOCATED x1, 0

    HEADER_P_FROM_PAYLOAD_P x0, x2
    str x1, [x2]  // Store header
    FOOTER_P_FROM_PAYLOAD_P x0, x2
    str x1, [x2]  // Store footer

    // Create new epilogue
    NEXT_PAYLOAD_P x0, x2
    HEADER_P_FROM_PAYLOAD_P x2, x2
    mov x1, #0  // This will zero-out the size as well
    SET_ALLOCATED x1, 1
    str x1, [x2]

    bl _coalesce
    b .Lextend_heap_ret
.Lextend_heap_sbrk_failed:
    mov x0, #0  // Return NULL
.Lextend_heap_ret:
    ldp lr, x19, [sp], #16
    ret

