# -march=rv32i -mabi=ilp32
#
# The architecture is flexible, on top of the basic RV32i
#   c for compressed 16-bit instructions
#   m adds integer multiply/divide
#   a adds atomic instructions
#   f,d adds single or double precision floating point
#
# The ABI can be changed too:
#
# You can add an 'f' to ilp32 so you have additional floating point support in the ABI

# -ffreestanding
#   Indicates the code is bare-metal (not hosted), so
#   it doesn't have argc/argv in main()
#   it doesn't do optimizations such as transforming for loops into memcpy()'s
#   ... etc

# -nostartfiles
#   Don't include the default crt0, so we provide our own
#   Affects therefore linking

# -lc, -lgcc
#   Link C library (but -lc relies on my syscalls.c)
#   Link compiler builtins (such as integer arithmetic helpers, soft-float implementations, etc)

# -ffunction-sections -fdata-sections
#   Puts each function in its own section, and each global variable in its own section which helps the unused section GC (below)
# -T linker.ld -Wl,--gc-sections
#   Use the provided linker file and ask to eliminate (GC) unused sections

# -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables
#   The compiler generates metadata to help exceptions and longjmps unwind
#   For C++ that would mean calling destructors, running finally blocks, etc
#   Without them, exceptions and longjmps leave side effects
# 
#   Note:
#     Synchronous unwind tables (-funwind-tables) - Generated at safe points (function calls, exception handlers)
#     Asynchronous unwind tables (-fasynchronous-unwind-tables) - Generated for every instruction, allowing debuggers to unwind from any point

CC=riscv64-unknown-elf-gcc

CFLAGS=-Os \
	-march=rv32i -mabi=ilp32 \
	-ffreestanding -nostartfiles \
	-ffunction-sections -fdata-sections \
	-fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables
LDFLAGS=-Wl,--gc-sections -lgcc

SOURCES=crt0.S main.c uart.c utils.S

ifdef LIBC
CFLAGS+=-DLIBC
LDFLAGS+=-lc --specs=nano.specs
SOURCES+=syscalls.c
endif

FIRMWARE_ELF=firmware.elf
FIRMWARE_BIN=firmware.bin
FIRMWARE_MEM=firmware.mem

ifdef QEMU
LINKER_SCRIPT=linker-qemu.ld
CFLAGS+=-DQEMU
else
LINKER_SCRIPT=linker.ld
endif

PTY=/tmp/qemu-uart

all: $(FIRMWARE_ELF)

$(FIRMWARE_ELF): $(SOURCES) $(LINKER_SCRIPT)
	$(CC) $(CFLAGS) -T $(LINKER_SCRIPT) $(LDFLAGS) -o $@ $(SOURCES)

# -M virt: Generic virtual platform with UART, PLIC (interrupt controller), etc
# -bios none: Don't load any BIOS/bootloader
#     - Otherwise, QEMU can use either OpenSBI or U-boot, which have a configurable location to load the kernel from
# -kernel $(FIRMWARE_ELF) - Load ELF as the "kernel"
#     - QEMU strips ELF metadata and loads the program into the sections specified on it
#     - Then it jumps to the reset address
# -serial pty:$(PTY) - Connect the emulated UART to the indicated file
boot: $(FIRMWARE_ELF)
	qemu-system-riscv32 -M virt -cpu rv32i -bios none -kernel $(FIRMWARE_ELF) -nographic -serial pty:$(PTY)

# --omap crlf: CR->LF on output
# --imap lfcrlf: LF->CRLF on input
talk: $(FIRMWARE_ELF)
	picocom -b 115200 --omap crlf --imap lfcrlf --echo $(PTY)

# objcopy -O binary: converts from ELF to binary
# hexdump: v (verbose) e (convert using specification)
#   1/4: each one iteration read four bytes and format as expected from System Verilog
firmware: $(FIRMWARE_ELF)
	riscv64-unknown-elf-objcopy -O binary $(FIRMWARE_ELF) $(FIRMWARE_BIN)
	hexdump -ve '1/4 "%08x\n"' $(FIRMWARE_BIN) > $(FIRMWARE_MEM)

clean:
	rm -f *.o $(FIRMWARE_ELF) $(FIRMWARE_BIN) $(FIRMWARE_MEM)
