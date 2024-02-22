MAKEFLAGS += --silent
TARGET_CPU = -mcpu=cortex-m0

ASSEMBLER_FLAGS = --warn --fatal-warnings $(TARGET_CPU)
COMPILER_FLAGS = -Wall -O2 -nostdlib -nostartfiles -ffreestanding -ggdb -g0 $(TARGET_CPU)
LINKER_FLAGS = -nostdlib #-nostartfiles
DISASM_FLAGS = -d --source-comment=// -r 
#BUILD_PATH = ../build
#SDCARD_PATH = /Volumes/RPIBOOT

all : clean main notmain.bin 

clean:
	rm -f *.bin
	rm -f *.o
	rm -f *.elf
	rm -f *.disasm

main : rp2040_main.s
	arm-none-eabi-as $(ASSEMBLER_FLAGS) rp2040_main.s -o main.elf

notmain.bin : main.elf
	arm-none-eabi-objcopy -O binary main.elf main.bin
	arm-none-eabi-objdump $(DISASM_FLAGS) -D main.elf > main.disasm
