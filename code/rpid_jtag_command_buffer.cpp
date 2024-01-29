// #include "rpid_jtag_command_buffer.h"

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

// MUST HAVE
// - OK/FAULT - WAIT detection(retry if the bit was WAIT) 
// - cable-agnostic command buffer for RP2040 based debug probe
// - buffer overflow detection

// 16 dwords
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

struct JTAGCommandBuffer
{
    u8 *base;
    u32 used;
    u32 size;

    JTAGState current_state;

    // addresses
    u32 current_APBANKSEL;
    u32 current_APSEL;
    u32 current_DPBANKSEL;
    u32 current_A;

    // 12 bit(routing entry)  + 4 bit(routing bit count)
    // u16 routing_table[256];

    u8 routing_table[256];
    u8 routing_count[256]; //tells us how many times we should move the TMS
};

internal void
initialize_jtag_command_buffer(JTAGCommandBuffer *cb, u8 *base, u32 size)
{
    cb->base = base;
    cb->used = 0;
    cb->size = size;
    cb->current_state = RESET;

    // initializing these values to a nonsense value
    cb->current_APBANKSEL = ~0;
    cb->current_APSEL = ~0;
    cb->current_DPBANKSEL = ~0;
    cb->current_A = ~0;

    // there might be a smarter way of makes this table
    // i.e divide the stm into blocks(ir-block, dr-block), and embed the TMS sequence of exiting from one block into the enum value ,
    // but this is the initialization code so we don't really care for now
    for(u32 index = 0;
            index < 256;
            ++index)
    {
        cb->routing_table[index] = 0;
    }

    // top 4 bits of the index = dest, bottom 4 bits = current
    // TODO(gh) error-prone?
    cb->routing_table[(SHIFT_IR << 4) | RESET] = 0b0010;
    cb->routing_count[(SHIFT_IR << 4) | RESET] = 4;

    cb->routing_table[(SHIFT_DR << 4) | RESET] = 0b0110;
    cb->routing_count[(SHIFT_DR << 4) | RESET] = 4;

    cb->routing_table[(SHIFT_IR << 4) | EXIT1_DR] = 0b00111;
    cb->routing_count[(SHIFT_IR << 4) | EXIT1_DR] = 5;

    cb->routing_table[(SHIFT_DR << 4) | EXIT1_IR] = 0b0011;
    cb->routing_count[(SHIFT_DR << 4) | EXIT1_IR] = 4;

    cb->routing_table[(SHIFT_IR << 4) | EXIT2_DR] = 0b00111;
    cb->routing_count[(SHIFT_IR << 4) | EXIT2_DR] = 5;

    cb->routing_table[(SHIFT_DR << 4) | EXIT2_IR] = 0b0011;
    cb->routing_count[(SHIFT_DR << 4) | EXIT2_IR] = 4;

    // cb->routing_table[] = ;
    // cb->routing_count[] = ;
}

internal void
push_DPACC_read(JTAGCommandBuffer *cb, u32 a)
{
}

internal void
push_DPACC_write(JTAGCommandBuffer *cb, u32 DPBANKSEL, u32 data)
{
    u8 routing = cb->routing_table[(SHIFT_IR << 4) | cb->current_state];
    u8 routing_count = cb->routing_count[(SHIFT_IR << 4) | cb->current_state];

    // TODO(gh) for now this doesn't check any invalid routing
    if(routing)
    {
        cb->base[cb->used++] = 0x4a;
        cb->base[cb->used++] = routing_count - 1;
        cb->base[cb->used++] = routing; 
        cb->current_state = SHIFT_IR;
    }

    // shift in 4 bits to update the instruction and exit
    cb->base[cb->used++] = 0x1b; // shift in
    cb->base[cb->used++] = 0x02;
    cb->base[cb->used++] = (IR_DPACC & 0x7);
    cb->base[cb->used++] = 0x4a; // exit
    cb->base[cb->used++] = 0x0;
    cb->base[cb->used++] = (((IR_DPACC>>3)&1) << 7) | 1;

    if(routing)

    // for simplicity we check the command buffer overflow once at the end
    assert(cb->used <= cb->size);
    
    // TODO(gh) routing 
    /*
    goto_reset,
    goto_shift_ir_from_reset,

    shift_in_4bits_and_exit(IR_DPACC),
    goto_shift_dr_from_exit_ir,
    */
}

internal void
push_APACC_read(JTAGCommandBuffer *cb)
{
}

internal void
push_APACC_write(JTAGCommandBuffer *cb)
{
}

