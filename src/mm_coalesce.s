.include "mm_list_traversal_macros.inc"

.section .text

.global _coalesce


_coalesce:
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
