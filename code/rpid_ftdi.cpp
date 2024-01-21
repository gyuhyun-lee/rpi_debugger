#include "rpid_ftdi.h"

internal u32
ftdi_write(FTDIApi *ftdi_api, u8 *buffer, u32 byte_count)
{
    u32 bytes_written;
    assert(ftdi_api->ft_Write(ftdi_api->ft_handle, buffer, byte_count, &bytes_written) == FT_OK);
    assert(byte_count == bytes_written);

    return bytes_written;
}

internal void 
ftdi_receive_queue_should_be_empty(FTDIApi *ftdi_api)
{
    u32 remaining_bytes;
    assert(ftdi_api->ft_GetQueueStatus(ftdi_api->ft_handle, &remaining_bytes) == FT_OK);
    assert(remaining_bytes == 0);
}
