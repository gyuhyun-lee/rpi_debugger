.cpu cortex-m0
.thumb // NOTE(gh) 16-bit thumb mode, so 32-bit fetch would actually fetch 2 instructions

// constants 
.equ GPIO_FUNCSEL_SIO, 5
.equ GPIO_FUNCSEL_PIO0, 6
.equ GPIO_FUNCSEL_PIO1, 6

// addresses, these will be stored at the end of the instruction stream
// as they are too large
.equ RESETS_BASE, 0x4000c000 // 1 == peripheral is in reset
.equ SIO_BASE, 0xd0000000
.equ IO_BANK0_BASE, 0x40014000 
.equ PIO0_BASE, 0x50200000
.equ PIO1_BASE, 0x50300000
.equ XOSC_BASE, 0x40024000

.equ RESETS_RESET, (RESETS_BASE+0x3000)
.equ RESETS_RESET_DONE_RW, (RESETS_BASE + 0x8)

.equ CLK_BASE, 0x40008000

.equ CLK_REF_CTRL_RW, (CLK_BASE+0x30+0x0000)
.equ CLK_REF_CTRL_XOR, (CLK_BASE+0x30+0x1000)
.equ CLK_REF_CTRL_SET, (CLK_BASE+0x30+0x2000)
.equ CLK_REF_CTRL_CLR, (CLK_BASE+0x30+0x3000)

.equ CLK_SYS_CTRL_RW, (CLK_BASE+0x3C+0x0000)
.equ CLK_SYS_CTRL_XOR, (CLK_BASE+0x3C+0x1000)
.equ CLK_SYS_CTRL_SET, (CLK_BASE+0x3C+0x2000)
.equ CLK_SYS_CTRL_CLR, (CLK_BASE+0x3C+0x3000)

.equ XOSC_CTRL_RW, (XOSC_BASE+0x00+0x0000)
.equ XOSC_CTRL_XOR, (XOSC_BASE+0x00+0x1000)
.equ XOSC_CTRL_SET, (XOSC_BASE+0x00+0x2000)
.equ XOSC_CTRL_CLR, (XOSC_BASE+0x00+0x3000)

.equ XOSC_STATUS_RW, (XOSC_BASE+0x04+0x0000)
.equ XOSC_STATUS_XOR, (XOSC_BASE+0x04+0x1000)
.equ XOSC_STATUS_SET, (XOSC_BASE+0x04+0x2000)
.equ XOSC_STATUS_CLR, (XOSC_BASE+0x04+0x3000)

.equ XOSC_STARTUP_RW, (XOSC_BASE+0x0C+0x0000)
.equ XOSC_STARTUP_XOR, (XOSC_BASE+0x0C+0x1000)
.equ XOSC_STARTUP_SET, (XOSC_BASE+0x0C+0x2000)
.equ XOSC_STARTUP_CLR, (XOSC_BASE+0x0C+0x3000)

.equ SIO_GPIO_OUT_RW, (SIO_BASE + 0x10) // SIO_BASE + GPIO_OUT
.equ SIO_GPIO_OUT_SET, (SIO_BASE + 0x14) // SIO_BASE + GPIO_OUT_SET
.equ SIO_GPIO_OUT_CLR, (SIO_BASE + 0x18) // SIO_BASE + GPIO_OUT_CLR 
.equ SIO_GPIO_OUT_XOR, (SIO_BASE + 0x01c) // SIO_BASE + GPIO_OUT_XOR
.equ SIO_GPIO_OE_SET, (SIO_BASE + 0x24) // SIO_BASE + GPIO_OE_SET
.equ SIO_GPIO_OE_CLR, (SIO_BASE + 0x28) // SIO_BASE + GPIO_OE_CLR 

// IO_BANK0_BASE + sizeof(iobank0_status_ctrl_hw_t) * gpio_index + x(register offset in iobank0_status_ctrl_hw_t struct)
.equ GPIO0_CTRL_RW, (IO_BANK0_BASE + (0x8 * 0) + 4 + 0x0000) 
.equ GPIO0_CTRL_XOR, (IO_BANK0_BASE + (0x8 * 0) + 4 + 0x1000) 
.equ GPIO0_CTRL_SET, (IO_BANK0_BASE + (0x8 * 0) + 4 + 0x2000) 
.equ GPIO0_CTRL_CLR, (IO_BANK0_BASE + (0x8 * 0) + 4 + 0x3000) 

.equ GPIO1_CTRL_RW, (IO_BANK0_BASE + (0x8 * 1) + 4 + 0x0000) 
.equ GPIO1_CTRL_XOR, (IO_BANK0_BASE + (0x8 * 1) + 4 + 0x1000) 
.equ GPIO1_CTRL_SET, (IO_BANK0_BASE + (0x8 * 1) + 4 + 0x2000) 
.equ GPIO1_CTRL_CLR, (IO_BANK0_BASE + (0x8 * 1) + 4 + 0x3000) 

.equ GPIO2_CTRL_RW, (IO_BANK0_BASE + (0x8 * 2) + 4 + 0x0000) 
.equ GPIO2_CTRL_XOR, (IO_BANK0_BASE + (0x8 * 2) + 4 + 0x1000) 
.equ GPIO2_CTRL_SET, (IO_BANK0_BASE + (0x8 * 2) + 4 + 0x2000) 
.equ GPIO2_CTRL_CLR, (IO_BANK0_BASE + (0x8 * 2) + 4 + 0x3000) 

.equ GPIO25_CTRL_RW, (IO_BANK0_BASE + (0x8 * 25) + 4 + 0x0000) 
.equ GPIO25_CTRL_XOR, (IO_BANK0_BASE + (0x8 * 25) + 4 + 0x1000) 
.equ GPIO25_CTRL_SET, (IO_BANK0_BASE + (0x8 * 25) + 4 + 0x2000) 
.equ GPIO25_CTRL_CLR, (IO_BANK0_BASE + (0x8 * 25) + 4 + 0x3000) 

// PIO
.equ PIO0_CTRL, (PIO0_BASE + 0x0)
.equ PIO0_FSTAT, (PIO0_BASE + 0x4)
.equ PIO0_FDEBUG, (PIO0_BASE + 0x8)
.equ PIO0_FLEVEL, (PIO0_BASE + 0xc)
.equ PIO0_TXF0, (PIO0_BASE + 0x10)
.equ PIO0_TXF1, (PIO0_BASE + 0x14)
.equ PIO0_TXF2, (PIO0_BASE + 0x18)
.equ PIO0_TXF3, (PIO0_BASE + 0x1c)
.equ PIO0_RXF0, (PIO0_BASE + 0x20)
.equ PIO0_RXF1, (PIO0_BASE + 0x24)
.equ PIO0_RXF2, (PIO0_BASE + 0x28)
.equ PIO0_RXF3, (PIO0_BASE + 0x2c)
.equ PIO0_IRQ, (PIO0_BASE + 0x30)
.equ PIO0_IRQ_FORCE, (PIO0_BASE + 0x34)
.equ PIO0_INPUT_SYNC_BYPASS, (PIO0_BASE + 0x38)
.equ PIO0_DBG_PADOUT, (PIO0_BASE + 0x3c)
.equ PIO0_DBG_PADOE, (PIO0_BASE + 0x40)
.equ PIO0_DBG_CFGINFO, (PIO0_BASE + 0x44)

// although each 'slot' is 4 bytes in the address space, each 'instruction' is 2 bytes
.equ PIO0_INSTR_MEM_START, (PIO0_BASE + 0x048) 
// user-defined PIO instruction location inside SRAM. At startup, debug probe should load & store the instructions
// from here to PIO0_INSTR_MEM_START
.equ PIO0_INSTR_MEM_SRARM_START, 0x20040000 // sram bank 4 for now 

.equ PIO_SM0_CLKDIV, (PIO0_BASE + 0x0c8) // Frequency = clock freq / (CLKDIV_INT + CLKDIV_FRAC / 256)
.equ PIO_SM0_EXECCTRL, (PIO0_BASE + 0x0cc) 
.equ PIO_SM0_SHIFTCTRL, (PIO0_BASE + 0x0d0) // out/in shift registers control
.equ PIO_SM0_ADDR, (PIO0_BASE + 0x0d4) // RO
.equ PIO_SM0_INSTR, (PIO0_BASE + 0x0d8) // write to change the SM's
.equ PIO_SM0_PINCTRL, (PIO0_BASE + 0x0dc)

// gnu entry point
.globl _start
_start:

start_xosc:
    // TODO(gh) also set the timer using CLK_RESUS just in case?
    ldr r2, =XOSC_CTRL_RW
    mov r0, #0xAA
    lsl r0, #4
    str r0, [r2] // 0xAA0 = 1-15mhz range

    ldr r2, =XOSC_CTRL_SET
    mov r0, #0xfa
    lsl r0, r0, #4
    mov r1, #0xb 
    orr r0, r0, r1 // create 0xfab
    lsl r0, r0, #12
    str r0, [r2] // enable XOSC

    mov r0, #1
    lsl r0, #31
    ldr r2, =XOSC_STATUS_RW
wait_until_xosc_stable :
    ldr r1, [r2]
    tst r0, r1
    beq wait_until_xosc_stable 

switch_to_xosc :
    // TODO(gh) this is from dwelch, why do we need to change the
    // clk_ref first and then derive clk_sys from it?
    ldr r2, =CLK_REF_CTRL_RW
    mov r0, #2
    str r0, [r2]
    ldr r2, =CLK_SYS_CTRL_RW
    mov r0, #0
    str r0, [r2]

    mov r1, #1
    lsl r0, r1, #5 // IO Bank0
    lsl r1, r1, #10 // PIO0
    orr r0, r0, r1  

    ldr r2, =RESETS_RESET 

    // rp2040 starts with most of the peripherals being in a reset state,
    // so we should clear the reset state to enable the peripheral
    str r0, [r2] 

    // wait until the reset clear has been done
    ldr r2, =RESETS_RESET_DONE_RW
wait_until_reset_is_undone : 
    ldr r1, [r2]
    tst r1, r0 // & two registers, set the flags
    beq wait_until_reset_is_undone // branch if the result == 0 

    mov r0, #1
    lsl r0, r0, #2 // GPIO 2 bit
disable_gpio_2 :
    ldr r2, =SIO_GPIO_OE_CLR
    str r0, [r2] // disable output for this gpio
    ldr r2, =SIO_GPIO_OUT_CLR
    str r0, [r2] 

change_gpio_2_function :
    ldr r2, =GPIO2_CTRL_RW
    mov r1, #GPIO_FUNCSEL_SIO
    str r1, [r2] 

enable_gpio_2 :
    ldr r2, =SIO_GPIO_OE_SET 
    str r0, [r2]


    // load 32(always) pio instructions from SRAM5
    // and store it in PIO0 instruction buffer
    mov r4, #32
    ldr r2, =PIO0_INSTR_MEM_SRARM_START
    ldr r3, =PIO0_INSTR_MEM_START
load_pio0_instructions :
    // TODO(gh) find out what happens to the bus
    // when we load a 16-bit value
    ldrh r1, [r2]
    str r1, [r3]

    add r2, r2, #2 
    add r3, r3, #4 // instruction buffer has 4byte stride

    sub r4, #1
    bne load_pio0_instructions

init_pio_sm0 : 
/*
    // change sm0 clock divisor
    ldr r2, =PIO_SM0_CLKDIV 
    mov r1, #1
    lsl r1, r1, #16
    str r1, [r2]
*/

    // make GPIO0 to be controllable by the PIO,
    // and set the direction to be output
    ldr r2, =GPIO0_CTRL_RW
    // mov r1, #0x3
    // lsl r1, r1, #12
    // mov r3, #6 
    // orr r1, r1, r3
    mov r1, #6
    str r1, [r2]

    // change the wrapping address
    // the numbers are per pio instruction(31 == last pio instruction in buffer)
    ldr r2, =PIO_SM0_EXECCTRL
    mov r1, #2 // wrap_top
    lsl r1, r1, #12
    mov r3, #1 // wrap_bottom
    lsl r3, r3, #7
    orr r1, r1, r3 
    str r1, [r2]

    // move the program counter of SM0
    mov r1, #0
    ldr r2, =PIO_SM0_INSTR
    str r1, [r2]

    // TODO(gh) just a debug, move this somewhere else
    // pre-populate GPIO addresses
    ldr r3, =SIO_GPIO_OUT_SET
    ldr r4, =SIO_GPIO_OUT_CLR
    ldr r5, =SIO_GPIO_OUT_RW
    mov r0, #1
    lsl r0, r0, #2

    // start the SM0
    mov r1, #1
    ldr r2, =PIO0_CTRL
    str r1, [r2]

    nop // debug, for sm0 set pindirs
change_gpio_2 : 
    // ldr r0, [r5]
    // lsl r0, r0, #2
    str r0, [r5]
    b change_gpio_2

    /*
    
    mov r0, #1
    lsl r0, r0, #25 // GPIO 25 bit
disable_gpio_25 :
    ldr r2, =SIO_GPIO_OE_CLR
    str r0, [r2] // disable output for gpio 25
    ldr r2, =SIO_GPIO_OUT_CLR
    str r0, [r2] // turn off gpio 25 

change_gpio_25_function :
    ldr r2, =GPIO25_CTRL_RW
    mov r1, #GPIO_FUNCSEL_SIO
    str r1, [r2] // gpio 25 funtion = 5(SIO)

enable_gpio_25 :
    ldr r2, =SIO_GPIO_OE_SET
    str r0, [r2]

    // pre-populate addresses for the LED
    ldr r2, =SIO_GPIO_OUT_SET
    ldr r3, =SIO_GPIO_OUT_CLR
    mov r4, #1 // iter
    lsl r4, r4, #14
loop_led_on : 
    str r0, [r2] // set GPIO 25
    sub r4, #1
    bne loop_led_on
    mov r4, #1 // iter
    lsl r4, r4, #18   

loop_led_off:
    str r0, [r3] // clear GPIO 25
    sub r4, #1
    bne loop_led_off
    mov r4, #1 // iter
    lsl r4, r4, #18   
    b loop_led_on
    */

    



