// Defines functions to manage the arena

.include "constants.inc"
.include "sys_macros.inc"
.include "mm_errno_constants.inc"

.section .bss

.align PTR_ALIGN

_mem_heap_start: .skip PTR_SIZE_BYTES  // Points to first byte of heap

_mem_brk: .skip PTR_SIZE_BYTES  // Points to last byte of heap plus 1

_mem_heap_end: .skip PTR_SIZE_BYTES  // Max legal heap addr plus 1

.section .text

.global mem_init
.global mem_sbrk
.global mem_deinit

.global _get_mem_heap_start
.global _get_mem_brk
.global _get_mem_heap_end

// Retrieves the internal _mem_heap_start value
// Only used for testing
_get_mem_heap_start:
    ldr x0, =_mem_heap_start
    ldr x0, [x0]
    ret

// Retrieves the internal _mem_brk value
// Only used for testing
_get_mem_brk:
    ldr x0, =_mem_brk
    ldr x0, [x0]
    ret

// Retrieves the internal _mem_heap_end value
// Only used for testing
_get_mem_heap_end:
    ldr x0, =_mem_heap_end
    ldr x0, [x0]
    ret

// Initializes a contiguous memory arena of the given size.
//
// Arguments:
//   x0 - Requested arena size in bytes (should be > 0). Treated
//        as an unsigned integer.
//
// Returns:
//   x0 - Return status:
//        0   = Success
//       -1   = Failure (error code is set in mm_errno)
//
// Clobbers (Registers modified):
//   x0 - Used for input, temporary values, and return code
//   x1 - Used for rounding, pointer arithmetic, and addressing
//   x2–x5 - Clobbered by sys_mmap macro
//   x8 - Set by sys_mmap to syscall number
//   x19 - Callee-saved: used to store rounded arena size
//   sp - Adjusted to save/restore x19 and lr
//
// Global Data Written:
//   _mem_heap_start - Set to start of mmap'd memory
//   _mem_brk        - Set to heap start (current break)
//   _mem_heap_end   - Set to heap start + arena size
//
// Notes:
//   - The requested size is rounded up to the nearest multiple of
//     PAGE_SIZE_BYTES.
//   - On error, sets mm_errno to:
//       MM_ERR_INTERNAL (mm_init already called)
//       MM_ERR_INVAL (called with 0 size)
//       MM_ERR_NOMEM (mmap failure)
mem_init:
    stp x19, lr, [sp, #-16]!
    cbz x0, .Linit_invalid_size_err  // Size should not be 0
    ldr x1, =_mem_heap_start
    ldr x1, [x1]
    cbnz x1, .Linit_already_initialized_err  // Expect heap_start to be NULL
    // Round the requested amount to the next multiple of PAGE_SIZE_BYTES
    mov x1, #PAGE_SIZE_BYTES - 1
    add x0, x0, x1
    bic x19, x0, x1
    // mmap(addr=0, length=x1, prot=RW, flags=PRIVATE|ANON, fd=-1, offset=0)
    sys_mmap #0, x19, #PROT_READ | PROT_WRITE, #MAP_PRIVATE | MAP_ANONYMOUS, #-1, #0
    cmp x0, #MAP_FAILED
    b.eq .Linit_mmap_err
    // Save mmap result into the global pointers
    ldr x1, =_mem_heap_start
    str x0, [x1]
    ldr x1, =_mem_brk
    str x0, [x1]
    ldr x1, =_mem_heap_end
    add x0, x0, x19
    str x0, [x1]
    mov x0, #0  // Return success
    b .Linit_ret 
.Linit_invalid_size_err:
    mov x0, #MM_ERR_INVAL
    bl set_mm_errno
    mov x0, #-1
    b .Linit_ret
.Linit_already_initialized_err:
    mov x0, #MM_ERR_INTERNAL
    bl set_mm_errno
    mov x0, #-1  // Return failure
    b .Linit_ret
.Linit_mmap_err:
    mov x0, #MM_ERR_NOMEM
    bl set_mm_errno
    mov x0, #-1  // Return failure
    b .Linit_ret
.Linit_ret:
    ldp x19, lr, [sp], #16
    ret

// Adjusts the program break by the increment, returning the previous break.
//
// Analogous to the glibc `sbrk()` function.
//
// Arguments:
//   x0 - Increment in bytes:
//        - Positive: grow the heap
//        - Negative: shrink the heap
//        - Zero: return the current break without making changes
//
// Returns:
//   x0 - Return value:
//        - On success: the previous value of the program break (before
//          adjustment)
//        - On failure: -1, and `mm_errno` is set to:
//            - MM_ERR_INTERNAL: mem_init not called
//            - MM_ERR_INVAL: requested change would move break below heap start
//            - MM_ERR_NOMEM: requested change would move break above heap end
//
// Clobbers (Registers modified):
//   x0 - Input (increment), temporary, and return value
//   x1 - Address of `_mem_brk`
//   x2 - Copy of requested increment
//   x3 - Calculated new break address
//   x4 - Temporary: heap start or heap end
//   x8 - Used internally by `set_mm_errno` (syscall stub)
//
// Notes:
//   - This routine must be called after `mem_init`, which sets `_mem_brk`.
//   - The break must remain within bounds: [_mem_heap_start, _mem_heap_end).
//   - On error, `_mem_brk` is left unchanged and -1 is returned.
mem_sbrk:
    str lr, [sp, #-16]!
    mov x2, x0
    ldr x1, =_mem_brk
    ldr x0, [x1]
    cbz x0, .Lerr_not_initialized  // Fail if _mem_brk is uninitialized
    cbz x2, .Lbrk_ret  // If increment is 0, return current break
    add x3, x0, x2  // Compute new break: new_brk = old_brk + increment
    ldr x4, =_mem_heap_start     // Load heap start
    ldr x4, [x4]
    cmp x3, x4
    b.lt .Lerr_too_small         // Error if new break is below heap start
    ldr x4, =_mem_heap_end       // Load heap end (exclusive)
    ldr x4, [x4]
    cmp x3, x4
    b.ge .Lerr_too_big           // Error if new break is >= heap end
    str x3, [x1]                 // Commit the new break to _mem_brk
    b .Lbrk_ret                  // Return old break (in x0)
.Lerr_not_initialized:
    mov x0, #MM_ERR_INTERNAL     // Error: break not initialized
    bl set_mm_errno
    b .Lbrk_ret_err
.Lerr_too_small:
    mov x0, #MM_ERR_INVAL        // Error: new break is below heap start
    bl set_mm_errno
    b .Lbrk_ret_err
.Lerr_too_big:
    mov x0, #MM_ERR_NOMEM        // Error: new break exceeds heap end
    bl set_mm_errno
    b .Lbrk_ret_err
.Lbrk_ret_err:
    mov x0, #-1                  // Return -1 to indicate failure
.Lbrk_ret:
    ldr lr, [sp], #16            // Restore return address
    ret

// Deinitializes the arena by unmapping the region allocated by mem_init.
//
// Arguments:
//   None (reads internal global variables)
//
// Returns:
//   x0 - Return status:
//        0   = Success (arena unmapped or already uninitialized)
//       -1   = Failure (invalid heap state or munmap failure; mm_errno is set)
//
// Clobbers (Registers modified):
//   x0 - Used for arena start, syscall result, and return code
//   x1 - Used for arena end and intermediate addresses
//   x8 - Set to syscall number by `sys_munmap`
//
// Global Data Written:
//   _mem_heap_start - Reset to 0 on successful unmap
//   _mem_brk        - Reset to 0 on successful unmap
//   _mem_heap_end   - Reset to 0 on successful unmap
//
// Notes:
//   - If the arena was not initialized (i.e., `_mem_heap_start == 0`), the
//     function returns 0 immediately without making a syscall.
//   - If the arena size is invalid (`_mem_heap_end <= _mem_heap_start`),
//     the function returns -1 and sets `mm_errno = MM_ERR_CORRUPT`.
//   - If `munmap` fails, the function returns -1 and sets
//     `mm_errno = MM_ERR_INTERNAL`; pointers are left unchanged.
//   - On success, all heap-related global pointers are cleared.
mem_deinit:
    str lr, [sp, #-16]!
    ldr x0, =_mem_heap_start
    ldr x0, [x0]
    cbz x0, .Ldeinit_ret_success   // Heap not initialized, return immediately
    ldr x1, =_mem_heap_end
    ldr x1, [x1]
    subs x1, x1, x0  // Calculate the arena size
    b.le .Ldeinit_invalid_heap_state  // _mem_heap_start > _mem_heap_end
    sys_munmap x0, x1
    cbnz x0, .Ldeinit_munmap_err
    // Success: Reset the heap pointers to NULL
    mov x0, #0
    ldr x1, =_mem_heap_start
    str x0, [x1]
    ldr x1, =_mem_brk
    str x0, [x1]
    ldr x1, =_mem_heap_end
    str x0, [x1]
.Ldeinit_ret_success:
    mov x0, #0
    b .Ldeinit_ret
.Ldeinit_invalid_heap_state:
    mov x0, #MM_ERR_CORRUPT
    bl set_mm_errno
    mov x0, #-1
    b .Ldeinit_ret
.Ldeinit_munmap_err:
    mov x0, #MM_ERR_INTERNAL
    bl set_mm_errno
    mov x0, #-1
    b .Ldeinit_ret
.Ldeinit_ret:
    ldr lr, [sp], #16
    ret
