#ifndef RPID_USB_H
#define RPID_USB_H

#define PICOBOOT_COMMAND_MAGIC_VALUE 0x431fd10b

#pragma pack(push, 1)
struct PicoBootCommand // all commands are 32 bytes, should be cleared to 0 before use
{
    u32 magic; // The value 0x431fd10b
    u32 token; // A user provided token to identify this request by
    u8 command_ID; // The ID of the command. Note that the top bit indicates data transfer direction (0x80 = IN)
    u8 command_size;// Number of bytes of valid data in the args field
    u16 pad0; // 0x0000
    u32 transfer_length; // The number of bytes the host expects to send or receive over the bulk channel
    // 16 bytes of command specific data padded with zeros
    u32 args0;
    u32 args1;
    u32 args2;
    u32 args3;
};
#pragma pack(pop)

/*!
    @struct IOUSBDevRequest
    @discussion Parameter block for control requests, using a simple pointer
    for the data to be transferred.
    @field bmRequestType Request type: kUSBStandard, kUSBClass or kUSBVendor
    @field bRequest Request code
    @field wValue 16 bit parameter for request, host endianess
    @field wIndex 16 bit parameter for request, host endianess
    @field wLength Length of data part of request, 16 bits, host endianess
    @field pData Pointer to data for request - data returned in bus endianess
    @field wLenDone Set by standard completion routine to number of data bytes
        actually transferred

    typedef struct
    {
        UInt8  bmRequestType;
        UInt8  bRequest;
        UInt16 wValue;
        UInt16 wIndex;
        UInt16 wLength;
        void*  pData;
        UInt32 wLenDone;
    } IOUSBDevRequest;
    typedef IOUSBDevRequest* IOUSBDeviceRequestPtr;


    IOUSBFamily error codes
    Also check IOReturn.h more more error codes
    #define	iokit_usb_err(return)       (sys_iokit|sub_iokit_usb|return)
    #define kIOUSBUnknownPipeErr        iokit_usb_err(0x61)									// 0xe0004061  Pipe ref not recognized
    #define kIOUSBTooManyPipesErr       iokit_usb_err(0x60)									// 0xe0004060  Too many pipes
    #define kIOUSBNoAsyncPortErr        iokit_usb_err(0x5f)									// 0xe000405f  no async port
    #define kIOUSBNotEnoughPipesErr     iokit_usb_err(0x5e)									// 0xe000405e  not enough pipes in interface
    #define kIOUSBNotEnoughPowerErr     iokit_usb_err(0x5d)									// 0xe000405d  not enough power for selected configuration
    #define kIOUSBEndpointNotFound      iokit_usb_err(0x57)									// 0xe0004057  Endpoint Not found
    #define kIOUSBConfigNotFound        iokit_usb_err(0x56)									// 0xe0004056  Configuration Not found
    #define kIOUSBTransactionTimeout    iokit_usb_err(0x51)									// 0xe0004051  Transaction timed out
    #define kIOUSBTransactionReturned   iokit_usb_err(0x50)									// 0xe0004050  The transaction has been returned to the caller
    #define kIOUSBPipeStalled           iokit_usb_err(0x4f)									// 0xe000404f  Pipe has stalled, error needs to be cleared
    #define kIOUSBInterfaceNotFound     iokit_usb_err(0x4e)									// 0xe000404e  Interface ref not recognized
    #define kIOUSBLowLatencyBufferNotPreviouslyAllocated        iokit_usb_err(0x4d)			// 0xe000404d  Attempted to use user land low latency isoc calls w/out calling PrepareBuffer (on the data buffer) first 
    #define kIOUSBLowLatencyFrameListNotPreviouslyAllocated     iokit_usb_err(0x4c)			// 0xe000404c  Attempted to use user land low latency isoc calls w/out calling PrepareBuffer (on the frame list) first
    #define kIOUSBHighSpeedSplitError	iokit_usb_err(0x4b)									// 0xe000404b  Error to hub on high speed bus trying to do split transaction
    #define kIOUSBSyncRequestOnWLThread	iokit_usb_err(0x4a)									// 0xe000404a  A synchronous USB request was made on the workloop thread (from a callback?).  Only async requests are permitted in that case
    #define kIOUSBDeviceNotHighSpeed	iokit_usb_err(0x49)									// 0xe0004049  Name is deprecated, see below
    #define kIOUSBDeviceTransferredToCompanion					iokit_usb_err(0x49)			// 0xe0004049  The device has been tranferred to another controller for enumeration
    #define kIOUSBClearPipeStallNotRecursive 					iokit_usb_err(0x48)			// 0xe0004048  IOUSBPipe::ClearPipeStall should not be called recursively
    #define kIOUSBDevicePortWasNotSuspended 					iokit_usb_err(0x47)			// 0xe0004047  Port was not suspended
#ifdef SUPPORTS_SS_USB
	#define kIOUSBEndpointCountExceeded	iokit_usb_err(0x46)									// 0xe0004046  The endpoint was not created because the controller cannot support more endpoints
	#define kIOUSBDeviceCountExceeded	iokit_usb_err(0x45)									// 0xe0004045  The device cannot be enumerated because the controller cannot support more devices
    #define kIOUSBStreamsNotSupported   iokit_usb_err(0x44)                                 // 0xe0004044   The request cannot be completed because the XHCI controller does not support streams
#endif
 */

// this is only specific to RP2040!
struct RP2040USBInterface
{
    IOUSBInterfaceInterface **macos_usb_interface; // TODO(gh) support more platforms

    u8 bulk_in_endpoint_index;
    u8 bulk_out_endpoint_index;
}; 

#endif
