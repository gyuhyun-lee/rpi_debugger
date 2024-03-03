.cpu cortex-m0
.thumb // NOTE(gh) 16-bit thumb mode, so one instruction fetch would actually fetch 2 instructions

.include "rp2040_defines.S"

.macro set_bit, reg, bit_pos
    mov \reg, #1
    lsl \reg, #\bit_pos
.endm

.macro deassert_peri_reset, reg_address, reg0, reg1, bit_pos

deassert_peri\@: 
    ldr \reg_address, =RESETS_RESET_CLR
    mov \reg0, #1
    lsl \reg0, \reg0, #\bit_pos
    str \reg0, [\reg_address] 

    ldr \reg_address, =RESETS_RESET_DONE_RW
loop_deassert_done\@ :
    ldr \reg1, [\reg_address]
    tst \reg0, \reg1
    beq loop_deassert_done\@
.endm

// gnu entry point
.globl _start
_start:

// @-----------------------------------------------------------------------------------------------------------------------------------
#define xosc_base           r7
#define xosc_set_base       r6
    
#define xosc_delay_counter  r0
set_xosc_startup_delay : 
    ldr xosc_base, =XOSC_BASE
    ldr xosc_set_base, =XOSC_SET_BASE
    mov xosc_delay_counter, #47 // basically a 1ms delay
    str xosc_delay_counter, [xosc_base, #XOSC_STARTUP_OFFSET]
#undef xosc_delay_counter  

#define xosc_enable_value r0
eanble_xosc:
    ldr xosc_enable_value, =XOSC_ENABLE_VALUE
    str xosc_enable_value, [xosc_set_base, #XOSC_CTRL_OFFSET] // enable XOSC
#undef xosc_enable_value 

#define xosc_stable_bit r0
#define xosc_status     r1
wait_until_xosc_stable : 
loop_until_xosc_stable : 
    ldr xosc_status, [xosc_base, #XOSC_STATUS_OFFSET]
    lsr xosc_status, #31
    beq loop_until_xosc_stable 
#undef xosc_stable_bit
#undef xosc_status  

#define clk_base r7
#define clk_ref_src r0
#define clk_sys_src r1
switch_to_xosc :
	ldr clk_base, =CLK_BASE
	mov clk_ref_src, #2			// clk_ref source = XOSC
	str clk_ref_src, [clk_base, #0x30]
	mov clk_sys_src, #0			// clk_sys source = clk_ref
	str clk_sys_src, [clk_base, #0x3c]	
#undef clk_base
#undef clk_ref_src
#undef clk_sys_src

#undef xosc_base           
#undef xosc_set_base       
// @-----------------------------------------------------------------------------------------------------------------------------------
#if 1 // disable pll
/*
    PLL programming sequence 
    • Program the FBDIV(feedback divider)
    • Turn on the main power and VCO
    • Wait for the VCO to lock (i.e. keep its output frequency stable)
    • Set up post dividers and turn them on

    result = (FREF / REFDIV) × FBDIV / (POSTDIV1 × POSTDIV2)
    120Mhz = (12Mhz / 1) × 100 / (5 × 2)
    
    FREF is always drived from XOSC(12Mhz for the pico)
    REFDIV is normally 1
    FBDIV - the bigger the better accuracy but with higher power consumption
    POSDIV1 should be bigger than POSTDIV2 for lower power consumption
*/
    deassert_peri_reset r7, r0, r1, 12

#define pll_sys_base  r7
#define pll_sys_clr_base r6
    ldr pll_sys_base, =PLL_SYS_BASE
    ldr pll_sys_clr_base, =PLL_SYS_CLR_BASE

#define FBDIV r0
configure_feedback_divider : 
    mov FBDIV, #120
    str FBDIV, [pll_sys_base, #PLL_SYS_FBDIV_INT_OFFSET]
#undef FBDIV

#define POSDIV1 r0
#define POSDIV2 r1
configure_post_dividers : 
    mov POSDIV1, #6
    lsl POSDIV1, #16
    mov POSDIV2, #2 
    lsl POSDIV2, #12
    orr POSDIV1, POSDIV2
    str POSDIV1, [pll_sys_base, #PLL_SYS_PRIM_OFFSET]
#undef POSDIV1
#undef POSDIV2

#define VCOPD r0
#define PD r1
power_on_main_power_and_vco : 
    set_bit VCOPD, 5
    mov PD, #1
    orr PD, VCOPD
    str PD, [pll_sys_clr_base, #PLL_SYS_PWR_OFFSET]
#undef VCOPD
#undef PD

#define pll_sys_ctrl_reg r1
wait_vco_lock : 
loop_wait_vco_lock : 
    ldr pll_sys_ctrl_reg, [pll_sys_base, #PLL_SYS_CS_OFFSET]
    lsr pll_sys_ctrl_reg, #31
    beq loop_wait_vco_lock // lock bit == bit31
#undef pll_sys_ctrl_reg

#define POSTDIVPD r0
turn_on_post_dividers : 
    set_bit POSTDIVPD, 3
    str POSTDIVPD, [pll_sys_clr_base, #PLL_SYS_PWR_OFFSET]
#undef POSTDIVPD

#undef pll_sys_base
#undef pll_sys_clr_base
// @-----------------------------------------------------------------------------------------------------------------------------------
#define clk_base r7
#define clk_sys_ctrl1 r1
#define clk_sys_ctrl0 r0
switch_to_pll_sys :
    ldr clk_base, =CLK_BASE
    mov clk_sys_ctrl0, #1 // clksrc_clk_sys_aux
    str clk_sys_ctrl0, [clk_base, #0x3C]
#undef clk_base
#undef clk_sys_ctrl1
#undef clk_sys_ctrl0

#endif // disable_pll_sys
// @-----------------------------------------------------------------------------------------------------------------------------------
    deassert_peri_reset r7, r0, r1, 5 // enable iobank 0
// @-----------------------------------------------------------------------------------------------------------------------------------
#define io_bank0_base r7
#define gpio_funcsel r0 
    ldr io_bank0_base, =IO_BANK0_BASE
    mov gpio_funcsel, #GPIO_FUNCSEL_PIO0

gpio0_configure : // swdclk
    str gpio_funcsel, [io_bank0_base, #GPIO0_CTRL_OFFSET]

gpio1_configure :  // swdio
    str gpio_funcsel, [io_bank0_base, #GPIO1_CTRL_OFFSET]

#undef io_bank0_base
#undef gpio_funcsel

// @-----------------------------------------------------------------------------------------------------------------------------------
    deassert_peri_reset r7, r0, r1, 10 // enable pio 0

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
    add r3, r3, #4 // instruction buffer has 4byte stride in address space
    sub r4, #1
    bne load_pio0_instructions

// @-----------------------------------------------------------------------------------------------------------------------------------
// sm0 - swd clk 
#define sm0_base r7
    ldr sm0_base, =SM0_BASE

#define wrap_top r0
#define wrap_bottom r1
configure_sm0_execctrl : 
    mov wrap_top, #2 
    lsl wrap_top, #12
    mov wrap_bottom, #1 
    lsl wrap_bottom, #7
    orr wrap_top, wrap_bottom
    str wrap_top, [sm0_base, #SM_EXECCTRL_OFFSET]
#undef wrap_top
#undef wrap_bottom

#define sm0_set_base 
#define s r0
configure_sm0_pinctrl : 
#undef s

#define pc r0
configure_sm0_instr : 
    // move the program counter of SM0
    mov pc, #0
    str pc, [sm0_base, #SM_INSTR_OFFSET]
#undef pc 

#undef sm0_base
// @-----------------------------------------------------------------------------------------------------------------------------------
// sm1 - swd dio + clk for read / write loop

#define sm1_base r7
    ldr sm1_base, =SM1_BASE

#define wrap_top r0
#define wrap_bottom r1
configure_sm1_execctrl : 
    mov wrap_top, #2 
    lsl wrap_top, #12
    mov wrap_bottom, #1 
    lsl wrap_bottom, #7
    orr wrap_top, wrap_bottom
    str wrap_top, [sm1_base, #SM_EXECCTRL_OFFSET]
#undef wrap_top
#undef wrap_bottom

#define sm1_set_base r6
#define s r0
configure_sm1_pinctrl : 
    ldr sm1_set_base, =SM1_SET_BASE
    mov s, #1
    lsl s, #SM_PINCTRL_OUT_BASE_SHIFT
    str s, [sm1_set_base, #SM_PINCTRL_OFFSET]

    mov s, #1
    lsl s, #SM_PINCTRL_IN_BASE_SHIFT
    str s, [sm1_set_base, #SM_PINCTRL_OFFSET]

    mov s, #1
    lsl s, #SM_PINCTRL_OUT_COUNT_SHIFT
    str s, [sm1_set_base, #SM_PINCTRL_OFFSET]

    mov s, #2
    lsl s, #SM_PINCTRL_SET_COUNT_SHIFT
    str s, [sm1_set_base, #SM_PINCTRL_OFFSET]

    mov s, #1
    lsl s, #SM_PINCTRL_SIDESET_COUNT_SHIFT
    str s, [sm1_set_base, #SM_PINCTRL_OFFSET]
#undef s
#undef sm1_set_base

#define pc r0
configure_sm1_instr : 
    // move the program counter of SM0
    mov pc, #0
    str pc, [sm1_base, #SM_INSTR_OFFSET]
#undef pc 

#undef sm1_base

// @-----------------------------------------------------------------------------------------------------------------------------------
#define pio0_base r7
    ldr pio0_base, =PIO0_BASE

#define sm_enable r0
start_sms : 
    mov sm_enable, #3
    str sm_enable, [pio0_base, #PIO0_CTRL_OFFSET]
#undef sm_enable
    
#if 0
    ldr r2, =PIO_SM0_TXF
    mov r1, #0b10101010
    str r1, [r2]
#endif

#undef pio0_base

// @-----------------------------------------------------------------------------------------------------------------------------------

#if 1
#define sio_gpio_oe_clr_reg r7
#define sio_gpio_out_clr_reg r6
#define bit2 r0
    mov bit2, #1
    lsl bit2, #2
disable_gpio2 :
    ldr sio_gpio_oe_clr_reg, =SIO_GPIO_OE_CLR
    str bit2, [sio_gpio_oe_clr_reg]
    ldr sio_gpio_out_clr_reg, =SIO_GPIO_OUT_CLR
    str bit2, [sio_gpio_out_clr_reg]
#undef bit2
#undef sio_gpio_oe_clr_reg
#undef sio_gpio_out_clr_reg

#define io_bank0_base r7
#define funcsel r0
change_gpio2_function : 
    ldr io_bank0_base, =IO_BANK0_BASE
    mov funcsel, #GPIO_FUNCSEL_SIO
    str funcsel, [io_bank0_base, #GPIO2_CTRL_OFFSET]
#undef io_bank0_base
#undef funcsel

#define sio_gpio_oe_set_reg r7
#define bit2 r0
enable_gpio2 : 
    ldr sio_gpio_oe_set_reg, =SIO_GPIO_OE_SET
    mov bit2, #1
    lsl bit2, #2
    str bit2, [sio_gpio_oe_set_reg]
#undef sio_gpio_oe_set_reg
#undef bit2

#define sio_gpio_out_set_reg r7
#define sio_gpio_out_clr_reg r6
#define bit2 r0
    // pre-populate addresses for the LED
    ldr sio_gpio_out_set_reg, =SIO_GPIO_OUT_SET
    ldr sio_gpio_out_clr_reg, =SIO_GPIO_OUT_CLR
    mov bit2, #1
    lsl bit2, #2

    // TODO(gh) why am I getting 45-55 duty cycle for this?
loop_gpio2 :
    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    str bit2, [sio_gpio_out_set_reg]
    str bit2, [sio_gpio_out_clr_reg]

    b loop_gpio2
#endif
#undef bit2
#undef sio_gpio_out_set_reg
#undef sio_gpio_out_clr_reg

// @-----------------------------------------------------------------------------------------------------------------------------------

    



