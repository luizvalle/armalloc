// Tests the functions from src/mem.s

#include <criterion/criterion.h>
#include <criterion/parameterized.h>
#include <stddef.h>
#include <stdio.h>
#include <unistd.h>
#include "mem.h"

// Helper to cast pointers to byte offsets
#define PTR_DIFF(a, b) ((ptrdiff_t)((char *)(a) - (char *)(b)))

// Register mem_deinit() to be called after every function to make sure all
// tests are hermetic.
TestSuite(mem_init, .fini = (void (*)(void))mem_deinit);

ParameterizedTestParameters(mem_init, successful_mem_init_param_test) {
    static size_t sizes[] = {
        100,       // Less than a page
        4096 * 1,  // 1 page
        4096 * 4,  // 4 pages
        8192,      // 2 pages (non-multiple input)
        12345      // Arbitrary size
    };
    return cr_make_param_array(size_t, sizes, sizeof(sizes) / sizeof(size_t));
}

// Tests that calling mem_init() with various valid sizes succeeds.
ParameterizedTest(
    const size_t *arena_size, mem_init, successful_mem_init_param_test) {
    const int init_result = mem_init(*arena_size);
    cr_assert_eq(
        init_result, 0, "Expected mem_init() to return 0, but returned %d",
        init_result);

    const void * const init_mem_heap_start = mem_get_mem_heap_start();
    const void * const init_mem_brk = mem_get_mem_brk();
    const void * const init_mem_heap_end = mem_get_mem_heap_end();

    cr_assert_not_null(
        init_mem_heap_start,
        "mem_heap_start should not be NULL after mem_init");

    cr_assert_eq(
        init_mem_heap_start,
        init_mem_brk,
        "mem_brk (%p) should be equal to mem_heap_start (%p) after mem_init()",
        init_mem_brk,
        init_mem_heap_start);

    cr_assert_gt(init_mem_heap_end, init_mem_heap_start,
              "mem_heap_end (%p) should be greater than mem_heap_start (%p) "
              "after mem_init()",
              init_mem_heap_end, init_mem_heap_start);

    const ptrdiff_t actual_size = PTR_DIFF(
        init_mem_heap_end, init_mem_heap_start);
    cr_assert(actual_size >= (ptrdiff_t)*arena_size,
              "Allocated size (%td) should be at least %zu bytes",
              actual_size, *arena_size);

    const int deinit_result = mem_deinit();
    cr_assert_eq(
        deinit_result, 0, "Expected mem_dinit() to return 0, but returned %d",
        deinit_result);

    const void * const deinit_mem_heap_start = mem_get_mem_heap_start();
    const void * const deinit_mem_brk = mem_get_mem_brk();
    const void * const deinit_mem_heap_end = mem_get_mem_heap_end();

    cr_assert_null(
        deinit_mem_heap_start,
        "mem_heap_start (%p) should be NULL after mem_deinit()",
        deinit_mem_heap_start);

    cr_assert_null(
        deinit_mem_brk,
        "mem_brk (%p) should be NULL after mem_deinit()",
        deinit_mem_brk);

    cr_assert_null(
        deinit_mem_heap_end,
        "mem_heap_end (%p) should be NULL after mem_deinit()",
        deinit_mem_heap_end);
}

ParameterizedTestParameters(mem_init, invalid_mem_init_param_test) {
    static size_t sizes[] = {
        -4096,
        -1,
        0,
    };
    return cr_make_param_array(size_t, sizes, sizeof(sizes) / sizeof(size_t));
}

// Tests that calling mem_init() with various invalid sizes fails.
ParameterizedTest(
    const size_t *arena_size, mem_init, invalid_mem_init_param_test) {
    // Create a pipe to capture the stderr of the function.
    int pipefd[2];
    cr_assert(pipe(pipefd) == 0, "Failed to create pipe");

    // Save original stderr
    const int saved_stderr = dup(STDERR_FILENO);
    cr_assert(saved_stderr != -1, "Failed to duplicate stderr");

    // Redirect stderr to pipe
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[1]);

    const int init_result = mem_init(*arena_size);

    // Retrieve the error message
    char buffer[256] = {0};
    const ssize_t count = read(pipefd[0], buffer, sizeof(buffer) - 1);

    // Restore stderr
    dup2(saved_stderr, STDERR_FILENO);
    close(saved_stderr);
    close(pipefd[0]);

    cr_assert_lt(
        init_result, 0,
        "Expected mem_init() to return a negative number (error), but "
        "returned %d",
        init_result);

    cr_assert(count > 0, "Expected error message to be printed to stderr");
    cr_assert(
        strstr(buffer, "arena size must be > 0") != NULL,
        "Expected error message to contain 'arena size must be > 0'");

    const void * const init_mem_heap_start = mem_get_mem_heap_start();
    const void * const init_mem_brk = mem_get_mem_brk();
    const void * const init_mem_heap_end = mem_get_mem_heap_end();

    cr_assert_null(
        init_mem_heap_start,
        "mem_heap_start (%p) should be NULL after mem_init()",
        init_mem_heap_start);

    cr_assert_null(
        init_mem_brk,
        "mem_brk (%p) should be NULL after mem_init()",
        init_mem_brk);

    cr_assert_null(
        init_mem_heap_end,
        "mem_heap_end (%p) should be NULL after mem_init()",
        init_mem_heap_end);
}

// mem_deinit() is also used in the mem_init() tests to make sure the tests are
// hermetic. Those tests check if mem_deinit() works on successful uses of
// mem_init(). Hence, we do not test success here.
TestSuite(mem_deinit_special_cases);

// Tests that calling mem_deinit() without first calling mem_init() has no
// effect.
Test(mem_deinit_special_cases, mem_init_not_called) {
    const int result = mem_deinit();

    cr_assert_eq(
        result, 0,
        "Expected mem_deinit() to return 0, but returned %d",
        result);
}
