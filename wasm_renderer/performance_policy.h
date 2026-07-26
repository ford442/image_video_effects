#pragma once

// Keep in sync with src/config/performancePolicy.ts and src/config/formatPolicy.ts
namespace pixelocity::policy {

constexpr int kInternalRenderResolution = 2048;
constexpr int kRenderWorkgroupSize      = 16;

constexpr float kMinRenderScale = 0.25f;
constexpr float kMaxRenderScale = 1.0f;

// Preset scales (Battery / Balanced / Ultra)
constexpr float kBatteryScale   = 0.5f;
constexpr float kBalancedScale  = 0.75f;
constexpr float kUltraScale     = 1.0f;

constexpr int kBatteryMaxSlots   = 1;
constexpr int kBalancedMaxSlots  = 2;
constexpr int kUltraMaxSlots     = 3;
constexpr int kLowEndMaxSlots    = 1;

// Tier C graph pass caps — keep in sync with src/config/performancePolicy.ts
// WASM GraphRunner follow-up: GH #929

constexpr int kBatteryMaxPassesPerFrame  = 4;
constexpr int kBalancedMaxPassesPerFrame = 8;
constexpr int kUltraMaxPassesPerFrame    = 16;
constexpr int kAutoMobileMaxPassesPerFrame = 6;
constexpr int kAutoDesktopMaxPassesPerFrame = 12;

// Internal color storage format — see docs/FORMAT_TIERS.md
enum class InternalColorFormat : int {
    Rgba32Float = 0,
    Rgba16Float = 1,
};

constexpr InternalColorFormat kUltraColorFormat     = InternalColorFormat::Rgba32Float;
constexpr InternalColorFormat kBalancedColorFormat = InternalColorFormat::Rgba16Float;
constexpr InternalColorFormat kBatteryColorFormat  = InternalColorFormat::Rgba16Float;

constexpr uint32_t kRgba32BytesPerPixel = 16u;
constexpr uint32_t kRgba16BytesPerPixel = 8u;

inline uint32_t BytesPerPixelRgba(InternalColorFormat fmt) {
    return fmt == InternalColorFormat::Rgba32Float ? kRgba32BytesPerPixel : kRgba16BytesPerPixel;
}

}  // namespace pixelocity::policy
