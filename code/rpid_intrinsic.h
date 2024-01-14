#ifndef RPID_INTRINSIC_H
#define RPID_INTRINSIC_H

// NOTE(gh) intrinsic functions are those that the provided by the compiler based on the language(some are non_portable).
// Most of the bit operations are included in this case, including sin, cos functions, too.
// To know more, check https://en.wikipedia.org/wiki/Intrinsic_function

// TODO(gh) Remove this!!!
#include <math.h>

// TODO(gh) add functionality for other compilers(gcc, msvc)
// NOTE(gh) kinda interesting that they do not have compare exchange for floating point numbers

#if RPID_LLVM
// TODO(gh) Can also be used for GCC, because this is a GCC extension of Clang?
//#elif RPID_GCC

// NOTE(gh) These functions do not care whether it's 32bit or 64bit
#define atomic_compare_exchange(ptr, expected, desired) __sync_bool_compare_and_swap(ptr, expected, desired)
#define atomic_compare_exchange_64(ptr, expected, desired) __sync_bool_compare_and_swap(ptr, expected, desired)

// TODO(gh) Do we really need increment intrinsics?
#define atomic_increment(ptr) __sync_add_and_fetch(ptr, 1)
#define atomic_increment_64(ptr) __sync_add_and_fetch(ptr, 1)

#define atomic_add(ptr, value_to_add) __atomic_add_fetch(ptr, value_to_add, __ATOMIC_RELAXED)
#define atomic_add_64(ptr, value_to_add) __atomic_add_fetch(ptr, value_to_add, __ATOMIC_RELAXED)

// TODO(gh) mem order?
#define atomic_exchange(ptr, value) __atomic_exchange_n(ptr, value, __ATOMIC_SEQ_CST)
#endif

#elif RPID_MSVC

inline u32
count_set_bit(u32 value, u32 size_in_bytes)
{
    u32 result = 0;

    u32 size_in_bit = 8 * size_in_bytes;
    for(u32 bit_shift_index = 0;
            bit_shift_index < size_in_bit;
            ++bit_shift_index)
    {
        if(value & (1 << bit_shift_index))
        {
            result++;
        }
    }

    return result;
}

inline u32
find_most_significant_bit(u8 value)
{
    u32 result = 0;
    for(u32 bit_shift_index = 0;
            bit_shift_index < 8;
            ++bit_shift_index)
    {
        if(value & 128)
        {
            result = bit_shift_index;
            break;
        }

        value = value << 1;
    }

    return result;
}

#define sin(value) sin_(value)
#define cos(value) cos_(value)
#define acos(value) acos_(value)
#define atan2(y, x) atan2_(y, x)

inline f32
sin_(f32 rad)
{
    // TODO(gh) : intrinsic?
    return sinf(rad);
}

inline f32
cos_(f32 rad)
{
    // TODO(gh) : intrinsic?
    return cosf(rad);
}

inline f32
acos_(f32 rad)
{
    return acosf(rad);
}

inline f32
atan2_(f32 y, f32 x)
{
    return atan2f(y, x);
}

inline i32
round_f32_to_i32(f32 value)
{
    // TODO(gh) : intrinsic?
    return (i32)roundf(value);
}

inline u32
round_f32_to_u32(f32 value)
{
    // TODO(gh) : intrinsic?
    return (u32)roundf(value);
}

inline u32
round_f64_to_u32(f64 value)
{
    return (u32)round(value);
}

inline u32
ceil_f32_to_u32(f32 value)
{
    return (u32)ceilf(value);
}

inline f32
floor_f32(f32 value)
{
    return floorf(value);
}

inline f32
power(f32 base, u32 exponent)
{
    f32 result = powf(base, exponent);
    return result;
}

inline u32
power(u32 base, u32 exponent)
{
    u32 result = 1;
    if(exponent != 0)
    {
        for(u32 i = 0;
                i < exponent;
                ++i)
        {
            result *= base;
        }
    }

    return result; 
}

#if 1
inline f32
abs_f32(f32 value)
{
    f32 result = fabsf(value);

    return result;
}

inline f64
abs_f64(f64 value)
{
    f64 result = fabs(value);

    return result;
}
#endif

// TODO(gh) this function can go wrong so easily...
inline u64
pointer_diff(void *start, void *end)
{
    //assert(start && end);
    u64 result = ((u8 *)start - (u8 *)end);

    return result;
}

#include <string.h>
// TODO/gh: intrinsic zero memory?
// TODO(gh): can be faster using wider vectors
inline void
zero_memory(void *memory, u64 size)
{
    // TODO(gh) Is this actually faster than memset?
#if 0
    u8 *byte = (u8 *)memory;
    uint8x16_t zero_128 = vdupq_n_u8(0);

    while(size > 16)
    {
        vst1q_u8(byte, zero_128);

        byte += 16;
        size -= 16;
    }

    if(size > 0)
    {
        while(size--)
        {
            *byte++ = 0;
        }
    }
#else
    // TODO(gh): support for intel simd, too!
    memset (memory, 0, size);
#endif
}

// TODO(gh): Intrinsic?
inline u8
reverse_bits(u8 value)
{
    u8 result = 0;

    for(u32 i = 0;
            i < 8;
            ++i)
    {
        if(((value >> i) & 1) == 0)
        {
            result |= (1 << i);
        }
    }

    return result;
}

#endif

