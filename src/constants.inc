// Defines some constants used by the program

.equ INT_SIZE_BYTES,                    4
.equ INT_ALIGN,                         2  // Since log_2(4) = 2
.equ WORD_SIZE_BYTES,                   8
.equ WORD_ALIGN,                        3  // Since log_2(8) = 3
.equ DWORD_SIZE_BYTES,                  WORD_SIZE_BYTES * 2
.equ PTR_SIZE_BYTES,                    WORD_SIZE_BYTES
.equ PTR_ALIGN,                         3  // Since log_2(8) = 3
.equ PAGE_SIZE_BYTES,                   4096
.equ STDIN,                             0
.equ STDOUT,                            1
.equ STDERR,                            2
.equ PROT_READ,                         0x1
.equ PROT_WRITE,                        0x2
.equ MAP_PRIVATE,                       0x2
.equ MAP_ANONYMOUS,                     0x20
.equ MAP_FAILED,                        -1
