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
