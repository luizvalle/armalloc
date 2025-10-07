# Makefile for building and running unit tests
#
# Usage examples:
#   make BUILD=debug all         # Build all tests (debug mode)
#   make BUILD=release test      # Build and run all tests (release mode)
#   make BUILD=debug mem_test    # Build only mem_test
#   make BUILD=debug mm_test     # Build only mm_test
#   make BUILD=debug clean       # Clean debug build artifacts
#
# Produces:
#   ../build/<mode>/mem_test
#   ../build/<mode>/mm_test

include ../config.mk

# List of test source files
TEST_SRCS := mem_test.c mm_test.c
TEST_BINS := $(patsubst %.c,$(BUILDDIR)/%,$(TEST_SRCS))
TEST_OBJS := $(patsubst %.c,$(BUILDDIR)/%.o,$(TEST_SRCS))

# Libraries to link
LDLIBS := -L$(BUILDDIR) -larmalloc64 -lcriterion

.PHONY: all clean debug release test $(notdir $(TEST_BINS))

# Default: build everything
all: $(TEST_BINS)

# Build individual tests by name (e.g. make mem_test)
$(notdir $(TEST_BINS)): %: $(BUILDDIR)/%
	@echo "Built $@ in $(BUILD) mode"

# Compile each test object
$(BUILDDIR)/%.o: %.c
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) -MMD -MP -c $< -o $@

# Link each test binary
$(BUILDDIR)/%: $(BUILDDIR)/%.o
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

# Run all tests
test: $(TEST_BINS)
	@for testbin in $(TEST_BINS); do \
		echo "Running $$testbin..."; \
		$$testbin || exit $$?; \
	done

# Clean build artifacts
clean:
	rm -f $(TEST_OBJS) $(TEST_BINS) $(TEST_OBJS:.o=.d)

# Convenience targets
debug:
	$(MAKE) BUILD=debug all

release:
	$(MAKE) BUILD=release all

# Include dependency files if they exist
-include $(TEST_OBJS:.o=.d)
