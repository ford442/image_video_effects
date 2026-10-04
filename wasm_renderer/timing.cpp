#include "renderer.h"
#include "wasm_internal.h"
#include <webgpu/webgpu.h>
#include <cstdio>
#include <cmath>
#include <algorithm>
#include <memory>

namespace pixelocity {

using wasm_internal::MakeStringView;
using wasm_internal::kTsFrameStart;
using wasm_internal::kTsComputeEnd;
using wasm_internal::kTsParallelStart;
using wasm_internal::kTsParallelEnd;
using wasm_internal::kTsChainedStart;
using wasm_internal::kTsChainedEnd;
using wasm_internal::kTsPresentStart;
using wasm_internal::kTsPresentEnd;
using wasm_internal::kTsPhaseQueryCount;
using wasm_internal::kTsPassQueryBase;
using wasm_internal::kTsQueryCapacity;
using wasm_internal::kMaxProfiledSlotPasses;

// Phase block (8) + one begin/end pair per profiled compute pass.
static constexpr uint32_t TS_QUERY_COUNT = kTsQueryCapacity;
// Weight of the newest readback in the per-pass moving average (TS PASS_EMA_ALPHA).
static constexpr float kPassEmaAlpha = 0.3f;

static float TimestampDeltaMs(uint64_t start, uint64_t end, uint64_t periodNs) {
    if (periodNs == 0 || end <= start) return 0.0f;
    return static_cast<float>((end - start) * periodNs) / 1e6f;
}

bool WebGPURenderer::CreateTimestampQueries() {
    if (!device_.get() || !queue_.get()) return false;

    // The device, not the adapter, decides: the feature must have been granted.
    if (!wgpuDeviceHasFeature(device_.get(), WGPUFeatureName_TimestampQuery)) {
        printf("[WASM] Timestamp queries: device has no timestamp-query feature\n");
        supportsTimestampQuery_ = false;
        return false;
    }

    WGPUQuerySetDescriptor qsDesc = WGPU_QUERY_SET_DESCRIPTOR_INIT;
    qsDesc.label = MakeStringView("Timestamp Queries");
    qsDesc.type = WGPUQueryType_Timestamp;
    qsDesc.count = TS_QUERY_COUNT;
    timestampQuerySet_.reset(wgpuDeviceCreateQuerySet(device_.get(), &qsDesc));
    if (!timestampQuerySet_.get()) {
        printf("[WASM] Timestamp queries: failed to create query set\n");
        supportsTimestampQuery_ = false;
        return false;
    }

    WGPUBufferDescriptor resolveDesc = WGPU_BUFFER_DESCRIPTOR_INIT;
    resolveDesc.label = MakeStringView("Timestamp Resolve");
    resolveDesc.size = TS_QUERY_COUNT * sizeof(uint64_t);
    resolveDesc.usage = WGPUBufferUsage_QueryResolve | WGPUBufferUsage_CopySrc;
    resolveDesc.mappedAtCreation = false;
    timestampResolveBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &resolveDesc));
    if (!timestampResolveBuffer_.get()) {
        timestampQuerySet_.reset();
        supportsTimestampQuery_ = false;
        return false;
    }

    WGPUBufferDescriptor readDesc = WGPU_BUFFER_DESCRIPTOR_INIT;
    readDesc.label = MakeStringView("Timestamp Readback");
    readDesc.size = TS_QUERY_COUNT * sizeof(uint64_t);
    readDesc.usage = WGPUBufferUsage_CopyDst | WGPUBufferUsage_MapRead;
    readDesc.mappedAtCreation = false;
    timestampReadbackBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &readDesc));
    if (!timestampReadbackBuffer_.get()) {
        timestampQuerySet_.reset();
        timestampResolveBuffer_.reset();
        supportsTimestampQuery_ = false;
        return false;
    }

    // Browser WebGPU reports resolved timestamps in nanoseconds (emdawnwebgpu
    // has no wgpuQueueGetTimestampPeriod), so the period is a fixed 1 ns.
    timestampPeriodNs_ = 1;

    tsFramePasses_.reserve(kMaxProfiledSlotPasses);
    readbackPasses_.reserve(kMaxProfiledSlotPasses);

    supportsTimestampQuery_ = true;
    printf("[WASM] Timestamp queries enabled (period=%llu ns, %u profiled passes)\n",
           static_cast<unsigned long long>(timestampPeriodNs_), kMaxProfiledSlotPasses);
    return true;
}

void WebGPURenderer::ResetTimestampFrameState() {
    tsFrameStartWritten_ = false;
    tsHadParallel_ = false;
    tsHadChained_ = false;
    tsFramePasses_.clear();
}

void WebGPURenderer::PickComputeTimestampWrites(SlotMode mode, int slot,
                                                const std::string& shaderId,
                                                const std::string& label,
                                                int32_t& beginIndex, int32_t& endIndex) {
    beginIndex = -1;
    endIndex = -1;
    if (!supportsTimestampQuery_ || !timestampQuerySet_.get()) return;
    // Later passes run unprofiled (a 6-slot frame never gets close).
    if (tsFramePasses_.size() >= kMaxProfiledSlotPasses) return;

    const uint32_t passIndex = static_cast<uint32_t>(tsFramePasses_.size());
    tsFramePasses_.push_back(ProfiledPass{slot, mode, shaderId, label});
    beginIndex = static_cast<int32_t>(kTsPassQueryBase + 2u * passIndex);
    endIndex = beginIndex + 1;

    tsFrameStartWritten_ = true;
    if (mode == SlotMode::Parallel) {
        tsHadParallel_ = true;
    } else {
        tsHadChained_ = true;
    }
}

// Phase timings from the rebuilt phase block. Unchanged from the phase-only
// layout: mirrors TS decodeGpuTimings — indices a frame never wrote are 0, so
// fall back to frame start / compute end for the phase bounds.
static void DecodePhaseTimings(const uint64_t* stamps, bool hadParallel, bool hadChained,
                               uint64_t periodNs, float& parallelMs, float& chainedMs,
                               float& totalMs, bool& resolved) {
    const uint64_t frameStart = stamps[kTsFrameStart];
    const uint64_t computeEnd = stamps[kTsComputeEnd];
    uint64_t parallelStart = stamps[kTsParallelStart];
    uint64_t parallelEnd = stamps[kTsParallelEnd];
    if (hadParallel) {
        if (parallelStart == 0) parallelStart = frameStart;
        if (parallelEnd == 0) parallelEnd = computeEnd;
    }
    uint64_t chainedStart = stamps[kTsChainedStart];
    uint64_t chainedEnd = stamps[kTsChainedEnd];
    if (hadChained) {
        if (chainedStart == 0) {
            chainedStart = stamps[kTsParallelEnd] > 0 ? stamps[kTsParallelEnd] : frameStart;
        }
        if (chainedEnd == 0) chainedEnd = computeEnd;
    }

    parallelMs = hadParallel ? TimestampDeltaMs(parallelStart, parallelEnd, periodNs) : 0.0f;
    chainedMs = hadChained ? TimestampDeltaMs(chainedStart, chainedEnd, periodNs) : 0.0f;

    const float frameToPresent = TimestampDeltaMs(
        stamps[kTsFrameStart], stamps[kTsPresentEnd], periodNs);
    const float computeOnly = TimestampDeltaMs(
        stamps[kTsFrameStart], stamps[kTsComputeEnd], periodNs);
    totalMs = frameToPresent > 0.0f ? frameToPresent : computeOnly;

    resolved = (stamps[kTsFrameStart] > 0 && stamps[kTsPresentEnd] > stamps[kTsFrameStart])
            || (stamps[kTsFrameStart] > 0 && stamps[kTsComputeEnd] > stamps[kTsFrameStart]);
}

void WebGPURenderer::OnTimestampReadback(WGPUMapAsyncStatus status, void* userdata) {
    auto* self = static_cast<WebGPURenderer*>(userdata);
    if (!self) return;
    self->timestampReadbackPending_ = false;

    // A failed or cancelled map leaves the buffer unmapped; nothing to undo.
    if (status != WGPUMapAsyncStatus_Success) return;

    const uint32_t queryCount = self->readbackQueryCount_;
    const void* mapped = wgpuBufferGetConstMappedRange(
        self->timestampReadbackBuffer_.get(), 0, queryCount * sizeof(uint64_t));
    if (!mapped) {
        wgpuBufferUnmap(self->timestampReadbackBuffer_.get());
        return;
    }

    self->DecodeTimestampReadback(static_cast<const uint64_t*>(mapped), queryCount);
    wgpuBufferUnmap(self->timestampReadbackBuffer_.get());
}

// Kept out of the map callback: that callback is ASYNCIFY-instrumented, and
// inlining this pure decode into it cost ~2 KB of .wasm.
__attribute__((noinline))
void WebGPURenderer::DecodeTimestampReadback(const uint64_t* stamps, uint32_t queryCount) {
    std::vector<ProfiledPass>& passes = readbackPasses_;
    const size_t passCount = std::min<size_t>(
        passes.size(), queryCount > kTsPassQueryBase ? (queryCount - kTsPassQueryBase) / 2 : 0);
    const uint64_t* pairs = stamps + kTsPassQueryBase;

    // Rebuild the phase block a pass-pair frame no longer writes: frame start
    // = first pass begin, compute end = last pass end, phase starts = first
    // pass of that mode. Same values the phase-only layout stamped.
    uint64_t phase[kTsPhaseQueryCount] = {};
    phase[kTsPresentStart] = stamps[kTsPresentStart];
    phase[kTsPresentEnd] = stamps[kTsPresentEnd];
    bool sawParallel = false;
    bool sawChained = false;
    for (size_t i = 0; i < passCount; ++i) {
        const uint64_t begin = pairs[2 * i];
        if (i == 0) phase[kTsFrameStart] = begin;
        if (i + 1 == passCount) phase[kTsComputeEnd] = pairs[2 * i + 1];
        if (passes[i].mode == SlotMode::Parallel) {
            if (!sawParallel) phase[kTsParallelStart] = begin;
            sawParallel = true;
        } else {
            if (!sawChained) phase[kTsChainedStart] = begin;
            sawChained = true;
        }
    }
    DecodePhaseTimings(phase, readbackHadParallel_, readbackHadChained_, timestampPeriodNs_,
                       gpuParallelTimeMs_, gpuChainedTimeMs_, gpuTotalTimeMs_,
                       gpuTimingsResolved_);

    // Per-pass decode (TS decodePassTimings): one entry per slot:label key,
    // iterations summed, then folded into the moving average. The snapshot is
    // dead after this, so its strings are moved, not copied.
    std::vector<PassTimingEntry> next;
    next.reserve(passCount);
    bool valid = false;
    for (size_t i = 0; i < passCount; ++i) {
        const uint64_t begin = pairs[2 * i];
        const uint64_t end = pairs[2 * i + 1];
        const bool ok = begin > 0 && end > begin;
        if (ok) valid = true;
        const float ms = ok ? TimestampDeltaMs(begin, end, timestampPeriodNs_) : 0.0f;
        ProfiledPass& meta = passes[i];
        PassTimingEntry* same = nullptr;
        for (PassTimingEntry& e : next) {
            if (e.slot == meta.slot && e.label == meta.label) { same = &e; break; }
        }
        if (same) {
            same->gpuMs += ms;
            same->iterations++;
        } else {
            next.push_back(PassTimingEntry{meta.slot, std::move(meta.shaderId),
                                           std::move(meta.label), ms, 1});
        }
    }
    passes.clear();

    if (!valid) return;
    for (PassTimingEntry& entry : next) {
        for (const PassTimingEntry& prev : passTimings_) {
            if (prev.slot == entry.slot && prev.label == entry.label) {
                entry.gpuMs = prev.gpuMs + (entry.gpuMs - prev.gpuMs) * kPassEmaAlpha;
                break;
            }
        }
    }
    // Passes absent from this readback drop out (TS smoothPassTimings).
    passTimings_.swap(next);
}

void WebGPURenderer::ResolveTimestampQueries() {
    if (!supportsTimestampQuery_ || !timestampQuerySet_.get() || !queue_.get() || !device_.get()) {
        return;
    }
    // Must resolve every frame that wrote timestamps. Gating resolve on
    // mapAsync completion left query indices written, so the next frame's
    // double-write failed validation and dropped the present (black flicker).
    if (!tsFrameStartWritten_) {
        return;
    }

    // Phase block + this frame's pass pairs, resolved in one range.
    const uint32_t queryCount =
        kTsPassQueryBase + 2u * static_cast<uint32_t>(tsFramePasses_.size());

    WGPUCommandEncoderHandle enc(CreateEncoder("Timestamp Resolve Encoder"));
    if (!enc) return;

    wgpuCommandEncoderResolveQuerySet(
        enc,
        timestampQuerySet_.get(),
        0,
        queryCount,
        timestampResolveBuffer_.get(),
        0);

    // When a prior readback is still mapped, resolve-only (frees query set)
    // and skip the CPU copy/map for this frame.
    const bool canReadback = !timestampReadbackPending_ && timestampReadbackBuffer_.get();
    if (canReadback) {
        wgpuCommandEncoderCopyBufferToBuffer(
            enc,
            timestampResolveBuffer_.get(), 0,
            timestampReadbackBuffer_.get(), 0,
            queryCount * sizeof(uint64_t));
    }

    FinishAndSubmit(enc, "Timestamp Resolve CmdBuf");

    if (!canReadback) {
        return;
    }

    timestampReadbackPending_ = true;
    readbackHadParallel_ = tsHadParallel_;
    readbackHadChained_ = tsHadChained_;
    readbackQueryCount_ = queryCount;
    // The frame's pass list is rebuilt from empty next Render(); hand it over.
    readbackPasses_.swap(tsFramePasses_);
    tsFramePasses_.clear();
    wgpuBufferMapAsync(
        timestampReadbackBuffer_.get(),
        WGPUMapMode_Read,
        0,
        queryCount * sizeof(uint64_t),
        WGPUBufferMapCallbackInfo{
            nullptr,
            WGPUCallbackMode_AllowSpontaneous,
            [](WGPUMapAsyncStatus status, WGPUStringView /*message*/,
               void* userdata1, void* /*userdata2*/) {
                std::unique_ptr<CallbackBox> box(static_cast<CallbackBox*>(userdata1));
                // Null after Shutdown(): the buffer and renderer are gone.
                if (WebGPURenderer* self = box->Get()) OnTimestampReadback(status, self);
            },
            NewCallbackBox(),
            nullptr
        });
}

const char* WebGPURenderer::GetPassTimingsJson() {
    using wasm_internal::AppendInt;
    using wasm_internal::AppendJsonString;
    using wasm_internal::AppendLit;
    using wasm_internal::AppendUInt;
    std::string& out = passTimingsJson_;
    out.clear();
    AppendLit(out, "[");
    for (size_t i = 0; i < passTimings_.size(); ++i) {
        const PassTimingEntry& p = passTimings_[i];
        if (i > 0) AppendLit(out, ",");
        AppendLit(out, "{\"slot\":");
        AppendInt(out, p.slot);
        AppendLit(out, ",\"shaderId\":");
        AppendJsonString(out, p.shaderId.c_str());
        AppendLit(out, ",\"label\":");
        AppendJsonString(out, p.label.c_str());
        // Fixed point at 0.1 us, finer than browser timestamp quantization.
        const float ms = std::isfinite(p.gpuMs) && p.gpuMs > 0.0f ? p.gpuMs : 0.0f;
        const auto tenthsOfUs = static_cast<uint64_t>(static_cast<double>(ms) * 1e4 + 0.5);
        AppendLit(out, ",\"gpuMs\":");
        AppendUInt(out, tenthsOfUs / 10000u);
        AppendLit(out, ".");
        AppendUInt(out, tenthsOfUs % 10000u, 4);
        AppendLit(out, ",\"iterations\":");
        AppendInt(out, p.iterations);
        AppendLit(out, "}");
    }
    AppendLit(out, "]");
    return out.c_str();
}

} // namespace pixelocity
