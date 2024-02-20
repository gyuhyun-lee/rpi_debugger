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
    command_packet.wIndex = 1; // interface index, should be 1
    command_packet.pData = (void *)read_buffer;
    command_packet.wLength = 16; // always 16 bytes

    IOReturn r = (*macos_usb_interface)->ControlRequest(macos_usb_interface, 0, &command_packet);
    assert(r == kIOReturnSuccess);
}

internal void
macos_write_to_bulk_out_endpoint(RP2040USBInterface *usb_interface, void *buffer, u32 byte_count)
{
    IOUSBInterfaceInterface **macos_usb_interface = usb_interface->macos_usb_interface;

    // TODO(gh) be more specific about retry / TO 
    IOReturn r;
    for(u32 i = 0;
            i < 4;
            i++)
    {
        r = (*macos_usb_interface)->WritePipeTO(macos_usb_interface, usb_interface->bulk_out_endpoint_index, buffer, byte_count, 10, 20);

        u32 read_buffer[4] = {};
        macos_get_usb_command_status(usb_interface, read_buffer);

        if(r == kIOReturnSuccess)
        {
            break;
        }
    }

    // TODO(gh) log
    assert(r == kIOReturnSuccess);
}

internal void
macos_read_from_bulk_in_endpoint(RP2040USBInterface *usb_interface, u32 address, void *read_buffer, u32 bytes_to_read)
{
    // write the 'read command' to the bulk out endpoint
    PicoBootCommand read_command = {};
    read_command.magic = PICOBOOT_COMMAND_MAGIC_VALUE;
    read_command.token = 0xdcdcdcdc;
    read_command.command_ID = 0x84;
    read_command.command_size = 0x08;
    read_command.pad0 = 0;
    read_command.transfer_length = bytes_to_read;
    read_command.args[0] = address; // address
    read_command.args[1] = bytes_to_read;
    macos_write_to_bulk_out_endpoint(usb_interface, &read_command, sizeof(PicoBootCommand));

    IOUSBInterfaceInterface **macos_usb_interface = usb_interface->macos_usb_interface;
    u32 bytes_read = bytes_to_read;
    // TODO(gh) be more specific about retry / TO 
    IOReturn kr;
    for(u32 i = 0;
            i < 4;
            i++)
    {
        kr = (*macos_usb_interface)->ReadPipeTO(macos_usb_interface, usb_interface->bulk_in_endpoint_index, read_buffer, &bytes_read, 10, 20);

        u32 read_buffer[4] = {};
        macos_get_usb_command_status(usb_interface, read_buffer);
        if(kr == kIOReturnSuccess)
        {
            break;
        }
    }

    // TODO(gh) log
    assert(kr == kIOReturnSuccess);
    assert(bytes_read == bytes_to_read);
}
