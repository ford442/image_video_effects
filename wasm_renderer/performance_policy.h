#pragma once

// Keep in sync with src/config/performancePolicy.ts
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

}  // namespace pixelocity::policy
