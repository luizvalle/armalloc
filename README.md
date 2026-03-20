# armalloc

A dynamic memory allocator written entirely in AArch64 (ARM64) assembly for Linux. It provides `mm_malloc` and `mm_free` without depending on libc's allocator, using only raw Linux syscalls (`mmap`/`munmap`) to obtain memory from the OS.

The allocator uses a segregated free list design with 8 size classes, boundary tags (header/footer) for coalescing, and first-fit search within each class.

## Project structure

```
include/
  mem.h              C header for the low-level memory arena API
  mm.h               C header for the high-level allocator API (malloc/free)
  mm_errno.h         Error code definitions
src/
  mem.s              Memory arena: mem_init, mem_sbrk, mem_deinit (mmap/munmap)
  mm.s               Allocator: mm_init, mm_deinit, mm_malloc, mm_free
  mm_errno.s         Error code get/set routines
  constants.inc      Shared constants (sizes, syscall flags)
  sys_macros.inc     Syscall wrapper macros (sys_mmap, sys_munmap)
  mm_errno_constants.inc  Error code constants for assembly
  mm_list_traversal_macros.inc  Block/list traversal macros
tests/
  mem_test.c         Tests for the memory arena layer
  mm_test.c          Tests for the allocator layer
```

## API

### High-level allocator (`mm.h`)

| Function | Signature | Description |
|---|---|---|
| `mm_init` | `int mm_init(size_t arena_size)` | Initialize the allocator with an arena of the given size |
| `mm_deinit` | `int mm_deinit(void)` | Release the arena and all allocated memory |
| `mm_malloc` | `void *mm_malloc(size_t size)` | Allocate a block with at least `size` bytes of payload |
| `mm_free` | `void mm_free(void *ptr)` | Free a previously allocated block |

### Low-level arena (`mem.h`)

| Function | Signature | Description |
|---|---|---|
| `mem_init` | `int mem_init(size_t size)` | Create a memory arena via `mmap` |
| `mem_sbrk` | `void *mem_sbrk(intptr_t increment)` | Adjust the program break within the arena |
| `mem_deinit` | `int mem_deinit(void)` | Release the arena via `munmap` |

### Error codes (`mm_errno.h`)

Errors are reported through `get_mm_errno()` / `set_mm_errno()`:

| Code | Name | Meaning |
|---|---|---|
| 0 | `MM_ERR_NONE` | Success |
| 1 | `MM_ERR_NOMEM` | Out of memory |
| 2 | `MM_ERR_INVAL` | Invalid argument |
| 3 | `MM_ERR_ALIGN` | Alignment error |
| 4 | `MM_ERR_CORRUPT` | Heap corruption detected |
| 5 | `MM_ERR_INTERNAL` | Internal allocator error |

## Implementation status

### Implemented

- **Memory arena** (`mem.s`) — `mem_init`, `mem_sbrk`, `mem_deinit` are fully implemented. The arena is backed by a single `mmap` allocation, and `mem_sbrk` simulates the `sbrk` interface within it.
- **Allocator initialization** (`mm.s`) — `mm_init` sets up 8 segregated free lists with prologue/epilogue sentinel blocks and an initial free block.
- **Allocator teardown** (`mm.s`) — `mm_deinit` releases the arena.
- **Internal helpers** (`mm.s`):
  - `_extend_heap` — grows the heap by allocating a new free block and coalescing it with neighbors.
  - `_coalesce` — merges adjacent free blocks (all 4 cases: both allocated, prev free, next free, both free).
  - `_add_to_free_list` / `_remove_from_free_list` — insert/remove blocks from the segregated free lists.
  - `_get_seglist_index` — maps a block size to the correct free list index.

### Not yet implemented

- **`mm_malloc`** — currently a stub (`ret`). Needs to:
  1. Reject invalid sizes (0) and set `mm_errno`.
  2. Round the requested size up to the minimum block size (32 bytes) and align to `DWORD_SIZE_BYTES`.
  3. Search the segregated free lists (starting from the appropriate size class) for a fitting free block.
  4. If found, split the block if the remainder is large enough, remove it from the free list, mark it as allocated, and return the payload pointer.
  5. If no fit is found, call `_extend_heap` and allocate from the new block.

- **`mm_free`** — currently a stub (`ret`). Needs to:
  1. Validate the pointer (non-null, aligned).
  2. Mark the block as free by clearing the allocated bit in the header and footer.
  3. Call `_coalesce` to merge with adjacent free blocks.

- **`mm_test` assertions** — the test file defines parameterized test cases for `mm_init` but the test body is empty. Needs assertions for return values and `mm_errno`, similar to `mem_test`.

- **Tests for `mm_malloc` and `mm_free`** — no test cases exist yet. Should cover:
  - Basic allocate/free cycle
  - Multiple allocations of varying sizes across different size classes
  - Free and reallocate (reuse of freed blocks)
  - Coalescing behavior after free
  - Heap extension when arena is exhausted
  - Edge cases: minimum size allocation, maximum arena allocation, double free detection

## Dependencies

### Cross-compilation toolchain

Install the AArch64 cross-compiler and binutils:
```
sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
```

### Criterion (ARM64)

The test suite uses [Criterion](https://github.com/Snaipe/Criterion). Since this project cross-compiles for AArch64, you need the ARM64 version of the library:
```
sudo dpkg --add-architecture arm64
sudo apt update
sudo apt install libcriterion-dev:arm64
```

### QEMU user-mode (for running on x86_64)

If you are on an x86_64 host, you can run the ARM64 binaries using QEMU user-mode emulation:
```
sudo apt install qemu-user qemu-user-binfmt libc6-arm64-cross
```

The `qemu-user-binfmt` package registers ARM64 ELF binaries with the kernel's binfmt_misc subsystem, allowing you to execute them directly as if they were native binaries.

## Building

```
make            # Build library and tests (debug mode, default)
make debug      # Same as above
make release    # Build in release mode (optimized)
make clean      # Clean build artifacts
```

## Running tests

Tests are written in C using [Criterion](https://github.com/Snaipe/Criterion) and call into the ARM64 assembly library via the C headers in `include/`.

There are two test binaries:

- **`mem_test`** — Tests the low-level memory arena (`mem_init`, `mem_sbrk`, `mem_deinit`). Covers initialization with various arena sizes, error handling (zero size, double init, uninitialized heap), sbrk boundary conditions (overflow, underflow, shrink), and proper cleanup via deinit.
- **`mm_test`** — Tests the high-level allocator (`mm_init`, `mm_deinit`, `mm_malloc`, `mm_free`) which manages segregated free lists on top of the memory arena.

### Running all tests

```
make test
```

On an x86_64 host with `qemu-user-binfmt` installed, `make test` works transparently — the kernel automatically invokes QEMU to run the ARM64 test binaries.

### Running individual tests

To run a single test binary:
```
# With binfmt_misc (transparent):
./build/debug/mem_test

# Or explicitly via QEMU:
qemu-aarch64 -L /usr/aarch64-linux-gnu ./build/debug/mem_test
```

The `-L` flag tells QEMU where to find the ARM64 shared libraries (libc, ld-linux, etc.).

To build only one test:
```
make -C tests mem_test    # or mm_test
```

### Expected output

Criterion produces colored output summarizing each test suite. A successful run looks like:

```
[====] Synthesis: Tested: 13 | Passing: 13 | Failing: 0 | Crashing: 0
```

Each individual test is listed with a pass/fail status:

```
[----] mem_init::parameterized_arena_size_test
[PASS] mem_init::parameterized_arena_size_test (#1)
[PASS] mem_init::parameterized_arena_size_test (#2)
...
[PASS] mem_sbrk::mem_init_not_called
[====] Synthesis: Tested: 13 | Passing: 13 | Failing: 0 | Crashing: 0
```

If a test fails, Criterion prints the assertion message with the expected vs. actual values, e.g.:

```
[FAIL] mem_init::parameterized_arena_size_test (#1):
  Expected mem_init(0) to return -1, but returned 0
```
