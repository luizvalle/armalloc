# TODO

Ordered by dependency — each step builds on the previous ones.

- [ ] **1. Fill in `mm_test` assertions for `mm_init`**
  - The parameterized test cases already exist in `tests/mm_test.c` but the test body is empty.
  - Add assertions for return value and `mm_errno`, following the pattern in `mem_test.c`.
  - Call `mm_deinit` after successful init. Verify existing code works before building on it.

- [ ] **2. Implement `mm_malloc`** in `src/mm.s`
  - Reject size 0 (set `MM_ERR_INVAL`, return NULL).
  - Calculate adjusted block size: `max(requested + DWORD_SIZE_BYTES, 32)`, aligned to `DWORD_SIZE_BYTES`.
  - Search segregated free lists starting from `_get_seglist_index(adjusted_size)` upward.
  - Within each list, walk from the sentinel's `fnext` looking for a block with `size >= adjusted_size`.
  - If found: remove from free list, optionally split if remainder >= 32 bytes (set up the split block's header/footer and add it to the free list), mark as allocated, return payload pointer.
  - If no fit in any list: call `_extend_heap` with `max(adjusted_size, PAGE_SIZE_BYTES) / WORD_SIZE_BYTES` words, then allocate from the new block.

- [ ] **3. Implement `mm_free`** in `src/mm.s`
  - Return immediately if `ptr` is NULL.
  - Clear the allocated bit in the block's header and footer.
  - Call `_coalesce` (which handles adding to the free list).

- [ ] **4. Write tests for `mm_malloc`** in `tests/mm_test.c`
  - Single allocation and verify the returned pointer is non-NULL and within the arena.
  - Multiple allocations of different sizes (hitting different size classes).
  - Allocate until the arena must extend, verify it still succeeds.
  - Allocate size 0, verify it returns NULL with `MM_ERR_INVAL`.

- [ ] **5. Write tests for `mm_free`** in `tests/mm_test.c`
  - Allocate then free, verify no crash.
  - Allocate, free, allocate again — verify the second allocation reuses freed space (returned pointer should match or be within the original block's range).
  - Free NULL — verify it's a no-op (no crash, no error).

- [ ] **6. Write tests for malloc/free interaction** in `tests/mm_test.c`
  - Allocate multiple blocks, free them in different orders (LIFO, FIFO, random), reallocate and verify.
  - Fragment the heap: allocate A, B, C, free B, allocate D (smaller than B) — verify D reuses B's space.
  - Coalescing: allocate A, B, C, free A and C, free B — verify the three blocks coalesce into one.
  - Stress test: many small allocations followed by freeing all, then one large allocation that should fit in the coalesced space.
