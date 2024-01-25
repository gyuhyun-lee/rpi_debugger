#ifndef RPID_FTDI_H
#define RPID_FTDI_H

#include "ftd2xx.h"

// commands for the mpsse processor of the ftdi chip
// command_tms_xx == without read
// command_tms_read_xx == with read
#define command_tms(length, byte) 0x4a, length, byte

// bit 7 controls what the TDI should be during moving the TMS,
// we should use it to determine the last bit of TDI
#define command_tms_goto_reset 0x4a, 4, 0b11111 
#define command_tms_goto_shift_ir_from_reset 0x4a, 4, 0b00110

#define command_tms_goto_shift_dr_from_reset 0x4a, 3, 0b0010
#define command_tms_goto_shift_dr_from_shift_ir(TDI) 0x4a, 4, ((TDI << 7) | 0b00111) // update-ir is implied
#define command_tms_goto_shift_ir_from_shift_dr 0x4a, 5, 0b001111 // update-dr is implied
 
// 31 cycles in update + 1 cycle in exit == 32 cycles
#define command_tms_read_shift_out_32bits_and_exit 0x6e, 7, 0x0, \
                                                   0x6e, 7, 0x0, \
                                                   0x6e, 7, 0x0, \
                                                   0x6e, 7, 0x0, \
                                                   0x4a, 0, 0x1
                                                   // TODO(gh) this clocks out 33 bits of TDO, why?
                                                   // 0x6e, 6, 0x0, \
                                                   // 0x6e, 0, 0x1

                                                    

// FTDI functions that the debugger doesn't need to use.
// the function types are defined as the original function name + _
#define PLATFORM_FT_ListDevices(name) u32 (name)(void *arg0, void *arg1, void *flags)
typedef PLATFORM_FT_ListDevices(FT_ListDevices_);

// when getting a handle to a ftdi device, there are multiple ways to do it.
// I think we can just check the serial number, and then use that as a constant value - which would be the simplest way of doing this
// VID = 0403h,  PID = 6014h
#define PLATFORM_FT_OpenEx(name) u32 (name)(void *arg0, u32 flags, void *handle)
typedef PLATFORM_FT_OpenEx(FT_OpenEx_);

#define PLATFORM_FT_Open(name) u32 (name)(int iDevice, void **ft_handle)
typedef PLATFORM_FT_Open(FT_Open_);

#define PLATFORM_FT_SetBaudRate(name) u32 (name)(void *ft_handle, u32 baud_rate)
typedef PLATFORM_FT_SetBaudRate(FT_SetBaudRate_);

#define PLATFORM_FT_Write(name) u32 (name)(void *ft_handle, void *buffer, u32 bytes_to_write, u32 *bytes_written);
typedef PLATFORM_FT_Write(FT_Write_);

#define PLATFORM_FT_Read(name) u32 (name)(void *ft_handle, void *buffer, u32 bytes_to_read, u32 *bytes_read);
typedef PLATFORM_FT_Read(FT_Read_);

// we need to use this function to configure the cable to be a
// Multi-Protocol Synchronous Serial Engine  (MPSSE) mode = 0x2
#define PLATFORM_FT_SetBitMode(name) u32 (name)(void *handle, u8 mask, u8 mode)
typedef PLATFORM_FT_SetBitMode(FT_SetBitMode_);

#define PLATFORM_FT_SetLatencyTimer(name) u32 (name)(void *handle, u8 timer)
typedef PLATFORM_FT_SetLatencyTimer(FT_SetLatencyTimer_);

#define PLATFORM_FT_SetTimeouts(name) u32 (name)(void *handle, u32 read_timeout, u32 write_timeout)
typedef PLATFORM_FT_SetTimeouts(FT_SetTimeouts_);

#define PLATFORM_FT_ResetDevice(name) u32 (name)(void *handle)
typedef PLATFORM_FT_ResetDevice(FT_ResetDevice_);

#define PLATFORM_FT_GetQueueStatus(name) u32 (name)(void *handle, u32 *remaining_bytes_in_queue)
typedef PLATFORM_FT_GetQueueStatus(FT_GetQueueStatus_);

// sets the maximum USB transmit size
#define PLATFORM_FT_SetUSBParameters(name) u32 (name)(void *handle, u32 in_byte_count, u32 out_byte_count)
typedef PLATFORM_FT_SetUSBParameters(FT_SetUSBParameters_);

#define PLATFORM_FT_SetChars(name) u32 (name)(void *handle, u8 uEventCh, u8 uEventChEn, u8 uErrorCh, u8 uErrorChEn)
typedef PLATFORM_FT_SetChars(FT_SetChars_);

#define PLATFORM_FT_SetFlowControl(name) u32 (name)(void *handle, u16 usFlowControl, u8 uXon, u8 uXoff)
typedef PLATFORM_FT_SetFlowControl(FT_SetFlowControl_);

#if 0
#define PLATFORM_FT_(name) u32 (name)()
typedef PLATFORM_FT_(FT_);
#endif

// has all the function pointers that we need from the FTDI library 
struct FTDIApi
{
    void *handle; 

    // TODO(gh) don't think these should be part of the runtime API,
    // but maybe they should be so that the user can change these parameters from the debugger?
    FT_ListDevices_ *ft_ListDevices;
    FT_Open_ *ft_Open;
    FT_SetBaudRate_ *ft_SetBaudRate;
    FT_SetBitMode_ *ft_SetBitMode;
    FT_SetLatencyTimer_ *ft_SetLatencyTimer;
    FT_SetTimeouts_ *ft_SetTimeouts;
    FT_ResetDevice_ *ft_ResetDevice;
    FT_SetUSBParameters_ *ft_SetUSBParameters;
    FT_SetChars_ *ft_SetChars;
    FT_SetFlowControl_ *ft_SetFlowControl;

    // ftdi runtime functions
    FT_Read_ *ft_Read;
    FT_Write_ *ft_Write;
    FT_GetQueueStatus_ *ft_GetQueueStatus;
};

#endif
