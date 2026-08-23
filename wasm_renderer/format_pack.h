#pragma once

#include "performance_policy.h"
#include <cstdint>
#include <cstring>
#include <vector>

// IEEE-754 binary16 pack/unpack for rgba16float queue writes.
// Keep in sync with src/config/formatPolicy.ts floatToHalfBits / packRgbaUploadData.
namespace pixelocity::format_pack {

inline uint16_t FloatToHalf(float value) {
    uint32_t x = 0;
    std::memcpy(&x, &value, sizeof(x));
    const uint32_t sign = (x >> 16) & 0x8000u;
    const uint32_t exp = (x >> 23) & 0xffu;
    const uint32_t mant = x & 0x7fffffu;

    if (exp == 255u) {
        if (mant == 0u) return static_cast<uint16_t>(sign | 0x7c00u);
        return static_cast<uint16_t>(sign | 0x7c00u | (mant >> 13) | 0x0200u);
    }
    if (exp == 0u) {
        return static_cast<uint16_t>(sign);
    }

    const int newExp = static_cast<int>(exp) - 127 + 15;
    if (newExp >= 31) return static_cast<uint16_t>(sign | 0x7c00u);
    if (newExp <= 0) {
        if (newExp < -10) return static_cast<uint16_t>(sign);
        const uint32_t den = (mant | 0x800000u) >> (1 - newExp);
        return static_cast<uint16_t>(sign | (den >> 13));
    }
    return static_cast<uint16_t>(sign | (static_cast<uint32_t>(newExp) << 10) | (mant >> 13));
}

inline float HalfToFloat(uint16_t h) {
    const uint32_t sign = (static_cast<uint32_t>(h & 0x8000u) << 16);
    const uint32_t exp = (h >> 10) & 0x1fu;
    const uint32_t mant = h & 0x3ffu;
    uint32_t f = 0;
    if (exp == 0u) {
        if (mant == 0u) {
            f = sign;
        } else {
            uint32_t m = mant;
            int e = -14;
            while ((m & 0x400u) == 0u) {
                m <<= 1;
                --e;
            }
            m &= 0x3ffu;
            f = sign | (static_cast<uint32_t>(e + 127) << 23) | (m << 13);
        }
    } else if (exp == 31u) {
        f = sign | 0x7f800000u | (mant << 13);
    } else {
        f = sign | ((exp - 15u + 127u) << 23) | (mant << 13);
    }
    float out;
    std::memcpy(&out, &f, sizeof(out));
    return out;
}

inline uint32_t BytesPerPixel(policy::InternalColorFormat fmt) {
    return policy::BytesPerPixelRgba(fmt);
}

inline uint32_t BytesPerRow(int width, policy::InternalColorFormat fmt) {
    return static_cast<uint32_t>(width) * BytesPerPixel(fmt);
}

/** Pack float32 RGBA into the allocated storage format. rgba32float is a view of src. */
inline void PackRgba(
    const float* src,
    size_t floatCount,
    policy::InternalColorFormat fmt,
    std::vector<uint8_t>& dst
) {
    if (fmt == policy::InternalColorFormat::Rgba32Float) {
        const size_t bytes = floatCount * sizeof(float);
        dst.resize(bytes);
        std::memcpy(dst.data(), src, bytes);
        return;
    }
    const size_t halfCount = floatCount;
    dst.resize(halfCount * sizeof(uint16_t));
    auto* out = reinterpret_cast<uint16_t*>(dst.data());
    for (size_t i = 0; i < halfCount; ++i) {
        out[i] = FloatToHalf(src[i]);
    }
}

}  // namespace pixelocity::format_pack
