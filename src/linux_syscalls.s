/*
 * linux_syscalls.s - Macros to wrap the 64-bit Linux system calls.
 */

/*
 * Change the data segment size
 *
 * Args:
 *      increment - The number of bytes to increment the data segment by.
 *
 * Return:
 *      x0 - On success, the address of the previous program break.
             On failure, -1.
 */
.macro sbrk increment
    stp x1, x8, [sp, #-16]!

    mov x8, #214  // syscall: brk
    mov x0, #0  // Get the current break
    svc 0

    mov x1, x0  // Store the break in x1

    add x0, x1, #\increment
    svc 0  // Set the new program break

    // Check if the syscall failed
    cmp x0, x1
    b.eq 1f

    mov x0, x1  // Return the old program break
    b 2f  // Go to cleanup

1:  // Failure
    mov x0, #-1

2:  // Cleanup
    ldp x1, x8, [sp], #16
.endm
