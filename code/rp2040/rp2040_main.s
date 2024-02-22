.cpu cortex-m0
.thumb


// main entry point
start:
    mov r0, #1
    lsl r0, r0, #25 // GPIO 25 bit

    ldr r2, =RESETS_RESET_CLR

    // rp2040 starts with most of the peripherals being in a reset state,
    // so we should clear the reset state to enable the peripheral
    str r0, [r2] 

    // wait until the reset clear has been done
    ldr r2, =RESETS_RESET_DONE_RW
wait_reset_clear : 
    ldr r1, [r2]
    tst r1, r0 // & two registers and set the flags
    bne wait_reset_clear

turn_off_gpio_25 :
    ldr r2, =SIO_GPIO_OE_CLR
    str r0, [r2] // disable output for gpio 25
    ldr r2, =SIO_GPIO_OUT_CLR
    str r0, [r2] // turn off gpio 25 
    ldr r2, =IO_BANK0_GPIO25_CTRL_RW

turn_on_gipo_25 :
    mov r1, #5
    str r1, [r2] // gpio 25 funtion = 5

    ldr r2, =SIO_GPIO_OE_SET
    str r0, [r2]

    // pre-populate addresses
    ldr r2, =SIO_GPIO_OUT_SET
    ldr r3, =SIO_GPIO_OUT_CLR
    mov r4, #1 // iter
    lsl r4, r4, #18

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

// constants 
// TODO(gh) doesn't work after certain memory boundary
    RESETS_RESET_CLR: .word 0x4000f000
    RESETS_RESET_DONE_RW : .word 0x4000c008 
    SIO_GPIO_OE_CLR : .word 0xd0000028 
    SIO_GPIO_OE_SET : .word 0xd0000024
    SIO_GPIO_OUT_CLR : .word 0xd0000018 
    SIO_GPIO_OUT_SET : .word 0xd0000014
    IO_BANK0_GPIO25_CTRL_RW: .word 0x400140cc

    



