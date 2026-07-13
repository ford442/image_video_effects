#include "renderer.h"
#include "wasm_internal.h"
#include <webgpu/webgpu.h>
#include <cstdio>
#include <algorithm>

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

static constexpr uint32_t TS_QUERY_COUNT = 8;

static float TimestampDeltaMs(uint64_t start, uint64_t end, uint64_t periodNs) {
    if (periodNs == 0 || end <= start) return 0.0f;
    return static_cast<float>((end - start) * periodNs) / 1e6f;
}

bool WebGPURenderer::CreateTimestampQueries() {
    if (!device_.get() || !queue_.get()) return false;

#ifndef WGPUFeatureName_TimestampQuery
    supportsTimestampQuery_ = false;
    return false;
#else
    if (!wgpuAdapterHasFeature(adapter_.get(), WGPUFeatureName_TimestampQuery)) {
        printf("[WASM] Timestamp queries: adapter does not support timestamp-query\n");
        supportsTimestampQuery_ = false;
        return false;
    }

    WGPUQuerySetDescriptor qsDesc = {};
    qsDesc.label = MakeStringView("Timestamp Queries");
    qsDesc.type = WGPUQueryType_Timestamp;
    qsDesc.count = TS_QUERY_COUNT;
    timestampQuerySet_.reset(wgpuDeviceCreateQuerySet(device_.get(), &qsDesc));
    if (!timestampQuerySet_.get()) {
        printf("[WASM] Timestamp queries: failed to create query set\n");
        supportsTimestampQuery_ = false;
        return false;
    }

    WGPUBufferDescriptor resolveDesc = {};
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

    WGPUBufferDescriptor readDesc = {};
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

    timestampPeriodNs_ = wgpuQueueGetTimestampPeriod(queue_.get());
    if (timestampPeriodNs_ == 0) {
        printf("[WASM] Timestamp queries: queue timestamp period is 0 — using wall-clock fallback\n");
        timestampQuerySet_.reset();
        timestampResolveBuffer_.reset();
        timestampReadbackBuffer_.reset();
        supportsTimestampQuery_ = false;
        return false;
    }

    supportsTimestampQuery_ = true;
    printf("[WASM] Timestamp queries enabled (period=%llu ns)\n",
           static_cast<unsigned long long>(timestampPeriodNs_));
    return true;
#endif
}

void WebGPURenderer::ResetTimestampFrameState() {
    tsFrameStartWritten_ = false;
    tsParallelStartWritten_ = false;
    tsChainedStartWritten_ = false;
}

void WebGPURenderer::OnTimestampReadback(WGPUMapAsyncStatus status, void* userdata) {
    auto* self = static_cast<WebGPURenderer*>(userdata);
    if (!self) return;
    self->timestampReadbackPending_ = false;

    if (status != WGPUMapAsyncStatus_Success) {
        if (self->timestampReadbackBuffer_.get()) {
            wgpuBufferUnmap(self->timestampReadbackBuffer_.get());
        }
        return;
    }

    const void* mapped = wgpuBufferGetConstMappedRange(
        self->timestampReadbackBuffer_.get(), 0, TS_QUERY_COUNT * sizeof(uint64_t));
    if (!mapped) {
        wgpuBufferUnmap(self->timestampReadbackBuffer_.get());
        return;
    }

    const auto* stamps = static_cast<const uint64_t*>(mapped);

    self->gpuParallelTimeMs_ = TimestampDeltaMs(
        stamps[kTsParallelStart], stamps[kTsParallelEnd], self->timestampPeriodNs_);
    self->gpuChainedTimeMs_ = TimestampDeltaMs(
        stamps[kTsChainedStart], stamps[kTsChainedEnd], self->timestampPeriodNs_);

    const float frameToPresent = TimestampDeltaMs(
        stamps[kTsFrameStart], stamps[kTsPresentEnd], self->timestampPeriodNs_);
    const float computeOnly = TimestampDeltaMs(
        stamps[kTsFrameStart], stamps[kTsComputeEnd], self->timestampPeriodNs_);
    self->gpuTotalTimeMs_ = frameToPresent > 0.0f ? frameToPresent : computeOnly;

    self->gpuTimingsResolved_ = (stamps[kTsFrameStart] > 0 && stamps[kTsPresentEnd] > stamps[kTsFrameStart])
                             || (stamps[kTsFrameStart] > 0 && stamps[kTsComputeEnd] > stamps[kTsFrameStart]);

    wgpuBufferUnmap(self->timestampReadbackBuffer_.get());
}

void WebGPURenderer::ResolveTimestampQueries() {
    if (!supportsTimestampQuery_ || !timestampQuerySet_.get() || !queue_.get() || !device_.get()) {
        return;
    }
    if (!tsFrameStartWritten_ || timestampReadbackPending_) {
        return;
    }

    WGPUCommandEncoderDescriptor encDesc = {};
    encDesc.label = MakeStringView("Timestamp Resolve Encoder");
    WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);
    if (!enc) return;

    wgpuCommandEncoderResolveQuerySet(
        enc,
        timestampQuerySet_.get(),
        0,
        TS_QUERY_COUNT,
        timestampResolveBuffer_.get(),
        0);

    wgpuCommandEncoderCopyBufferToBuffer(
        enc,
        timestampResolveBuffer_.get(), 0,
        timestampReadbackBuffer_.get(), 0,
        TS_QUERY_COUNT * sizeof(uint64_t));

    WGPUCommandBufferDescriptor cbDesc = {};
    cbDesc.label = MakeStringView("Timestamp Resolve CmdBuf");
    WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
    wgpuQueueSubmit(queue_.get(), 1, &cb);
    wgpuCommandBufferRelease(cb);
    wgpuCommandEncoderRelease(enc);

    timestampReadbackPending_ = true;
    wgpuBufferMapAsync(
        timestampReadbackBuffer_.get(),
        WGPUMapMode_Read,
        0,
        TS_QUERY_COUNT * sizeof(uint64_t),
        WGPUBufferMapCallbackInfo{
            nullptr,
            WGPUCallbackMode_AllowSpontaneous,
            [](WGPUMapAsyncStatus status, WGPUStringView /*message*/,
               void* userdata1, void* /*userdata2*/) {
                OnTimestampReadback(status, userdata1);
            },
            this,
            nullptr
        });
}

} // namespace pixelocity
