MAKEFLAGS += --silent
TARGET_CPU = -mcpu=cortex-m0

ASSEMBLER_FLAGS = $(TARGET_CPU)
COMPILER_FLAGS = -Wall -O2 -nostdlib -nostartfiles -ffreestanding -ggdb -g0 $(TARGET_CPU)
LINKER_FLAGS = -nostdlib #-nostartfiles
DISASM_FLAGS = -d --source-comment=// -r 
#BUILD_PATH = ../build
#SDCARD_PATH = /Volumes/RPIBOOT

PIOASM_PATH = ../../misc/pioasm 

all : clean main notmain.bin pio

clean:
	rm -f *.bin
	rm -f *.o
	rm -f *.elf
	rm -f *.disasm

main : rp2040_main.S
	# even though we only have once main file for now,
	# we go through the linker process to catch unknown label(constants) errors
	arm-none-eabi-gcc $(COMPILER_FLAGS) rp2040_main.S -o rp2040_main.elf
	# passing in the linker memory map file to see the instructions starting at 0x0
	# in disasm
	# arm-none-eabi-ld $(LINKER_FLAGS) -T memmap.ld rp2040_main.o -o rp2040_main.elf

notmain.bin : rp2040_main.elf
	arm-none-eabi-objcopy -O binary rp2040_main.elf rp2040_main.bin
	arm-none-eabi-objdump $(DISASM_FLAGS) -D rp2040_main.elf > rp2040_main.disasm

pio : pio0.pio
	$(PIOASM_PATH) -o hex pio0.pio pio0.bin

