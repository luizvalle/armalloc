#include "mm.h"

int main(int argc, char **argv) {
    mm_init();
    mm_deinit();
    mm_malloc(0);
    mm_free(NULL);
    return 0;
}
