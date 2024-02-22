#include "rpid_usb.h"

// returns 16-byte command status from the interface
internal void
macos_get_usb_command_status(RP2040USBInterface *usb_interface, u32 *read_buffer)
{
    IOUSBInterfaceInterface **macos_usb_interface = usb_interface->macos_usb_interface;
    IOUSBDevRequest command_packet = {};
    command_packet.bmRequestType = 0b11000001; // request status from USB interface
    command_packet.bRequest = 0x42;
    command_packet.wValue = 0;
    command_packet.wIndex = 1; // in this case, index of the interface
    command_packet.wLength = 0; // always 16 bytes
    command_packet.pData = (void *)read_buffer;

    IOReturn r = (*macos_usb_interface)->ControlRequest(macos_usb_interface, 0, &command_packet);
    assert(r == kIOReturnSuccess);
}

internal b32
macos_write_to_bulk_out_endpoint(RP2040USBInterface *usb_interface, void *buffer, u32 byte_count)
{
    b32 result = false;
    IOUSBInterfaceInterface **macos_usb_interface = usb_interface->macos_usb_interface;

    u64 start_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    while(!result)
    {
        if((*macos_usb_interface)->WritePipeTO(macos_usb_interface, usb_interface->bulk_out_endpoint_index, buffer, byte_count, 10, 20) == kIOReturnSuccess)
        {
            result = true;
            break;
        }

        u64 end_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        u64 time_passed_ms = (((end_ns - start_ns) / 1000000));
        if(time_passed_ms > 100) // wait for 1 milliseconds
        {
            // TODO(gh) log
            printf("could not do bulk write for %llums", time_passed_ms);
            assert(0);
            break;
        }
    }

    return result;
}

internal b32
macos_read_from_bulk_in_endpoint(RP2040USBInterface *usb_interface, u32 address, void *read_buffer, u32 bytes_to_read, u32 token = 0xdcdcdcdc)
{
    b32 result = false;

    u64 start_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    while(!result)
    {
        // write the 'read command' to the bulk out endpoint
        PicoBootCommand read_command = {};
        read_command.magic = PICOBOOT_COMMAND_MAGIC_VALUE;
        read_command.token = token;
        read_command.command_ID = 0x84;
        read_command.command_size = 0x08;
        read_command.pad0 = 0;
        read_command.transfer_length = bytes_to_read;
        read_command.args0 = address; // address
        read_command.args1 = bytes_to_read;
        read_command.args2 = 0;
        read_command.args3 = 0;
        // assert(sizeof(PicoBootCommand) == 32);

        if(macos_write_to_bulk_out_endpoint(usb_interface, &read_command, sizeof(PicoBootCommand)))
        {
            IOUSBInterfaceInterface **macos_usb_interface = usb_interface->macos_usb_interface;
            u32 bytes_read = bytes_to_read;

            IOReturn kr = (*macos_usb_interface)->ReadPipeTO(macos_usb_interface, usb_interface->bulk_in_endpoint_index, read_buffer, &bytes_read, 1, 1);
            if(kr == kIOReturnSuccess)
            {
                result = true;
                break;
            }
        }

        u64 end_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        u64 time_passed_ms = (((end_ns - start_ns) / 1000000));
        if(time_passed_ms > 100) // wait for 1 milliseconds
        {
            // TODO(gh) log
            printf("could not do bulk read for %llums", time_passed_ms);
            assert(0);
            break;
        }
    }

    return result;
}


/*
   bulk in packet
   success
0000   01 01 28 01 20 00 00 00 00 00 00 00 00 00 00 00
0010   d8 04 00 00 00 00 00 00 00 00 10 00 01 01 84 02
0020   ff 00 00 00 8a 2e 03 00 00 1f 04 20 eb 00 00 00
0030   35 00 00 00 31 00 00 00 4d 75 01 03 7a 00 c4 00
0040   1d 00 00 00 00 23 02 88
   

   failed 
0000   01 01 28 01 00 00 00 00 d6 02 00 e0 00 00 00 00
0010   da 04 00 00 00 00 00 00 00 00 10 00 01 01 84 02
0020   ff 00 00 00 8a 2e 03 00
*/

/*
   bulk out packet
   success
0000   01 01 28 01 20 00 00 00 00 00 00 00 00 00 00 00
0010   d7 04 00 00 00 00 00 00 00 00 10 00 01 01 03 02
0020   ff 00 00 00 8a 2e 03 00 0b d1 1f 43 dc dc dc dc
0030   84 08 00 00 20 00 00 00 00 00 00 00 20 00 00 00
0040   00 00 00 00 00 00 00 00
   
fail
0000   01 01 28 01 20 00 00 00 00 00 00 00 00 00 00 00
0010   d9 04 00 00 00 00 00 00 00 00 10 00 01 01 03 02
0020   ff 00 00 00 8a 2e 03 00 0b d1 1f 43 dc dc dc dc
0030   84 08 00 00 20 00 00 00 00 00 00 00 20 00 00 00
0040   00 00 00 00 00 00 00 00



*/

