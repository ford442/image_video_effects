#pragma once

#include <webgpu/webgpu.h>
#include <cstdint>

// WGPU_DEPTH_SLICE_UNDEFINED was added in the 2024 WebGPU spec update; provide
// a fallback if the installed header predates the addition.
#ifndef WGPU_DEPTH_SLICE_UNDEFINED
static constexpr uint32_t WGPU_DEPTH_SLICE_UNDEFINED = 0xFFFFFFFFu;
#endif

namespace pixelocity {
namespace wasm_internal {

/** Which optional per-frame texture copies a shader needs (mirrors TS ShaderBindingUsage). */
struct ShaderBindingUsage {
    bool writesDataA = false;
    bool writesDataB = false;
    bool readsDataC = false;
    bool usesHistory = false;
};

// Timestamp query indices (keep in sync with timing.cpp / WebGPURenderer.ts).
constexpr int32_t kTsFrameStart    = 0;
constexpr int32_t kTsComputeEnd    = 1;
constexpr int32_t kTsParallelStart = 2;
constexpr int32_t kTsParallelEnd   = 3;
constexpr int32_t kTsChainedStart  = 4;
constexpr int32_t kTsChainedEnd    = 5;
constexpr int32_t kTsPresentStart  = 6;
constexpr int32_t kTsPresentEnd    = 7;

WGPUStringView MakeStringView(const char* str);
uint32_t AlignUp(uint32_t value, uint32_t align);
bool CheckLimit(const char* name, uint64_t have, uint64_t need, bool& ok);
void ParseWorkgroupSize(const char* wgslCode, uint32_t& x, uint32_t& y);
ShaderBindingUsage AnalyzeShaderBindings(const char* wgslCode);

} // namespace wasm_internal
} // namespace pixelocity
