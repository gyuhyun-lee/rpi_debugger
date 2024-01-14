#ifndef RPID_PLATFORM_H
#define RPID_PLATFORM_H

#ifdef __cplusplus
extern "C" {
#endif

#include "rpid_types.h" 

#include <math.h>

struct PlatformReadFileResult
{
    u8 *memory;
    u64 size; // TOOD/gh : make this to be at least 64bit
};

#define PLATFORM_GET_FILE_SIZE(name) u64 (name)(const char *filename)
typedef PLATFORM_GET_FILE_SIZE(platform_get_file_size);

#define PLATFORM_READ_FILE(name) PlatformReadFileResult (name)(const char *filename)
typedef PLATFORM_READ_FILE(platform_read_file);

#define PLATFORM_WRITE_ENTIRE_FILE(name) void (name)(const char *file_name, void *memory_to_write, u32 size)
typedef PLATFORM_WRITE_ENTIRE_FILE(platform_write_entire_file);

#define PLATFORM_FREE_FILE_MEMORY(name) void (name)(void *memory)
typedef PLATFORM_FREE_FILE_MEMORY(platform_free_file_memory);

struct PlatformAPI
{
    platform_read_file *read_file;
    platform_write_entire_file *write_entire_file;
    platform_free_file_memory *free_file_memory;

    // NOTE(gh) all the ftdi driver related functions. this can be more generic 
    // in the future and support multiple cables

    // platform_atomic_compare_and_exchange32() *atomic_compare_and_exchange32;
    // platform_atomic_compare_and_exchange64() *atomic_compare_and_exchange64;
};

struct PlatformKey
{
    // NOTE(gh) was_down will copy from is_down at the end of the frame,
    // which solves the granurarity of the keyboard event not being good enough. 
    b32 is_down;
    b32 was_down;
};

enum PlatformKeyID
{
    PlatformKeyID_MoveUp,
    PlatformKeyID_MoveDown,
    PlatformKeyID_MoveLeft,
    PlatformKeyID_MoveRight,

    PlatformKeyID_ActionUp,
    PlatformKeyID_ActionDown,
    PlatformKeyID_ActionLeft,
    PlatformKeyID_ActionRight,

    PlatformKeyID_Shoot,

    PlatformKeyID_ToggleSimulation,
    PlatformKeyID_AdvanceSubstep,
    PlatformKeyID_FallbackSubstep,
    PlatformKeyID_AdvanceFrame,
    PlatformKeyID_FallbackFrame,
};

struct PlatformInput
{
    // NOTE(gh) 256 is a random number that is big enough to hold most of the keys,
    // but the keys that are actually being used are the ones that have effective enum ID
    PlatformKey keys[256];

    PlatformKey space;

    f32 dt_per_frame;
    f32 time_elasped_from_start;
};

inline b32
is_key_pressed(PlatformInput *platform_input, PlatformKeyID ID)
{
    b32 result = platform_input->keys[ID].is_down && !platform_input->keys[ID].was_down;

    return result;
}

inline b32
is_key_down(PlatformInput *platform_input, PlatformKeyID ID)
{
    b32 result = platform_input->keys[ID].is_down;

    return result;
}

// TODO(gh) Make this string to be similar to what Casey has done in his HH project
// which is non-null terminated string with the size
// NOTE(gh) this function has no bound check
internal void
unsafe_string_append(char *dest, const char *source, u32 source_size)
{
    while(*dest != '\0')
    {
        dest++;
    }

    while(source_size-- > 0)
    {
        *dest++ = *source++;
    }
}

// NOTE(gh) this function has no bound check
internal void
unsafe_string_append(char *dest, const char *source)
{
    while(*dest != '\0')
    {
        dest++;
    }
    
    while(*source != '\0')
    {
        *dest++ = *source++;
    }
}

struct PlatformMemory
{
    void *permanent_memory;
    u64 permanent_memory_size;

    void *transient_memory;
    u64 transient_memory_size;
};

// TODO(gh) sub_arena!
struct MemoryArena
{
    void *base;
    size_t total_size;
    size_t used;

    u32 temp_memory_count;
};

internal MemoryArena
start_memory_arena(void *base, size_t size, b32 should_be_zero = true)
{
    MemoryArena result = {};

    result.base = (u8 *)base;
    result.total_size = size;

    // TODO/gh :zeroing memory every time might not be a best idea
    if(should_be_zero)
    {
        // zero_memory(result.base, result.total_size);
    }

    return result;
}


// NOTE(gh): Works for both platform memory(world arena) & temp memory
#define push_array(memory, type, count) (type *)push_size(memory, count * sizeof(type))
#define push_struct(memory, type) (type *)push_size(memory, sizeof(type))

// TODO(gh) : Alignment might be an issue, always take account of that
internal void *
push_size(MemoryArena *memory_arena, size_t size, b32 should_be_no_temp_memory = true, size_t alignment = 0)
{
   assert(size != 0);

    if(should_be_no_temp_memory)
    {
        assert(memory_arena->temp_memory_count == 0);
    }

    assert(memory_arena->used <= memory_arena->total_size);

    void *result = (u8 *)memory_arena->base + memory_arena->used;
    memory_arena->used += size;

    return result;
}

internal MemoryArena
start_sub_arena(MemoryArena *base_arena, size_t size, b32 should_be_zero = true)
{
    MemoryArena result = {};

    result.base = (u8 *)push_size(base_arena, size, should_be_zero);
    result.total_size = size;

    return result;
}

struct TempMemory
{
    MemoryArena *memory_arena;

    // TODO/gh: temp memory is for arrays only, so dont need to keep track of 'used'?
    void *base;
    size_t total_size;
    size_t used;
};

// TODO(gh) : Alignment might be an issue, always take account of that
internal void *
push_size(TempMemory *temp_memory, size_t size, size_t alignment = 0)
{
    assert(size != 0);

    void *result = (u8 *)temp_memory->base + temp_memory->used;
    temp_memory->used += size;

    assert(temp_memory->used <= temp_memory->total_size);

    return result;
}

internal TempMemory
start_temp_memory(MemoryArena *memory_arena, size_t size, b32 should_be_zero = true)
{
    TempMemory result = {};
    if(memory_arena)
    {
    result.base = (u8 *)memory_arena->base + memory_arena->used;
    result.total_size = size;
    result.memory_arena = memory_arena;

    push_size(memory_arena, size, false);

    memory_arena->temp_memory_count++;
    if(should_be_zero)
    {
        // zero_memory(result.base, result.total_size);
    }
    }

    return result;
}

// TODO(gh) no need to pass the pointer
internal void
end_temp_memory(TempMemory *temp_memory)
{
    MemoryArena *memory_arena = temp_memory->memory_arena;
    // NOTE(gh) : safe guard for using this temp memory after ending it 
    temp_memory->base = 0;

    memory_arena->temp_memory_count--;
    // IMPORTANT(gh) : As the nature of this, all temp memories should be cleared at once
    memory_arena->used -= temp_memory->total_size;
}

u64 rdtsc(void)
{
	u64 val;
#if RPID_ARM 
    // TODO(gh) Counter count seems like it's busted, find another way to do this
	asm volatile("mrs %0, cntvct_el0" : "=r" (val));
#elif RPID_X64
    val = __rdtsc();
#endif
	return val;
}

#define PLATFORM_DEBUG_PRINT_CYCLE_COUNTERS(name) void (name)(debug_cycle_counter *debug_cycle_counters)

struct ThreadWorkQueue;
#define THREAD_WORK_CALLBACK(name) void name(void *data)
typedef THREAD_WORK_CALLBACK(ThreadWorkCallback);

// TODO(gh) Good idea?
enum GPUWorkType
{
    GPUWorkType_Null,
    GPUWorkType_AllocateBuffer,
    GPUWorkType_AllocateTexture2D,
    GPUWorkType_WriteEntireTexture2D,
    GPUWorkType_BuildAccelerationStructure,
};
struct ThreadAllocateBufferData
{
    void **handle_to_populate;
    void **memory_to_populate;
    u64 size_to_allocate;
};

struct ThreadAllocateTexture2DData
{
    void **handle_to_populate;
    i32 width;
    i32 height;
    i32 bytes_per_pixel;
};
struct ThreadWriteEntireTexture2D
{
    void *handle;

    void *source;
    
    i32 width;
    i32 height;
    i32 bytes_per_pixel;
};

// TODO(gh) task_with_memory
struct ThreadWorkItem
{
    union
    {
        ThreadWorkCallback *callback; // callback to the function that we wanna execute
        GPUWorkType gpu_work_type;
    };
    void *data;

    b32 written; // indicates whether this item is properly filled or not
};

#define PLATFORM_COMPLETE_ALL_THREAD_WORK_QUEUE_ITEMS(name) void name(ThreadWorkQueue *queue, b32 main_thread_should_do_work)
typedef PLATFORM_COMPLETE_ALL_THREAD_WORK_QUEUE_ITEMS(platform_complete_all_thread_work_queue_items);

#define PLATFORM_ADD_THREAD_WORK_QUEUE_ITEM(name) void name(ThreadWorkQueue *queue, ThreadWorkCallback *thread_work_callback, u32 gpu_work_type, void *data)
typedef PLATFORM_ADD_THREAD_WORK_QUEUE_ITEM(platform_add_thread_work_queue_item);

#define PLATFORM_DO_THREAD_WORK_ITEM(name) b32 (name)(ThreadWorkQueue *queue, u32 thread_index)
typedef PLATFORM_DO_THREAD_WORK_ITEM(platform_do_thread_work_item);

// IMPORTANT(gh): There is no safeguard for the situation where one work takes too long, and meanwhile the work queue was filled so quickly
// causing writeItem == readItem
struct ThreadWorkQueue
{
    void *semaphore;

    // NOTE(gh) : volatile forces the compiler not to optimize the value out, and always to the load(as other thread can change it)
    // NOTE(gh) These two just increments, and the function is responsible for doing the modular 
    int volatile work_index; // index to the queue that is currently under work
    int volatile add_index; // Only the main thread should increment this, as this is not barriered!!!

    int volatile completion_goal;
    int volatile completion_count;

    ThreadWorkItem items[1024];

    // TODO(gh) Not every queue has this!
    void *render_context;

    // now this can be passed onto other codes, such as seperate game code to be used as rendering 
    platform_add_thread_work_queue_item *add_thread_work_queue_item;
    platform_complete_all_thread_work_queue_items * complete_all_thread_work_queue_items;
    // NOTE(gh) Should NOT be used from the game code side!
    platform_do_thread_work_item *_do_thread_work_item;
};

#define GAME_UPDATE_AND_RENDER(name) void (name)(PlatformAPI *platform_api, PlatformInput *platform_input, PlatformMemory *platform_memory)
typedef GAME_UPDATE_AND_RENDER(UpdateAndRender);

#ifdef __cplusplus
}
#endif

#endif
