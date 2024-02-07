#ifndef RPID_FTDI_H
#define RPID_FTDI_H

#include "ftd2xx.h"

// TDI & TMS should change before the rising edge of TCK 
// TDO will be sampled at the falling edge of TCK
// TODO(gh) FTDI has both the TDO sample & TMS with read commands
// what's the difference?
enum FTDICommand
{
    FTDI_COMMAND_SHIFT_IN_BITS = 0x1b,
    FTDI_COMMAND_SHIFT_IN_BYTES = 0x19,

    FTDI_COMMAND_SHIFT_OUT_BITS = 0x6e,

    // FTDI_COMMAND_SHIFT_INOUT_BITS = ,
    // FTDI_COMMAND_SHIFT_INOUT_BYTES = ,

    FTDI_COMMAND_MOVE_STM = 0x4a, // without read, if you wanna read something use shift_out_bits
};

// commands for the mpsse processor of the ftdi chip

// TMS will be sampled on the rising edge of the tck
// length should be <= 8. if the length is 8, the last value is always the initial value of TMS
#define tms_noread(length, data, TDI) 0x4a, (length-1), ((TDI << 7) | data)
#define tms_read(length, data, TDI) 0x6e, (length-1), ((TDI << 7) | data)

// TCK will be sampled on the rising edge of the tck
// length should be <= 8
#define tdi_bit(length, data) 0x1b, (length-1), data
#define tdi_byte // TODO(gh) this would be better if we have a bunch of bytes to send through TDI

// bit 7 controls what the TDI should be during moving the TMS,
// we should use it to determine the last bit of TDI
#define goto_reset tms_noread(5, 0b11111, 0) 

// goto shift_ir
#define goto_shift_ir_from_reset tms_noread(5, 0b00110, 0)
#define goto_shift_ir_from_exit_dr tms_noread(5, 0b00111, 0) 

// goto shift_dr
#define goto_shift_dr_from_reset tms_noread(4, 0b0010, 0) 
// #define goto_shift_dr_from_shift_ir(TDI) 0x4a, 4, ((TDI << 7) | 0b00111) // update-ir is implied
#define goto_shift_dr_from_exit_ir tms_noread(4, 0b0011, 0) 
#define goto_shift_dr_from_exit_dr tms_noread(4, 0b0011, 0)
 
// 32 cycles in update + 1 cycle in exit == 33 cycles
// each tms command will _always_ generate one byte, no matter what the length is(Command Processor for MPSSE and MCU Host Bus Emulation Modes p16)
// the only way to do this in 4 commands(32 cycles) is by having a initial value of 1 for TMS
#define shift_out_32bits_and_exit tms_read(8, 0, 0), \
                                  tms_read(8, 0, 0), \
                                    tms_read(8, 0, 0), \
                                    tms_read(8, 0, 0), \
                                    tms_noread(1, 1, 0)

// TODO(gh) for now, we will just accept the fact that there's no way to 
// get the bits in the order & position (without the garbage bits) that we want as long as we're reading
// less than 8 bits. this works in this case because the first 3 bits are 
// the ACK bits, which tell us whether the operation was a success or not.
// TL:DR, the first byte would have :
// bit 5 set if the result was WAIT
// bit 4 set if the result was OK/FAULT
#define shift_out_35bits_and_exit tms_read(3, 0, 0), \
                                  tms_read(8, 0, 0), \
                                  tms_read(8, 0, 0), \
                                    tms_read(8, 0, 0), \
                                    tms_read(8, 0, 0), \
                                    tms_noread(1, 1, 0)

                                    

// useful for DPACC / APACC scan chain
// data = 32 bits
// A = 4 bits, but the bottom 2 bits are always 0 so we can only modify the top 2 bits. 
// The address that is listed inside the ADIv5 document is full 4bits
// RnW = 1bit(read = 0b1, write = 0b0)
#define shift_in_35bits_and_exit(RnW, A, data) tdi_bit(3, ((A>>2) << 1) | RnW), \
                                                tdi_bit(8, (data & 0xff)), \
                                                tdi_bit(8, ((data >> 8) & 0xff)), \
                                                tdi_bit(8, ((data >> 16) & 0xff)), \
                                                tdi_bit(7, ((data >> 24) & 0x7f)), \
                                                tms_noread(1, 1, (data>>31)&1)

// shift in 35 bits of data while shifting out the same amount 
#define shift_inout_35bits_and_exit(RnW, A, data) tms_read(8, 0, 0), \
                                          tms_read(8, 0, 0), \
                                          tms_read(8, 0, 0), \
                                          tms_read(8, 0, 0), \

// TODO(gh) assert here if there are more than 4 bits?
// the last TMS command is used to exit the state & give the last TDI bit
#define shift_in_4bits_and_exit(bits) 0x1b, 0x02, (bits & 0x7), \
                                      0x4a, 0x00, ((((bits>>3)&1) << 7) | 1)

// Coresight macro defines
// APSEL should be 8 bits, APBANKSEL should be 4 bits
#define SELECT_APACC(APSEL, APBANKSEL) ((APSEL << 24) | (APBANKSEL << 4))
#define SELECT_DPACC(DPBANKSEL) DPBANKSEL

// same as the other one, but just here for better code readability
enum DPACCRnW
{
    DPACC_write = 0,
    DPACC_read = 1,
};
enum APACCRnW
{
    APACC_write = 0,
    APACC_read = 1,
};


enum DPRegister
{
    DR_CTRL_STAT = 0x4,
    DR_SELECT = 0x8,
    DR_RDBUFF = 0xC,
};

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
