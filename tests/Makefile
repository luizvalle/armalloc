# Makefile for the unit tests

CC = aarch64-linux-gnu-gcc
CFLAGS = -Wall -O0 -g
SRCDIR = ../src
LIB = $(SRCDIR)/libmem.a

TEST_C = test_mem.c
TEST_MEM = test_mem

.PHONY: all clean run_tests

all: run_tests

$(TEST_MEM): $(TEST_C) $(LIB)
	$(CC) $(CFLAGS) -I$(SRCDIR) -o $@ $(TEST_C) $(LIB) -lcriterion

run_tests: $(TEST_MEM)
	./$(TEST_MEM)

clean:
	rm -f $(TEST_MEM)
