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

// need to undef these from the macos framework 
// so that we can define these ourselves
#undef internal
#undef assert

#include "rpid_types.h"
#include "rpid_intrinsic.h"
#include "rpid_platform.h"
#include "rpid_ftdi.cpp" 

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

int main(void)
{ 
    //TODO : writefile?
    PlatformAPI platform_api = {};
    platform_api.read_file = debug_macos_read_file;
    platform_api.write_entire_file = debug_macos_write_entire_file;
    platform_api.free_file_memory = debug_macos_free_file_memory;

    PlatformMemory platform_memory = {};

    platform_memory.permanent_memory_size = gigabytes(1);
    platform_memory.transient_memory_size = gigabytes(3);
    u64 total_size = platform_memory.permanent_memory_size + platform_memory.transient_memory_size;
    vm_allocate(mach_task_self(), 
                (vm_address_t *)&platform_memory.permanent_memory,
                total_size, 
                VM_FLAGS_ANYWHERE);
    platform_memory.transient_memory = (u8 *)platform_memory.permanent_memory + platform_memory.permanent_memory_size;

    // load ftdi library
    void *ftdi_library = dlopen("../lib/libftd2xx.1.4.24.dylib", RTLD_LAZY|RTLD_GLOBAL);
    FTDIApi ftdi_api = {};
    if(ftdi_library)
    {
        // get all the necessary function pointers. some of these will be passed onto the 
        // application level so that the debugger can have the functionality to send jtag signals
        // to the cable
        ftdi_api.ft_ListDevices = (FT_ListDevices_ *)dlsym(ftdi_library, "FT_ListDevices");
        ftdi_api.ft_Open = (FT_Open_ *)dlsym(ftdi_library, "FT_Open");
        ftdi_api.ft_SetBaudRate = (FT_SetBaudRate_ *)dlsym(ftdi_library, "FT_SetBaudRate");
        ftdi_api.ft_SetBitMode = (FT_SetBitMode_ *)dlsym(ftdi_library, "FT_SetBitMode");
        ftdi_api.ft_SetLatencyTimer = (FT_SetLatencyTimer_ *)dlsym(ftdi_library, "FT_SetLatencyTimer");
        ftdi_api.ft_SetTimeouts = (FT_SetTimeouts_ *)dlsym(ftdi_library, "FT_SetTimeouts");
        ftdi_api.ft_ResetDevice = (FT_ResetDevice_ *)dlsym(ftdi_library, "FT_ResetDevice");

        ftdi_api.ft_Read = (FT_Read_ *)dlsym(ftdi_library, "FT_Read");
        ftdi_api.ft_Write = (FT_Write_ *)dlsym(ftdi_library, "FT_Write");
        ftdi_api.ft_GetQueueStatus = (FT_GetQueueStatus_ *)dlsym(ftdi_library, "FT_GetQueueStatus");

        // not a fan of the defensive programming, but can be useful when we're using an unknown library
        assert(ftdi_api.ft_Open(0, &ftdi_api.handle) == FT_OK);
        assert(ftdi_api.ft_ResetDevice(ftdi_api.handle) == FT_OK);
        assert(ftdi_api.ft_SetBitMode(ftdi_api.handle, 0, FT_BITMODE_RESET) == FT_OK);
        assert(ftdi_api.ft_SetLatencyTimer(ftdi_api.handle, 2) == FT_OK);
        assert(ftdi_api.ft_SetTimeouts(ftdi_api.handle, 3000, 3000) == FT_OK);
        assert(ftdi_api.ft_SetBitMode(ftdi_api.handle, 0x0B, FT_BITMODE_MPSSE) == FT_OK);

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

        // send jtag setup commands to the mpsse
        u32 command_byte_count = sizeof(jtag_setup_commands);
        u32 bytes_written;
        assert(ftdi_api.ft_Write(ftdi_api.handle, jtag_setup_commands, command_byte_count, &bytes_written) == FT_OK);
        assert(command_byte_count == bytes_written);

#if 1
        // once the dap state machine is reset, the IR would be IDCODE.
        // there is implied 0 or 1(depending on the initial TMS value) between commands 
        // as the cable sends out additional clock. to avoid this, we're gonna make all our commands
        // to have one less bit, as long the last bit should be 0
        u8 command[] = 
        {
            command_tms_goto_reset,
#if 0
            command_tms_goto_shift_ir_from_reset, 

            // shift in 4 bit IDCODE instruction through TDI
            // the last bit will be taken care of the following TMS command
            // 0x1b, 0x02, 0b110, // TODO(gh) why should this be 0x1b, not 0x1a?
            0x3b, 0x02, 0b110,  // with read

            command_tms_goto_shift_dr_from_shift_ir(1), 
#else
            command_tms_goto_shift_dr_from_reset,
#endif

            // TODO(gh) these commands should be verified
            command_tms_shift_out_32bits_with_read,
            command_tms_goto_reset,
        };
        ftdi_write(&ftdi_api, command, array_count(command));

#if 0
        ftdi_wait_receive_queue(&ftdi_api, 4);

        u8 idcode_buffer[4];
        ftdi_read(&ftdi_api, idcode_buffer, 4);
        ftdi_receive_queue_should_be_empty(&ftdi_api);

        /*
            IDCODE structure
            IDCODE should be 0x4ba00477 for raspberry pi 3 b+.

            bit 0 should always be 1
            bits [11:1] are the designer ID, which should be 0x43b(page B3-104 of ADIv5.0-5.2 document). In total, bits[11:0] should be 0x477
            bits [27:12] are the part number, which should be 0xBA00, which stands for a JTAG-DP designed by ARM(page 3-4 CoreSight Technology System Design Guide)
            bits [31:28] are the version number, and is IMPLEMENTATION DEFINED.
         */

#if 0
        assert((idcode_buffer[0] == 0x77) && 
                (idcode_buffer[1] == 0x04) &&
                (idcode_buffer[2] == 0x0a) &&
                (idcode_buffer[3] == 0x4b));
#endif
#endif
#endif
        
#if 0 // testing loopback functionality. make sure to send 0x84 to the mpsse which is an opcode for setting up the cable to loopback mode
        // send some bytes to check the loopback functionality
        u8 loopback_command[] = 
        {
            0x31, // opcode
            0x00, // byte count low
            0x00,  // byte count high
        };

        u8 loopback_bytes[] = 
        {
            0x00,
            0x01,
            0x02,
            0x03,
            0x04,
            0x05,
            0x06,
            0x07,
            0x08,
            0x09,
            0x0a,
            0x0b,
            0x0c,
            0x0d,
            0x0e,
            0x0f,
        };

        u32 data_byte_count = sizeof(loopback_bytes);
        loopback_command[1] = data_byte_count & 0xff;
        loopback_command[2] = (data_byte_count >> 8) & 0xff;

        // first, send the TDI output command
        u32 loopback_byte_count = sizeof(loopback_command);
        assert(ftdi_api.ft_Write(ftdi_api.handle, loopback_command, loopback_byte_count, &bytes_written) == FT_OK);
        assert(loopback_byte_count == bytes_written);

        // second, send the bytes that we wanna output
        assert(ftdi_api.ft_Write(ftdi_api.handle, loopback_bytes, data_byte_count, &bytes_written) == FT_OK);
        assert(data_byte_count == bytes_written);

        u32 bytes_received = 0;
        u32 queue_check = 0;
        while(bytes_received != bytes_written)
        {
            if((queue_check & 511) == 0)
            {
                // TODO(gh) check for timeout
            }

            assert(ftdi_api.ft_GetQueueStatus(ftdi_api.handle, &bytes_received) == FT_OK);

            queue_check++;
        }

        // using malloc is a bad idea, but for now it's fine because this is a test code
        u8 *receive_buffer = (u8 *)malloc(bytes_received * sizeof(u8));
        u32 bytes_read;
        assert(ftdi_api.ft_Read(ftdi_api.handle, receive_buffer, bytes_received, &bytes_read) == FT_OK);
        assert(bytes_received == bytes_read);

        // check whether we received the bytes that we sent 
        assert(memcmp(loopback_bytes, receive_buffer, bytes_read) == 0);

        // check whether the queue has any unexpected byte
        u32 remaining_bytes;
        assert(ftdi_api.ft_GetQueueStatus(ftdi_api.handle, &remaining_bytes) == FT_OK);
        assert(remaining_bytes == 0);
#endif
    }

    // TODO(gh) get monitor width and height and use that 
#if 1
    // 2.5k -ish
    i32 window_width = 3200;
    i32 window_height = 1800;
#else
    // 1080p
    i32 window_width = 1920;
    i32 window_height = 1080;
#endif

    // TODO(gh) find out how to have variable refresh rate from the OS side
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

    // TODO(gh): when connected to the external display, this should be window_width and window_height
    // but if not, this should be window_width/2 and window_height/2. Turns out it's based on the resolution(or maybe ppi),
    // because when connected to the apple studio display, the application should use the same value as the macbook monitor
    //NSRect window_rect = NSMakeRect(100.0f, 100.0f, (f32)window_width, (f32)window_height);
    NSRect window_rect = NSMakeRect(100.0f, 100.0f, (f32)window_width/2.0f, (f32)window_height/2.0f);

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

    [app activateIgnoringOtherApps:YES];
    [app run];

    is_running = true;
    // while(is_running)
    {
        // main loop
    }

    return 0;
}











