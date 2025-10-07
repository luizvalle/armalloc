// Tests the functions from src/mm.s

#include <criterion/criterion.h>
#include <criterion/parameterized.h>
#include <stddef.h>
#include <stdio.h>
#include <unistd.h>
#include "mm.h"
#include "mm_errno.h"


TestSuite(mm_init);


typedef struct {
    size_t arena_size;
    int expected_ret_value;
    int expected_mm_errno;
} mm_init_arena_size_return_code_test_case_t;


ParameterizedTestParameters(
    mm_init,
    parameterized_arena_size_return_code_test) {
    static mm_init_arena_size_return_code_test_case_t init_cases[] = {
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
        sizeof(init_cases) / sizeof(mm_init_arena_size_return_code_test_case_t);
    return cr_make_param_array(
        mm_init_arena_size_return_code_test_case_t, init_cases, num_cases);
}


// Tests that calling mem_init() with various sizes returns the expected codes
ParameterizedTest(
    const mm_init_arena_size_return_code_test_case_t *tc,
    mm_init, parameterized_arena_size_return_code_test) {
}

