// Defines some macros that call Linux systems calls.

.equ SYS_WRITE,					64	 // write to a file descriptor
.equ SYS_MMAP,                  222  // creates a new mapping in the virtual address space
.equ SYS_MUNMAP,                215  // unmap the region created by mmap

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

// Issues the Linux syscall to create a memory mapping using `mmap()`.
// This allows you to allocate virtual memory directly from the OS,
// commonly used for implementing allocators without relying on libc.
//
// Syntax:
//   sys_mmap addr, length, prot, flags, fd, offset
//
// Parameters:
//   addr   [Register or #0]
//          - Suggested start address of the mapping (or 0 to let kernel choose)
//
//   length [Register or Immediate]
//          - Length of the mapping in bytes (must be multiple of page size)
//
//   prot   [Immediate or Register]
//          - Memory protection flags (bitwise OR of PROT_READ, PROT_WRITE, etc.)
//            Common values:
//              - 0x1 = PROT_READ
//              - 0x2 = PROT_WRITE
//              - 0x4 = PROT_EXEC
//
//   flags  [Immediate or Register]
//          - Mapping flags (e.g., private, anonymous)
//            Common values:
//              - 0x02 = MAP_PRIVATE
//              - 0x20 = MAP_ANONYMOUS
//
//   fd     [Immediate or Register]
//          - File descriptor (set to -1 for anonymous mapping)
//
//   offset [Register or #0]
//          - Offset in the file (must be 0 for anonymous mappings)
//
// Return:
//   x0 - On success, the address of the mapped memory region.
//        On failure, a value in the range -4095 to -1 (error code).
//
// Registers Modified:
//   x0 - Set to `addr` and receives return value
//   x1 - Set to `length`
//   x2 - Set to `prot`
//   x3 - Set to `flags`
//   x4 - Set to `fd`
//   x5 - Set to `offset`
//   x8 - Set to syscall number
//   Other registers are unaffected
.macro sys_mmap addr, length, prot, flags, fd, offset
    mov x0, \addr
    mov x1, \length
    mov x2, \prot
    mov x3, \flags
    mov x4, \fd
    mov x5, \offset
    mov x8, #SYS_MMAP
    svc 0
.endm

// Issues the Linux syscall to unmap a region of memory.
//
// This macro wraps the `munmap` system call which removes memory mappings
// previously created with `mmap` or similar.
//
// Syntax:
//   sys_munmap addr, length
//
// Parameters:
//   addr   [Register]
//          - Starting address of the memory region to unmap
//          - Must be page-aligned
//
//   length [Immediate or Register]
//          - Size of the memory region in bytes
//          - Must be a multiple of the system page size
//
// Registers Modified:
//   x0 - Set to `addr` (starting address)
//   x1 - Set to `length` (size of the region)
//   x8 - Set to syscall number
//   Other registers are unaffected
//
// Return Value:
//   On success: x0 = 0
//   On failure: x0 = -1
//
// Notes:
//   - The caller is responsible for ensuring alignment and validity of the address and length.
//   - This syscall should not be used to unmap regions not previously mapped with `mmap`.
.macro sys_munmap addr, length
    mov x0, \addr
    mov x1, \length
    mov x8, #SYS_MUNMAP
    svc 0
.endm
