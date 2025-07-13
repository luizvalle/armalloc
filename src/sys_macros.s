/*
* sys_macros.s - Macros that call Linux systems calls.
*/
.include "unistd.s"

// Issues the Linux syscall to write `length` bytes from memory at `buffer`
// to the file descriptor `fd`.
//
// Syntax:
//   sys_write fd, buffer, length
//
// Parameters:
//   fd     [Immediate or Register]
//          - File descriptor (e.g., 1 for stdout, 2 for stderr)
//
//   buffer [Label or Symbol]
//          - Label referring to a memory location (e.g., .asciz string)
//          - Will be loaded as an address into register x1
//
//   length [Immediate or Register]
//          - Number of bytes to write (e.g., 14)
//
// Registers Modified:
//   x0 - Set to `fd`
//   x1 - Set to address of `buffer`
//   x2 - Set to `length`
//   x8 - Set to syscall number (64 for write)
//   Other registers are unaffected
.macro sys_write fd, buffer, length
    mov x0, \fd
    ldr x1, =\buffer
    mov x2, \length
    mov x8, #SYS_WRITE
    svc 0
.endm
