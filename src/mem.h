// Defines the C function stubs for the functions in mem.s

#ifndef __MEM_H__
#define __MEM_H__

#include <stddef.h>


#ifdef __cplusplus
extern "C" {
#endif

int mem_init(size_t size);
int mem_deinit();

const void * const mem_get_mem_heap_start();
const void * const mem_get_mem_brk();
const void * const mem_get_mem_heap_end();

#ifdef __cplusplus
}
#endif
#endif
