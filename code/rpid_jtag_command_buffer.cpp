#include "rpid_jtag_command_buffer.h"

// TODO(gh) do 100 DPACC read/write, check the CTRL/STAT register to see if any of the bit is set

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
    cb->current_IR = IR_IDCODE;

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
    cb->routing_table[(SHIFT_IR << 4) | RESET] = routing_table_entry(0b0010, 4);
    cb->routing_table[(SHIFT_DR << 4) | RESET] = routing_table_entry(0b0110, 4);
    cb->routing_table[(SHIFT_IR << 4) | EXIT1_DR] = routing_table_entry(0b00111, 5);
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
    }

    assert(cb->used <= cb->size);
}

// for 4 bit IR
internal void
push_update_IR4(JTAGCommandBuffer *cb, IR4Type new_IR)
{
    if(cb->current_IR != IR_DPACC)
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

internal void
push_DPACC_read(JTAGCommandBuffer *cb, u32 A, u32 DPBANKSEL = 0)
{
    push_update_IR4(cb, IR_DPACC);

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
        cb->base[cb->used++] = 3-1; // 3 bytes
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

    push_move_state_machine(cb, SHIFT_DR);

    u32 current_A = (cb->current_SELECT >> 8) & 0xf;
    if(current_A != A)
    {
        // update the A 

        // update the bottom 3 bits
        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS;
        cb->base[cb->used++] = 3-1;
        cb->base[cb->used++] = ((A>>2) << 1) | DPACC_read;

        // shift in 32 garbage bits and exit
        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BYTES;
        cb->base[cb->used++] = 3-1;
        cb->base[cb->used++] = 0; // byte 0
        cb->base[cb->used++] = 0; // byte 1
        cb->base[cb->used++] = 0; // byte 2
        cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM; // exit
        cb->base[cb->used++] = 1-1;
        cb->base[cb->used++] = 1;

        cb->current_state = EXIT1_DR;
        cb->current_SELECT = (cb->current_SELECT & 0xff0000ff) | (A << 8); // TODO(gh) only clear the A part
    }

    push_move_state_machine(cb, SHIFT_DR);

    // TODO(gh) we can pipeline other DPACC read/write with this one
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_OUT_BITS;
    cb->base[cb->used++] = 3-1;
    cb->base[cb->used++] = 1; // also mark this one as read, so that we won't accidentally update the register
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

    assert(cb->used <= cb->size);
}

internal void
push_DPACC_write(JTAGCommandBuffer *cb, u32 data, u32 A, u32 DPBANKSEL = 0)
{
    push_update_IR4(cb, IR_DPACC);

    // for DPv1 & 2, check whether we should update the DPBANKSEL
    if((cb->current_SELECT & 0xf) != DPBANKSEL)
    {
        push_move_state_machine(cb, SHIFT_DR);

        // update DPBANKSEL while preserving the rest of the bits
        u32 new_SELECT = (cb->current_SELECT & ~(0xf)) | DPBANKSEL;

        u8 byte0 = (u8)(new_SELECT & 0xff); // ubfx
        u8 byte3 = (u8)((new_SELECT >> 24) & 0xff); // ubfx

        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS;
        cb->base[cb->used++] = 2;
        cb->base[cb->used++] = (0x8 >> 2) << 1; // write to SELECT
        cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BYTES;
        cb->base[cb->used++] = 3-1; // 3 bytes
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

    push_move_state_machine(cb, SHIFT_DR);

    // write the DR and exit
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS;
    cb->base[cb->used++] = 3-1;
    cb->base[cb->used++] = ((A>>2) << 1) | DPACC_write;
    // TODO(gh) use the TDI byte instruction here?
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = (u8)(data & 0xff);
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = (u8)((data >> 8) & 0xff);
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 8-1;
    cb->base[cb->used++] = (u8)((data >> 16) & 0xff);
    cb->base[cb->used++] = FTDI_COMMAND_SHIFT_IN_BITS; 
    cb->base[cb->used++] = 7-1;
    cb->base[cb->used++] = (u8)((data >> 16) & 0x7f);
    cb->base[cb->used++] = FTDI_COMMAND_MOVE_STM; // exit
    cb->base[cb->used++] = 1-1;
    cb->base[cb->used++] = (u8)(((data>>31) & 1) << 7) | 1;

    cb->current_state = EXIT1_DR;
    // TODO(gh) find out what happens if we do DPACC with write and then read the register right away. can we read from it without chaing the address?
    // if we can do that, we should also preserve the information about A 
    cb->current_SELECT = (cb->current_SELECT & 0xff0000ff) | (A << 8);

    assert(cb->used <= cb->size);
}

/*
internal void
push_DPACC_readwrite()
{
}

internal void
push_APACC_read(JTAGCommandBuffer *cb)
{
}

internal void
push_APACC_write(JTAGCommandBuffer *cb)
{
}
*/


