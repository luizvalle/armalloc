# Makefile for the unit tests

CC = aarch64-linux-gnu-gcc
CFLAGS = -Wall -O0 -g
SRCDIR = ../src
LIB = $(SRCDIR)/libmem.a

MEM_TEST_C = mem_test.c
MEM_TEST_HEADERS = ../src/mem.h ../src/mm_errno.h
MEM_TEST = mem_test

.PHONY: all clean run_tests

all: clean $(MEM_TEST)

$(MEM_TEST): $(MEM_TEST_C) $(MEM_TEST_HEADERS) $(LIB)
	$(CC) $(CFLAGS) -I$(SRCDIR) -o $@ $(MEM_TEST_C) $(LIB) -lcriterion

run_tests: $(MEM_TEST)
	./$(MEM_TEST)

clean:
	rm -f $(MEM_TEST)
