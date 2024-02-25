MAKEFLAGS += --silent
TARGET_CPU = -mcpu=cortex-m0

ASSEMBLER_FLAGS = --warn --fatal-warnings $(TARGET_CPU)
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

main : rp2040_main.s
	arm-none-eabi-as $(ASSEMBLER_FLAGS) rp2040_main.s -o rp2040_main.elf

notmain.bin : rp2040_main.elf
	arm-none-eabi-objcopy -O binary rp2040_main.elf rp2040_main.bin
	arm-none-eabi-objdump $(DISASM_FLAGS) -D rp2040_main.elf > rp2040_main.disasm

pio : pio0.pio
	$(PIOASM_PATH) -o hex pio0.pio pio0.bin

