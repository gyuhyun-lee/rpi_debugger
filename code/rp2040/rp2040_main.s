.cpu cortex-m0
.thumb // NOTE(gh) 16-bit thumb mode, so one instruction fetch would actually fetch 2 instructions

.include "rp2040_defines.S"

.macro set_bit, reg, bit_pos
set_bit\@ :
    mov \reg, #1
    lsl \reg, #\bit_pos
.endm

.macro delay, iter, cycle_count
    mov \iter, #\cycle_count
loop_delay\@ :
    sub \iter, #1
    bne loop_delay\@
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

// each bits in enable_bits mean sm0 - sm3
.macro enable_sms pio0_set_base, enable_reg, enable_bits
    ldr \pio0_set_base, =PIO0_SET_BASE
enable_sms\@ : 
    mov \enable_reg, #\enable_bits
    str \enable_reg, [\pio0_set_base, #PIO0_CTRL_OFFSET]
.endm

.macro disable_sms pio0_clr_base, disable_reg, disable_bits
    ldr \pio0_clr_base, =PIO0_CLR_BASE
disable_sms\@ : 
    mov \disable_reg, #\disable_bits
    str \disable_reg, [\pio0_clr_base, #PIO0_CTRL_OFFSET]
.endm

// gnu entry point
.global _start
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

gpio0_configure : // swdio
    str gpio_funcsel, [io_bank0_base, #GPIO0_CTRL_OFFSET]

gpio1_configure :  // swdclk
    str gpio_funcsel, [io_bank0_base, #GPIO1_CTRL_OFFSET]

#undef io_bank0_base
#undef gpio_funcsel

// @-----------------------------------------------------------------------------------------------------------------------------------
    deassert_peri_reset r7, r0, r1, 10 // enable pio 0

// @-----------------------------------------------------------------------------------------------------------------------------------
config_pio_output_direction_mask :

#define pio0_base r7
#define inst_B0 r0
#define inst_B1 r1
store_set_pindir_instruction : // set both dio & clk to be output
    ldr pio0_base, =PIO0_BASE
    mov inst_B1, #0xe0
    lsl inst_B1, #8
    mov inst_B0, #0x83
    orr inst_B1, inst_B0
    str inst_B1, [pio0_base, #PIO0_INSTR_MEM_START_OFFSET]
#undef inst_B0
#undef inst_B1
#undef pio0_base

#define pio0_set_base r7
#define enable_reg r0
    enable_sms pio0_set_base, enable_reg, 1
#undef enable_reg
#undef pio0_set_base 

    // should be enough time to set the direction
#define iter r0
    delay iter, 32
#undef iter
    
#define pio0_clr_base r7
#define disable_reg r0
    disable_sms pio0_clr_base, disable_reg, 1
#undef disable_reg
#undef pio0_clr_base

// @-----------------------------------------------------------------------------------------------------------------------------------
#define src_addr r7 // SRAM 
#define dest_addr r6 // PIO instruction buffer
#define iter r0
#define inst r1

load_pio0_instructions :
    // load 32(always) pio instructions from SRAM5
    // and store it in PIO0 instruction buffer
    mov iter, #32
    ldr src_addr, =PIO0_INSTR_MEM_SRARM_START
    ldr dest_addr, =PIO0_INSTR_MEM_START
loop_load_pio0_instructions :
    ldrh inst, [src_addr]
    str inst, [dest_addr]

    add src_addr, #2 
    add dest_addr, #4 // instruction buffer has 4byte stride in address space
    sub iter, #1
    bne loop_load_pio0_instructions

#undef src_addr  
#undef dest_addr 
#undef iter 
#undef inst 
     
// @-----------------------------------------------------------------------------------------------------------------------------------
// configure sm0 to be swdclk + swdio

#define sm0_set_base r6
#define s r0
configure_sm0_pinctrl : 
    ldr sm0_set_base, =SM0_SET_BASE

#if 0
    mov s, #0
    lsl s, #SM_PINCTRL_OUT_BASE_SHIFT
    str s, [sm0_set_base, #SM_PINCTRL_OFFSET]

    mov s, #0
    lsl s, #SM_PINCTRL_SET_BASE_SHIFT
    str s, [sm0_set_base, #SM_PINCTRL_OFFSET]
#endif

    mov s, #1
    lsl s, #SM_PINCTRL_SIDESET_BASE_SHIFT
    str s, [sm0_set_base, #SM_PINCTRL_OFFSET]

#if 0
    mov s, #0
    lsl s, #SM_PINCTRL_IN_BASE_SHIFT
    str s, [sm0_set_base, #SM_PINCTRL_OFFSET]
#endif

    mov s, #1
    lsl s, #SM_PINCTRL_OUT_COUNT_SHIFT
    str s, [sm0_set_base, #SM_PINCTRL_OFFSET]

    mov s, #1
    lsl s, #SM_PINCTRL_SET_COUNT_SHIFT
    str s, [sm0_set_base, #SM_PINCTRL_OFFSET]

    mov s, #1
    lsl s, #SM_PINCTRL_SIDESET_COUNT_SHIFT
    str s, [sm0_set_base, #SM_PINCTRL_OFFSET]
#undef s
#undef sm0_set_base

#define sm0_base r7
#define pc r0
configure_sm0_instr : 
    ldr sm0_base, =SM0_BASE
    // initialize the program counter
    mov pc, #0
    str pc, [sm0_base, #SM_INSTR_OFFSET]
#undef pc 
#undef sm0_base

// @-----------------------------------------------------------------------------------------------------------------------------------
// start sm

#define pio0_set_base r7
#define enable_reg r0
    enable_sms pio0_set_base, enable_reg, 1
#undef pio0_set_base
#undef enable_reg

// @-----------------------------------------------------------------------------------------------------------------------------------

// TEST(gh) set arbitrary header + 32 bit 
// and test read-write routine

#define pio0_base r7
    ldr pio0_base, =PIO0_BASE

#define header r0 // IMPORTANT(gh) need to preserve this register for retry!
push_header : 
    mov header, #0b01010101
    str header, [pio0_base, #SM0_TXFIFO_OFFSET]
#undef header 

#if 1

#define rxempty_test_bit r1
#define pio0_fstat r2
wait_for_ack : 
    set_bit rxempty_test_bit, 8
loop_wait_for_ack : 
    ldr pio0_fstat, [pio0_base, #PIO0_FSTAT_OFFSET] 
    tst rxempty_test_bit, pio0_fstat // 1 == FIFO empty
    bne loop_wait_for_ack // TODO(gh) this doesn't work
#undef pio0_fstat
#undef rxempty_test_bit

#define ack r1
pull_ack :
    ldr ack, [pio0_base, #SM0_RXFIFO_OFFSET]
// TODO(gh) test ack
#undef ack

#if 1
// read_test
#define sm0_base r6
#define pc r0
move_sm0_pc : 
    ldr sm0_base, =SM0_BASE
    mov pc, #26 // TODO(gh) there gotta be a better way ... 
    str pc, [sm0_base, #SM_INSTR_OFFSET]
#undef pc
#undef sm0_base
#else

// write test

#define data r1
push_data : 
    ldr data, =0xaaaaaaaa
    str data, [pio0_base, #SM0_TXFIFO_OFFSET]
#undef data

#define sm0_base r6
#define pc r0
move_sm0_pc : 
    ldr sm0_base, =SM0_BASE
    mov pc, #18 // TODO(gh) there gotta be a better way ... 
    str pc, [sm0_base, #SM_INSTR_OFFSET]
#undef pc
#undef sm0_base

#endif

#if 0

#endif
#endif

#undef pio0_base


// @-----------------------------------------------------------------------------------------------------------------------------------

#if 0
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
#undef bit2
#undef sio_gpio_out_set_reg
#undef sio_gpio_out_clr_reg

// @-----------------------------------------------------------------------------------------------------------------------------------
#endif

    



