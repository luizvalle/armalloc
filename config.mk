# Shared Makefile config
#
# Imported by the other Makefiles

# Default build mode is debug
BUILD ?= debug

# Directories
BUILDDIR = ../build/$(BUILD)
SRCDIR = ../src
INCLUDEDIR = ../include

# Compiler tools
CC = aarch64-linux-gnu-gcc
AS = aarch64-linux-gnu-as
AR = aarch64-linux-gnu-ar

# Flags per mode
CFLAGS_debug = -Wall -O0 -g -I$(INCLUDEDIR) -MMD -MP
CFLAGS_release = -Wall -O2 -DNDEBUG -I$(INCLUDEDIR)
ASFLAGS_debug = -g
ASFLAGS_release =

# Select flags based on BUILD
CFLAGS = $(CFLAGS_$(BUILD))
ASFLAGS = $(ASFLAGS_$(BUILD))