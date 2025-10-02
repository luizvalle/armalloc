.include "constants.inc"
.include "mm_list_traversal_macros.inc"

.equ NUM_SEG_LISTS, 8

.section .bss

seg_listp: .skip NUM_SEG_LISTS * PTR_SIZE_BYTES

.section .text

.global mm_init
.global mm_deinit
.global mm_malloc
.global mm_free


// Initializes the memory manager with segregated free lists.
//
// Syntax:
//   bl mm_init
//
// Parameters:
//   None
//
// Return Value:
//   x0 [Register]
//      - 0 on success (memory manager initialized successfully)
//      - Non-zero on failure (mem_init failure code or -1 for other errors)
//
// Behavior:
//   - Initializes the underlying memory system via mem_init
//   - Allocates space for NUM_SEG_LISTS prologue blocks plus padding and
//     epilogue
//   - Sets up each segregated free list as a circular doubly-linked list
//   - Creates prologue blocks (allocated sentinel nodes) for each size class
//   - Places an epilogue block (size=0, allocated=1) at the end
//   - Extends heap with an initial free block of PAGE_SIZE bytes
//   - All prologue blocks are self-referencing (fprev=fnext=self) initially
//
// Algorithm:
//   1. Call mem_init() to initialize memory subsystem
//   2. Allocate (2 + NUM_SEG_LISTS * 4) words via mem_sbrk:
//      - 1 word for alignment padding
//      - NUM_SEG_LISTS * 4 words for prologue blocks (4 words each)
//      - 1 word for epilogue header
//   3. Store alignment padding (0) and advance pointer
//   4. For each segregated list (0 to NUM_SEG_LISTS-1):
//      - Create prologue header (size=32 bytes, allocated=1)
//      - Set up circular links (fprev=fnext=self)
//      - Create prologue footer matching header
//      - Store payload pointer in seg_listp[i] array
//      - Advance to next block position
//   5. Create epilogue header (size=0, allocated=1)
//   6. Extend heap with PAGE_SIZE free block
//   7. Return 0 on success, -1 on heap extension failure
//
// Memory Layout After Initialization:
//   [alignment padding: 8 bytes]
//   [seg_list[0] prologue: header(32,1) + links + footer(32,1)]
//   [seg_list[1] prologue: header(32,1) + links + footer(32,1)]
//   ...
//   [seg_list[7] prologue: header(32,1) + links + footer(32,1)]
//   [epilogue: header(0,1)]
//   [initial free block: header + payload + footer]
//   [new epilogue: header(0,1)]
//
// Segregated List Size Classes:
//   seg_listp[0]: 32-63 bytes      seg_listp[4]: 512-1023 bytes
//   seg_listp[1]: 64-127 bytes     seg_listp[5]: 1024-2047 bytes
//   seg_listp[2]: 128-255 bytes    seg_listp[6]: 2048-4095 bytes
//   seg_listp[3]: 256-511 bytes    seg_listp[7]: 4096+ bytes
//
// Example Usage:
//   bl mm_init                     // Initialize memory manager
//   cbnz x0, init_failed          // Branch if initialization failed
//   // Memory manager ready for malloc/free operations
//
// Registers Modified:
//   x0  - Return value (0 on success, error code on failure)
//   x1  - Used for header/footer values (overwritten)
//   x2  - Used for size calculations and seg_listp address (overwritten)
//   x3  - Used as loop iteration counter (overwritten)
//   x4  - Used for payload address calculations (overwritten)
//   lr  - Saved/restored (for function calls)
//
// Function Calls:
//   - mem_init() - Initialize underlying memory system
//   - mem_sbrk(size) - Allocate initial heap space
//   - extend_heap(words) - Add initial free block
//
// Error Conditions:
//   - Returns mem_init error code if memory initialization fails
//   - Returns -1 if mem_sbrk fails (insufficient system memory)
//   - Returns -1 if extend_heap fails (cannot create initial free block)
//
// Global State Modified:
//   - seg_listp[0..7] array populated with prologue payload pointers
//   - Heap initialized with prologue blocks, epilogue, and initial free space
//   - Memory manager ready for allocation/deallocation operations
mm_init:
    str lr, [sp, #-16]!

    // Call mem_init with x0
    bl mem_init
    cbnz x0, .Linit_ret  // Call failed, return the same result as mem_init

    // Allocated space for the empty segmented free list
    mov x0, #2 + NUM_SEG_LISTS * 4
    bl mem_sbrk  // mem_sbrk(2 + NUM_SEG_LISTS * 4)
    cmp x0, #-1
    b.eq .Linit_ret  // mem_sbrk failed

    str xzr, [x0], #WORD_SIZE_BYTES  // Alignment padding

    // Initialize the segregated free lists
    mov x2, #2 * DWORD_SIZE_BYTES  // The size of all the header and footers
    SET_SIZE x1, x2
    SET_ALLOCATED x1, 1
    ldr x2, =seg_listp
    mov x3, #0  // Iteration index
.Linit_seglists_loop:
    // Initialize the header
    str x1, [x0]
    SET_FPREV x0, x0
    SET_FNEXT x0, x0

    // Initialize the footer
    str x1, [x0, #3 * WORD_SIZE_BYTES]

    add x4, x0, #WORD_SIZE_BYTES  // Pointer to payload
    str x4, [x2, x3, LSL #PTR_ALIGN]  // Update the segmented list array

    add x0, x0, #2 * DWORD_SIZE_BYTES  // Next block
    add x3, x3, #1
    cmp x3, #NUM_SEG_LISTS
    b.lt .Linit_seglists_loop
    // End of loop

    // Store the epilogue header
    mov x2, #0
    SET_SIZE x1, x2
    SET_ALLOCATED x1, 1
    str x1, [x0]

    // Extend the heap with a free block of PAGE_SIZE_BYTES
    mov x0, #PAGE_SIZE_BYTES / WORD_SIZE_BYTES
    bl _extend_heap
    cbz x0, .Lmm_init_extend_head_err

    mov x0, #0
    b .Linit_ret
.Lmm_init_extend_head_err:
    mov x0, #-1
.Linit_ret:
    ldr lr, [sp], #16
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
//   - _coalesce(payload) - Merges adjacent free blocks
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


_coalesce:
    stp lr, x19, [sp, #-16]!

    // Retrieve the addresses of the previous and next blocks
    // x1 = address of previous block's payload
    // x2 = address of next block's payload
    PREV_PAYLOAD_P x0, x1
    NEXT_PAYLOAD_P x0, x2

    // Retrieve the some information for the current block that will be used
    // x0 = address of payload
    // x3 = address of header
    // x4 = contents of header
    // x5 = size of the block
    HEADER_P_FROM_PAYLOAD_P x0, x3
    ldr x4, [x3]
    GET_SIZE x4, x5

    // Retrieve some information for the previous block
    // x6 = address of header
    // x7 = contents of header
    HEADER_P_FROM_PAYLOAD_P x1, x6
    ldr x7, [x6]

    // Retrieve some information for the next block
    // x8 = address of header
    // x9 = contents of header
    HEADER_P_FROM_PAYLOAD_P x2, x8
    ldr x9, [x8]

    // Calculate the jump table index
    // index = (next.allocated << 1) | prev.allocated
    // x10 = prev.allocated
    // x11 = next.allocated
    // x12 = jump table index
    GET_ALLOCATED x7, x10
    GET_ALLOCATED x9, x11
    orr w12, w10, w11, LSL #1

    // Jump table dispatch
    // x13 = jump table branch address
    adrp x13, .coalesce_jump_table  // Get the page address
    add x13, x13, :lo12:.coalesce_jump_table  // Add the page offset
    ldr x13, [x13, x12, LSL #3]  // Each element is 2^3 = 8 bytes
    br x13

.align 3
.coalesce_jump_table:
    .quad .Lcoalesce_case_neither_allocated
    .quad .Lcoalesce_case_only_prev_allocated
    .quad .Lcoalesce_case_only_next_allocated
    .quad .Lcoalesce_case_both_allocated

.Lcoalesce_case_neither_allocated:
    // Should coalesce the previous, current, and next blocks

    // x5 = current size
    // x10 = previous size
    // x11 = next size
    GET_SIZE x7, x10
    GET_SIZE x9, x11

    // x5 = combined size
    add x5, x5, x10
    add x5, x5, x11

    // Set the size in prev's header
    SET_SIZE x7, x5
    str x7, [x6]

    // Set the size in next's footer
    // x14 = &next.footer
    // x15 = *x14
    FOOTER_P_FROM_PAYLOAD_P x2, x14
    ldr x15, [x14]
    SET_SIZE x15, x5
    str x15, [x14]

    mov x19, x1  // Save the prev block's payload address

    // Remove prev block from free list
    mov x0, x1
    bl _remove_from_free_list

    // Remove the next block from free list
    mov x0, x2
    bl _remove_from_free_list

    b .Lcoalesce_add_to_list

.Lcoalesce_case_only_prev_allocated:
    // Should coalesce the current and next blocks

    // x11 = next size
    GET_SIZE x9, x11

    // x5 = combined size
    add x5, x5, x11

    // Set the size in the current header
    SET_SIZE x4, x5
    str x4, [x3]

    // Set the size in the new footer
    // x16 = address of the new footer
    FOOTER_P_FROM_PAYLOAD_P x0, x14
    ldr x15, [x14]
    SET_SIZE x15, x5
    str x15, [x14]

    // Remove the next block from the free list
    mov x19, x0  // Save the current block's payload address
    mov x0, x2
    bl _remove_from_free_list

    b .Lcoalesce_add_to_list

.Lcoalesce_case_only_next_allocated:
    // Should coalesce the previous and current blocks

    // x10 = prev size
    GET_SIZE x7, x10

    // x5 = combined size
    add x5, x5, x10

    // Set the size in previous block's header
    SET_SIZE x7, x5
    str x7, [x6]

    // Set the size in the new footer (current block's footer)
    // x14 = address of the new footer
    FOOTER_P_FROM_PAYLOAD_P x1, x14
    str x7, [x14]

    // Remove the prev block from the free list
    mov x19, x1  // Save the previous block's payload address
    mov x0, x1
    bl _remove_from_free_list

    b .Lcoalesce_add_to_list

.Lcoalesce_case_both_allocated:
    // Nothing to coalesce

    mov x19, x0

    b .Lcoalesce_add_to_list

// After the branches above, x19 should contain the pointer to the payload
// of the coalesced block to add to the free list.
.Lcoalesce_add_to_list:
    mov x0, x19  // Save the payload address
    bl _add_to_free_list
    mov x0, x19  // Return the payload address

.Lcoalesce_ret:
    ldp lr, x19, [sp], #16
    ret


// Inserts a memory block into the appropriate segregated free list.
//
// Syntax:
//   bl _add_to_free_list
//
// Parameters:
//   x0 [Register]
//      - Pointer to the payload of the memory block to insert
//
// Return Value:
//   None
//
// Behavior:
//   - Determines the size of the block from its header
//   - Finds the corresponding segregated free list based on the block size
//   - Inserts the block at the beginning of the list (after the sentinel node)
//   - Updates fnext and fprev pointers of the block, the sentinel, and the
//     original first free block
//   - Ensures the doubly-linked free list remains consistent
//
// Algorithm:
//   1. Save lr and payload pointer (x19) on stack
//   2. Load header from payload, then read block size
//   3. Call _get_seglist_index to get the free list index
//   4. Load the sentinel pointer of the appropriate segregated free list
//   5. Load the original first free block in the list
//   6. Set new block's fnext to the original first free block
//   7. Set new block's fprev to the sentinel
//   8. Set original first free block's fprev to the new block
//   9. Set sentinel's fnext to the new block
//   10. Restore registers and return
//
// Registers Modified:
//   x0 - Temporary, used for block size and free list index
//   x1 - Temporary, used to load list pointers
//   x2 - Header of sentinel node
//   x3 - Header of original first free block
//   x4 - Header of the block being inserted
//   x19 - Saved payload pointer
//   lr  - Link register saved/restored
_add_to_free_list:
    stp lr, x19, [sp, #-16]!

    mov x19, x0

    // Get the size of the block
    HEADER_P_FROM_PAYLOAD_P x19, x1
    ldr x0, [x1]
    GET_SIZE x0, x0

    // Get the header of the free list to insert into
    bl _get_seglist_index
    ldr x1, =seg_listp
    ldr x1, [x1, x0, LSL #PTR_ALIGN]

    // Get the header of the list's sentinel node
    HEADER_P_FROM_PAYLOAD_P x1, x2

    // Get the header of the original first free payload in the list
    NEXT_FREE_PAYLOAD_P x1, x3
    HEADER_P_FROM_PAYLOAD_P x3, x3

    // Set the fnext and fprev pointers of the block
    HEADER_P_FROM_PAYLOAD_P x19, x4
    SET_FNEXT x4, x3
    SET_FPREV x4, x2

    // Set the fprev of the original first free payload in the list
    SET_FPREV x3, x4

    // Set the fnext of the header to point to the new payload
    SET_FNEXT x2, x4

    ldp lr, x19, [sp], #16
    ret


// Removes a memory block from its segregated free list.
//
// Syntax:
//   bl _remove_from_free_list
//
// Parameters:
//   x0 [Register]
//      - Pointer to the payload of the memory block to remove
//
// Return Value:
//   None
//
// Behavior:
//   - Retrieves the payload addresses of the block’s previous and next free
//     blocks
//   - Converts these payload addresses into their corresponding header
//     addresses
//   - Updates the fnext pointer of the previous block to point to the next
//     block
//   - Updates the fprev pointer of the next block to point to the previous
//     block
//
// Algorithm:
//   1. Save lr on the stack
//   2. Use PREV_FREE_PAYLOAD_P to load the payload address of the previous free
//      block into x1
//   3. Use NEXT_FREE_PAYLOAD_P to load the payload address of the next free
//      block into x2
//   4. Convert x1 (previous payload) into its header address in x3
//   5. Convert x2 (next payload) into its header address in x4
//   6. Set the fnext pointer of the previous block (x1) to the header of the
//      next block (x4)
//   7. Set the fprev pointer of the next block (x2) to the header of the
//      previous block (x3)
//   8. Restore lr and return
//
// Registers Modified:
//   x1 - Payload address of previous free block
//   x2 - Payload address of next free block
//   x3 - Header address of previous free block
//   x4 - Header address of next free block
_remove_from_free_list:
    str lr, [sp, #-16]!

    // Retrieve the payload addresses of the previous and next free blocks
    // x1 = payload address of the previous free block
    // x2 = payload address of the next free block
    PREV_FREE_PAYLOAD_P x0, x1
    NEXT_FREE_PAYLOAD_P x0, x2

    // Retrieve the header addresses of the previous and next free blocks
    // x3 = header address of the previous free block
    // x4 = header address of the next free block
    HEADER_P_FROM_PAYLOAD_P x1, x3
    HEADER_P_FROM_PAYLOAD_P x2, x4

    // Set the next pointer of the previous free payload to the address of the
    // next free payload's header
    SET_FNEXT x3, x4

    // Set the prev pointer of the next free payload to the address of the
    // previus free payload's header
    SET_FPREV x4, x3

    ldr lr, [sp], #16
    ret


// Returns the index into the segregated free list corresponding to a given block size.
//
// Syntax:
//   bl _get_seglist_index
//
// Parameters:
//   x0 [Register]
//      - Size of the memory block in bytes
//
// Return Value:
//   x0 [Register]
//      - Index of the segregated free list for the given block size
//
// Behavior:
//   - Determines which segregated free list a block belongs to based on its
//     size
//   - First divides size by 2^6 (64) since the first list handles blocks 32–63
//     bytes
//   - Uses log2 to determine which power-of-two bucket the adjusted size falls
//     into
//   - Clamps the result at NUM_SEG_LISTS - 1 to prevent overflow
//   - Returns 0 if size is smaller than 64 bytes
//
// Algorithm:
//   1. Divide size by 64: size >>= 6
//   2. If resulting size is 0, return 0
//   3. Count leading zeros in size (clz) to find highest set bit
//   4. Compute floor(log2(size)) = 64 - clz(size)
//   5. Clamp index to maximum of NUM_SEG_LISTS - 1
//   6. Return computed index
//
// Registers Modified:
//   x0 - Input size / return value (seglist index)
//   x1 - Temporary for clz result
//   w2 - Temporary for calculations
_get_seglist_index:
    // Divide the block size by 2^6 = 64 as the first list contains blocks
    // of size 32 <= x < 64
    lsr x0, x0, #6
    cbz x0, .Lget_seglist_index_zero

    // Calculate floor(log2(x1))
    clz x1, x0  // Count the number of leading zeros
    mov w2, #64
    sub w1, w2, w1  // floor(log2(x1))

    // Clamp at most NUM_SEG_LISTS - 1
    mov w2, #(NUM_SEG_LISTS - 1)
    cmp w1, w2
    csel w0, w1, w2, lt
    ret

.Lget_seglist_index_zero:
    mov x0, #0
    ret

