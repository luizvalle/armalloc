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

