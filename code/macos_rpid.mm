// TODO(gh) Find out what is the difference between import and include in objc?
#import <Cocoa/Cocoa.h> 
#import <CoreGraphics/CoreGraphics.h> 
#import <mach/mach_time.h> // mach_absolute_time
#import <stdio.h> // printf for debugging purpose
#import <sys/stat.h>
#import <libkern/OSAtomic.h>
#import <pthread.h>
#import <semaphore.h>
#import <Carbon/Carbon.h>
#import <dlfcn.h> // dlsym
#import <metalkit/metalkit.h>
#import <metal/metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
// USB
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUsbLib.h>
#import <IOKit/IOCFPlugIn.h>

// need to undef these from the macos framework 
// so that we can define these ourselves
#undef internal
#undef assert

#include "rpid_types.h"
#include "rpid_intrinsic.h"
#include "rpid_platform.h"
#include "rpid_ftdi.cpp" 
#include "rpid_jtag_command_buffer.cpp"
#include "rpid_usb.cpp"
/*
   RP2040 2.4.2.8 There are no separate power domains on RP2040
   So when I read from the ctrl/stat register, both the system & debug power domain should be on? or off?

   Interpolator can be useful because we can treat it as as an extra register. i.e we can do the address + offset calculation by storing the address register inside the interpolator
   Although the rate of the clocks that the PMU is generating all the same(also same as the clk_sys), the power output(whether '1' should be 3.3v or 1.8v ... and so on) is different. 


    PMU - power management unit
    MPU - Memory protection unit 
    NVIC -  / WIC

    TODO(gh) RP2040 tests
    - RP2040 boot sequence says that at startup, it uses a 48MHZ system/usb clock. test this by big-baning one of the GPIOs up and down and then measure the timing using the logic analyzer.
 */

// TODO(gh): Get rid of global variables?
global v2 last_mouse_p;
global v2 mouse_diff;

global b32 is_running;

internal u64 
mach_time_diff_in_nano_seconds(u64 begin, u64 end, f32 nano_seconds_per_tick)
{
    return (u64)(((end - begin)*nano_seconds_per_tick));
}

PLATFORM_GET_FILE_SIZE(macos_get_file_size) 
{
    u64 result = 0;

    int File = open(filename, O_RDONLY);
    struct stat FileStat;
    fstat(File , &FileStat); 
    result = FileStat.st_size;
    close(File);

    return result;
}

PLATFORM_READ_FILE(debug_macos_read_file)
{
    PlatformReadFileResult result = {};

    int File = open(filename, O_RDONLY);
    int Error = errno;
    if(File >= 0) // NOTE : If the open() succeded, the return value is non-negative value.
    {
        struct stat FileStat;
        fstat(File , &FileStat); 
        off_t fileSize = FileStat.st_size;

        if(fileSize > 0)
        {
            // TODO/gh : no more os level allocations!
            result.size = fileSize;
            result.memory = (u8 *)malloc(result.size);
            if(read(File, result.memory, result.size) == -1)
            {
                free(result.memory);
                result.size = 0;
            }
        }

        close(File);
    }
    else
    {
        // TODO(gh) log, file doesn't exist
        assert(0);
    }

    return result;
}

PLATFORM_WRITE_ENTIRE_FILE(debug_macos_write_entire_file)
{
    int file = open(file_name, O_WRONLY|O_CREAT|O_TRUNC, S_IRWXU);

    if(file >= 0) 
    {
        if(write(file, memory_to_write, size) == -1)
        {
            // TODO(gh) : log
        }

        close(file);
    }
    else
    {
        // TODO(gh) :log
        printf("Failed to create file\n");
    }
}

PLATFORM_FREE_FILE_MEMORY(debug_macos_free_file_memory)
{
    free(memory);
}

@interface 
app_delegate : NSObject<NSApplicationDelegate>
@end
@implementation app_delegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [NSApp stop:nil];

    // NOTE(gh) Technique from GLFW, posting an empty event 
    // so that we can put the application to front 
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    NSEvent* event =
        [NSEvent otherEventWithType: NSApplicationDefined
        location: NSMakePoint(0, 0)
            modifierFlags: 0
            timestamp: 0
            windowNumber: 0
            context: nil
            subtype: 0
            data1: 0
            data2: 0];
    [NSApp postEvent: event atStart: YES];
    [pool drain];
}
@end

internal void
register_platform_key_input(PlatformInput *input, PlatformKeyID ID, b32 is_down)
{
    input->keys[ID].is_down = is_down;
}

internal void
macos_handle_event(NSApplication *app, NSWindow *window, PlatformInput *platform_input)
{
    NSPoint mouse_location = [NSEvent mouseLocation];
    NSRect frame_rect = [window frame];
    NSRect content_rect = [window contentLayoutRect];

    v2 bottom_left_p = {};
    bottom_left_p.x = frame_rect.origin.x;
    bottom_left_p.y = frame_rect.origin.y;

    v2 content_rect_dim = {}; 
    content_rect_dim.x = content_rect.size.width; 
    content_rect_dim.y = content_rect.size.height;

    v2 rel_mouse_location = {};
    rel_mouse_location.x = mouse_location.x - bottom_left_p.x;
    rel_mouse_location.y = mouse_location.y - bottom_left_p.y;

    f32 mouse_speed_when_clipped = 0.08f;
    if(rel_mouse_location.x >= 0.0f && rel_mouse_location.x < content_rect_dim.x)
    {
        mouse_diff.x = mouse_location.x - last_mouse_p.x;
    }
    else if(rel_mouse_location.x < 0.0f)
    {
        mouse_diff.x = -mouse_speed_when_clipped;
    }
    else
    {
        mouse_diff.x = mouse_speed_when_clipped;
    }

    if(rel_mouse_location.y >= 0.0f && rel_mouse_location.y < content_rect_dim.y)
    {
        mouse_diff.y = mouse_location.y - last_mouse_p.y;
    }
    else if(rel_mouse_location.y < 0.0f)
    {
        mouse_diff.y = -mouse_speed_when_clipped;
    }
    else
    {
        mouse_diff.y = mouse_speed_when_clipped;
    }

    // NOTE(gh) : MacOS screen coordinate is bottom-up, so just for the convenience, make y to be bottom-up
    mouse_diff.y *= -1.0f;

    last_mouse_p.x = mouse_location.x;
    last_mouse_p.y = mouse_location.y;

    //printf("%f, %f\n", mouse_diff.x, mouse_diff.y);

    // TODO : Check if this loop has memory leak.
    while(1)
    {
        NSEvent *event = [app nextEventMatchingMask:NSAnyEventMask
            untilDate:nil
            inMode:NSDefaultRunLoopMode
            dequeue:YES];
        if(event)
        {
            switch([event type])
            {
                case NSEventTypeKeyUp:
                case NSEventTypeKeyDown:
                {
                    b32 was_down = event.ARepeat;
                    b32 is_down = ([event type] == NSEventTypeKeyDown);

                    if((is_down != was_down) || !is_down)
                    {
                        u16 key_code = [event keyCode];
                        // printf("%d, isDown : %d, WasDown : %d\n", key_code, is_down, was_down);
                        if(key_code == kVK_Escape)
                        {
                            is_running = false;
                        }
                        else if(key_code == kVK_ANSI_W)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_MoveUp, is_down);
                        }
                        else if(key_code == kVK_ANSI_A)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_MoveLeft, is_down);
                        }
                        else if(key_code == kVK_ANSI_S)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_MoveDown, is_down);
                        }
                        else if(key_code == kVK_ANSI_D)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_MoveRight, is_down);
                        }

                        else if(key_code == kVK_LeftArrow)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_ActionLeft, is_down);
                        }
                        else if(key_code == kVK_RightArrow)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_ActionRight, is_down);
                        }
                        else if(key_code == kVK_UpArrow)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_ActionUp, is_down);
                        }
                        else if(key_code == kVK_DownArrow)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_ActionDown, is_down);
                        }

                        else if(key_code == kVK_ANSI_P)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_ToggleSimulation, is_down);
                        }
                        else if(key_code == kVK_ANSI_L)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_AdvanceSubstep, is_down);
                        }
                        else if(key_code == kVK_ANSI_K)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_FallbackSubstep, is_down);
                        }
                        else if(key_code == kVK_ANSI_O)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_AdvanceFrame, is_down);
                        }
                        else if(key_code == kVK_ANSI_I)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_FallbackFrame, is_down);
                        }

                        else if(key_code == kVK_Space)
                        {
                            register_platform_key_input(platform_input, PlatformKeyID_Shoot, is_down);
                        }

                        else if(key_code == kVK_Return)
                        {
                            if(is_down)
                            {
                                NSWindow *window = [event window];
                                // TODO : proper buffer resize here!
                                [window toggleFullScreen:0];
                            }
                        }
                    }
                }break;

            default:
            {
                [app sendEvent : event];
            }
            }
        }
        else
        {
            break;
        }
    }
} 

// NOTE(gh): returns the base path where all the folders(code, misc, data) are located
internal void
macos_get_base_path(char *dest)
{
    NSString *app_path_string = [[NSBundle mainBundle] bundlePath];
    u32 length = [app_path_string lengthOfBytesUsingEncoding: NSUTF8StringEncoding];
    unsafe_string_append(dest, 
            [app_path_string cStringUsingEncoding: NSUTF8StringEncoding],
            length);

    u32 slash_to_delete_count = 2;
    for(u32 index = length-1;
            index >= 0;
            --index)
    {
        if(dest[index] == '/')
        {
            slash_to_delete_count--;
            if(slash_to_delete_count == 0)
            {
                break;
            }
        }
        else
        {
            dest[index] = 0;
        }
    }
}

internal time_t
macos_get_last_modified_time(char *file_name)
{
    time_t result = 0; 

    struct stat file_stat = {};
    stat(file_name, &file_stat); 
    result = file_stat.st_mtime;

    return result;
}

struct MacOSGameCode
{
    void *library;
    time_t last_modified_time; // u32 bit integer
    UpdateAndRender *update_and_render;
};

internal void
macos_load_game_code(MacOSGameCode *game_code, char *file_name)
{
    // NOTE(gh) dlclose does not actually unload the dll, 
    // it only gets unloaded if there is no object that is referencing the dll.
    // TODO(gh) library should be remain open? If so, we need another way to 
    // actually unload the dll so that the fresh dll can be loaded.
    if(game_code->library)
    {
        int error = dlclose(game_code->library);
        game_code->update_and_render = 0;
        game_code->last_modified_time = 0;
        game_code->library = 0;
    }

    void *library = dlopen(file_name, RTLD_LAZY|RTLD_GLOBAL);
    if(library)
    {
        game_code->library = library;
        game_code->last_modified_time = macos_get_last_modified_time(file_name);
        game_code->update_and_render = (UpdateAndRender *)dlsym(library, "update_and_render");
    }
}

// this is a callback function from the IOKit when it detects a matching usb device.
// TODO(gh) one thing to note is that MacOS sometimes cache the device even though the device has been disconnected.
// so if the user plugs the device in and out and then in, OS might not call this because it already has the information 
// of the device. 
internal void 
raw_usb_device_added(void *refCon, io_iterator_t io_iter)
{
    io_service_t usb_device_iter = IOIteratorNext(io_iter); // returns 0 if there is no more device
    RP2040USBInterface usb_interface = {};

    IOUSBDeviceInterface        **usb_device = 0; 
    while (usb_device_iter)
    {
        IOCFPlugInInterface         **plugin_interface = 0;
        /*
           USB Device Descriptor
            offset                  size        description
            0	    bLength	        1           Size of the Descriptor in Bytes (18 bytes)
            1	    bDescriptorType	1           Device Descriptor (0x01)
            2	    bcdUSB          2           USB Specification Number which device complies too.
            4	    bDeviceClass	1	        If equal to Zero, each interface specifies it’s own class code. 
                                                If equal to 0xFF, the class code is vendor specified.
                                                Otherwise field is valid Class Code.
            5	bDeviceSubClass	    1		    Subclass Code (Assigned by USB Org)
            6	bDeviceProtocol	    1		    Protocol Code (Assigned by USB Org)
            7	bMaxPacketSize	    1		    Maximum Packet Size for Zero Endpoint. Valid Sizes are 8, 16, 32, 64
            8	idVendor	        2	        Vendor ID (Assigned by USB Org)
            10	idProduct	        2           Product ID (Assigned by Manufacturer)
            12	bcdDevice	        2	        Device Release Number
            14	iManufacturer	    1		    Index of Manufacturer String Descriptor
            15	iProduct	        1		    Index of Product String Descriptor
            16	iSerialNumber	    1	        Index of Serial Number String Descriptor
            17	bNumConfigurations	1	        Number of Possible Configurations
         */
        i32 score;

        // create an intermediate plug-in
        // TODO(gh) this function is not documented, and seems like it's hanging the xcode(but works fine on CLion)
        IOCreatePlugInInterfaceForService(usb_device_iter,
                                          kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
                                          &plugin_interface, &score);
        IOObjectRelease(usb_device_iter); // don’t need the device object after intermediate plug-in is created
        if(!plugin_interface)
        {
            printf("unable to create a plug-in\n");
            continue;
        }

        // create the device interface
        (*plugin_interface)->QueryInterface(plugin_interface,
                                                     CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
                                                     (void **)&usb_device);
        (*plugin_interface)->Release(plugin_interface); // don’t need the intermediate plug-in after device interface is created
        if (!usb_device)
        {
            printf("couldn’t create a device interface\n");
            continue;
        }
 
        // check these values for confirmation
        u16 vendor_ID;
        u16 product_ID;
        (*usb_device)->GetDeviceVendor(usb_device, &vendor_ID);
        (*usb_device)->GetDeviceProduct(usb_device, &product_ID);

        if((vendor_ID == 0x2e8a) && product_ID == 0x3)
        {
            printf("found the debug probe\n");
            if ((*usb_device)->USBDeviceOpenSeize(usb_device) != kIOReturnSuccess)
            {
                printf("unable to open the USB device with an exclusive access\n");
                (*usb_device)->Release(usb_device);

                // TODO(gh) log
                assert(0);
            }

            break;
        }

        // not RP2040, move on to the next one
        (*usb_device)->Release(usb_device);
        usb_device_iter = IOIteratorNext(io_iter); // returns 0 if there is no more device
    } // while(usb_device_iter)

    // configure device
    if(usb_device)
    {
        u8 config_count;
        (*usb_device)->GetNumberOfConfigurations(usb_device, &config_count);
        assert(config_count == 1); // there should be only 1 config, which is PICOBOOT
        if(config_count != 0)
        {
            /*
               configuration descriptor 
                offset                  size        description
                0	    bLength	        1	        Size of Descriptor in Bytes 
                1	    bDescriptorType	1           Configuration Descriptor (0x02)
                2	    wTotalLength	2	        Total length in bytes of data returned
                4	    bNumInterfaces	1	        Number of Interfaces
                5	bConfigurationValue	1	        Value to use as an argument to select this configuration
                6	iConfiguration	    1		    Index of String Descriptor describing this configuration
                7	bmAttributes	    1	        D7 Reserved, set to 1. (USB 1.0 Bus Powered)
                                                    D6 Self Powered
                                                    D5 Remote Wakeup
                                                    D4..0 Reserved, set to 0.
                8	bMaxPower	        1		    Maximum Power Consumption in 2mA units
             */
            // get the first configuration descriptor 
            IOUSBConfigurationDescriptorPtr config_desc;
            if((*usb_device)->GetConfigurationDescriptorPtr(usb_device, 0, &config_desc) == kIOReturnSuccess)
            {
                // set the device’s configuration. The configuration value is found in
                // the bConfigurationValue field of the configuration descriptor
                if((*usb_device)->SetConfiguration(usb_device, config_desc->bConfigurationValue) == kIOReturnSuccess)
                {
                    // success
                    printf("configured the usb device for the first-time\n");
                }
                else
                {
                    // TODO(gh) log
                    printf("failed to set the configuration using index %u", 0);
                    assert(0);
                }
            }
            else
            {
                // TODO(gh) log
                printf("failed to get the configuration descriptor for index %u\n", 0);
                assert(0);
            }
        }
        else
        {
            // TODO(gh) log
            printf("no configuration available for this usb device\n");
            assert(0);
        }

        // find the bulk transfer interface of the RP2040 PICOBOOT using the values that were specified in RP2040 DS
        IOUSBFindInterfaceRequest request;
        request.bInterfaceClass = 0xff; // vendor specific
        request.bInterfaceSubClass = 0;
        request.bInterfaceProtocol = 0;
        request.bAlternateSetting = kIOUSBFindInterfaceDontCare;
        io_iterator_t interface_iter;
        (*usb_device)->CreateInterfaceIterator(usb_device,
                                                &request, &interface_iter);
        io_service_t usb_interface_iter = IOIteratorNext(interface_iter);
        if(usb_interface_iter) // there should be only 1 interface, which is why this is not a while loop
        {
            //Create an intermediate plug-in
            IOCFPlugInInterface         **plugin_interface = 0;
            i32 score;
            IOCreatePlugInInterfaceForService(usb_interface_iter,
                                            kIOUSBInterfaceUserClientTypeID,
                                            kIOCFPlugInInterfaceID,
                                            &plugin_interface, &score);
            //Release the usbInterface object after getting the plug-in
            IOObjectRelease(usb_interface_iter);
            if (!plugin_interface)
            {
                printf("unable to create a plug-in\n");
                // TODO(gh) log
                assert(0);
            }

            //Now create the device interface for the interface
            /*
               interface descriptor
                offset                  size        description
                0	    bLength	        1	        Size of Descriptor in Bytes (9 Bytes)
                1	    bDescriptorType	1	        Interface Descriptor (0x04)
                2	bInterfaceNumber	1	        Number of Interface
                3	bAlternateSetting	1	        Value used to select alternative setting
                4	bNumEndpoints	    1	        Number of Endpoints used for this interface
                5	bInterfaceClass	    1	        Class Code (Assigned by USB Org)
                6	bInterfaceSubClass	1	        Subclass Code (Assigned by USB Org)
                7	bInterfaceProtocol	1	        Protocol Code (Assigned by USB Org)
                8	iInterface	        1	        Index of String Descriptor Describing this interface
            */
            IOUSBInterfaceInterface **macos_usb_interface = 0;
            (*plugin_interface)->QueryInterface(plugin_interface,
                                                CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
                                                (LPVOID *) &macos_usb_interface);
            // no longer need the intermediate plug-in
            (*plugin_interface)->Release(plugin_interface);
            if(!macos_usb_interface)
            {
                printf("unable to get usb interface desc\n");

                // TODO(gh) log
                assert(0);
            }

            // double-check the class & sub-class IDs
            u8 interface_class;
            u8 interface_subclass;
            u8 interface_number; // should be 1 for PICOBOOT
            u8 alternate_setting;
            (*macos_usb_interface)->GetInterfaceClass(macos_usb_interface,
                                                &interface_class);
            (*macos_usb_interface)->GetInterfaceSubClass(macos_usb_interface,
                                                &interface_subclass);
            (*macos_usb_interface)->GetInterfaceNumber(macos_usb_interface,
                                                        &interface_number);
            (*macos_usb_interface)->GetAlternateSetting(macos_usb_interface,
                                                        &alternate_setting);
            assert((interface_class == 0xff) && (interface_subclass == 0) && (interface_number == 1));

            if((*macos_usb_interface)->USBInterfaceOpen(macos_usb_interface) == kIOReturnSuccess)
            {
                usb_interface.macos_usb_interface = macos_usb_interface;
            }
            else
            {
                printf("unable to open the usb interface\n");
                // TODO(gh) log
                assert(0);
            }
        }
    } // if(usb_device)

    // get bulk in/out endpoint indices
    if(usb_interface.macos_usb_interface)
    {
        IOUSBInterfaceInterface **macos_usb_interface = usb_interface.macos_usb_interface;

        u8 endpoint_count = 0;
        (*macos_usb_interface)->GetNumEndpoints(macos_usb_interface, &endpoint_count);
        assert(endpoint_count == 2); // there should be only two endpoints, bulk 'in' and 'out'

        // since RP2040 DS says that we should not rely on the index of the endpoints, 
        // loop to find which endpoint is 'in' or 'out'
        for(u32 endpoint_index = 1;
                endpoint_index < (endpoint_count + 1); // disregard the 0th endpoint(control endpoint)
                endpoint_index++)
        {
            /*
                endpoint descriptor
                offset                  size        description
                0	    bLength	        1	        Size of Descriptor in Bytes (7 bytes)
                1	bDescriptorType	    1	        Endpoint Descriptor (0x05)
                2	bEndpointAddress	1	        Endpoint Address
                                                    Bits 0..3b Endpoint Number.
                                                    Bits 4..6b Reserved. Set to Zero
                                                    Bits 7 Direction 0 = Out, 1 = In (Ignored for Control Endpoints)

                3	bmAttributes	    1	        Bits 0..1 Transfer Type
                                                    00 = Control
                                                    01 = Isochronous
                                                    10 = Bulk
                                                    11 = Interrupt
                                                    Bits 2..7 are reserved. If Isochronous endpoint,
                                                    Bits 3..2 = Synchronisation Type (Iso Mode)
                                                    00 = No Synchonisation
                                                    01 = Asynchronous
                                                    10 = Adaptive
                                                    11 = Synchronous
                                                    Bits 5..4 = Usage Type (Iso Mode)
                                                    00 = Data Endpoint
                                                    01 = Feedback Endpoint
                                                    10 = Explicit Feedback Data Endpoint
                                                    11 = Reserved

                4	wMaxPacketSize	2	            Maximum Packet Size this endpoint is capable of sending or receiving
                6	bInterval	    1	            Interval for polling endpoint data transfers. Value in frame counts. 
                                                    Ignored for Bulk & Control Endpoints. 
                                                    Isochronous must equal 1 and field may range from 1 to 255 for interrupt endpoints.
             */

            // RP2040 has 3 endpoints in PICOBOOT mode, the first one is always the control endpoint which isn't part of num_endpoint.
            // we can use this one to send the control requests(RP2040 DS 2.8.5.5)
            // rest of them are bulk in/out endpoints
            // for more information, see https://github.com/raspberrypi/pico-bootrom/blob/master/bootrom/usb_boot_device.c
            u8 direction;
            u8 index;
            u8 transfer_type;
            u16 max_packet_size;
            u8 interval; 
            if((*macos_usb_interface)->GetPipeProperties(macos_usb_interface,
                                                    endpoint_index, &direction,
                                                    &index, &transfer_type,
                                                    &max_packet_size, &interval) == kIOReturnSuccess)
            {
                assert(transfer_type == kUSBBulk); // kUSBBulk == 2
                switch(direction)
                {
                    case kUSBOut: // 0
                    {
                        usb_interface.bulk_out_endpoint_index = (u8)endpoint_index;
                    }break;

                    case kUSBIn: // 1
                    {
                        usb_interface.bulk_in_endpoint_index = (u8)endpoint_index;
                    }break;

                    default :
                    {
                        // TODO(gh) log, we're not expecting any other endpoints
                        assert(0); 
                    }
                }
            }
            else
            {
                // TODO(gh) log
                printf("couldn't get any endpoint index\n");
                assert(0);
            }
        }
    } // if(usb_interface.macos_usb_interface)

    IOUSBInterfaceInterface **macos_usb_interface = usb_interface.macos_usb_interface;

    // clear any stall/halt bits from every endpoints
    // this also synchronizes bit toggle(usbspec 1.1 )
    assert((*usb_interface.macos_usb_interface)->AbortPipe(usb_interface.macos_usb_interface, usb_interface.bulk_in_endpoint_index) == kIOReturnSuccess);
    assert((*usb_interface.macos_usb_interface)->ClearPipeStallBothEnds(usb_interface.macos_usb_interface, usb_interface.bulk_in_endpoint_index) == kIOReturnSuccess);

    assert((*usb_interface.macos_usb_interface)->AbortPipe(usb_interface.macos_usb_interface, usb_interface.bulk_out_endpoint_index) == kIOReturnSuccess);
    assert((*usb_interface.macos_usb_interface)->ClearPipeStallBothEnds(usb_interface.macos_usb_interface, usb_interface.bulk_out_endpoint_index) == kIOReturnSuccess);

    // create async event source
#if 0
    CFRunLoopSourceRef async_event_source;
    if((*usb_interface.macos_usb_interface)->CreateInterfaceAsyncEventSource(usb_interface.macos_usb_interface, &async_event_source) == kIOReturnSuccess)
    {
        int a = 1;
        CFRunLoopAddSource(CFRunLoopGetCurrent(), 
                            async_event_source,
                            kCFRunLoopCommonModes);
    }
    else
    {
        // TODO(gh) log 
        printf("failed to create async event source\n");
        assert(0);
    }
#endif

#if 1
    // reset the pipe using the control pipeline,
    // here we cannot use WritePipe and should use ControlRequest
    {
        IOUSBDevRequest *setup_packet = (IOUSBDevRequest *)malloc(sizeof(IOUSBDevRequest));
        setup_packet->bmRequestType = 0b01000001;
        setup_packet->bRequest = 0b01000001;
        setup_packet->wValue = 0;
        setup_packet->wIndex = 1; // in this case, index of the interface
        setup_packet->wLength = 0;

        IOReturn kr = (*usb_interface.macos_usb_interface)->ControlRequest(usb_interface.macos_usb_interface, 0, setup_packet);
        assert(kr == kIOReturnSuccess);

    }
#endif

#if 0
    // get exclusive access
    {
        PicoBootCommand excl_command = {};
        excl_command.magic = PICOBOOT_COMMAND_MAGIC_VALUE;
        excl_command.token = 0xdccccc;
        excl_command.command_ID = 0x1;
        excl_command.command_size = 0x01;
        excl_command.pad0 = 0;
        excl_command.transfer_length = 0;
        excl_command.args0 = 2;
        excl_command.args1 = 0; 
        excl_command.args2 = 0; 
        excl_command.args3 = 0; 
        macos_write_to_bulk_out_endpoint(&usb_interface, &excl_command, sizeof(PicoBootCommand)); 
        macos_wait_for_command_complete(&usb_interface);

        macos_bulk_transfer_in_zero(&usb_interface); // end the command sequence

        int a = 1;
    }
    sleep(1);
#endif

    char base_path[256];
    memset(base_path, 0, 256); 
    macos_get_base_path(base_path);

    char pio_bin_path[256];
    memset(pio_bin_path, 0, 256);
    unsafe_string_append(pio_bin_path, base_path);
    unsafe_string_append(pio_bin_path, "code/rp2040/pio0.bin");
    PlatformReadFileResult pio0_bin_file = debug_macos_read_file(pio_bin_path);
    assert(pio0_bin_file.size <= 32*5); // each instruction is 5 bytes in hex file, who knows why...

    // TODO(gh) this is so bad... is there a way to output the pioasm as a binary file?
    u32 pio0_instruction_count = pio0_bin_file.size / 5;
    u16 pio0_instructions[32]; // always write 64 bytes, padded with 0 
    memset(pio0_instructions, 0, 2*32);
    for(u32 i = 0;
            i < pio0_instruction_count;
            i++)
    {
        u8 *instruction = (u8 *)pio0_bin_file.memory + 5*i;
        u16 h0 = (u16)*(instruction + 0);
        u16 h1 = (u16)*(instruction + 1);
        u16 h2 = (u16)*(instruction + 2);
        u16 h3 = (u16)*(instruction + 3);

        if((h0 >= 0x61) && (h0 <= 0x66))
        {
            h0 -= 87;
        }
        else if((h0 >= 0x41) && (h0 <= 0x46))
        {
            h0 -= 65;
        }
        else if((h0 >= 0x30) && (h0 <= 0x39))
        {
            h0 -= 48;
        }
        else
        {
            assert(0);
        }

        if((h1 >= 0x61) && (h1 <= 0x66))
        {
            h1 -= 87;
        }
        else if((h1 >= 0x41) && (h1 <= 0x46))
        {
            h1 -= 65;
        }
        else if((h1 >= 0x30) && (h1 <= 0x39))
        {
            h1 -= 48;
        }
        else
        {
            assert(0);
        }
        
        if((h2 >= 0x61) && (h2 <= 0x66))
        {
            h2 -= 87;
        }
        else if((h2 >= 0x41) && (h2 <= 0x46))
        {
            h2 -= 65;
        }
        else if((h2 >= 0x30) && (h2 <= 0x39))
        {
            h2 -= 48;
        }
        else
        {
            assert(0);
        }
        
        if((h3 >= 0x61) && (h3 <= 0x66))
        {
            h3 -= 87;
        }
        else if((h3 >= 0x41) && (h3 <= 0x46))
        {
            h3 -= 65;
        }
        else if((h3 >= 0x30) && (h3 <= 0x39))
        {
            h3 -= 48;
        }
        else
        {
            assert(0);
        }

        // even worse, h0 - h3 is in backwards...
        pio0_instructions[i] = (h0 << 12) |
                               (h1 << 8) | 
                               (h2 << 4) | 
                               (h3 << 0);
    }

#if 1
    u32 pio0_instruction_address = 0x20040000;
    macos_write_to_rp2040(&usb_interface, pio0_instruction_address, pio0_instructions, 32*2);
    {
        void *read_buffer = malloc(32*2);
        macos_read_from_rp2040(&usb_interface, pio0_instruction_address, read_buffer, 32*2);
        macos_wait_for_command_complete(&usb_interface);
        for(u32 i = 0;
                i < 32;
                i++)
        {
            u16 read = *((u16 *)read_buffer + i);

            if(read != pio0_instructions[i])
            {
                assert(0);
            }
        }
    }
#endif

    char bin_path[256];
    memset(bin_path, 0, 256); // TODO(gh) zero-memory
    unsafe_string_append(bin_path, base_path);
    unsafe_string_append(bin_path, "code/rp2040/rp2040_main.bin");
    // unsafe_string_append(bin_path, "code/rp2040/notmain.bin");
    PlatformReadFileResult bin_file = debug_macos_read_file(bin_path);

    u32 core0_instruction_address = 0x20000000;

    // write the code to ram
    macos_write_to_rp2040(&usb_interface, core0_instruction_address, bin_file.memory, bin_file.size);

    // debug, testing whether I get the same bytes that I wrote
    void *read_buffer = malloc(bin_file.size);
    macos_read_from_rp2040(&usb_interface, core0_instruction_address, read_buffer, bin_file.size);
    macos_wait_for_command_complete(&usb_interface);
    for(u32 i = 0;
            i < bin_file.size;
            i++)
    {
        u8 read = *((u8 *)read_buffer + i);
        u8 file = *((u8 *)bin_file.memory + i);

        if(read != file)
        {
            assert(0);
        }
    }

    // move the PC and reboot RP2040
    PicoBootCommand reboot_command = {};
    reboot_command.magic = PICOBOOT_COMMAND_MAGIC_VALUE;
    reboot_command.token = 0x1234;
    reboot_command.command_ID = 0x2;
    reboot_command.command_size = 0x0c;
    reboot_command.pad0 = 0;
    reboot_command.transfer_length = 0;
    reboot_command.args0 = core0_instruction_address; // PC
    reboot_command.args1 = 0x20004000; // SP
    //reboot_command.args0 = 0; // PC
    //reboot_command.args1 = 0; // SP
    reboot_command.args2 = 10;
    reboot_command.args3 = 0;
    macos_bulk_transfer_out(&usb_interface, &reboot_command, sizeof(PicoBootCommand)); // write out the command
    macos_bulk_transfer_in_zero(&usb_interface);

#if 0
    u32 data_size = 256; // 256B is the minimum granularity, rp2040 will pad the data with 0 if it's smaller than 256B
    void *test_output = malloc(data_size);
    for(u32 iter = 0;
            iter < 1000;
            iter++)
    {
        memset(test_output, 0, data_size);
        u32 address = 0;
        b32 read_result = macos_read_from_bulk_in_endpoint(&usb_interface, address, test_output, data_size, 0x0);
        printf("%u : ", iter);
        if(read_result)
        {
            // debug, print out the data that we read 
            for(u32 i = 0;
                    i < data_size;
                    i++)
            {
                printf("%u ", *((u8 *)(test_output) + i));
            }
        }
        else
        {
            printf("failed");
        }
        printf("\n");

        // if(iter & 1)
        if(0)
        {
            // assert((*usb_interface.macos_usb_interface)->AbortPipe(usb_interface.macos_usb_interface, usb_interface.bulk_in_endpoint_index) == kIOReturnSuccess);
            // assert((*usb_interface.macos_usb_interface)->ClearPipeStallBothEnds(usb_interface.macos_usb_interface, usb_interface.bulk_in_endpoint_index) == kIOReturnSuccess);

            // assert((*usb_interface.macos_usb_interface)->AbortPipe(usb_interface.macos_usb_interface, usb_interface.bulk_out_endpoint_index) == kIOReturnSuccess);
            // assert((*usb_interface.macos_usb_interface)->ClearPipeStallBothEnds(usb_interface.macos_usb_interface, usb_interface.bulk_out_endpoint_index) == kIOReturnSuccess);
        }

        // sleep(1);
    }
#endif

    int a00 = 1;
}

internal void
raw_usb_device_removed(void *refCon, io_iterator_t io_iter)
{
    kern_return_t   kr;
    io_service_t    object;
 
    io_service_t usb_device_iter = IOIteratorNext(io_iter);
    while (usb_device_iter)
    {
        // TODO(gh) this will fire for other usb devices too since we know that the matching dictionary doesn't work
        // this will also fire if the rp2040 reboots and starts executing the code instead of going into a usb boot mode
        if(IOObjectRelease(usb_device_iter) != kIOReturnSuccess)
        {
            // TODO(gh) log
            printf("couldn’t release raw usb device object, possibly not our debug probe?\n");
            continue;
        }
    }
}

// only iothread will be running this code. this is basically a CFRunLoop with
// some IO events embedded
internal void*
macos_io_thread_proc(void *data)
{
    /*
       This usb initialization sequence is from 
       https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/USBBook/USBDeviceInterfaces/USBDevInterfaces.html
     */
    // open a master port to talk to the IOKit
    mach_port_t iokit_master_port;
    kern_return_t kernel_return = IOMasterPort(MACH_PORT_NULL, &iokit_master_port);
    assert((kernel_return == 0) && iokit_master_port);

    // create a dictionary to the IOKit so that we can find the usb device that we want
    CFMutableDictionaryRef usb_matching_dict = IOServiceMatching(kIOUSBDeviceClassName);
    assert(usb_matching_dict);
#if 0 // TODO(gh) this is not working, even though the same routine was being used in libusb / apple
    i32 usb_vendor_ID = 0x2e8a; // rp2040
    CFDictionarySetValue(usb_matching_dict, CFSTR(kUSBVendorID),
                        CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usb_vendor_ID));
#endif

    // open a notification port and add it to the CFRunLoop. IOKit will use this port to notify us 
    // whenever there is a new device being connected or the states change
    IONotificationPortRef notification_port = IONotificationPortCreate(iokit_master_port);
    CFRunLoopSourceRef runloop_source = IONotificationPortGetRunLoopSource(notification_port);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), 
                        runloop_source,
                        kCFRunLoopDefaultMode);

    // this is some obj-c crap I think, the explanation from them is : 
    // "Retain additional dictionary references because each call to IOServiceAddMatchingNotification consumes one reference"
    usb_matching_dict = (CFMutableDictionaryRef) CFRetain(usb_matching_dict);
    usb_matching_dict = (CFMutableDictionaryRef) CFRetain(usb_matching_dict);
    usb_matching_dict = (CFMutableDictionaryRef) CFRetain(usb_matching_dict);

    // TODO(gh) remove this malloc..?
    io_iterator_t *io_iters = (io_iterator_t *)malloc(4*sizeof(io_iterator_t));
    io_iters[0] = 0;
    io_iters[1] = 0;
    io_iters[2] = 0;
    io_iters[3] = 0;

    // first connected
    IOServiceAddMatchingNotification(notification_port,
                                     kIOMatchedNotification, usb_matching_dict,
                                     raw_usb_device_added, 0, io_iters + 0);
    raw_usb_device_added(0, io_iters[0]); // debug probe might be already connected, so try to find it ourselves at least once

    // disconnected
    IOServiceAddMatchingNotification(notification_port,
                    kIOTerminatedNotification, usb_matching_dict,
                    raw_usb_device_removed, 0, io_iters + 1);
    raw_usb_device_removed(0, io_iters[1]);

    mach_port_deallocate(mach_task_self(), iokit_master_port);

    // CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
    CFRunLoopRun(); // infinite loop

    return 0;
}

int main(void)
{ 
    //TODO : writefile?
    PlatformAPI platform_api = {};
    platform_api.read_file = debug_macos_read_file;
    platform_api.write_entire_file = debug_macos_write_entire_file;
    platform_api.free_file_memory = debug_macos_free_file_memory;

    PlatformMemory platform_memory = {};

    // we definitely don't need this memory(and this much memory) 
    platform_memory.permanent_memory_size = megabytes(16);
    platform_memory.transient_memory_size = megabytes(32);
    u64 total_size = platform_memory.permanent_memory_size + platform_memory.transient_memory_size;
    vm_allocate(mach_task_self(), 
            (vm_address_t *)&platform_memory.permanent_memory,
            total_size, 
            VM_FLAGS_ANYWHERE);
    platform_memory.transient_memory = (u8 *)platform_memory.permanent_memory + platform_memory.permanent_memory_size;

    // create iothread and start running
    pthread_attr_t  attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t thread = 0; // for now, we don't care about storing this because this is a background thread which will be running until the user closes the debugger
    if(pthread_create(&thread, &attr, &macos_io_thread_proc, 0) != 0)
    {
        assert(0);
    }
    pthread_attr_destroy(&attr);

#if 0

#endif

    // load ftdi library
    void *ftdi_library = dlopen("../lib/libftd2xx.1.4.24.dylib", RTLD_LAZY|RTLD_GLOBAL);
    FTDIApi ftdi_api = {};
    // if(ftdi_library)
    if(0)
    {
        // get all the necessary function pointers. some of these will be passed onto the 
        // application level so that the debugger can send the necessary jtag signals
        // to the cable
        ftdi_api.ft_ListDevices = (FT_ListDevices_ *)dlsym(ftdi_library, "FT_ListDevices");
        ftdi_api.ft_Open = (FT_Open_ *)dlsym(ftdi_library, "FT_Open");
        ftdi_api.ft_SetBaudRate = (FT_SetBaudRate_ *)dlsym(ftdi_library, "FT_SetBaudRate");
        ftdi_api.ft_SetBitMode = (FT_SetBitMode_ *)dlsym(ftdi_library, "FT_SetBitMode");
        ftdi_api.ft_SetLatencyTimer = (FT_SetLatencyTimer_ *)dlsym(ftdi_library, "FT_SetLatencyTimer");
        ftdi_api.ft_SetTimeouts = (FT_SetTimeouts_ *)dlsym(ftdi_library, "FT_SetTimeouts");
        ftdi_api.ft_ResetDevice = (FT_ResetDevice_ *)dlsym(ftdi_library, "FT_ResetDevice");
        ftdi_api.ft_SetUSBParameters = (FT_SetUSBParameters_ *)dlsym(ftdi_library, "FT_SetUSBParameters");
        ftdi_api.ft_SetChars = (FT_SetChars_ *)dlsym(ftdi_library, "FT_SetChars");
        ftdi_api.ft_SetFlowControl = (FT_SetFlowControl_ *)dlsym(ftdi_library, "FT_SetFlowControl");

        ftdi_api.ft_Read = (FT_Read_ *)dlsym(ftdi_library, "FT_Read");
        ftdi_api.ft_Write = (FT_Write_ *)dlsym(ftdi_library, "FT_Write");
        ftdi_api.ft_GetQueueStatus = (FT_GetQueueStatus_ *)dlsym(ftdi_library, "FT_GetQueueStatus");

        // the sequence here is from AN_135 FTDI MPSSE Basics doc
        assert(ftdi_api.ft_Open(0, &ftdi_api.handle) == FT_OK);
        assert(ftdi_api.ft_ResetDevice(ftdi_api.handle) == FT_OK);

        assert(ftdi_api.ft_SetUSBParameters(ftdi_api.handle, 64*1024, 64*1024) == FT_OK);
        assert(ftdi_api.ft_SetChars(ftdi_api.handle, false, 0, false, 0) == FT_OK); // disable event & error characters
        assert(ftdi_api.ft_SetTimeouts(ftdi_api.handle, 3000, 3000) == FT_OK); // in milliseconds
        assert(ftdi_api.ft_SetLatencyTimer(ftdi_api.handle, 2) == FT_OK);
        assert(ftdi_api.ft_SetFlowControl(ftdi_api.handle, FT_FLOW_RTS_CTS, 0, 0) == FT_OK); // TODO(gh) not exactly sure what this is 

        assert(ftdi_api.ft_SetBitMode(ftdi_api.handle, 0, FT_BITMODE_RESET) == FT_OK);
        assert(ftdi_api.ft_SetBitMode(ftdi_api.handle, 0x0B, FT_BITMODE_MPSSE) == FT_OK);

        ftdi_flush_receive_fifo(&ftdi_api);
        // ftdi_receive_queue_should_be_empty(&ftdi_api);

        // setup jtag commands

        // bit 0 = TCK
        // bit 1 = TDI
        // bit 2 = TDO
        // bit 3 = TMS
        u8 jtag_setup_commands[] = 
        { 
            0x80, // opcode
            0x00,  // initial value
            0x0B,  // direction, only the TDO is the input to the cable

            // loopback
            // 0x84, // opcode

            // tck period = 12Mhz / ((1+divisor) * 2)
            // currently the clock is running at 0.1mhz
            0x86,  // opcode
            0x3b, // divisor low 8bits
            0x00  // divisor high 8bits
        };
        u32 command_byte_count = sizeof(jtag_setup_commands);
        u32 bytes_written;
        assert(ftdi_api.ft_Write(ftdi_api.handle, jtag_setup_commands, command_byte_count, &bytes_written) == FT_OK);
        assert(command_byte_count == bytes_written);
        ftdi_receive_queue_should_be_empty(&ftdi_api);

        JTAGCommandBuffer jtag_command_buffer;
        u32 command_buffer_memory_size = 1024;
        u8 *command_buffer_base_memory = (u8 *)malloc(command_buffer_memory_size); // TODO(gh) remove malloc
        initialize_jtag_command_buffer(&jtag_command_buffer, command_buffer_base_memory, command_buffer_memory_size); 

        /*
           Initializing ARM ADI
           There are three power domains in the ADI.
           1. Always on power domain - DP registers
           2. Debug power domain - probably the Debug APB? If so, why does
           3. System power domain

           Powering up either the debug domain or the system domain 
           will allow the APB multiplexor to get the input from each end(CoreSight Components TRM 2.11.2).

           DP is the master of the internal bus(DAPBUS) that connects DP with all the other APs.
           All the APs are the slave of the DP.
           Both the APB-AP & system can be the master of the Debug APB(this is a bus). 
           This is done with the APB Mux. APB-AP always take priority when it comes down to who has access to the DEBUG APB.

           Both the DP and AP are run based on the DAPCLK, which should be equivalent to PCLKDBG(DEBUG APB Clock)
           APB-Mux will take both the PCLKDBG(Drives all logic, except for the System Slave port interface) & PCLKSYS(Drives the System Slave port interface)

Question : 

            only power up the debug domain and see if we can read the AP registers
            if that's possible, only power up the debug domain and see if we can read the memory
            1. Mux arbitration?
            2. why does the system need to access debug APB? - debug monitor(Corsight architecture spec v2 D2.4.1)
            3. Debug domain == Debug APB? Where are the APB registers?
            4. master vs slave
            5. bus vs bridge
         */
        push_DPACC_write(&jtag_command_buffer, ((1 << 30) | (1 << 28)), A_CTRL_STAT);
        pop_jtag_command_buffer(&jtag_command_buffer, &ftdi_api);
        ftdi_receive_queue_should_be_empty(&ftdi_api);

        // bunch of test routines
        // push_test_IDCODE(&jtag_command_buffer);
        // push_test_RDBUFF(&jtag_command_buffer);
        push_test_IDR0(&jtag_command_buffer);

        push_DPACC_read(&jtag_command_buffer, 0x4, 0x4); // test dpv0 vs dpv1
        push_move_state_machine(&jtag_command_buffer, RESET);
        // push_DPACC_read(&jtag_command_buffer, 0x4);
        pop_jtag_command_buffer(&jtag_command_buffer, &ftdi_api);
        
    } // if(ftdi_library)

#if 0
    // 2.5k -ish
    i32 window_width = 3200;
    i32 window_height = 1800;
#else
    // 1080p
    i32 window_width = 1920;
    i32 window_height = 1080;
#endif

    // TODO(gh): the value here is based on the pixel density, so we need to figure out a way to get the dpi of the monitor
    //NSRect window_rect = NSMakeRect(100.0f, 100.0f, (f32)window_width, (f32)window_height);
    NSRect window_rect = NSMakeRect(100.0f, 100.0f, (f32)window_width/2.0f, (f32)window_height/2.0f);

    u32 target_frames_per_second = 60;
    f32 target_seconds_per_frame = 1.0f/(f32)target_frames_per_second;
    u32 target_nano_seconds_per_frame = (u32)(target_seconds_per_frame*sec_to_nanosec);

    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy :NSApplicationActivationPolicyRegular];
    app_delegate *delegate = [app_delegate new];
    [app setDelegate: delegate];

    NSMenu *app_main_menu = [NSMenu alloc];
    NSMenuItem *menu_item_with_item_name = [NSMenuItem new];
    [app_main_menu addItem : menu_item_with_item_name];
    [NSApp setMainMenu:app_main_menu];

    NSMenu *SubMenuOfMenuItemWithAppName = [NSMenu alloc];
    NSMenuItem *quitMenuItem = [[NSMenuItem alloc] initWithTitle:@"Quit" 
                                                    action:@selector(terminate:)  // Decides what will happen when the menu is clicked or selected
                                                    keyEquivalent:@"q"];
    [SubMenuOfMenuItemWithAppName addItem:quitMenuItem];
    [menu_item_with_item_name setSubmenu:SubMenuOfMenuItemWithAppName];

    NSWindow *window = [[NSWindow alloc] initWithContentRect : window_rect
                                        // Apple window styles : https://developer.apple.com/documentation/appkit/nswindow/stylemask
                                        styleMask : NSTitledWindowMask|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
                                       backing : NSBackingStoreBuffered
                                        defer : NO];
    NSString *app_name = [[NSProcessInfo processInfo] processName];
    [window setTitle:app_name];
    [window makeKeyAndOrderFront:0];
    [window makeKeyWindow];
    [window makeMainWindow];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    NSString *name = device.name;
    bool has_unified_memory = device.hasUnifiedMemory;
    u64 max_allocation_size = device.recommendedMaxWorkingSetSize;
    MTKView *view = [[MTKView alloc] initWithFrame : window_rect
                                        device:device];
    [window setContentView:view];
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float;

    CAMetalLayer *metal_layer = (CAMetalLayer*)[view layer];
    id<MTLCommandQueue> command_queue = [device newCommandQueue];

    [app activate];
    [app run];

    // CFRunLoopRun();

    is_running = true;
#if 1
    u64 last_time = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    while(is_running)
    {
        // main loop
        MTLRenderPassDescriptor* renderpass = view.currentRenderPassDescriptor; // TODO(gh) memory leak
        if(renderpass)
        {
        }

        u64 time_passed_in_nsec = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - last_time;
        u32 time_passed_in_msec = (u32)(time_passed_in_nsec / sec_to_millisec);
        f32 time_passed_in_sec = (f32)time_passed_in_nsec / sec_to_nanosec;
        if(time_passed_in_nsec < target_nano_seconds_per_frame)
        {
            // NOTE(gh): Because nanosleep is such a high resolution sleep method, for precise timing,
            // we need to undersleep and spend time in a loop
            u64 undersleep_nano_seconds = target_nano_seconds_per_frame / 5;
            if(time_passed_in_nsec + undersleep_nano_seconds < target_nano_seconds_per_frame)
            {
                timespec time_spec = {};
                time_spec.tv_nsec = target_nano_seconds_per_frame - time_passed_in_nsec -  undersleep_nano_seconds;

                nanosleep(&time_spec, 0);
            }

            // For a short period of time, loop
            time_passed_in_nsec = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - last_time;
            while(time_passed_in_nsec < target_nano_seconds_per_frame)
            {
                time_passed_in_nsec = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - last_time;
            }
            time_passed_in_msec = (u32)(time_passed_in_nsec / sec_to_millisec);
            time_passed_in_sec = (f32)time_passed_in_nsec / sec_to_nanosec;
        }
        else
        {
            // TODO : Missed Frame!
            // TODO(gh) : Whenever we miss the frame re-sync with the display link
            // printf("Missed frame, exceeded by %dms(%.6fs)!\n", time_passed_in_msec, time_passed_in_sec);
        }
        last_time = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    }
#endif

    return 0;
}











