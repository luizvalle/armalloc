# Makefile for the main source code
#
# Creates a library, `libmem.a`, that can be statically linked with any program

AS = aarch64-linux-gnu-as
AR = aarch64-linux-gnu-ar

SRC_S = mm.s mem.s
OBJ = $(SRC_S:.s=.o)
LIB = libmem.a

.PHONY: all clean

all: clean $(LIB)

%.o: %.s
	$(AS) -g -o $@ $<

$(LIB): $(OBJ)
	$(AR) rcs $@ $^

clean:
	rm -f $(OBJ) $(LIB)
