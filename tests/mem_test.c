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

TestSuite(mem_init);

typedef struct {
    size_t arena_size;
    int expected_ret_value;
    int expected_mm_errno;
} mem_init_arena_size_test_case_t;

ParameterizedTestParameters(mem_init, parameterized_arena_size_test) {
    static mem_init_arena_size_test_case_t init_cases[] = {
        {
            // Invalid size (0)
            .arena_size = 0,
            .expected_ret_value = -1,
            .expected_mm_errno = MM_ERR_INVAL,
        },
        {
            // Less than a page
            .arena_size = 10,
            .expected_ret_value = 0,
            .expected_mm_errno = MM_ERR_NONE,
        },
        {
            // A full page
            .arena_size = 4096,
            .expected_ret_value = 0,
            .expected_mm_errno = MM_ERR_NONE,
        },
        {
            // 4 pages
            .arena_size = 4096 * 4,
            .expected_ret_value = 0,
            .expected_mm_errno = MM_ERR_NONE,
        },
        {
            // A large random number
            .arena_size = 12345,
            .expected_ret_value = 0,
            .expected_mm_errno = MM_ERR_NONE,
        },
    };
    const size_t num_cases =
        sizeof(init_cases) / sizeof(mem_init_arena_size_test_case_t);
    return cr_make_param_array(
        mem_init_arena_size_test_case_t, init_cases, num_cases);
}

// Tests that calling mem_init() with various sizes has the expected results
ParameterizedTest(
    const mem_init_arena_size_test_case_t *tc,
    mem_init, parameterized_arena_size_test) {
    set_mm_errno(MM_ERR_NONE);  // Reset mm_errno

    const int init_result = mem_init(tc->arena_size);

    cr_assert_eq(
        init_result, tc->expected_ret_value,
        "Expected mem_init(%zu) to return %d, but returned %d",
        tc->arena_size, tc->expected_ret_value, init_result);
    
    const int init_mm_errno = get_mm_errno();

    cr_assert_eq(
        init_mm_errno, tc->expected_mm_errno,
        "Expected mem_init(%zu) to set mm_errno to %d but it is set to %d",
        tc->arena_size, tc->expected_mm_errno, init_mm_errno);

    const void *init_mem_heap_start = _get_mem_heap_start();
    const void *init_mem_brk = _get_mem_brk();
    const void *init_mem_heap_end = _get_mem_heap_end();

    if (tc->expected_ret_value == 0) {
        // Expected success
        cr_assert_not_null(
            init_mem_heap_start,
            "Expected mem_init(%zu) to set mem_heap_start to a non-NULL value",
            tc->arena_size);
            
        cr_assert_eq(
            init_mem_heap_start, init_mem_brk,
            "Expected mem_init(%zu) to set heap_start (%p) = brk (%p)",
            tc->arena_size,
            init_mem_heap_start,
            init_mem_brk);
        
        cr_assert_gt(init_mem_heap_end, init_mem_heap_start,
            "Expected mem_init(%zu) to set heap_end (%p) > heap_start (%p)",
            tc->arena_size, init_mem_heap_end, init_mem_heap_start); 

        const ptrdiff_t actual_size = PTR_DIFF(
            init_mem_heap_end, init_mem_heap_start);
        cr_assert(actual_size >= (ptrdiff_t)tc->arena_size,
                "Expected mem_init(%zu) to allocate at least %zu bytes, but "
                "allocated only %td bytes",
                tc->arena_size, tc->arena_size, actual_size);

        set_mm_errno(MM_ERR_NONE);

        const int deinit_result = mem_deinit();
        const int deinit_mm_errno = get_mm_errno();

        cr_assert_eq(
            deinit_result, 0,
            "Expected mem_deinit() to return 0, but returned %d",
            deinit_result);
    
        cr_assert_eq(
            deinit_mm_errno, MM_ERR_NONE,
            "Expected mem_deinit() to leave mm_errno as MM_ERR_NONE but got %d",
            deinit_mm_errno);

        const void *deinit_mem_heap_start = _get_mem_heap_start();
        const void *deinit_mem_brk = _get_mem_brk();
        const void *deinit_mem_heap_end = _get_mem_heap_end();

        cr_assert_null(
            deinit_mem_heap_start,
            "Expected mem_deinit() to set mem_heap_start (%p) to NULL",
            deinit_mem_heap_start);

        cr_assert_null(
            deinit_mem_brk,
            "Expected mem_deinit() to set mem_brk (%p) to NULL",
            deinit_mem_brk);
    
        cr_assert_null(
            deinit_mem_heap_end,
            "Expected mem_deinit() to set mem_heap_end (%p) to NULL",
            deinit_mem_heap_end);
    } else {
        // Expected failure
        cr_assert_null(
            init_mem_heap_start,
            "Expected mem_init(%zu) to leave mem_heap_start (%p) NULL",
            tc->arena_size, init_mem_heap_start);

        cr_assert_null(
            init_mem_brk,
            "Expected mem_init(%zu) to leave mem_brk (%p) NULL",
            tc->arena_size, init_mem_brk);
        
        cr_assert_null(
            init_mem_heap_end,
            "Expected mem_init(%zu) to leave mem_heap_end (%p) NULL",
            tc->arena_size, init_mem_heap_end);
    }
}

// Tests that calling mem_init twice fails as expected
Test(mem_init, mem_init_called_twice_fail) {
    const size_t arena_size = 4096;
    const int first_init_ret = mem_init(arena_size);

    cr_assert_eq(
        first_init_ret, 0,
        "Expected the first mem_init(%zu) to succeed, but it failed");
    
    set_mm_errno(MM_ERR_NONE);

    const int second_init_ret = mem_init(arena_size);

    cr_assert_eq(
        second_init_ret, -1,
        "Expected the second mem_init(%zu) to fail by returning -1, but it "
        "returned %d",
        arena_size, second_init_ret);
    
    const int mm_errno = get_mm_errno();

    cr_assert_eq(
        mm_errno, MM_ERR_INTERNAL,
        "Expected the second mem_init(%zu) to set mm_errno to "
        "MM_ERR_INTERNAL but it was set to %d",
        arena_size, mm_errno);

    mem_deinit();
}

// Tests that calling mem_init a second time after a failed first attempt
// succeeds.
Test(mem_init, mem_init_recover_after_failed_init) {
    const int first_init_ret = mem_init(0);

    cr_assert_eq(
        first_init_ret, -1,
        "Expected the first mem_init(0) to fail, but it succeeded");
    
    set_mm_errno(MM_ERR_NONE);

    const size_t arena_size = 4096;

    const int second_init_ret = mem_init(arena_size);
    const int mm_errno = get_mm_errno();

    cr_assert_eq(
        second_init_ret, 0,
        "Expected the second mem_init(%zu) to succeed but it failed with "
        "mm_errno set to %d",
        arena_size, mm_errno);

    mem_deinit();
}

// Tests that calling mem_init a second time after mem_deinit succeeds
Test(mem_init, mem_init_recover_after_deinit) {
    const size_t arena_size = 4096;
    const int first_init_ret = mem_init(arena_size);

    cr_assert_eq(
        first_init_ret, 0,
        "Expected the first mem_init(%zu) to succeed, but it failed");

    cr_assert_eq(mem_deinit(), 0, "Expected mem_deinit() to succeed");
    
    set_mm_errno(MM_ERR_NONE);

    const int second_init_ret = mem_init(arena_size);

    cr_assert_eq(
        second_init_ret, 0,
        "Expected the second mem_init(%zu) to succeed but it failed",
        arena_size);
    
    const int mm_errno = get_mm_errno();

    cr_assert_eq(
        mm_errno, MM_ERR_NONE,
        "Expected the second mem_init(%zu) to set mm_errno to "
        "MM_ERR_NONE but it was set to %d",
        arena_size, mm_errno);

    mem_deinit();
}

TestSuite(mem_deinit);

// Tests that mem_deinit() works as expected after a successful mem_init()
Test(mem_deinit, successful_after_successful_mem_init) {
    const size_t arena_size = 4096;
    cr_assert_eq(
        mem_init(arena_size), 0,
        "Expected mem_init(%zu) to succeed but it failed",
        arena_size);
        
    set_mm_errno(MM_ERR_NONE);

    const int deinit_result = mem_deinit();
    const int deinit_mm_errno = get_mm_errno();

    cr_assert_eq(
        deinit_result, 0,
        "Expected mem_deinit() to return 0, but returned %d",
        deinit_result);

    cr_assert_eq(
        deinit_mm_errno, MM_ERR_NONE,
        "Expected mem_deinit() to leave mm_errno as MM_ERR_NONE but got %d",
        deinit_mm_errno);

    const void *deinit_mem_heap_start = _get_mem_heap_start();
    const void *deinit_mem_brk = _get_mem_brk();
    const void *deinit_mem_heap_end = _get_mem_heap_end();

    cr_assert_null(
        deinit_mem_heap_start,
        "Expected mem_deinit() to set mem_heap_start (%p) to NULL",
        deinit_mem_heap_start);

    cr_assert_null(
        deinit_mem_brk,
        "Expected mem_deinit() to set mem_brk (%p) to NULL",
        deinit_mem_brk);

    cr_assert_null(
        deinit_mem_heap_end,
        "Expected mem_deinit() to set mem_heap_end (%p) to NULL",
        deinit_mem_heap_end);
}

// Tests that mem_deinit() is safe to call even if mem_init() was never called
Test(mem_deinit, mem_deinit_succeeds_after_no_mem_init) {
    const void *mem_heap_start = _get_mem_heap_start();
    const void *mem_brk = _get_mem_brk();
    const void *mem_heap_end = _get_mem_heap_end();

    cr_assert_null(
        mem_heap_start,
        "Expected mem_heap_start (%p) to be NULL",
        mem_heap_start);

    cr_assert_null(
        mem_brk,
        "Expected mem_brk (%p) to be NULL",
        mem_brk);

    cr_assert_null(
        mem_heap_end,
        "Expected mem_heap_end (%p) to be NULL",
        mem_heap_end);

    set_mm_errno(MM_ERR_NONE);

    const int deinit_result = mem_deinit();
    const int deinit_mm_errno = get_mm_errno();

    cr_assert_eq(
        deinit_result, 0,
        "Expected mem_deinit() to return 0, but returned %d",
        deinit_result);

    cr_assert_eq(
        deinit_mm_errno, MM_ERR_NONE,
        "Expected mem_deinit() to leave mm_errno as MM_ERR_NONE but got %d",
        deinit_mm_errno);

    const void *deinit_mem_heap_start = _get_mem_heap_start();
    const void *deinit_mem_brk = _get_mem_brk();
    const void *deinit_mem_heap_end = _get_mem_heap_end();

    cr_assert_null(
        deinit_mem_heap_start,
        "Expected mem_deinit() to set mem_heap_start (%p) to NULL",
        deinit_mem_heap_start);

    cr_assert_null(
        deinit_mem_brk,
        "Expected mem_deinit() to set mem_brk (%p) to NULL",
        deinit_mem_brk);

    cr_assert_null(
        deinit_mem_heap_end,
        "Expected mem_deinit() to set mem_heap_end (%p) to NULL",
        deinit_mem_heap_end);
}

TestSuite(mem_sbrk);

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

    const void *heap_start = _get_mem_heap_start();
    const void *heap_end = _get_mem_heap_end();

    cr_assert_not_null(heap_start, "get_mem_heap_start() returned NULL");
    cr_assert_not_null(heap_end, "get_mem_heap_end() returned NULL");

    for (size_t i = 0; i < tc->num_increments; i++) {
        const intptr_t incr = tc->increments[i];

        set_mm_errno(MM_ERR_NONE);  // Reset mm_errno before calling mem_sbrk()

        const void *prev_brk = _get_mem_brk();
        const void *result = mem_sbrk(incr);
        const void *new_brk = _get_mem_brk();

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

    const void *heap_start = _get_mem_heap_start();
    const void *heap_end = _get_mem_heap_end();

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

        const void *prev_brk = _get_mem_brk();
        const void *result = mem_sbrk(incr);
        const void *new_brk = _get_mem_brk();
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
