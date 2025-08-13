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
//   output_reg - contains calculated footer address (intermediate values overwritten)
//   payload_p_reg - preserved unchanged
//   Depends on GET_SIZE macro for additional register usage
.macro FOOTER_P_FROM_PAYLOAD_P payload_p_reg, output_reg
   HEADER_P_FROM_PAYLOAD_P \payload_p_reg, \output_reg
   ldr \output_reg, [\output_reg]
   GET_SIZE \output_reg, \output_reg
   sub \output_reg, \output_reg, #DWORD_SIZE_BYTES 
   add \output_reg, \payload_p_reg, \output_reg
.endm


extend_heap:
    stp lr, x19, [sp, #-16]!
    tst x0, #1
    b.eq .Lextend_heap_even_input
    add x0, x0, #1  // Make the number even
.Lextend_heap_even_input:
    lsl x0, x0, #WORD_ALIGN  // Multiply by WORD_SIZE_BYTES
    mov x19, x0  // Save the size we requested
    bl mem_sbrk
    cmp x0, #-1
    b.eq .Lextend_heap_sbrk_failed
    SET_SIZE x1, x19
    SET_ALLOCATED x1, 0
    HEADER_P_FROM_PAYLOAD_P x0, x2
    str x1, [x2]
    FOOTER_P_FROM_PAYLOAD_P x0, x2
    str x1, [x2]
    // TODO: Implement this
.Lextend_heap_sbrk_failed:
    mov x0, #0
.Lextend_heap_ret:
    ldp lr, x19, [sp], #16
    ret

// Initializes the memory manager.
mm_init:
    str lr, [sp, #-16]!
    // mem_init(x0)
    bl mem_init
    cbnz x0, .Linit_ret
    // Calculate the number of words needed for the empty list
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
    mov x3, #0
.Linit_seglists_loop:
    // Initialize the header
    str x1, [x0]
    SET_FPREV x0, x0
    SET_FNEXT x0, x0

    // Initialize the footer
    str x1, [x0, #3 * WORD_SIZE_BYTES]

    add x4, x0, #WORD_SIZE_BYTES  // Pointer to payload
    str x4, [x2, x3, LSL #3]  // Update the segmented list array

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
