// Defines functions to manage the arena

.include "constants.inc"
.include "sys_macros.inc"
.include "mm_errno_constants.inc"

.section .bss

.align PTR_ALIGN

_mem_heap_start: .skip PTR_SIZE_BYTES  // Points to first byte of heap

_mem_brk: .skip PTR_SIZE_BYTES  // Points to last byte of heap plus 1

_mem_heap_end: .skip PTR_SIZE_BYTES  // Max legal heap addr plus 1

.section .data

_invalid_arena_size_str: .asciz "mem_init() error: arena size must be > 0.\n"

// Compute the size of the string (including the null terminator)
// '.': current location counter
// '. - _invalid_arena_size_str': difference between current address and label
// This sets '_invalid_arena_size_str_size' to the number of bytes in the string
.equ _invalid_arena_size_str_size, . - _invalid_arena_size_str

_mmap_failed_str: .asciz "mem_init() error: mmap().\n"

// Compute the size of the string (including the null terminator)
// '.': current location counter
// '. - _mmap_failed_str': difference between current address and label
// This sets '_mmap_failed_str_size' to the number of bytes in the string
.equ _mmap_failed_str_size, . - _mmap_failed_str

_mem_sbrk_too_small_str:
    .ascii "mem_sbrk() error: The requested increment would cause brk to be "
    .asciz "smaller than heap start.\n"

// Compute the size of the string (including the null terminator)
// '.': current location counter
// '. - _mem_sbrk_too_small_str': difference between current address and label
// This sets '_mem_sbrk_too_small_str_size' to the number of bytes in the string
.equ _mem_sbrk_too_small_str_size, . - _mem_sbrk_too_small_str

_mem_sbrk_no_space_left_str:
    .ascii "mem_sbrk() error: The heap does not have enough space left to "
    .asciz "accomate the request.\n"

// Compute the size of the string (including the null terminator)
// '.': current location counter
// '. - _mem_sbrk_no_space_left_str': difference between current address and
// label
// This sets '_mem_sbrk_no_space_left_str_size' to the number of bytes in the
// string
.equ _mem_sbrk_no_space_left_str_size, . - _mem_sbrk_no_space_left_str

.section .text

.global mem_init
.global mem_sbrk
.global mem_deinit

.global get_mem_heap_start
.global get_mem_brk
.global get_mem_heap_end

// Retrieves the internal _mem_heap_start value
// Only used for testing
get_mem_heap_start:
    ldr x0, =_mem_heap_start
    ldr x0, [x0]
    ret

// Retrieves the internal _mem_brk value
// Only used for testing
get_mem_brk:
    ldr x0, =_mem_brk
    ldr x0, [x0]
    ret

// Retrieves the internal _mem_heap_end value
// Only used for testing
get_mem_heap_end:
    ldr x0, =_mem_heap_end
    ldr x0, [x0]
    ret

// Initializes a contiguous memory arena of the given size.
//
// Arguments:
//   x0 - Requested arena size in bytes (must be > 0).
//
// Returns:
//   x0 - Return status:
//        0   = Success
//       -1   = Failure (invalid size or mmap failure)
//
// Clobbers (Registers modified):
//   x0 - Used for input, temporary values, and return code
//   x1 - Used for size rounding and storing addresses
//   x2–x5 - Clobbered via `sys_mmap`
//   x8 - Set to syscall number by `sys_mmap`
//   x19 - Used to store the original requested size (callee-saved, preserved)
//   sp - Stack is adjusted to save/restore x19
//
//   The function preserves all other registers.
//   x19 is preserved internally via stack.
//
// Global Data Written:
//   _mem_heap_start - Set to start of mmap'd memory
//   _mem_brk        - Initially set to heap start (current break)
//   _mem_heap_end   - Set to heap start + requested size
//
// Notes:
//   - The requested size is rounded up to the nearest multiple of
//     PAGE_SIZE_BYTES.
//   - On error, writes diagnostic messages to STDERR using sys_write.
//   - Assumes `_mem_heap_start`, `_mem_brk`, `_mem_heap_end` are defined in
//     `.bss`
//     as 8-byte variables.
//   - Assumes constants are defined:
//       PAGE_SIZE_BYTES, PROT_READ, PROT_WRITE, MAP_PRIVATE, MAP_ANONYMOUS,
//       MAP_FAILED
mem_init: 
    cmp x0, #0
    b.gt .Lvalid_arena_size
    sys_write #STDERR, _invalid_arena_size_str, #_invalid_arena_size_str_size
    mov x0, #-1
    ret
.Lvalid_arena_size:
    str x19, [sp, #-16]!
    // Round the requested size to a multiple of PAGE_SIZE_BYTES.
    // Assumes PAGE_SIZE_BYTES is a power of 2.
    mov x1, #PAGE_SIZE_BYTES - 1
    add x0, x0, x1
    bic x1, x0, x1
    mov x19, x1  // Save the requested size for later
    sys_mmap #0, x1, #PROT_READ | PROT_WRITE, #MAP_PRIVATE | MAP_ANONYMOUS, #-1, #0
    cmp x0, #MAP_FAILED
    b.ne .Lmmap_succeeded
    sys_write #STDERR, _mmap_failed_str, #_mmap_failed_str_size
    mov x0, #-1
    b .Lmem_init_ret
.Lmmap_succeeded:  
    ldr x1, =_mem_heap_start
    str x0, [x1]
    ldr x1, =_mem_brk
    str x0, [x1]
    ldr x1, =_mem_heap_end
    add x0, x0, x19
    str x0, [x1]
    mov x0, #0
.Lmem_init_ret:
    ldr x19, [sp], #16
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
    str lr, [sp, #-16]!          // Save return address on stack
    mov x2, x0                   // Copy requested increment into x2
    ldr x1, =_mem_brk            // Load address of _mem_brk (heap break pointer)
    ldr x0, [x1]                 // Load current break (soon to be returned)
    cmp x0, #0
    b.eq .Lerr_not_initialized   // Fail if _mem_brk is uninitialized
    cmp x2, #0
    b.eq .Lbrk_ret               // If increment is 0, return current break
    add x3, x0, x2               // Compute new break: new_brk = old_brk +
                                 // increment
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
    ret                          // Return to caller

// Deinitializes the arena by unmapping the region allocated by mem_init()
//
// Arguments:
//   None (reads internal global variable `_mem_heap_start`)
//
// Returns:
//   x0 - Return status:
//        0   = Success (arena was unmapped or already uninitialized)
//       -1   = Failure (munmap syscall failed)
//
// Clobbers (Registers modified):
//   x0 - Used for input, result from `sys_munmap`, and return code
//   x1 - Used to compute arena size and store temporary addresses
//   x8 - Set to syscall number by `sys_munmap`
//
//   The function preserves all other registers.
//
// Global Data Written:
//   _mem_heap_start - Reset to 0
//   _mem_brk        - Reset to 0
//   _mem_heap_end   - Reset to 0
//
// Notes:
//   - If the arena was not initialized (i.e., `_mem_heap_start == 0`), the
//     function returns 0 immediately without making a syscall.
//   - If the arena size is nonpositive (`_mem_heap_end <= _mem_heap_start`),
//     `munmap` is skipped, but pointers are still reset.
//   - If `munmap` fails, the function returns -1 and the pointers are not
//     reset.
mem_deinit:
    ldr x0, =_mem_heap_start
    ldr x0, [x0]
    cmp x0, #0  // Check if we are initialized
    b.ne .Larena_exists
    mov x0, #0
    ret  // Nothing to do, return early
.Larena_exists:
    ldr x1, =_mem_heap_end
    ldr x1, [x1]
    subs x1, x1, x0  // Calculate the arena size
    b.le .Lreset_pointers
    ldr x0, =_mem_heap_start
    ldr x0, [x0]
    sys_munmap x0, x1
    cmp x0, #0
    b.eq .Lreset_pointers
    mov x0, #-1  // Error
    ret
.Lreset_pointers:
    mov x0, #0
    ldr x1, =_mem_heap_start
    str x0, [x1]
    ldr x1, =_mem_brk
    str x0, [x1]
    ldr x1, =_mem_heap_end
    str x0, [x1]
    ret
