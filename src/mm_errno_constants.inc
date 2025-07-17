// Error code constants for custom malloc memory manager
//
// These constants mirror the definitions in mm_errno.h and should be kept in
// sync.
// They are used to populate mm_errno when errors occur during memory allocation.

// No error occurred; operation was successful.
.equ MM_ERR_NONE,         0

// Memory allocation failed due to insufficient space (e.g., sbrk failure).
.equ MM_ERR_NOMEM,        1

// An invalid argument was passed to a memory routine (e.g., malloc(0)).
.equ MM_ERR_INVAL,        2

// Memory alignment error (e.g., request for misaligned block).
.equ MM_ERR_ALIGN,        3

// Heap corruption detected (e.g., buffer overrun, double free).
.equ MM_ERR_CORRUPT,      4

// Internal allocator error (e.g., unexpected state or unimplemented case).
.equ MM_ERR_INTERNAL,     5
