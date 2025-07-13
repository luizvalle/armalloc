// Defines C function stubs for the functions in mm.s

#ifndef __MM_H__
#define __MM_H__

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void mm_init(void);
void mm_deinit(void);
void *mm_malloc(size_t size);
void mm_free(void *ptr);

#ifdef __cplusplus
}
#endif
#endif
