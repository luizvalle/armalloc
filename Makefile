# Root Makefile for building and managing the entire project
#
# Usage:
#   make all         - Build all components (default build mode)
#   make debug       - Build all components in debug mode (with debug symbols)
#   make release     - Build all components in release mode (optimized)
#   make clean       - Clean build artifacts from all subdirectories
#   make test        - Build and run all unit tests
#
# You can specify the build mode explicitly by setting BUILD:
#   make BUILD=debug all
#   make BUILD=release test
#
# Project structure:
#   src/     - Main source code (static library or binaries)
#   tests/   - Unit tests

.PHONY: all clean debug release test

SUBDIRS := src tests

all:
	@for dir in $(SUBDIRS); do $(MAKE) -C $$dir all; done

debug:
	@for dir in $(SUBDIRS); do $(MAKE) -C $$dir debug; done

release:
	@for dir in $(SUBDIRS); do $(MAKE) -C $$dir release; done

clean:
	@for dir in $(SUBDIRS); do $(MAKE) -C $$dir clean; done

test:
	$(MAKE) -C tests test