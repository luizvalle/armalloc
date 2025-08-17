.include "constants.inc"
.include "mm_errno_constants.inc"

.equ NUM_SEG_LISTS, 8

.section .bss

seg_listp: .skip NUM_SEG_LISTS * PTR_SIZE_BYTES

.section .text

.global mm_init
.global mm_deinit
.global mm_malloc
.global mm_free


// uint64_t      size : 60;    // Bits 0-59
// uint64_t    unused :  3;    // Bits 60-62
// uint64_t allocated :  1;    // Bit 63
.equ SIZE_MASK, (1 << 60) - 1
.equ ALLOCATED_MASK, 1 << 63


// Sets the size field in a memory allocator header while preserving other fields.
//
// Syntax:
//   SET_SIZE header_reg, size_reg
//
// Parameters:
//   header_reg [Register]
//              - Register containing the current header value to modify
//              - Must contain a valid header with existing allocated/unused bits
//
//   size_reg   [Register]
//              - Register containing the new size value in bytes
//              - Value will be masked to fit in 60 bits (max 2^60 - 1)
//              - WARNING: This register's value will be modified by the macro
//
// Behavior:
//   - Clears bits 0-59 in header_reg (existing size field)
//   - Masks size_reg to 60 bits to prevent overflow into other fields
//   - Sets the new size value in bits 0-59 of header_reg
//   - Preserves unused bits (60-62) and allocated bit (63)
//
// Example Usage:
//   ldr x1, [x0]              // Load current header
//   mov x2, #32               // New size = 32 bytes
//   SET_SIZE x1, x2    // Set size, preserve allocated flag
//   str x1, [x0]              // Store modified header
//
// Registers Modified:
//   header_reg - Updated with new size field
//   size_reg   - Masked to 60 bits (original value lost)
//   No other registers are affected
//
// Dependencies:
//   Requires SIZE_MASK constant to be defined as (1 << 60) - 1
.macro SET_SIZE header_reg, size_reg
    and \header_reg, \header_reg, #~SIZE_MASK
    and \size_reg, \size_reg, #SIZE_MASK
    orr \header_reg, \header_reg, \size_reg
.endm


// Extracts the size field from a memory allocator header.
//
// Parameters:
//   header_reg [Register]
//              - Register containing the header value to read from
//              - Header value is preserved (non-destructive operation)
//
//   output_reg [Register]
//              - Register that will receive the extracted size value
//              - Must be different from header_reg for non-destructive behavior
//
// Behavior:
//   - Extracts bits 0-59 from header_reg (size field)
//   - Stores the size value in output_reg
//   - Preserves the original header value in header_reg
//   - Clears unused and allocated bits in the output
//
// Example Usage:
//   ldr x1, [x0]              // Load header
//   GET_SIZE x1, x2    // x2 = size, x1 unchanged
//   // Can still use x1 for other header operations
//
// Registers Modified:
//   output_reg - Set to the size value (bits 0-59 of header)
//   header_reg - Unchanged (preserved)
//   No other registers are affected
.macro GET_SIZE header_reg, output_reg
    and \output_reg, \header_reg, #SIZE_MASK
.endm


// Sets the allocated flag in a memory allocator header while preserving other fields.
//
// Parameters:
//   header_reg     [Register]
//                  - Register containing the header value to modify
//                  - Header will be updated with new allocated flag
//
//   allocated_imm  [Immediate: 0 or 1]
//                  - New allocation status (0 = free, 1 = allocated)
//                  - Must be exactly 0 or 1
//
// Behavior:
//   - Clears bit 63 (allocated flag) in header_reg
//   - If allocated_imm == 1: Sets bit 63 to indicate block is allocated
//   - If allocated_imm == 0: Leaves bit 63 cleared (block is free)
//   - Preserves size field (bits 0-59) and unused bits (60-62)
//
// Example Usage:
//   ldr x1, [x0]           // Load header
//   SET_ALLOCATED x1, 1    // Mark as allocated
//   str x1, [x0]           // Store back
//
//   ldr x2, [x3]           // Load another header
//   SET_ALLOCATED x2, 0    // Mark as free
//   str x2, [x3]           // Store back
//
// Registers Modified:
//   header_reg - Updated with new allocated flag
//   No other registers are affected
.macro SET_ALLOCATED header_reg, allocated_imm
    and \header_reg, \header_reg, #~ALLOCATED_MASK  // Clear the bit
.if \allocated_imm == 1
    orr \header_reg, \header_reg, #ALLOCATED_MASK  // Set the bit
.endif
    // If allocated_imm == 0, bit stays cleared from the AND operation
.endm


// Extracts the allocated flag from a memory allocator header.
//
// Parameters:
//   header_reg [Register]
//              - Register containing the header value to read from
//              - Header value is preserved (non-destructive operation)
//
//   output_reg [Register]
//              - Register that will receive the extracted allocated flag
//              - Must be different from header_reg for non-destructive behavior
//
// Behavior:
//   - Extracts bit 63 from header_reg (allocated flag)
//   - Shifts the result to produce a clean 0 or 1 value
//   - Stores the result in output_reg (0 = free, 1 = allocated)
//   - Preserves the original header value in header_reg
//
// Example Usage:
//   ldr x1, [x0]              // Load header
//   GET_ALLOCATED x1, x2      // x2 = 0 (free) or 1 (allocated)
//   cmp x2, #1                // Natural comparison
//   b.eq block_is_allocated   // Branch if allocated
//
// Return Values:
//   output_reg = 0  // Block is free
//   output_reg = 1  // Block is allocated
//
// Registers Modified:
//   output_reg - Set to 0 or 1 based on allocated flag
//   header_reg - Unchanged (preserved)
//   No other registers are affected
.macro GET_ALLOCATED header_reg, output_reg
    and \output_reg, \header_reg, #ALLOCATED_MASK
    lsr \output_reg, \output_reg, #63  // output_reg >> 63
.endm


// Sets the previous pointer (fprev) in a memory allocator header's links field.
//
// Syntax:
//   SET_FPREV header_addr_reg, fprev_addr_reg
//
// Parameters:
//   header_addr_reg [Register]
//                   - Register containing the address of the header structure
//                   - Points to the header whose fprev field will be modified
//                   - Register value is preserved (non-destructive operation)
//
//   fprev_addr_reg  [Register]
//                   - Register containing the address to store in fprev field
//                   - Can be any valid pointer address or NULL
//                   - Register value is preserved (non-destructive operation)
//
// Behavior:
//   - Stores fprev_addr_reg value at header_addr + WORD_SIZE_BYTES (fprev field)
//   - Does not modify any other header fields
//
// Memory Layout:
//   header_addr + 0:                 64-bit header bitfield (size/unused/allocated)
//   header_addr + WORD_SIZE_BYTES:   fprev pointer (modified)
//   header_addr + DWORD_SIZE_BYTES:  fnext pointer (unchanged)
//
// Example Usage:
//   mov x0, #header_addr          // Address of current header
//   mov x1, #prev_header_addr     // Address of previous header
//   SET_FPREV x0, x1              // current->fprev = prev_header
//
//   // For circular initialization:
//   SET_FPREV x0, x0              // header->fprev = header (self-reference)
//
// Registers Modified:
//   None - both input registers are preserved
//   Memory at header_addr + WORD_SIZE_BYTES is modified
.macro SET_FPREV header_addr_reg, fprev_addr_reg
    str \fprev_addr_reg, [\header_addr_reg, #WORD_SIZE_BYTES]
.endm


// Gets the previous pointer (fprev) from a memory allocator header's links field.
//
// Syntax:
//   GET_FPREV header_addr_reg, output_reg
//
// Parameters:
//   header_addr_reg [Register]
//                   - Register containing the address of the header structure
//                   - Points to the header whose fprev field will be read
//                   - Register value is preserved (non-destructive operation)
//
//   output_reg      [Register]
//                   - Register that will receive the fprev pointer value
//
// Behavior:
//   - Loads the pointer value from header_addr + WORD_SIZE_BYTES (fprev field)
//   - Stores the result in output_reg
//   - Does not modify the header or any other fields
//
// Example Usage:
//   mov x0, #header_addr          // Address of header
//   GET_FPREV x0, x1              // x1 = header->fprev
//   cmp x1, x0                    // Compare with self (circular check)
//   b.eq is_circular              // Branch if self-referencing
//
//   cbz x1, list_start            // Branch if fprev is NULL (start of list)
//
// Registers Modified:
//   output_reg      - Set to the fprev pointer value
//   header_addr_reg - Unchanged (preserved)
.macro GET_FPREV header_addr_reg, output_reg
    ldr \output_reg, [\header_addr_reg, #WORD_SIZE_BYTES]
.endm


// Sets the next pointer (fnext) in a memory allocator header's links field.
//
// Syntax:
//   SET_FNEXT header_addr_reg, fnext_addr_reg
//
// Parameters:
//   header_addr_reg [Register]
//                   - Register containing the address of the header structure
//                   - Points to the header whose fnext field will be modified
//                   - Register value is preserved (non-destructive operation)
//
//   fnext_addr_reg  [Register]
//                   - Register containing the address to store in fnext field
//                   - Can be any valid pointer address or NULL
//                   - Register value is preserved (non-destructive operation)
//
// Behavior:
//   - Stores fnext_addr_reg value at header_addr + DWORD_SIZE_BYTES
//   - Equivalent to: header->links.fnext = fnext_addr
//   - Does not modify any other header fields
//
// Memory Layout:
//   header_addr + 0:                 64-bit header bitfield (size/unused/allocated)
//   header_addr + WORD_SIZE_BYTES:   fprev pointer (unchanged)
//   header_addr + DWORD_SIZE_BYTES:  fnext pointer (modified)
//
// Example Usage:
//   mov x0, #header_addr          // Address of current header
//   mov x1, #next_header_addr     // Address of next header
//   SET_FNEXT x0, x1              // current->fnext = next_header
//
//   // For circular initialization:
//   SET_FNEXT x0, x0              // header->fnext = header (self-reference)
//
//   // For list termination:
//   mov x1, #0                    // NULL pointer
//   SET_FNEXT x0, x1              // Mark end of list
//
// Registers Modified:
//   None - both input registers are preserved
//   Memory at header_addr + DWORD_SIZE_BYTES is modified
.macro SET_FNEXT header_addr_reg, fnext_addr_reg
    str \fnext_addr_reg, [\header_addr_reg, #DWORD_SIZE_BYTES]
.endm


// Gets the next pointer (fnext) from a memory allocator header's links field.
//
// Syntax:
//   GET_FNEXT header_addr_reg, output_reg
//
// Parameters:
//   header_addr_reg [Register]
//                   - Register containing the address of the header structure
//                   - Points to the header whose fnext field will be read
//                   - Register value is preserved (non-destructive operation)
//
//   output_reg      [Register]
//                   - Register that will receive the fnext pointer value
//
// Behavior:
//   - Loads the pointer value from header_addr + DWORD_SIZE_BYTES (fnext field)
//   - Stores the result in output_reg
//   - Does not modify the header or any other fields
//
// Example Usage:
//   mov x0, #header_addr          // Address of header
//   GET_FNEXT x0, x1              // x1 = header->fnext
//   cbz x1, list_end              // Branch if fnext is NULL (end of list)
//
//   cmp x1, x0                    // Compare with self (circular check)
//   b.eq is_circular              // Branch if self-referencing
//
// Registers Modified:
//   output_reg      - Set to the fnext pointer value
//   header_addr_reg - Unchanged (preserved)
.macro GET_FNEXT header_addr_reg, output_reg
    ldr \output_reg, [\header_addr_reg, #DWORD_SIZE_BYTES]
.endm


// Calculates the payload address from a given header address.
//
// Syntax:
//   GET_PAYLOAD_P_FROM_HEADER_P header_addr_reg, output_reg
//
// Parameters:
//   header_addr_reg   [Register]
//                     - Register containing the block header address
//                     - Points to the beginning of the block's metadata
//                     - Register value is preserved (non-destructive operation)
//
//   output_reg        [Register]
//                     - Register to store the calculated payload address
//                     - Will contain pointer to the block's user data area
//                     - Used as destination for the calculation
//
// Behavior:
//   - Calculates payload address by adding header size to header address
//   - Assumes each block header is exactly WORD_SIZE_BYTES in length
//   - The payload immediately follows the header in memory
//   - Equivalent to:
//      payload = (void*)((char*)header + WORD_SIZE_BYTES)
//
// Memory Layout:
//   [header (WORD_SIZE_BYTES)][payload (user data)...]
//   ^                         ^
//   header_addr_reg           output_reg (result)
//
// Example Usage:
//   mov x0, #block_header           // Address of block header
//   GET_PAYLOAD_P_FROM_HEADER_P x0, x1  // x1 = payload address for this block
//
// Registers Modified:
//   output_reg - contains calculated payload address
//   header_addr_reg - preserved unchanged
//
// Note: This is the inverse operation of HEADER_P_FROM_PAYLOAD_P, which
//       calculates header address from payload address.
.macro GET_PAYLOAD_P_FROM_HEADER_P header_addr_reg, output_reg
    add \output_reg, \header_addr_reg, #WORD_SIZE_BYTES
.endm


// Calculates the header address from the payload pointer.
//
// Syntax:
//   HEADER_P_FROM_PAYLOAD_P payload_p_reg, output_reg
//
// Parameters:
//   payload_p_reg [Register]
//                 - Register containing the payload address
//                 - Points to the user data portion of an allocated block
//                 - Register value is preserved (non-destructive operation)
//
//   output_reg    [Register]
//                 - Register to store the calculated header address
//                 - Will contain pointer to the header structure
//                 - Previous value is overwritten
//
// Behavior:
//   - Calculates header address by subtracting WORD_SIZE_BYTES from payload
//   - Equivalent to: header = (header_t*)((char*)payload - WORD_SIZE)
//   - Header immediately precedes payload in memory layout
//
// Memory Layout:
//   header_addr:                     64-bit header bitfield (calculated address)
//   header_addr + WORD_SIZE_BYTES:   payload start (input address)
//
// Example Usage:
//   mov x0, #payload_addr         // Address of user data
//   HEADER_P_FROM_PAYLOAD_P x0, x1 // x1 = header address
//   // Now x1 points to header, x0 still has payload address
//
//   // Chain with other operations:
//   HEADER_P_FROM_PAYLOAD_P x2, x3 // Get header from different payload
//   ldr x4, [x3]                  // Load header value
//
// Registers Modified:
//   output_reg - contains calculated header address
//   payload_p_reg - preserved unchanged
.macro HEADER_P_FROM_PAYLOAD_P payload_p_reg, output_reg
    sub \output_reg, \payload_p_reg, #WORD_SIZE_BYTES
.endm


// Calculates the footer address from the payload pointer.
//
// Syntax:
//   FOOTER_P_FROM_PAYLOAD_P payload_p_reg, output_reg
//
// Parameters:
//   payload_p_reg [Register]
//                 - Register containing the payload address
//                 - Points to the user data portion of an allocated block
//                 - Register value is preserved (non-destructive operation)
//
//   output_reg    [Register]
//                 - Register to store the calculated footer address
//                 - Will contain pointer to the footer structure
//                 - Used as temporary register during calculation
//
// Behavior:
//   - Calculates footer address using block size from header
//   - Equivalent to:
//      footer = (
//                  (footer_t*)((char*)payload
//                  + header(payload)->size - DWORD_SIZE))
//   - Reads header to get block size, then computes footer location
//   - Footer is located at the end of the allocated block
//
// Memory Layout:
//   header_addr:                           64-bit header bitfield
//   header_addr + WORD_SIZE_BYTES:         payload start (input address)
//   ...
//   payload + size - DWORD_SIZE_BYTES:     footer location (calculated address)
//
// Example Usage:
//   mov x0, #payload_addr           // Address of user data
//   FOOTER_P_FROM_PAYLOAD_P x0, x1  // x1 = footer address
//   ldr x2, [x1]                   // Load footer value
//
//   // Verify header/footer consistency:
//   HEADER_P_FROM_PAYLOAD_P x0, x3  // Get header address
//   FOOTER_P_FROM_PAYLOAD_P x0, x4  // Get footer address
//   ldr x5, [x3]                   // Compare header and footer values
//   ldr x6, [x4]
//
// Registers Modified:
//   output_reg - contains calculated footer address (intermediate values
//                overwritten)
//   payload_p_reg - preserved unchanged
//   Depends on GET_SIZE macro for additional register usage
.macro FOOTER_P_FROM_PAYLOAD_P payload_p_reg, output_reg
   HEADER_P_FROM_PAYLOAD_P \payload_p_reg, \output_reg
   ldr \output_reg, [\output_reg]
   GET_SIZE \output_reg, \output_reg
   sub \output_reg, \output_reg, #DWORD_SIZE_BYTES 
   add \output_reg, \payload_p_reg, \output_reg
.endm


// Calculates the address of the next payload from the current payload pointer.
//
// Syntax:
//   NEXT_PAYLOAD_P cur_payload_p_reg, output_reg
//
// Parameters:
//   cur_payload_p_reg [Register]
//                     - Register containing the current payload address
//                     - Points to the user data portion of the current
//                       allocated block
//                     - Register value is preserved (non-destructive operation)
//
//   output_reg        [Register]
//                     - Register to store the calculated next payload address
//                     - Will contain pointer to the next block's payload
//                     - Used as temporary register during calculation
//
// Behavior:
//   - Calculates next payload address by adding current block size to current
//     payload
//   - Equivalent to:
//      next_payload = (void*)((char*)payload + header(payload)->size)
//   - Reads the current block's header to get its size, then advances by that
//     amount
//
// Example Usage:
//   mov x0, #current_payload        // Address of current block's data
//   NEXT_PAYLOAD_P x0, x1          // x1 = next block's payload address
//
// Registers Modified:
//   output_reg - contains calculated next payload address
//   cur_payload_p_reg - preserved unchanged
.macro NEXT_PAYLOAD_P cur_payload_p_reg, output_reg
    HEADER_P_FROM_PAYLOAD_P \cur_payload_p_reg, \output_reg
    ldr \output_reg, [\output_reg]
    GET_SIZE \output_reg, \output_reg
    add \output_reg, \cur_payload_p_reg, \output_reg
.endm


// Calculates the address of the previous payload from the current payload pointer.
//
// Syntax:
//   PREV_PAYLOAD_P cur_payload_p_reg, output_reg
//
// Parameters:
//   cur_payload_p_reg [Register]
//                     - Register containing the current payload address
//                     - Points to the user data portion of the current
//                       allocated block
//                     - Register value is preserved (non-destructive operation)
//
//   output_reg        [Register]
//                     - Register to store the calculated previous payload
//                       address
//                     - Will contain pointer to the previous block's payload
//                     - Used as temporary register during calculation
//
// Behavior:
//   - Calculates previous payload address by reading the previous block's size
//     from its footer and subtracting that amount from current payload
//   - Assumes blocks store size information in both header and footer for
//     bidirectional traversal
//   - Footer is located immediately before the current block's header
//   - Equivalent to:
//      prev_size = footer(current_payload - DWORD_SIZE_BYTES)->size
//      prev_payload = (void*)((char*)current_payload - prev_size)
//
// Memory Layout Assumption:
//   [prev_header][prev_payload...][prev_footer][cur_header][cur_payload...]
//                                      ^
//                                 footer contains
//                                 previous block size
//
// Example Usage:
//   mov x0, #current_payload        // Address of current block's data
//   PREV_PAYLOAD_P x0, x1          // x1 = previous block's payload address
//
// Registers Modified:
//   output_reg - contains calculated previous payload address
//   cur_payload_p_reg - preserved unchanged
.macro PREV_PAYLOAD_P cur_payload_p_reg, output_reg
    // Caculate the address of the previous block's footer
    // (located DWORD_SIZE_BYTES before current payload)
    sub \output_reg, \cur_payload_p_reg, #DWORD_SIZE_BYTES

    // Load the previous block's size from its footer
    ldr \output_reg, [\output_reg]

    // Extract the size field from the footer data
    GET_SIZE \output_reg, \output_reg

    // Calculate previous payload address by subtracting previous block size
    // from current payload address
    sub \output_reg, \cur_payload_p_reg, \output_reg
.endm


// Calculates the address of the next free block's payload in the free list.
//
// Syntax:
//   NEXT_FREE_PAYLOAD_P cur_payload_p_reg, output_reg
//
// Parameters:
//   cur_payload_p_reg [Register]
//                     - Register containing the current free block's payload
//                       address
//                     - Points to the user data portion of the current free
//                       block
//                     - Must be a block that is currently in the free list
//                     - Register value is preserved (non-destructive operation)
//
//   output_reg        [Register]
//                     - Register to store the next free block's payload address
//                     - Will contain pointer to the next free block's payload
//                     - Used as temporary register during calculation
//
// Behavior:
//   - Traverses the free list forward to find the next free block
//   - Reads the 'next' pointer from the current block's header
//   - Converts the next block's header address to its payload address
//   - Does NOT traverse by physical memory layout, but by free list linkage
//   - Equivalent to:
//      next_header = header(current_payload)->fnext
//      next_payload = payload_from_header(next_header)
//
// Example Usage:
//   mov x0, #current_free_payload   // Address of current free block's data
//   NEXT_FREE_PAYLOAD_P x0, x1      // x1 = next free block's payload address
//
// Registers Modified:
//   output_reg - contains next free block's payload address (or null if end)
//   cur_payload_p_reg - preserved unchanged
//
// Note: This traverses the logical free list, not physical memory order.
//       Use NEXT_PAYLOAD_P for physical memory traversal.
.macro NEXT_FREE_PAYLOAD_P cur_payload_p_reg, output_reg
    HEADER_P_FROM_PAYLOAD_P \cur_payload_p_reg, \output_reg
    GET_FNEXT \output_reg, \output_reg
    GET_PAYLOAD_P_FROM_HEADER_P \output_reg, \output_reg
.endm


// Calculates the address of the previous free block's payload in the free list.
//
// Syntax:
//   PREV_FREE_PAYLOAD_P cur_payload_p_reg, output_reg
//
// Parameters:
//   cur_payload_p_reg [Register]
//                     - Register containing the current free block's payload
//                       address
//                     - Points to the user data portion of the current free
//                       block
//                     - Must be a block that is currently in the free list
//                     - Register value is preserved (non-destructive operation)
//
//   output_reg        [Register]
//                     - Register to store the previous free block's payload
//                       address
//                     - Will contain pointer to the previous free block's
//                       payload
//                     - Used as temporary register during calculation
//
// Behavior:
//   - Traverses the free list backward to find the previous free block
//   - Reads the 'previous' pointer from the current block's header
//   - Converts the previous block's header address to its payload address
//   - Does NOT traverse by physical memory layout, but by free list linkage
//   - Equivalent to:
//      prev_header = header(current_payload)->fprev
//      prev_payload = payload_from_header(prev_header)
//
// Example Usage:
//   mov x0, #current_free_payload   // Address of current free block's data
//   PREV_FREE_PAYLOAD_P x0, x1   // x1 = previous free block's payload address
//
// Registers Modified:
//   output_reg - contains previous free block's payload address
//   cur_payload_p_reg - preserved unchanged
//
// Note: This traverses the logical free list, not physical memory order.
//       Use PREV_PAYLOAD_P for physical memory traversal.
.macro PREV_FREE_PAYLOAD_P cur_payload_p_reg, output_reg
    HEADER_P_FROM_PAYLOAD_P \cur_payload_p_reg, \output_reg
    GET_FPREV \output_reg, \output_reg
    GET_PAYLOAD_P_FROM_HEADER_P \output_reg, \output_reg
.endm


coalesce:
    str lr, [sp, #-16]!

    // Retrieve the addresses of the previous and next blocks
    PREV_PAYLOAD_P x0, x1
    NEXT_PAYLOAD_P x0, x2

    // Retrieve the size of the current block
    HEADER_P_FROM_PAYLOAD_P x0, x3
    ldr x4, [x3]
    GET_SIZE x4, x4

    // Retrieve the allocated status of the previous block
    HEADER_P_FROM_PAYLOAD_P x1, x5
    GET_ALLOCATED x5, x5

    // Retrieve the allocated status of the next block
    HEADER_P_FROM_PAYLOAD_P x2, x6
    GET_ALLOCATED x6, x6

    // Calculate the jump table index
    orr w7, w5, w6, LSL #1  // w5 = prev | (next << 1)

    // Jump table dispatch
    adrp x8, .coalesce_jump_table  // Get the page address
    add x8, x8, :lo12:.coalesce_jump_table  // Add the page offset
    ldr x8, [x8, x7, LSL #3]  // Each element in the jump table is 2^3 = 8 bytes
    br x8

.align 3
.coalesce_jump_table:
    .quad .Lcoalesce_case_neither_allocated
    .quad .Lcoalesce_case_only_prev_allocated
    .quad .Lcoalesce_case_only_next_allocated
    .quad .Lcoalesce_case_both_allocated

.Lcoalesce_case_neither_allocated:
    b .Lcoalesce_add_to_list
.Lcoalesce_case_only_prev_allocated:
    b .Lcoalesce_add_to_list
.Lcoalesce_case_only_next_allocated:
    b .Lcoalesce_add_to_list
.Lcoalesce_case_both_allocated:
    b .Lcoalesce_add_to_list

.Lcoalesce_add_to_list:
    // TODO: Implement
.Lcoalesce_ret:
    ldr lr, [sp], #16
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
//   - coalesce(payload) - Merges adjacent free blocks
//
// Error Conditions:
//   - Returns NULL if mem_sbrk fails (heap cannot be extended)
extend_heap:
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

    bl coalesce
    b .Lextend_heap_ret
.Lextend_heap_sbrk_failed:
    mov x0, #0  // Return NULL
.Lextend_heap_ret:
    ldp lr, x19, [sp], #16
    ret


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
//   - Allocates space for NUM_SEG_LISTS prologue blocks plus padding and epilogue
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
//
// Dependencies:
//   - SET_SIZE, SET_ALLOCATED macros for header manipulation
//   - SET_FPREV, SET_FNEXT macros for link manipulation
//   - Constants: NUM_SEG_LISTS, WORD_SIZE_BYTES, DWORD_SIZE_BYTES, PAGE_SIZE_BYTES, PTR_ALIGN
//   - mem_init, mem_sbrk, extend_heap functions
//   - seg_listp global array
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
    bl extend_heap
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
