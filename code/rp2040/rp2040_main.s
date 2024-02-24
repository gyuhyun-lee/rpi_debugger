.cpu cortex-m0
.thumb // NOTE(gh) 16-bit thumb mode, so 32-bit fetch would actually fetch 2 instructions

// constants 
// RESETS_BASE 0x4000c000
// 
.equ RESETS_BASE, 0x4000c000
.equ SIO_BASE, 0xd0000000
.equ IO_BANK0_BASE, 0x40014000 

.equ RESETS_RESET_CLR, (RESETS_BASE+0x3000)
.equ RESETS_RESET_DONE_RW, (RESETS_BASE + 0x8)

.equ SIO_GPIO_OUT_SET, (SIO_BASE + 0x14) // SIO_BASE + GPIO_OUT_SET
.equ SIO_GPIO_OUT_CLR, (SIO_BASE + 0x18) // SIO_BASE + GPIO_OUT_CLR 
.equ SIO_GPIO_OE_SET, (SIO_BASE + 0x24) // SIO_BASE + GPIO_OE_SET
.equ SIO_GPIO_OE_CLR, (SIO_BASE + 0x28) // SIO_BASE + GPIO_OE_CLR 

.equ IO_BANK0_GPIO25_CTRL_RW, (IO_BANK0_BASE + (0x8 * 25) + 4) // IO_BANK0_BASE + sizeof(iobank0_status_ctrl_hw_t) * 25 + 4(seconds register in iobank0_status_ctrl_hw_t)

// main entry point
start:
    mov r0, #1
    lsl r0, r0, #5 // IO Bank0

    ldr r2, =RESETS_RESET_CLR // RESETS_RESET_CLR

    // rp2040 starts with most of the peripherals being in a reset state,
    // so we should clear the reset state to enable the peripheral
    str r0, [r2] 

    // wait until the reset clear has been done
    ldr r2, =RESETS_RESET_DONE_RW
wait_until_reset_is_undone : 
    ldr r1, [r2]
    tst r1, r0 // & two registers, set the flags
    beq wait_until_reset_is_undone // compare weith 0

    mov r0, #1
    lsl r0, r0, #25 // GPIO 25 bit

turn_off_gpio_25 :
    ldr r2, =SIO_GPIO_OE_CLR
    str r0, [r2] // disable output for gpio 25
    ldr r2, =SIO_GPIO_OUT_CLR
    str r0, [r2] // turn off gpio 25 

    // 
change_gpio_25_function :
    ldr r2, =IO_BANK0_GPIO25_CTRL_RW
    mov r1, #5
    str r1, [r2] // gpio 25 funtion = 5

turn_back_on_gipo_25 :
    ldr r2, =SIO_GPIO_OE_SET
    str r0, [r2]

    // pre-populate addresses
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


// TODO(gh) doesn't work after certain memory boundary
    RESETS_RESET_DONE_RW : .word  // RESETS_BASE + 0x8

    SIO_GPIO_OUT_SET : .word (0xd0000000 + 0x14) // SIO_BASE + GPIO_OUT_SET
    SIO_GPIO_OUT_CLR : .word  
    SIO_GPIO_OE_CLR : .word (0xd0000000 + 0x28) 

    IO_BANK0_GPIO25_CTRL_RW: .word 

    



