# Makefile for building the static library `libarmalloc64.a`
#
# Usage:
#   make BUILD=debug all        - Build in debug mode (with symbols, no optimization)
#   make BUILD=release all      - Build in release mode (optimized, no debug symbols)
#   make BUILD=debug clean      - Remove debug build artifacts
#   make BUILD=release clean    - Remove release build artifacts
#
# Shortcuts:
#   make debug                  - Equivalent to: make BUILD=debug all
#   make release                - Equivalent to: make BUILD=release all
#
# Produces:
#   ../build/debug/libarmalloc64.a or ../build/release/libarmalloc64.a

include ../config.mk

SRC_S = mm.s mem.s mm_errno.s
OBJ = $(SRC_S:.s=.o)
OBJ := $(addprefix $(BUILDDIR)/, $(notdir $(OBJ)))
LIB = $(BUILDDIR)/libarmalloc64.a

.PHONY: all clean debug release

all: clean $(LIB)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/%.o: %.s | $(BUILDDIR)
	$(AS) $(ASFLAGS) -o $@ $<

$(LIB): $(OBJ)
	$(AR) rcs $@ $^

clean:
	rm -f $(OBJ) $(LIB)

debug:
	$(MAKE) BUILD=debug all

release:
	$(MAKE) BUILD=release all