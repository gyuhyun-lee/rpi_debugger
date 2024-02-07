#include "rpid_jtag_command_buffer.h"

// TODO(gh) change this command buffer to be cable independent(for now this depends on the FTDI cable)

#define routing_table_entry(route, bit_count) ((bit_count << 12) | route)

// execute all commands inside the buffer while retaining the current state
internal void
flush_jtag_command_buffer(JTAGCommandBuffer *cb, FTDIApi *ftdi_api)
{
    ftdi_write(ftdi_api, cb->base, cb->used);
    cb->used = 0;
}

internal void
initialize_jtag_command_buffer(JTAGCommandBuffer *cb, u8 *base, u32 size)
{
    cb->base = base;
    cb->used = 0;
    cb->size = size;
    cb->current_state = RESET;

    cb->current_SELECT = ~0;
    cb->current_IR = IR_NULL; // IR_IDCODE; // TODO(gh) ADI doc says that the instruction register becomes IDCODE in a reset state?

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
    cb->routing_table[(SHIFT_IR << 4) | RESET] = routing_table_entry(0b00110, 5);
    cb->routing_table[(SHIFT_DR << 4) | RESET] = routing_table_entry(0b0010, 4);

    cb->routing_table[(SHIFT_DR << 4) | IDLE] = routing_table_entry(0b001, 3);
    cb->routing_table[(SHIFT_IR << 4) | IDLE] = routing_table_entry(0b011, 3);

    cb->routing_table[(SHIFT_IR << 4) | EXIT1_DR] = routing_table_entry(0b00111, 5);
    cb->routing_table[(SHIFT_DR << 4) | EXIT1_DR] = routing_table_entry(0b0011, 4);
    cb->routing_table[(IDLE << 4) | EXIT1_DR] = routing_table_entry(0b01, 2);

    cb->routing_table[(SHIFT_DR << 4) | EXIT1_IR] = routing_table_entry(0b0011, 4);
    cb->routing_table[(SHIFT_IR << 4) | EXIT2_DR] = routing_table_entry(0b00111, 5);
    cb->routing_table[(SHIFT_DR << 4) | EXIT2_IR] = routing_table_entry(0b0011, 4);

    // cb->routing_table[] = ;
    // cb->routing_count[] = ;

    // reset the state machine(will not reset until we flush the command buffer)
    cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM;
    cb->base[cb->used++] = 5-1;
    cb->base[cb->used++] = 0b11111;
}

internal void
push_move_state_machine(JTAGCommandBuffer *cb, JTAGState dest)
{
    if(dest != RESET)
    {
        u16 routing_table_entry = cb->routing_table[(dest << 4) | cb->current_state];
        u32 routing = routing_table_entry & 0xfff; // ubfx
        u32 routing_bit_count = routing_table_entry >> 12; // ubfx

        // TODO(gh) for now this doesn't check whether the routing is valid or invalid
        if(routing)
        {
            cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM;
            cb->base[cb->used++] = routing_bit_count - 1;
            cb->base[cb->used++] = routing; 
            cb->current_state = dest;
        }
        else
        {
            // check if the routing was invalid - we should probably add this routing as our table entry.
            assert(cb->current_state == dest);

            // TODO(gh) ADI doc says that the instruction register becomes IDCODE in a reset state?
            cb->current_IR = IR_NULL;
        }
    }
    else
    {
        // we can always go to RESET state by holding the TMS line up for 5 cycles
        cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM;
        cb->base[cb->used++] = 5-1;
        cb->base[cb->used++] = 0b11111; 
        cb->current_state = dest;
    }

    assert(cb->used <= cb->size);
}

// for 4 bit IR
internal void
push_update_IR4(JTAGCommandBuffer *cb, IR4Type new_IR)
{
    if(cb->current_IR != new_IR)
    {
        push_move_state_machine(cb, SHIFT_IR);

        // shift in 4 bits to update the instruction and exit
        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; // shift in
        cb->base[cb->used++] = 3-1;
        cb->base[cb->used++] = (new_IR & 0x7);
        cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM; // last bit + exit
        cb->base[cb->used++] = 1-1;
        cb->base[cb->used++] = (((new_IR>>3)&1) << 7) | 1;

        cb->current_state = EXIT1_IR;
        cb->current_IR = new_IR;
    }
}

// TODO(gh) finish this one
internal void
push_DPACC_read(JTAGCommandBuffer *cb, u32 A, u32 DPBANKSEL = 0)
{
    push_update_IR4(cb, IR_DPACC);

#if 1
    // only for DPv1 & 2
    if((cb->current_SELECT & 0xf) != DPBANKSEL)
    {
        push_move_state_machine(cb, SHIFT_DR);

        // update DPBANKSEL while preserving the rest of the bits
        cb->current_SELECT &= ~(0xf); 
        cb->current_SELECT |= DPBANKSEL;

        u8 byte0 = (u8)(cb->current_SELECT & 0xff); // ubfx
        u8 byte3 = (u8)((cb->current_SELECT >> 24) & 0xff); // ubfx

        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS;
        cb->base[cb->used++] = 2;
        cb->base[cb->used++] = (0x8 >> 2) << 1; // write to SELECT
        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BYTES;
        cb->base[cb->used++] = 3-1; // length low
        cb->base[cb->used++] = 0; // length high
        cb->base[cb->used++] = byte0; // byte 0
        cb->base[cb->used++] = 0; // byte 1 is always 0
        cb->base[cb->used++] = 0; // byte 2 is always 0
        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; // for byte 3, the last bit should be clocked in with the TMS bit
        cb->base[cb->used++] = 7-1; // 7 bits
        cb->base[cb->used++] = byte3 & 0x7f;
        cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM;
        cb->base[cb->used++] = 1-1; // 1
        cb->base[cb->used++] = (byte3 & 0x80) | 1;
        cb->current_state = EXIT1_DR;
    }
#endif

    push_move_state_machine(cb, SHIFT_DR);

    // update A and re-try
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS;
    cb->base[cb->used++] = 3-1;
    cb->base[cb->used++] = ((A>>2) << 1) | DPACC_read;
    // TODO(gh) use the TDI byte instruction here?
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 7-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM; // exit
    cb->base[cb->used++] = 1-1;
    cb->base[cb->used++] = 1;
    cb->current_state = EXIT1_DR;

    // re-scan
    push_move_state_machine(cb, SHIFT_DR);
    // TODO(gh) we can pipeline other DPACC read/write with this one
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 3-1;
    cb->base[cb->used++] = (1 << 7); // also mark this one as read, so that we won't accidentally update the register
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 7-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS; // read 1 bit and exit
    cb->base[cb->used++] = 1-1;
    cb->base[cb->used++] = 1;
    cb->current_state = EXIT1_DR;

    assert(cb->used <= cb->size);
}

internal void
push_DPACC_write(JTAGCommandBuffer *cb, u32 data, u32 A, u32 DPBANKSEL = 0)
{
    push_update_IR4(cb, IR_DPACC);

    if(A != 0x8)
    {
        // for DPv1 & 2, check whether we should update the DPBANKSEL
        if((cb->current_SELECT & 0xf) != DPBANKSEL)
        {
            push_move_state_machine(cb, SHIFT_DR);

            // update DPBANKSEL while preserving the rest of the bits
            u32 new_SELECT = (cb->current_SELECT & ~(0xf)) | DPBANKSEL;

            u8 byte0 = (u8)(new_SELECT & 0xff); // ubfx
            u8 byte3 = (u8)((new_SELECT >> 24) & 0xff); // ubfx

            cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS;
            cb->base[cb->used++] = 3-1;
            cb->base[cb->used++] = (0x8 >> 2) << 1; // write to SELECT
            cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BYTES;
            cb->base[cb->used++] = 3-1; // length low
            cb->base[cb->used++] = 0; // length high
            cb->base[cb->used++] = byte0; // byte 0
            cb->base[cb->used++] = 0; // byte 1 is always 0
            cb->base[cb->used++] = 0; // byte 2 is always 0
            cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; // for byte 3, the last bit should be clocked in with the TMS bit
            cb->base[cb->used++] = 7-1; // 7 bits
            cb->base[cb->used++] = byte3 & 0x7f;
            cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM;
            cb->base[cb->used++] = 1-1; // 1
            cb->base[cb->used++] = (byte3 & 0x80) | 1;

            cb->current_state = EXIT1_DR;
            cb->current_SELECT = new_SELECT;
        }
    }
    else
    {
        // thsi function was trying to update SELECT,
        // so we should update the 'data' with new DPBANKSEL
        data &= ~(0xf);
        data |= DPBANKSEL;
    }

    push_move_state_machine(cb, SHIFT_DR);

    // write the DR and exit
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS;
    cb->base[cb->used++] = 3-1;
    cb->base[cb->used++] = ((A>>2) << 1) | DPACC_write;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BYTES;
    cb->base[cb->used++] = 3-1; // length low
    cb->base[cb->used++] = 0; // length high
    cb->base[cb->used++] = (u8)(data & 0xff); // byte 0
    cb->base[cb->used++] = (u8)((data >> 8) & 0xff); // byte 1
    cb->base[cb->used++] = (u8)((data >> 16) & 0xff); // byte 2
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 7-1;
    cb->base[cb->used++] = (u8)((data >> 24) & 0x7f);
    cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM; // exit
    cb->base[cb->used++] = 1-1;
    cb->base[cb->used++] = (u8)((data>>31) << 7) | 1;

    cb->current_state = EXIT1_DR;

    assert(cb->used <= cb->size);
}

internal void
push_APACC_read(JTAGCommandBuffer *cb, u32 APSEL, u32 APBANKSEL_A)
{
    u32 new_SELECT = (APSEL << 24) | (APBANKSEL_A & 0xf0);
    if((cb->current_SELECT & 0xff0000f0) != new_SELECT) // this is to preserve DPBANKSEL
    {
        cb->current_SELECT &= 0x0000000f; // preserve DPBANKSEL
        cb->current_SELECT |= new_SELECT;

        // update SELECT
        push_DPACC_write(cb, cb->current_SELECT, A_SELECT);
    }

#if 1
    u32 A = APBANKSEL_A & 0xf; 

    push_update_IR4(cb, IR_APACC);

    push_move_state_machine(cb, SHIFT_DR);

    // update A and re-try
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS;
    cb->base[cb->used++] = 3-1;
    cb->base[cb->used++] = ((A>>2) << 1) | DPACC_read;
    // TODO(gh) use the TDI byte instruction here?
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 7-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM; // exit
    cb->base[cb->used++] = 1-1;
    cb->base[cb->used++] = 1;
    cb->current_state = EXIT1_DR;

    // TODO(gh) only works for IDR register read
    push_move_state_machine(cb, IDLE);

    // re-scan
    push_move_state_machine(cb, SHIFT_DR);
    // TODO(gh) we can pipeline other DPACC read/write with this one
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 3-1;
    cb->base[cb->used++] = (1 << 7); // also mark this one as read, so that we won't accidentally update the register
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 7-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS; // read 1 bit and exit
    cb->base[cb->used++] = 1-1;
    cb->base[cb->used++] = 1;
    cb->current_state = EXIT1_DR;
#endif

    push_move_state_machine(cb, RESET);

    assert(cb->used <= cb->size);
}


// IDCODE should be 0x4ba00477 for raspberry pi 3 b+.
internal void
push_test_IDCODE(JTAGCommandBuffer *cb)
{
    push_update_IR4(cb, IR_IDCODE);

    push_move_state_machine(cb, SHIFT_DR);

    // IDCODE is a 32-bit scan chain
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = 0;
    cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM;
    cb->base[cb->used++] = 1-1;
    cb->base[cb->used++] = 1;
    cb->current_state = EXIT1_DR;

    push_move_state_machine(cb, RESET);
}

internal void
push_test_RDBUFF(JTAGCommandBuffer *cb)
{
    push_DPACC_read(cb, 0xC, 0x4);
}

internal void
push_test_IDR0(JTAGCommandBuffer *cb)
{
    push_APACC_read(cb, 0, 0xfc);
}

#if 0
// read & write the same register 1000 times to see if we'll ever get the wait bit set
internal void
push_test_multiple_DPACC(JTAGCommandBuffer *cb)
{
    // update the instruction
    push_move_state_machine(cb, SHIFT_IR);
    push_update_IR4(cb, IR_DPACC); 

    for(u32 i = 0;
            i < 1000;
            ++i)
    {
        // write 
        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS;
        cb->base[cb->used++] = 3-1;
        cb->base[cb->used++] = ((A_SELECT>>2) << 1) | DPACC_write;

        // read
        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
        cb->base[cb->used++] = 3-1;
        cb->base[cb->used++] = 0;
        cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM;
        cb->base[cb->used++] = 1-1;
        cb->base[cb->used++] = 1;
    }
}
#endif


/*
internal void
push_DPACC_readwrite()
{
}

internal void
push_APACC_write(JTAGCommandBuffer *cb)
{
}
*/


