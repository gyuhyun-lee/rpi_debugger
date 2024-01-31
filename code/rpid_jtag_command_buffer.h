#ifndef RPID_JTAG_COMMAND_BUFFER
#define RPID_JTAG_COMMAND_BUFFER

// push commands to the command buffer
// NICE TO HAVE(add these features when we actually encounter this kind of bugs)
// - minimal state change
//   detects which state is the stm in, and find a minimal route to go to the next state 
// - value verification
// - cycle count
// - logging
// - address/instruction reuse
//   if the next address / instruction are the same as the previous one,
//   reuse those without changing them again. 
//   however, this is only useful if the code that does this takes less time than actually changing the address
// - command re-ordering
//   a bit too extreme, this too might take longer than just executing the commands
// - pipelining
//   if the instruction is same, we can both write while reading, or request for read while reading.

// MUST HAVE
// - OK/FAULT - WAIT detection(retry if the bit was WAIT) 
// - cable-agnostic command buffer for RP2040 based debug probe
// - buffer overflow detection

// 16 states
enum JTAGState
{
    RESET = 0x0, // Test-Logic-Reset
    IDLE, // Run-Test/IDLE

    // DR
    DR_SCAN,
    CAPTURE_DR,
    SHIFT_DR,
    EXIT1_DR,
    PAUSE_DR,
    EXIT2_DR,
    UPDATE_DR,

    // IR 
    IR_SCAN,
    CAPTURE_IR,
    SHIFT_IR,
    EXIT1_IR,
    PAUSE_IR,
    EXIT2_IR,
    UPDATE_IR,
};

// this alone is enough in DPv0
// for DPv1 & 2, you also need to update DPBANKSEL which is the bottom 4 bits in SELECT
enum JTAGDROffsetA
{
    A_CTRL_STAT = 0x4,
    A_RDBUFF = 0xC,
    A_SELECT = 0x8,
};

struct JTAGCommandBuffer
{
    u8 *base;
    u32 used;
    u32 size;

    JTAGState current_state;
    IR4Type current_IR;

    // same as the SELECT register, but we have some additional bits in the RESERVED field. obviously we have to ignore
    // these bits when we are updating the SELECT register.
    u32 current_SELECT; 

    // 12 bit(routing entry)  + 4 bit(routing bit count)
    u16 routing_table[256];

    // u8 routing_table[256];
    // u8 routing_count[256]; //tells us how many times we should move the TMS
};

#endif
