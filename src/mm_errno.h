// Defines the utilities needed to interact with errno from C

#ifndef __MM_ERRNO_H__
#define __MM_ERRNO_H__

// No error occurred; operation was successful.
#define MM_ERR_NONE         0

// Memory allocation failed due to insufficient space (e.g., sbrk failure).
#define MM_ERR_NOMEM        1

// An invalid argument was passed to a memory routine (e.g., malloc(0)).
#define MM_ERR_INVAL        2

// Memory alignment error (e.g., #defineest for misaligned block).
#define MM_ERR_ALIGN        3

// Heap corruption detected (e.g., buffer overrun, double free).
#define MM_ERR_CORRUPT      4

// Internal allocator error (e.g., unexpected state or unimplemented case).
#define MM_ERR_INTERNAL     5

#ifdef __cplusplus
extern "C" {
#endif

// Retrieves the value of mm_errno
int get_mm_errno(void);

// Sets the value of mm_errno
void set_mm_errno(int val);

#ifdef __cplusplus
}
#endif

#endif  // __MM_ERRNO_H__
