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


// Initializes the memory manager.
mm_init:
    str lr, [sp, #-16]!
    // mem_init(x0)
    bl mem_init
    cbnz x0, .Linit_ret
    // Calculate the number of words needed for the empty list
    mov x0, #2 + NUM_SEG_LISTS * 4
    // mem_sbrk(2 + NUM_SEG_LISTS * 4)
    bl mem_sbrk
    cmp x0, #-1
    b.eq .Linit_ret  // mem_sbrk(2 + NUM_SEG_LISTS * 4) failed
    str xzr, [x0], #WORD_SIZE_BYTES  // Alignment padding
    // Initialize the segregated free lists
    mov x1, #NUM_SEG_LISTS
.Linit_seglists_loop:
    // TODO: Implement this
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
