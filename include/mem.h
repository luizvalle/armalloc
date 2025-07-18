// Defines the C function stubs for the functions in mem.s

#ifndef __MEM_H__
#define __MEM_H__

#include <stddef.h>
#include <stdint.h>

#define MEM_SBRK_FAILED ((void *)-1)

#ifdef __cplusplus
extern "C" {
#endif

// Initializes the heap memory arena.
// Returns 0 on success, or -1 on failure.
int mem_init(size_t size);

// Adjusts the program break by `increment` bytes.
// Returns the previous break address on success, or MEM_SBRK_FAILED on failure.
void *mem_sbrk(intptr_t increment);

// Releases the heap memory arena.
// Returns 0 on success, or -1 on failure.
int mem_deinit(void);

// Returns the start address of the heap memory region.
const void *get_mem_heap_start(void);

// Returns the current program break (end of allocated heap).
const void *get_mem_brk(void);

// Returns the end address (limit) of the heap memory region.
const void *get_mem_heap_end(void);

#ifdef __cplusplus
}
#endif

#endif // __MEM_H__
