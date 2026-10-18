#pragma once

#include <webgpu/webgpu.h>
#include <cstdint>
#include <string>

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
    bool writesDepth = false;  // binding 6 (depth write); gates depthWrite → depthRead feedback
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
constexpr uint32_t kTsPhaseQueryCount = 8;

// Per-pass profiling (#1314 D, measurement only). Each compute pass a slot
// encodes gets its own begin/end pair after the phase block:
//   pass i -> queries kTsPassQueryBase + 2i (begin), + 2i + 1 (end).
// A pass descriptor carries one begin and one end index, so compute passes
// stamp only their pair; the phase stamps above are rebuilt from the pairs at
// decode (timing.cpp). Present still writes kTsPresentStart/End directly.
constexpr uint32_t kMaxProfiledSlotPasses = 64;
constexpr uint32_t kTsPassQueryBase = kTsPhaseQueryCount;
constexpr uint32_t kTsQueryCapacity = kTsPhaseQueryCount + 2 * kMaxProfiledSlotPasses;

WGPUStringView MakeStringView(const char* str);
uint32_t AlignUp(uint32_t value, uint32_t align);
bool CheckLimit(const char* name, uint64_t have, uint64_t need, bool& ok);
void ParseWorkgroupSize(const char* wgslCode, uint32_t& x, uint32_t& y);
ShaderBindingUsage AnalyzeShaderBindings(const char* wgslCode);
/** Force write-only rgba storage decls onto the allocated BGL format (rgba16float or rgba32float). */
std::string RewriteWgslStorageFormats(const char* wgsl, const char* colorFormat);
/**
 * True when a live (non-commented) `#include` directive survived expansion.
 * Detection only — expansion belongs to src/wasm/bridge/wgslInclude.ts, the one
 * implementation. See src/contracts/wgsl_include.json.
 */
bool ContainsWgslIncludeDirective(const char* wgsl);
/** out.append(s, n), kept out of line (size: see wasm_internal.cpp). */
void AppendRaw(std::string& out, const char* s, size_t n);
/** AppendRaw for a string literal (length from the array, not by hand). */
template <size_t N>
inline void AppendLit(std::string& out, const char (&lit)[N]) { AppendRaw(out, lit, N - 1); }
/** Decimal digits of v, zero-padded to minDigits (no snprintf; see wasm_internal.cpp). */
void AppendUInt(std::string& out, uint64_t v, int minDigits = 1);
void AppendInt(std::string& out, int64_t v);
/** Append `s` to `out` as a quoted JSON string (quotes, backslashes, control chars escaped). */
void AppendJsonString(std::string& out, const char* s);

} // namespace wasm_internal
} // namespace pixelocity
