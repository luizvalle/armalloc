// Defines the infrastructure to propagate errors through error codes.

.include "constants.inc"

.section .bss

.align INT_ALIGN

mm_errno: .skip INT_SIZE_BYTES  // Private to this compilation unit

.section .text

.global get_mm_errno
.global set_mm_errno

// Returns the current value of the memory manager's global error code.
//
// Arguments:
//   None
//
// Returns:
//   x0 - The current value of `mm_errno`
//
// Clobbers (Registers modified):
//   x0 - Set to the value stored in `mm_errno`
get_mm_errno:
    ldr x0, =mm_errno
    ldr w0, [x0]
    ret

// Sets the memory manager's global error code to the given value.
//
// Arguments:
//   x0 - Error code to store in `mm_errno`
//
// Returns:
//   None
//
// Clobbers (Registers modified):
//   x1 - Used to hold the address of `mm_errno`
set_mm_errno:
    ldr x1, =mm_errno
    str w0, [x1]
    ret
