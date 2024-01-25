COMPILER = clang 
ARCHITECTURE = -arch arm64 # check this VS -march armv8+simd
MAKEFLAGS += --silent

MAIN_CODE_PATH = ../code
MACOS_BUILD_PATH = ../build
MACOS_APP_NAME = rpi_debugger.app
MACOS_EXE_PATH = $(MACOS_BUILD_PATH)/$(MACOS_APP_NAME)/Contents/MacOS
MACOS_RESOURCE_PATH = $(MACOS_BUILD_PATH)/$(MACOS_APP_NAME)/Contents/Resources
MACOS_FRAMEWORK = -framework Cocoa -framework CoreFoundation -framework CoreGraphics -framework CoreVideo -framework Metal -framework MetalKit -framework MetalPerformanceShaders 

# -O0 = unoptimized, -O2 = compiler optimized
COMPILER_FLAGS = -g -Wall -O0 -pthread -D RPID_DEBUG=1 -D RPID_SLOW=1 -D RPID_ARM=1 -D RPID_X86_X64=0 -D RPID_LLVM=1 -D RPID_MSVC=0 -D RPID_MACOS=1 -D RPID_LINUX=0 -D RPID_VULKAN=0 -D RPID_METAL=1

# prefix the name of the warning with 'no-' to disable certain warning
COMPILER_IGNORE_WARNINGS = -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -Wno-writable-strings -Wno-switch -Wno-objc-missing-super-calls -Wno-missing-braces -Wnonportable-include-path -Wno-uninitialized -Wno-nonportable-include-path -Wno-tautological-bitwise-compare -Wno-unused-but-set-variable -Wno-nullability-completeness

all : make_directory make_app compile_main get_disassembly cleanup

make_directory : 
	mkdir -p $(MACOS_BUILD_PATH)

make_app : 
	mkdir -p $(MACOS_BUILD_PATH)/$(MACOS_APP_NAME)
	mkdir -p $(MACOS_BUILD_PATH)/$(MACOS_APP_NAME)/Contents
	mkdir -p $(MACOS_BUILD_PATH)/$(MACOS_APP_NAME)/Contents/Resources
	mkdir -p $(MACOS_BUILD_PATH)/$(MACOS_APP_NAME)/Contents/MacOS

compile_main : $(MAIN_CODE_PATH)/macos_rpid.mm
	$(COMPILER) $(ARCHITECTURE) $(COMPILER_FLAGS) $(COMPILER_IGNORE_WARNINGS) $(MACOS_FRAMEWORK) -o $(MACOS_EXE_PATH)/rpi_debugger $(MAIN_CODE_PATH)/macos_rpid.mm 

get_disassembly : $(MACOS_EXE_PATH)/rpi_debugger
	# -d diassemble
	# -S show source code
	# --sysm show symbol table
	objdump -d --line-numbers -S --arch=arm64 --syms $(MACOS_EXE_PATH)/rpi_debugger > $(MACOS_EXE_PATH)/rpi_debugger.s

#clean all the object files.
cleanup : 
	 rm -rf *.o 
