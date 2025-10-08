// Defines C function stubs for the functions in mm.s

#ifndef __MM_H__
#define __MM_H__

#include <stddef.h>
#include <stdint.h>

#define NUM_SEG_LISTS 8

#ifdef __cplusplus
extern "C" {
#endif

int mm_init(size_t arena_size);
int mm_deinit(void);
void *mm_malloc(size_t size);
void mm_free(void *ptr);

#ifdef __cplusplus
}
#endif
#endif
