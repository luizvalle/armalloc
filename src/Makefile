CC = aarch64-linux-gnu-gcc
AS = aarch64-linux-gnu-as
LD = aarch64-linux-gnu-ld
CFLAGS = -Wall -O0
LDFLAGS =

# Files
OBJS = mm_test.o mm.o
TARGET = mm_test

# Build rules
.PHONY: all
all: $(TARGET)

mm_test.o: mm_test.c mm.h
	$(CC) $(CFLAGS) -c mm_test.c -o mm_test.o

%.o: %.s
	$(AS) $< -o $@

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS)

.PHONY: clean
clean:
	rm -f *.o $(TARGET)
