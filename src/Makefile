AS = as
AR = ar
CFLAGS = -g
LIBNAME = libmm.a

test: main.c $(LIBNAME)
	gcc main.c $(CFLAGS) -L. -lmm -o test

$(LIBNAME): mm.o
	$(AR) rcs $(LIBNAME) mm.o

mm.o: mm.s linux_syscalls.s
	$(AS) $(CLFAGS) mm.s -o mm.o

.PHONY: clean
clean:
	rm -f *.o $(LIBNAME) test

.PHONY: all
all: clean $(LIBNAME) test
