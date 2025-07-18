# Makefile for building and running unit tests
#
# Usage:
#   make BUILD=debug all        	- Build tests in debug mode
#   make BUILD=release all      	- Build tests in release mode
#   make BUILD=debug run_tests  	- Build and run tests in debug mode
#   make BUILD=release run_tests	- Build and run tests in release mode
#   make BUILD=debug clean      	- Clean debug build artifacts
#   make BUILD=release clean    	- Clean release build artifacts
#
# Produces:
#   ../build/debug/mem_test or ../build/release/mem_test

include ../config.mk

SRC_C = mem_test.c
OBJ = $(SRC_C:.c=.o)
OBJ := $(addprefix $(BUILDDIR)/, $(notdir $(OBJ)))
MEM_TEST = $(BUILDDIR)/mem_test

.PHONY: all debug release test clean

all: clean $(MEM_TEST)

$(BUILDDIR)/%.o: %.c
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) -MMD -MP -c $< -o $@

$(MEM_TEST): $(OBJ)
	@mkdir -p $(BUILDDIR)
	$(CC) $(CFLAGS) -o $@ $^ -L$(BUILDDIR) -larmalloc64 -lcriterion

test: $(MEM_TEST)
	$(MEM_TEST)

clean:
	rm -f $(OBJ) $(MEM_TEST) $(OBJ:.o=.d)

debug:
	$(MAKE) BUILD=debug all

release:
	$(MAKE) BUILD=release all

-include $(OBJ:.o=.d)