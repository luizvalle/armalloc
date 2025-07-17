// Tests the functions from src/mem.s

#include <criterion/criterion.h>
#include <criterion/parameterized.h>
#include <stddef.h>
#include <stdio.h>
#include <unistd.h>
#include "mem.h"
#include "mm_errno.h"

// Helper to cast pointers to byte offsets
#define PTR_DIFF(a, b) ((ptrdiff_t)((char *)(a) - (char *)(b)))
// Adds an offset to a pointer
#define PTR_ADD(ptr, offset) ((void *)((char *)(ptr) + (offset)))

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

    const void * init_mem_heap_start = get_mem_heap_start();
    const void * init_mem_brk = get_mem_brk();
    const void * init_mem_heap_end = get_mem_heap_end();

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

    const void * deinit_mem_heap_start = get_mem_heap_start();
    const void * deinit_mem_brk = get_mem_brk();
    const void * deinit_mem_heap_end = get_mem_heap_end();

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

    const void *init_mem_heap_start = get_mem_heap_start();
    const void *init_mem_brk = get_mem_brk();
    const void *init_mem_heap_end = get_mem_heap_end();

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

TestSuite(mem_sbrk, .fini = (void (*) (void))mem_deinit);

#define MAX_NUM_SBRK_INCREMENTS 10

typedef struct {
    size_t arena_size;  // Should be > 0
    size_t num_increments;  // Should be <= MAX_NUM_SBRK_INCREMENTS
    intptr_t increments[MAX_NUM_SBRK_INCREMENTS];
} mem_sbrk_test_case_t;

ParameterizedTestParameters(mem_sbrk, mem_sbrk_param_test) {
    static mem_sbrk_test_case_t sbrk_cases[] = {
        {
            .arena_size = 4096,
            .num_increments = 1,
            .increments = {0},  // Just query brk once
        },
        {
            .arena_size = 4096,
            .num_increments = 3,
            .increments = {1024, 1024, 0},  // Allocate two 1KB blocks
        },
        {
            .arena_size = 4096,
            .num_increments = 4,
            // Allocate 2x 2KB + 1 byte (secomd to last should fail)
            .increments = {2048, 2048, 1, 0},
        },
        {
            .arena_size = 8192,
            .num_increments = 2,
            // Negative increment on fresh heap (should fail)
            .increments = {-4096, 0},  
        },
        {
            .arena_size = 4096,
            .num_increments = 3,
            // Allocate full arena then shrink it back
            .increments = {4096, -4096, 0},
        },
    };
    const size_t num_cases = sizeof(sbrk_cases) / sizeof(mem_sbrk_test_case_t);
    return cr_make_param_array(mem_sbrk_test_case_t, sbrk_cases, num_cases);
}

// Tests that different allocation patterns behave as expected
ParameterizedTest(mem_sbrk_test_case_t *tc, mem_sbrk, mem_sbrk_param_test) {
    // Initialize the memory arena
    const size_t arena_size = tc->arena_size;
    cr_assert_eq(
        mem_init(arena_size), 0,
        "mem_init() failed with arena of size %zu", arena_size);

    const void *heap_start = get_mem_heap_start();
    const void *heap_end = get_mem_heap_end();

    cr_assert_not_null(heap_start, "get_mem_heap_start() returned NULL");
    cr_assert_not_null(heap_end, "get_mem_heap_end() returned NULL");

    for (size_t i = 0; i < tc->num_increments; i++) {
        const intptr_t incr = tc->increments[i];

        set_mm_errno(MM_ERR_NONE);  // Reset mm_errno before calling mem_sbrk()

        const void *prev_brk = get_mem_brk();
        const void *result = mem_sbrk(incr);
        const void *new_brk = get_mem_brk();

        const int mm_errno = get_mm_errno();

        if (PTR_ADD(prev_brk, incr) < heap_start) {
            // Underflow error
            cr_assert_eq(
                result, MEM_SBRK_FAILED,
                "mem_sbrk(%ld) should have failed but it returned %p",
                incr, result);
            cr_assert_eq(
                mm_errno, MM_ERR_INVAL,
                "Expected mm_errno to be set to MM_ERR_INVAL (%d) but was %d",
                mm_errno, MM_ERR_INVAL);
            cr_assert_eq(
                new_brk, prev_brk,
                "Expected the program break to not change but changed "
                "from %p to %p", prev_brk, new_brk);
        } else if (PTR_ADD(prev_brk, incr) >= heap_end) {
            // Overflow error
            cr_assert_eq(
                result, MEM_SBRK_FAILED,
                "mem_sbrk(%ld) should have failed but it returned %p",
                incr, result);
            cr_assert_eq(
                mm_errno, MM_ERR_NOMEM,
                "Expected mm_errno to be set to MM_ERR_NOMEM (%d) but was %d",
                mm_errno, MM_ERR_NOMEM);
            cr_assert_eq(
                new_brk, prev_brk,
                "Expected the program break to not change but changed "
                "from %p to %p", prev_brk, new_brk);
        } else {
            // Should succeed
            cr_assert_neq(
                result, MEM_SBRK_FAILED,
                "mem_sbrk(%ld) should not have failed but it returned "
                "MEM_SBRK_FAILED",
                incr, result);
            cr_assert_eq(
                result, prev_brk,
                "mem_sbrk(%ld) should return the old break %p, but returned %p",
                incr, prev_brk, result);

            const void *expected_new_brk = PTR_ADD(prev_brk, incr);
            cr_assert_eq(
                new_brk, expected_new_brk,
                "After mem_sbrk(%ld), expected new break %p but got %p",
                incr, expected_new_brk, new_brk);
            cr_assert_eq(
                mm_errno, MM_ERR_NONE,
                "mm_errno should be MM_ERR_NONE (%d) but is %d",
                MM_ERR_NONE, mm_errno);
        }
    }

    // De-initialize the memory arena
    cr_assert_eq(mem_deinit(), 0, "mem_deinit() failed");
}

// Makes sure mem_sbrk() handles an uninitialized heap correctly
Test(mem_sbrk, mem_init_not_called) {
    const intptr_t increments[] = {-1024, 0, 1, 1024, 4096};
    const size_t num_increments = sizeof(increments) / sizeof(intptr_t);

    const void *heap_start = get_mem_heap_start();
    const void *heap_end = get_mem_heap_end();

    // Since mem_init() was never called, heap pointers should be NULL
    cr_assert_null(
        heap_start,
        "get_mem_heap_start() returned %p but expected NULL", heap_start);
    cr_assert_null(
        heap_end,
        "get_mem_heap_end() returned %p but expected NULL", heap_end);

    for (size_t i = 0; i < num_increments; i++) {
        const intptr_t incr = increments[i];

        set_mm_errno(MM_ERR_NONE);  // Reset mm_errno before calling mem_sbrk()

        const void *prev_brk = get_mem_brk();
        const void *result = mem_sbrk(incr);
        const void *new_brk = get_mem_brk();
        const int mm_errno = get_mm_errno();

        cr_assert_eq(
            result, MEM_SBRK_FAILED,
            "mem_sbrk(%ld) should have failed but it returned %p",
             incr, result);
        cr_assert_eq(
            mm_errno, MM_ERR_INTERNAL,
             "Expected mm_errno to be set to MM_ERR_INTERNAL (%d) but was %d",
             mm_errno, MM_ERR_INTERNAL);
        cr_assert_eq(
                new_brk, prev_brk,
                "Expected the program break to not change but changed "
                "from %p to %p", prev_brk, new_brk);
    }
}
