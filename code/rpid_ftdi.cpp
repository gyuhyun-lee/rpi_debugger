#include "rpid_ftdi.h"

internal u32
ftdi_write(FTDIApi *ftdi_api, u8 *buffer, u32 byte_count)
{
    u32 bytes_written;
    assert(ftdi_api->ft_Write(ftdi_api->handle, buffer, byte_count, &bytes_written) == FT_OK);
    assert(byte_count == bytes_written);

    return bytes_written;
}

internal void
ftdi_read(FTDIApi *ftdi_api, u8 *buffer, u32 bytes_to_read)
{
    u32 bytes_read;
    assert(ftdi_api->ft_Read(ftdi_api->handle, buffer, bytes_to_read, &bytes_read) == FT_OK);
    assert(bytes_to_read == bytes_read);
}

internal void
ftdi_flush_receive_fifo(FTDIApi *ftdi_api)
{
    // TODO(gh) according to the C232HM cable spec sheet, this cable has 1KB receive/transmit buffer.
    // however, according to the AN_135 FTDI MPSSE Basics doc, it's only using 8bytes to flush the fifo.
    // which one is correct?
    u8 buffer[8];
    u32 bytes_in_fifo;
    assert(ftdi_api->ft_GetQueueStatus(ftdi_api->handle, &bytes_in_fifo) == FT_OK);

    assert(bytes_in_fifo <= array_count(buffer));

    if(bytes_in_fifo > 0)
    {
        u32 bytes_read;
        assert(ftdi_api->ft_Read(ftdi_api->handle, buffer, bytes_in_fifo, &bytes_read) == FT_OK);
        assert(bytes_in_fifo == bytes_read);
    }
}

// TODO(gh) combine this with ftdi_read, since we should not read from the receive buffer
// is there is not enough bytes inside the queue anyway?
internal void
ftdi_wait_receive_queue(FTDIApi *ftdi_api, u32 byte_count_to_wait)
{
    u32 queue_check = 0;
    u32 bytes_inside_receive_queue = 0;
    while(bytes_inside_receive_queue < byte_count_to_wait)
    {
        if((queue_check & 511) == 0)
        {
            // TODO(gh) check for timeout
        }

        assert(ftdi_api->ft_GetQueueStatus(ftdi_api->handle, &bytes_inside_receive_queue) == FT_OK);

        queue_check++;
    }
}

internal void 
ftdi_receive_queue_should_be_empty(FTDIApi *ftdi_api)
{
    u32 remaining_bytes;
    assert(ftdi_api->ft_GetQueueStatus(ftdi_api->handle, &remaining_bytes) == FT_OK);
    assert(remaining_bytes == 0);
}

#if 0
/*
   IDCODE should be 0x4ba00477 for raspberry pi 3 b+.

   bit 0 should always be 1
   bits [11:1] are the designer ID, which should be 0x43b(page B3-104 of ADIv5.0-5.2 document). In total, bits[11:0] should be 0x477
   bits [27:12] are the part number, which should be 0xBA00, which stands for a JTAG-DP designed by ARM(page 3-4 CoreSight Technology System Design Guide)
   bits [31:28] are the version number which is IMPLEMENTATION DEFINED.
 */
internal void
ftdi_test_IDCODE(FTDIApi *ftdi_api)
{
    u8 commands[] = 
    {
        goto_reset,
        goto_shift_ir_from_reset,
        shift_in_4bits_and_exit(IR_IDCODE),

        goto_shift_dr_from_exit_ir,
        shift_out_32bits_and_exit,
        goto_reset,
    };
    ftdi_write(ftdi_api, commands, array_count(commands));

    ftdi_wait_receive_queue(ftdi_api, 4);

    u8 receive_buffer[4] = {};
    ftdi_read(ftdi_api, receive_buffer, 4);
    ftdi_receive_queue_should_be_empty(ftdi_api);

    assert((receive_buffer[0] == 0x77) && 
            (receive_buffer[1] == 0x04) &&
            (receive_buffer[2] == 0xa0) &&
            (receive_buffer[3] == 0x4b));
}


/*
   DPIDR(debug port identification register) - only present in DPv1 & DPv2

   32 bit in total
   bit 0 - RAO
   bits[11:1] should be same as IDCODE
   bits[15:12] 
   1 - DPv1
   2 - DPv2
   all the other values are reserved 

   ...
*/
internal void
ftdi_test_DPIDR(FTDIApi *ftdi_api)
{
    u8 commands[] = 
    {
        goto_reset,
        // first update the ir to dpacc
        goto_shift_ir_from_reset, 
        shift_in_4bits_and_exit(IR_DPACC),

        // only write the RnW(bits[1:0]) & A value(bits[3:2])
        goto_shift_dr_from_exit_ir, 
        shift_in_35bits_and_exit(DPACC_read, 0, 0),

        // we need another scan to read the result
        goto_shift_dr_from_exit_dr,
        shift_out_35bits_and_exit, 


        goto_reset,
    };
    ftdi_write(ftdi_api, commands, array_count(commands));

    ftdi_wait_receive_queue(ftdi_api, 5);

    u8 receive_buffer[5] = {};
    ftdi_read(ftdi_api, receive_buffer, 5);
    ftdi_receive_queue_should_be_empty(ftdi_api);
}


/*
    IDR is the AP identification register that is located at 0xFC.
    Each AP is required to have IDR.
*/
internal void
ftdi_test_IDR(FTDIApi *ftdi_api)
{
    u8 commands[] = 
    {
        goto_reset,

        // update SELECT
        goto_shift_ir_from_reset, 
        shift_in_4bits_and_exit(IR_DPACC),
        goto_shift_dr_from_exit_ir, 
        shift_in_35bits_and_exit(DPACC_write, DR_SELECT, SELECT_APACC(0, 0xf)),
        
        // read the AP register
        goto_shift_ir_from_exit_dr,
        shift_in_4bits_and_exit(IR_APACC),
        goto_shift_dr_from_exit_ir,
        shift_in_35bits_and_exit(APACC_read, 0xC, 0),

        // we need another scan to read the result

        goto_shift_dr_from_exit_dr,
        shift_out_35bits_and_exit,

        // debug, retrying the read so that 
        // goto_shift_dr_from_exit_dr,
        //shift_out_35bits_and_exit, 

#if 0
        // debug, get the ctrl/stat register
        goto_shift_ir_from_exit_dr,
        shift_in_4bits_and_exit(IR_DPACC),
        goto_shift_dr_from_exit_ir,
        shift_in_35bits_and_exit(DPACC_write, DR_CTRL_STAT, 0),
        goto_shift_dr_from_exit_dr,
        shift_out_35bits_and_exit,
#endif
        
        goto_reset,
    };
    ftdi_write(ftdi_api, commands, array_count(commands));
    ftdi_wait_receive_queue(ftdi_api, 5);

    u8 receive_buffer[5] = {};
    ftdi_read(ftdi_api, receive_buffer, 5);
    ftdi_receive_queue_should_be_empty(ftdi_api);

    // TODO(gh) this should fire because we're getting the right data
    // but with the 'wait' bit set
    assert(((receive_buffer[0] & (1<<5)) == 0) &&
            (receive_buffer[1] == 0x77) && 
            (receive_buffer[2] == 0x04) &&
            (receive_buffer[3] == 0xa0) &&
            (receive_buffer[4] == 0x4b));
}
#endif








