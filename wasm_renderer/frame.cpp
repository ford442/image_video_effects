#include "renderer.h"
#include "wasm_internal.h"
#include "format_pack.h"
#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <array>
#include <algorithm>
#include <vector>

namespace pixelocity {

using wasm_internal::MakeStringView;
using wasm_internal::AlignUp;
using wasm_internal::CheckLimit;
using wasm_internal::ParseWorkgroupSize;
using wasm_internal::kTsFrameStart;
using wasm_internal::kTsComputeEnd;
using wasm_internal::kTsParallelStart;
using wasm_internal::kTsParallelEnd;
using wasm_internal::kTsChainedStart;
using wasm_internal::kTsChainedEnd;

static void CopyTex(WGPUCommandEncoder enc,
                    WGPUTexture src, WGPUTexture dst,
                    uint32_t w, uint32_t h) {
    WGPUTexelCopyTextureInfo s = {};
    s.texture = src; s.mipLevel = 0; s.origin = {0,0,0}; s.aspect = WGPUTextureAspect_All;
    WGPUTexelCopyTextureInfo d = {};
    d.texture = dst; d.mipLevel = 0; d.origin = {0,0,0}; d.aspect = WGPUTextureAspect_All;
    WGPUExtent3D ext = { w, h, 1 };
    wgpuCommandEncoderCopyTextureToTexture(enc, &s, &d, &ext);
}

void WebGPURenderer::UpdateUniformBuffer(bool includeHistoryHead) {
    if (!uniformBuffer_.get()) return;

    // Use std::array to avoid VLA (non-standard extension) and ensure stack allocation.
    static constexpr size_t UNIFORM_FLOAT_COUNT = 12 + MAX_RIPPLES * 4;
    std::array<float, UNIFORM_FLOAT_COUNT> uniformData = {};

    // config: time, rippleCount, resolutionX, resolutionY
    uniformData[0] = currentTime_;
    uniformData[1] = static_cast<float>(ripples_.size());
    uniformData[2] = static_cast<float>(canvasWidth_);
    uniformData[3] = static_cast<float>(canvasHeight_);

    // zoom_config: time, mouseX, mouseY, mouseDown
    uniformData[4] = currentTime_;
    uniformData[5] = mouseX_;
    uniformData[6] = mouseY_;
    uniformData[7] = mouseDown_ ? 1.0f : 0.0f;

    // zoom_params (global defaults; per-slot params are patched via WriteSlotParams)
    uniformData[8]  = zoomParams_[0];
    uniformData[9]  = zoomParams_[1];
    uniformData[10] = zoomParams_[2];
    uniformData[11] = zoomParams_[3];

    // ripples
    for (size_t i = 0; i < MAX_RIPPLES; i++) {
        if (i < ripples_.size()) {
            uniformData[12 + i * 4 + 0] = ripples_[i].x;
            uniformData[12 + i * 4 + 1] = ripples_[i].y;
            uniformData[12 + i * 4 + 2] = ripples_[i].startTime;
            uniformData[12 + i * 4 + 3] = 0.0f;
        } else {
            uniformData[12 + i * 4 + 0] = 0.0f;
            uniformData[12 + i * 4 + 1] = 0.0f;
            uniformData[12 + i * 4 + 2] = 0.0f;
            uniformData[12 + i * 4 + 3] = 0.0f;
        }
    }

    wgpuQueueWriteBuffer(queue_.get(), uniformBuffer_.get(), 0, uniformData.data(), uniformData.size() * sizeof(float));

    // Upload audio + FFT bins to extraBuffer_ (binding 10).
    // Layout matches TypeScript WebGPURenderer extraBuffer:
    //   [0]=bass [1]=mid [2]=treble [3]=reserved [4]=historyHead [5..132]=FFT bins
    if (extraBuffer_.get()) {
        float extraData[256] = {};
        extraData[0] = audioBass_;
        extraData[1] = audioMid_;
        extraData[2] = audioTreble_;
        extraData[3] = 0.0f;
        if (includeHistoryHead) {
            extraData[4] = static_cast<float>(historyHead_);
        } else {
            extraData[4] = 0.0f;
        }
        for (int i = 0; i < AUDIO_FFT_BINS; ++i) {
            extraData[EXTRA_BIN_OFFSET + i] = audioFreqBins_[i];
        }
        wgpuQueueWriteBuffer(queue_.get(), extraBuffer_.get(), 0, extraData, sizeof(extraData));
    }

    // Upload audio to plasmaBuffer_ (binding 12) as vec4(bass, mid, treble, 0).
    // Shaders using the AGENTS.md audio convention read from here:
    //   let bass   = plasmaBuffer[0].x;
    //   let mids   = plasmaBuffer[0].y;
    //   let treble = plasmaBuffer[0].z;
    if (plasmaBuffer_.get()) {
        float audioVec4[4] = { audioBass_, audioMid_, audioTreble_, 0.0f };
        wgpuQueueWriteBuffer(queue_.get(), plasmaBuffer_.get(), 0, audioVec4, sizeof(audioVec4));
    }
}

// ─── Render ──────────────────────────────────────────────────────────────────
//
// Multi-slot rendering pipeline (Phase 1):
//
//   source (readTexture_)
//     -> Slot 0 compute -> pingPong0_
//     -> Slot 1 compute -> pingPong1_
//     -> Slot 2 compute -> writeTexture_
//   Then: writeTexture_ -> readTexture_  (temporal feedback for next frame)
//         depthWrite_   -> depthRead_
//         dataTextureA_ -> dataTextureC_  (data-texture feedback)
//
// Each slot submission is a separate wgpuQueueSubmit so that per-slot
// zoom_params can be patched in the shared uniform buffer between passes
// while preserving queue FIFO ordering.
//
// Slots that reference the same texture as their output and the next slot's
// input are safe because wgpuQueueSubmit flushes operations in order.

// Helper: copy one texture to another within an already-open encoder.
void WebGPURenderer::Render() {
    if (!initialized_ || deviceLost_ || !device_.get() || !queue_.get()) return;

    const double renderStartMs = emscripten_get_now();
    lastParallelTimeMs_ = 0.0f;
    lastChainedTimeMs_  = 0.0f;
    ResetTimestampFrameState();

    // Upload all per-frame global uniforms (time, mouse, ripples, audio).
    // historyHead in extraBuffer[4] is written only when a shader uses binding 13.
    // (Computed below after slot scan; call deferred until usage is known.)

    const uint32_t W = static_cast<uint32_t>(canvasWidth_);
    const uint32_t H = static_cast<uint32_t>(canvasHeight_);

    // Aggregate binding usage across enabled slots (mirrors TS frame.ts).
    bool anyReadsC = false;
    bool anyWritesDataA = false;
    bool anyWritesDataB = false;
    bool anyUsesHistory = false;

    auto accumulateUsage = [&](const ShaderPipeline& sp) {
        anyReadsC = anyReadsC || sp.readsDataC;
        anyWritesDataA = anyWritesDataA || sp.writesDataA;
        anyWritesDataB = anyWritesDataB || sp.writesDataB;
        anyUsesHistory = anyUsesHistory || sp.usesHistory;
    };

    // Fixed output texture per slot index.
    WGPUTexture slotOutput[MAX_SHADER_SLOTS] = { pingPong0_.get(), pingPong1_.get(), writeTexture_.get() };

    // Determine the first enabled slot and the last enabled slot.
    // If no slot is configured, fall back to the legacy activeShaderId_.
    int firstEnabled = -1;
    int lastEnabled  = -1;
    for (int i = 0; i < MAX_SHADER_SLOTS; i++) {
        if (slots_[i].enabled && !slots_[i].shaderId.empty() &&
            shaders_.find(slots_[i].shaderId) != shaders_.end()) {
            if (firstEnabled < 0) firstEnabled = i;
            lastEnabled = i;
        }
    }

    if (firstEnabled < 0 && !activeShaderId_.empty()) {
        auto it = shaders_.find(activeShaderId_);
        if (it != shaders_.end()) {
            accumulateUsage(it->second);
        }
    } else {
        for (int i = 0; i < MAX_SHADER_SLOTS; i++) {
            if (!slots_[i].enabled || slots_[i].shaderId.empty()) continue;
            auto it = shaders_.find(slots_[i].shaderId);
            if (it != shaders_.end()) {
                accumulateUsage(it->second);
            }
        }
    }

    UpdateUniformBuffer(anyUsesHistory);

    // ── Legacy single-shader fallback ────────────────────────────────────────
    if (firstEnabled < 0) {
        if (!activeShaderId_.empty()) {
            auto it = shaders_.find(activeShaderId_);
            if (it != shaders_.end()) {
                // Single pass: readTexture_ -> writeTexture_
                WriteSlotParams(zoomParams_);
                WGPUBindGroup bg = CreateComputeBindGroup(readTexture_.get(), writeTexture_.get());

                WGPUCommandEncoderDescriptor encDesc = {};
                encDesc.label = MakeStringView("Single Encoder");
                WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);

                int32_t tsStart = -1;
                int32_t tsEndA = -1;
                int32_t tsEndB = -1;
                if (supportsTimestampQuery_) {
                    tsStart = kTsFrameStart;
                    tsEndA = kTsChainedEnd;
                    tsEndB = kTsComputeEnd;
                    tsFrameStartWritten_ = true;
                    tsChainedStartWritten_ = true;
                }

                DispatchComputePass(enc, it->second.pipeline.get(), bg,
                                    it->second.workgroupX, it->second.workgroupY,
                                    tsStart, tsEndA, tsEndB);
                wgpuBindGroupRelease(bg);

                CopyTex(enc, writeTexture_.get(), readTexture_.get(), W, H);
                CopyTex(enc, depthTextureWrite_.get(), depthTextureRead_.get(), W, H);
                // dataB first, dataA last — A is primary feedback and must win when both written
                if (anyReadsC && anyWritesDataB) {
                    CopyTex(enc, dataTextureB_.get(), dataTextureC_.get(), W, H);
                }
                if (anyReadsC && anyWritesDataA) {
                    CopyTex(enc, dataTextureA_.get(), dataTextureC_.get(), W, H);
                }
                if (anyUsesHistory) {
                    WGPUTexelCopyTextureInfo src = {};
                    src.texture = writeTexture_.get();
                    src.mipLevel = 0;
                    src.origin = {0, 0, 0};
                    src.aspect = WGPUTextureAspect_All;
                    WGPUTexelCopyTextureInfo dst = {};
                    dst.texture = historyTexture_.get();
                    dst.mipLevel = 0;
                    dst.origin = {0, 0, historyHead_};
                    dst.aspect = WGPUTextureAspect_All;
                    WGPUExtent3D ext = { W, H, 1 };
                    wgpuCommandEncoderCopyTextureToTexture(enc, &src, &dst, &ext);
                    historyHead_ = (historyHead_ + 1) % HISTORY_DEPTH;
                }

                WGPUCommandBufferDescriptor cbDesc = {};
                cbDesc.label = MakeStringView("Single CmdBuf");
                WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
                wgpuQueueSubmit(queue_.get(), 1, &cb);
                wgpuCommandBufferRelease(cb);
                wgpuCommandEncoderRelease(enc);
            }
        }
    } else {
        // ── Multi-slot pipeline ───────────────────────────────────────────────
        // The "chain input" starts as readTexture_ (previous frame output).
        WGPUTexture chainInput = readTexture_.get();

        for (int i = 0; i < MAX_SHADER_SLOTS; i++) {
            if (!slots_[i].enabled || slots_[i].shaderId.empty()) continue;
            auto it = shaders_.find(slots_[i].shaderId);
            if (it == shaders_.end()) continue;

            // Which texture does this slot read from?
            WGPUTexture readFrom = (slots_[i].mode == SlotMode::Parallel)
                                   ? readTexture_.get()   // parallel: always from source
                                   : chainInput;          // chained: previous slot output

            // Which texture does this slot write to?
            WGPUTexture writeTo = slotOutput[i];

            // Patch per-slot zoom_params before submitting this slot's pass.
            WriteSlotParams(slots_[i].params);

            const double slotStartMs = emscripten_get_now();

            WGPUBindGroup bg = CreateComputeBindGroup(readFrom, writeTo);

            WGPUCommandEncoderDescriptor encDesc = {};
            encDesc.label = MakeStringView("Slot Encoder");
            WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);

            int32_t tsStart = -1;
            int32_t tsEndA = -1;
            int32_t tsEndB = -1;
            if (supportsTimestampQuery_) {
                if (!tsFrameStartWritten_) {
                    tsStart = kTsFrameStart;
                    tsFrameStartWritten_ = true;
                }
                if (slots_[i].mode == SlotMode::Parallel) {
                    if (!tsParallelStartWritten_) {
                        if (tsStart < 0) tsStart = kTsParallelStart;
                        tsParallelStartWritten_ = true;
                    }
                    tsEndA = kTsParallelEnd;
                } else {
                    if (!tsChainedStartWritten_) {
                        if (tsStart < 0) tsStart = kTsChainedStart;
                        tsChainedStartWritten_ = true;
                    }
                    tsEndA = kTsChainedEnd;
                }
                if (i == lastEnabled) {
                    tsEndB = kTsComputeEnd;
                }
            }

            DispatchComputePass(enc, it->second.pipeline.get(), bg,
                                it->second.workgroupX, it->second.workgroupY,
                                tsStart, tsEndA, tsEndB);
            wgpuBindGroupRelease(bg);

            WGPUCommandBufferDescriptor cbDesc = {};
            cbDesc.label = MakeStringView("Slot CmdBuf");
            WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
            // Submit this slot separately so the next WriteSlotParams (called
            // before the next slot's encoder) takes effect on the GPU.
            wgpuQueueSubmit(queue_.get(), 1, &cb);
            wgpuCommandBufferRelease(cb);
            wgpuCommandEncoderRelease(enc);

            const float slotMs = static_cast<float>(emscripten_get_now() - slotStartMs);
            if (slots_[i].mode == SlotMode::Parallel) {
                lastParallelTimeMs_ += slotMs;
            } else {
                lastChainedTimeMs_ += slotMs;
            }

            // Update chain input for the next slot (if chained).
            chainInput = writeTo;
        }

        // If the last slot did not write directly to writeTexture_, copy its
        // output there so the render pipeline always reads from writeTexture_.
        if (slotOutput[lastEnabled] != writeTexture_.get()) {
            WGPUCommandEncoderDescriptor encDesc = {};
            encDesc.label = MakeStringView("Copy Encoder");
            WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);
            CopyTex(enc, slotOutput[lastEnabled], writeTexture_.get(), W, H);
            WGPUCommandBufferDescriptor cbDesc = {};
            cbDesc.label = MakeStringView("Copy CmdBuf");
            WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
            wgpuQueueSubmit(queue_.get(), 1, &cb);
            wgpuCommandBufferRelease(cb);
            wgpuCommandEncoderRelease(enc);
        }

        // End-of-frame texture copies for temporal feedback.
        {
            WGPUCommandEncoderDescriptor encDesc = {};
            encDesc.label = MakeStringView("Feedback Encoder");
            WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);
            CopyTex(enc, writeTexture_.get(),       readTexture_.get(),      W, H);
            CopyTex(enc, depthTextureWrite_.get(),  depthTextureRead_.get(), W, H);
            // dataB first, dataA last — A is primary feedback and must win when both written
            if (anyReadsC && anyWritesDataB) {
                CopyTex(enc, dataTextureB_.get(), dataTextureC_.get(), W, H);
            }
            if (anyReadsC && anyWritesDataA) {
                CopyTex(enc, dataTextureA_.get(), dataTextureC_.get(), W, H);
            }
            if (anyUsesHistory) {
                WGPUTexelCopyTextureInfo src = {};
                src.texture = writeTexture_.get();
                src.mipLevel = 0;
                src.origin = {0, 0, 0};
                src.aspect = WGPUTextureAspect_All;
                WGPUTexelCopyTextureInfo dst = {};
                dst.texture = historyTexture_.get();
                dst.mipLevel = 0;
                dst.origin = {0, 0, historyHead_};
                dst.aspect = WGPUTextureAspect_All;
                WGPUExtent3D ext = { W, H, 1 };
                wgpuCommandEncoderCopyTextureToTexture(enc, &src, &dst, &ext);
                historyHead_ = (historyHead_ + 1) % HISTORY_DEPTH;
            }
            WGPUCommandBufferDescriptor cbDesc = {};
            cbDesc.label = MakeStringView("Feedback CmdBuf");
            WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
            wgpuQueueSubmit(queue_.get(), 1, &cb);
            wgpuCommandBufferRelease(cb);
            wgpuCommandEncoderRelease(enc);
        }
    }

    // Present the final composed frame to the canvas (if surface is configured).
    PresentToSurface();

    lastTotalTimeMs_ = static_cast<float>(emscripten_get_now() - renderStartMs);

    ResolveTimestampQueries();

    // Update FPS counter
    frameCount_++;
    float currentTime = emscripten_get_now() / 1000.0f;
    if (currentTime - lastFrameTime_ >= 1.0f) {
        fps_ = frameCount_ / (currentTime - lastFrameTime_);
        frameCount_ = 0;
        lastFrameTime_ = currentTime;
    }
}

void WebGPURenderer::Present() {
    // WebGPU surface presentation is handled by the browser's animation loop.
}

// ─── Phase 2: Frame Capture ───────────────────────────────────────────────────

void WebGPURenderer::BeginFrameCapture() {
    if (captureState_ == CaptureState::Pending) return;  // already in flight
    if (!initialized_ || deviceLost_ || !writeTexture_.get() || !queue_.get() || !device_.get()) {
        captureState_ = CaptureState::Error;
        return;
    }

    const uint32_t W = static_cast<uint32_t>(canvasWidth_);
    const uint32_t H = static_cast<uint32_t>(canvasHeight_);

    // WebGPU requires bytesPerRow to be a multiple of 256.
    const uint32_t bpp = format_pack::BytesPerPixel(colorFormat_);
    const uint32_t bytesPerRow = AlignUp(W * bpp, 256u);
    const size_t   needed      = static_cast<size_t>(bytesPerRow) * H;

    // (Re)create the readback buffer if the size has changed.
    if (!readbackBuffer_.get() || readbackBufferSize_ < needed) {
        WGPUBufferDescriptor bufDesc = {};
        bufDesc.label            = MakeStringView("Readback Buffer");
        bufDesc.size             = needed;
        bufDesc.usage            = WGPUBufferUsage_CopyDst | WGPUBufferUsage_MapRead;
        bufDesc.mappedAtCreation = false;
        readbackBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &bufDesc));
        readbackBufferSize_ = needed;
    }
    readbackBytesPerRow_ = bytesPerRow;

    // Encode CopyTextureToBuffer: writeTexture_ → readbackBuffer_
    WGPUCommandEncoderDescriptor encDesc = {};
    encDesc.label = MakeStringView("Readback Encoder");
    WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);

    WGPUTexelCopyTextureInfo src = {};
    src.texture  = writeTexture_.get();
    src.mipLevel = 0;
    src.origin   = {0, 0, 0};
    src.aspect   = WGPUTextureAspect_All;

    WGPUTexelCopyBufferInfo dst = {};
    dst.buffer             = readbackBuffer_.get();
    dst.layout.offset      = 0;
    dst.layout.bytesPerRow = bytesPerRow;
    dst.layout.rowsPerImage = H;

    WGPUExtent3D extent = { W, H, 1 };
    wgpuCommandEncoderCopyTextureToBuffer(enc, &src, &dst, &extent);

    WGPUCommandBufferDescriptor cbDesc = {};
    cbDesc.label = MakeStringView("Readback CmdBuf");
    WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
    wgpuQueueSubmit(queue_.get(), 1, &cb);
    wgpuCommandBufferRelease(cb);
    wgpuCommandEncoderRelease(enc);

    captureState_ = CaptureState::Pending;

    // Request async mapping.  The callback fires when the browser has finished
    // copying the GPU data to the CPU-accessible buffer.
    wgpuBufferMapAsync(
        readbackBuffer_.get(),
        WGPUMapMode_Read, 0, needed,
        WGPUBufferMapCallbackInfo{
            nullptr,
            WGPUCallbackMode_AllowSpontaneous,
            [](WGPUMapAsyncStatus status, WGPUStringView /*message*/,
               void* userdata1, void* /*userdata2*/) {
                WebGPURenderer* self = static_cast<WebGPURenderer*>(userdata1);
                if (status == WGPUMapAsyncStatus_Success) {
                    self->captureState_ = CaptureState::Ready;
                } else {
                    printf("❌ Frame readback map failed (status=%d)\n",
                           static_cast<int>(status));
                    self->captureState_ = CaptureState::Error;
                }
            },
            this, nullptr
        });
}

int WebGPURenderer::ReadCapturedFrame(uint8_t* outRGBA8, int maxBytes) {
    if (captureState_ != CaptureState::Ready) return 0;
    if (!readbackBuffer_.get() || !outRGBA8) return 0;

    const uint32_t W = static_cast<uint32_t>(canvasWidth_);
    const uint32_t H = static_cast<uint32_t>(canvasHeight_);
    const int required = static_cast<int>(W * H * 4);
    if (maxBytes < required) return 0;

    const void* mapped = wgpuBufferGetConstMappedRange(readbackBuffer_.get(), 0,
                                                        readbackBufferSize_);
    if (!mapped) {
        captureState_ = CaptureState::Error;
        return 0;
    }

    const uint8_t* mappedBytes = static_cast<const uint8_t*>(mapped);
    const uint32_t bpp = format_pack::BytesPerPixel(colorFormat_);

    for (uint32_t y = 0; y < H; y++) {
        const uint8_t* rowSrc = mappedBytes + static_cast<size_t>(y) * readbackBytesPerRow_;
        uint8_t* rowDst = outRGBA8 + static_cast<size_t>(y) * W * 4;
        for (uint32_t x = 0; x < W; x++) {
            float r, g, b, a;
            if (colorFormat_ == policy::InternalColorFormat::Rgba16Float) {
                const uint16_t* px = reinterpret_cast<const uint16_t*>(rowSrc + static_cast<size_t>(x) * bpp);
                r = format_pack::HalfToFloat(px[0]);
                g = format_pack::HalfToFloat(px[1]);
                b = format_pack::HalfToFloat(px[2]);
                a = format_pack::HalfToFloat(px[3]);
            } else {
                const float* px = reinterpret_cast<const float*>(rowSrc + static_cast<size_t>(x) * bpp);
                r = px[0]; g = px[1]; b = px[2]; a = px[3];
            }
            rowDst[x * 4 + 0] = static_cast<uint8_t>(std::min(1.0f, std::max(0.0f, r)) * 255.0f);
            rowDst[x * 4 + 1] = static_cast<uint8_t>(std::min(1.0f, std::max(0.0f, g)) * 255.0f);
            rowDst[x * 4 + 2] = static_cast<uint8_t>(std::min(1.0f, std::max(0.0f, b)) * 255.0f);
            rowDst[x * 4 + 3] = static_cast<uint8_t>(std::min(1.0f, std::max(0.0f, a)) * 255.0f);
        }
    }
    return required;
}

void WebGPURenderer::EndFrameCapture() {
    if (readbackBuffer_.get() && captureState_ == CaptureState::Ready) {
        wgpuBufferUnmap(readbackBuffer_.get());
    }
    captureState_ = CaptureState::Idle;
}


} // namespace pixelocity
