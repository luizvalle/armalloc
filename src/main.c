#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

void *mm_init();

int main(void) {
    void *prev_pbrk = sbrk(0);
    printf("Previous program break: 0x%lx\n", (uintptr_t)prev_pbrk);

    void* ret_pbrk = mm_init();
    printf("Returned program break: 0x%lx\n", (uintptr_t)ret_pbrk);

    void *new_pbrk = sbrk(0);
    printf("New program break: 0x%lx\n", (uintptr_t)new_pbrk);

    printf("Difference: 0x%lx\n", new_pbrk - prev_pbrk);
}