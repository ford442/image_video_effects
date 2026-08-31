#include "renderer.h"
#include "performance_policy.h"
#include "format_pack.h"
#include "wasm_internal.h"
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

namespace {
WGPUTextureFormat RgbaStorageFormat(policy::InternalColorFormat fmt) {
    return fmt == policy::InternalColorFormat::Rgba16Float
        ? WGPUTextureFormat_RGBA16Float
        : WGPUTextureFormat_RGBA32Float;
}

void QueueWriteRgba(
    WGPUQueue queue,
    WGPUTexture texture,
    const float* rgba,
    int width,
    int height,
    policy::InternalColorFormat fmt,
    std::vector<uint8_t>& packed
) {
    if (!queue || !texture || !rgba || width <= 0 || height <= 0) return;
    const size_t floatCount = static_cast<size_t>(width) * static_cast<size_t>(height) * 4u;

    WGPUTexelCopyTextureInfo dest = {};
    dest.texture = texture;
    dest.mipLevel = 0;
    dest.origin = {0, 0, 0};
    dest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout layout = {};
    layout.offset = 0;
    layout.bytesPerRow = format_pack::BytesPerRow(width, fmt);
    layout.rowsPerImage = static_cast<uint32_t>(height);

    WGPUExtent3D extent = {};
    extent.width = static_cast<uint32_t>(width);
    extent.height = static_cast<uint32_t>(height);
    extent.depthOrArrayLayers = 1;

    if (fmt == policy::InternalColorFormat::Rgba32Float) {
        wgpuQueueWriteTexture(queue, &dest, rgba, floatCount * sizeof(float), &layout, &extent);
        return;
    }

    format_pack::PackRgba(rgba, floatCount, fmt, packed);
    wgpuQueueWriteTexture(queue, &dest, packed.data(), packed.size(), &layout, &extent);
}
}  // namespace

bool WebGPURenderer::TryCreateHistoryTexture(uint32_t width, uint32_t height, uint32_t layers) {
    if (!device_.get() || deviceLost_ || !instance_.get()) return false;

    wgpuDevicePushErrorScope(device_.get(), WGPUErrorFilter_OutOfMemory);

    WGPUTextureDescriptor texDesc = {};
    texDesc.nextInChain = nullptr;
    texDesc.dimension = WGPUTextureDimension_2D;
    texDesc.size = {width, height, layers};
    texDesc.mipLevelCount = 1;
    texDesc.sampleCount = 1;
    texDesc.format = RgbaStorageFormat(colorFormat_);
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst
                  | WGPUTextureUsage_StorageBinding | WGPUTextureUsage_CopySrc;
    texDesc.label = MakeStringView("History Texture");
    historyTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    struct PopResult { bool hadError = false; };
    PopResult pop;
    auto popCb = [](WGPUPopErrorScopeStatus status, WGPUErrorType type,
                    WGPUStringView message, void* userdata1, void* /*userdata2*/) {
        auto* out = static_cast<PopResult*>(userdata1);
        if (status != WGPUPopErrorScopeStatus_Success || type == WGPUErrorType_OutOfMemory
            || type == WGPUErrorType_Internal) {
            out->hadError = true;
            if (message.data && message.length > 0) {
                printf("[WASM] historyTex OOM: %.*s\n", (int)message.length, message.data);
            }
        }
    };
    WGPUFuture popFuture = wgpuDevicePopErrorScope(device_.get(), WGPUPopErrorScopeCallbackInfo{
        nullptr, WGPUCallbackMode_WaitAnyOnly, popCb, &pop, nullptr
    });
    WGPUFutureWaitInfo popWait = {};
    popWait.future = popFuture;
    wgpuInstanceWaitAny(instance_.get(), 1, &popWait, UINT64_MAX);

    if (!historyTexture_.get() || pop.hadError || deviceLost_) {
        historyTexture_.reset();
        return false;
    }
    historyLayerCount_ = layers;
    historyHead_ = 0;
    return true;
}

bool WebGPURenderer::CreateHistoryTextureFailSoft() {
    const uint32_t current = static_cast<uint32_t>(std::max(canvasWidth_, canvasHeight_));
    struct Rung { uint32_t size; uint32_t layers; };
    const Rung rungs[] = {
        { current, HISTORY_DEPTH },
        { 1024u, HISTORY_DEPTH },
        { 1024u, 4u },
        { 1024u, 1u },
    };
    for (const auto& rung : rungs) {
        if (rung.size > current) continue;
        historyTexture_.reset();
        if (TryCreateHistoryTexture(rung.size, rung.size, rung.layers)) {
            if (rung.size < current) {
                printf("[WASM] historyTex fail-soft: canvas %u → %u, layers %u (do not retry 2048)\n",
                       current, rung.size, rung.layers);
                canvasWidth_ = static_cast<int>(rung.size);
                canvasHeight_ = static_cast<int>(rung.size);
            } else if (rung.layers < HISTORY_DEPTH) {
                printf("[WASM] historyTex fail-soft: layers %u (size %u)\n", rung.layers, rung.size);
            }
            return true;
        }
        printf("[WASM] historyTex create failed at %ux%u × %u layers — dropping (do not retry 2048)\n",
               rung.size, rung.size, rung.layers);
    }
    lastError_ = "historyTex CreateCommittedResource OOM (all rungs failed)";
    return false;
}

bool WebGPURenderer::CreateResources() {
    // canvasWidth_/canvasHeight_ are set at init; defaults align with policy::kInternalRenderResolution.
    (void)policy::kInternalRenderResolution;
    // Create samplers
    WGPUSamplerDescriptor samplerDesc = {};
    samplerDesc.nextInChain = nullptr;
    // Dawn rejects maxAnisotropy < 1 (C++ {} leaves 0). Spec/JS default is 1.
    samplerDesc.maxAnisotropy = 1;
    samplerDesc.label = MakeStringView("Filtering Sampler");
    samplerDesc.magFilter = WGPUFilterMode_Linear;
    samplerDesc.minFilter = WGPUFilterMode_Linear;
    samplerDesc.mipmapFilter = WGPUMipmapFilterMode_Linear;
    samplerDesc.addressModeU = WGPUAddressMode_Repeat;
    samplerDesc.addressModeV = WGPUAddressMode_Repeat;
    samplerDesc.addressModeW = WGPUAddressMode_Repeat;
    filteringSampler_.reset(wgpuDeviceCreateSampler(device_.get(), &samplerDesc));

    samplerDesc.label = MakeStringView("Non-filtering Sampler");
    samplerDesc.magFilter = WGPUFilterMode_Nearest;
    samplerDesc.minFilter = WGPUFilterMode_Nearest;
    samplerDesc.mipmapFilter = WGPUMipmapFilterMode_Nearest;
    nonFilteringSampler_.reset(wgpuDeviceCreateSampler(device_.get(), &samplerDesc));

    samplerDesc.label = MakeStringView("Comparison Sampler");
    samplerDesc.compare = WGPUCompareFunction_Less;
    comparisonSampler_.reset(wgpuDeviceCreateSampler(device_.get(), &samplerDesc));

    // Uniform buffer layout:
    //   [0..11]   = 12 floats: config(4) + zoom_config(4) + zoom_params(4)
    //   [12..211] = 200 floats: 50 ripples × 4 floats each
    constexpr size_t UNIFORM_BASE_FLOATS = 12;
    constexpr size_t uniformSize = sizeof(float) * (UNIFORM_BASE_FLOATS + MAX_RIPPLES * 4);
    WGPUBufferDescriptor bufferDesc = {};
    bufferDesc.nextInChain = nullptr;
    bufferDesc.label = MakeStringView("Uniform Buffer");
    bufferDesc.size = uniformSize;
    bufferDesc.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst;
    bufferDesc.mappedAtCreation = false;
    uniformBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &bufferDesc));

    // Extra buffer: 256 floats of general-purpose shader data (audio FFT, etc.)
    constexpr size_t EXTRA_BUFFER_FLOATS = 256;
    bufferDesc.label = MakeStringView("Extra Buffer");
    bufferDesc.size = EXTRA_BUFFER_FLOATS * sizeof(float);
    bufferDesc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    extraBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &bufferDesc));

    // Plasma buffer: MAX_PLASMA_BALLS × sizeof(vec4<f32>) = MAX_PLASMA_BALLS × 16 bytes
    constexpr size_t PLASMA_ENTRY_BYTES = 16;  // sizeof(vec4<f32>)
    bufferDesc.label = MakeStringView("Plasma Buffer");
    bufferDesc.size = MAX_PLASMA_BALLS * PLASMA_ENTRY_BYTES;
    bufferDesc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    plasmaBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &bufferDesc));

    // Largest committed resource first (#1204). May shrink canvasWidth_/Height_.
    if (!CreateHistoryTextureFailSoft()) {
        printf("❌ historyTex allocation failed (GPUOutOfMemory)\n");
        return false;
    }

    // Create remaining textures at (possibly fail-soft) canvas size
    WGPUTextureDescriptor texDesc = {};
    texDesc.nextInChain = nullptr;
    texDesc.dimension = WGPUTextureDimension_2D;
    texDesc.size = {static_cast<uint32_t>(canvasWidth_), static_cast<uint32_t>(canvasHeight_), 1};
    texDesc.mipLevelCount = 1;
    texDesc.sampleCount = 1;

    // Ping-pong textures (tier-selected rgba format)
    texDesc.format = RgbaStorageFormat(colorFormat_);
    texDesc.usage = WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding | WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc;
    texDesc.label = MakeStringView("Read Texture");
    readTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Write Texture");
    writeTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Ping-Pong 0");
    pingPong0_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Ping-Pong 1");
    pingPong1_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Data Texture A");
    dataTextureA_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Data Texture B");
    dataTextureB_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Data Texture C");
    dataTextureC_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    texDesc.format = WGPUTextureFormat_R32Float;
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst
                  | WGPUTextureUsage_StorageBinding | WGPUTextureUsage_CopySrc;
    texDesc.size = {static_cast<uint32_t>(canvasWidth_), static_cast<uint32_t>(canvasHeight_), 1};
    texDesc.label = MakeStringView("Depth Texture Read");
    depthTextureRead_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Depth Texture Write");
    depthTextureWrite_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    // Empty texture (1x1 r32float) — deliberate match to TS emptyTex placeholder
    texDesc.size = {1, 1, 1};
    texDesc.format = WGPUTextureFormat_R32Float;
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst;
    texDesc.label = MakeStringView("Empty Texture");
    emptyTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    // Initialize empty texture to black (one r32float pixel)
    float black = 0.0f;

    WGPUTexelCopyTextureInfo emptyDest = {};
    emptyDest.texture = emptyTexture_.get();
    emptyDest.mipLevel = 0;
    emptyDest.origin = {0, 0, 0};
    emptyDest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout emptyDataLayout = {};
    emptyDataLayout.offset = 0;
    emptyDataLayout.bytesPerRow = sizeof(float);  // 4 bytes — one r32float pixel
    emptyDataLayout.rowsPerImage = 1;

    wgpuQueueWriteTexture(queue_.get(), &emptyDest, &black, sizeof(black), &emptyDataLayout, &texDesc.size);

    // Initialize data texture C and readTexture_ to zeros (avoids uninitialised GPU memory).
    // bytesPerRow must match the allocated colorFormat_ (rgba16float is 8 B/px, not 16).
    std::vector<float> zeros(static_cast<size_t>(canvasWidth_) * canvasHeight_ * 4, 0.0f);
    QueueWriteRgba(queue_.get(), dataTextureC_.get(), zeros.data(),
                   canvasWidth_, canvasHeight_, colorFormat_, packedUploadBuffer_);
    QueueWriteRgba(queue_.get(), readTexture_.get(), zeros.data(),
                   canvasWidth_, canvasHeight_, colorFormat_, packedUploadBuffer_);

    CreateTimestampQueries();

    return true;
}

void WebGPURenderer::RecreateTextures() {
    // Release size-dependent textures using RAII handles.
    // Size-independent objects (samplers, uniform/extra/plasma buffers, 1×1 emptyTexture_)
    // do NOT need to be recreated.
    readTexture_.reset();
    writeTexture_.reset();
    pingPong0_.reset();
    pingPong1_.reset();
    dataTextureA_.reset();
    dataTextureB_.reset();
    dataTextureC_.reset();
    historyTexture_.reset();
    depthTextureRead_.reset();
    depthTextureWrite_.reset();

    // Release old bind group — it holds views into the old textures.
    computeBindGroup_.reset();

    if (!CreateHistoryTextureFailSoft()) {
        printf("❌ RecreateTextures: historyTex allocation failed\n");
        return;
    }

    // Create new textures at the current canvas dimensions.
    WGPUTextureDescriptor texDesc = {};
    texDesc.nextInChain = nullptr;
    texDesc.dimension = WGPUTextureDimension_2D;
    texDesc.size = {static_cast<uint32_t>(canvasWidth_), static_cast<uint32_t>(canvasHeight_), 1};
    texDesc.mipLevelCount = 1;
    texDesc.sampleCount = 1;

    // Ping-pong textures (tier-selected rgba format)
    texDesc.format = RgbaStorageFormat(colorFormat_);
    texDesc.usage = WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding
                  | WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc;
    texDesc.label = MakeStringView("Read Texture");
    readTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Write Texture");
    writeTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Ping-Pong 0");
    pingPong0_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Ping-Pong 1");
    pingPong1_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Data Texture A");
    dataTextureA_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Data Texture B");
    dataTextureB_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Data Texture C");
    dataTextureC_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    texDesc.format = WGPUTextureFormat_R32Float;
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst
                  | WGPUTextureUsage_StorageBinding | WGPUTextureUsage_CopySrc;
    texDesc.size = {static_cast<uint32_t>(canvasWidth_), static_cast<uint32_t>(canvasHeight_), 1};
    texDesc.label = MakeStringView("Depth Texture Read");
    depthTextureRead_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Depth Texture Write");
    depthTextureWrite_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    // Zero-initialise textures that must start black.
    // Reuse videoStagingBuffer_ (rgba32float sized) to avoid a separate allocation.
    const size_t floatCount = static_cast<size_t>(canvasWidth_) * canvasHeight_ * 4;
    if (videoStagingBuffer_.size() < floatCount) {
        videoStagingBuffer_.assign(floatCount, 0.0f);
    } else {
        std::fill(videoStagingBuffer_.begin(),
                  videoStagingBuffer_.begin() + static_cast<std::ptrdiff_t>(floatCount),
                  0.0f);
    }

    QueueWriteRgba(queue_.get(), dataTextureC_.get(), videoStagingBuffer_.data(),
                   canvasWidth_, canvasHeight_, colorFormat_, packedUploadBuffer_);
    QueueWriteRgba(queue_.get(), readTexture_.get(), videoStagingBuffer_.data(),
                   canvasWidth_, canvasHeight_, colorFormat_, packedUploadBuffer_);

    // Rebuild the bind groups with the new texture views.
    // CreateBindGroups() already calls CreateRenderBindGroup() internally.
    CreateBindGroups();

    // Reconfigure the surface swap-chain for the new canvas dimensions.
    if (surface_.get()) {
        ConfigureSurface();
    }
}

void WebGPURenderer::ResizeCanvas(int newWidth, int newHeight) {
    if (newWidth <= 0 || newHeight <= 0) return;
    if (newWidth == canvasWidth_ && newHeight == canvasHeight_) return;
    if (!initialized_ || deviceLost_) return;

    printf("🔄 Resizing canvas: %dx%d → %dx%d\n",
           canvasWidth_, canvasHeight_, newWidth, newHeight);

    canvasWidth_  = newWidth;
    canvasHeight_ = newHeight;

    // Recreate all size-dependent GPU resources.
    RecreateTextures();

    // Invalidate the persistent staging buffer so it gets resized on next upload.
    videoStagingBuffer_.clear();

    // Release the readback buffer; it will be recreated at the new size on next capture.
    if (readbackBuffer_.get()) {
        if (captureState_ == CaptureState::Pending) {
            wgpuBufferUnmap(readbackBuffer_.get());
        }
        readbackBuffer_.reset();
        readbackBufferSize_  = 0;
        readbackBytesPerRow_ = 0;
    }
    captureState_ = CaptureState::Idle;

    // A resize gives presentation a fresh start at the new size.
    presentFailureCount_ = 0;

    printf("✅ Canvas resized successfully\n");
}

void WebGPURenderer::ClearReadTexture() {
    if (!queue_.get() || !readTexture_.get() || deviceLost_) return;

    const size_t floatCount = static_cast<size_t>(canvasWidth_) * canvasHeight_ * 4;
    if (floatCount == 0) return;

    if (videoStagingBuffer_.size() < floatCount) {
        videoStagingBuffer_.assign(floatCount, 0.0f);
    } else {
        std::fill(videoStagingBuffer_.begin(),
                  videoStagingBuffer_.begin() + static_cast<std::ptrdiff_t>(floatCount),
                  0.0f);
    }

    QueueWriteRgba(queue_.get(), readTexture_.get(), videoStagingBuffer_.data(),
                   canvasWidth_, canvasHeight_, colorFormat_, packedUploadBuffer_);
}

void WebGPURenderer::SetColorFormat(int formatEnum) {
    if (!initialized_ || deviceLost_) return;
    auto fmt = formatEnum == 1
        ? policy::InternalColorFormat::Rgba16Float
        : policy::InternalColorFormat::Rgba32Float;
    if (fmt == policy::InternalColorFormat::Rgba16Float && !supportsRgba16FloatStorage_) {
        printf("[WASM] rgba16float storage probe failed — fail-soft staying on rgba32float\n");
        fmt = policy::InternalColorFormat::Rgba32Float;
    }
    if (colorFormat_ == fmt) return;

    printf("[WASM] Switching internal color format to %s\n",
           fmt == policy::InternalColorFormat::Rgba16Float ? "rgba16float" : "rgba32float");
    colorFormat_ = fmt;
    shaders_.clear();

    computeBindGroupLayout_.reset();
    computePipelineLayout_.reset();
    if (!CreateBindGroupLayout()) {
        printf("❌ SetColorFormat: CreateBindGroupLayout failed\n");
        return;
    }

    RecreateTextures();
}

// ─── CreateComputeBindGroup ───────────────────────────────────────────────────

void WebGPURenderer::UploadRGBA8ToReadTexture(const uint8_t* data, int width, int height) {
    if (!queue_.get() || !readTexture_.get() || deviceLost_) return;

    // Convert uint8 RGBA to float RGBA, fitting within canvas bounds.
    // Pixels outside the source image remain black.
    const int dstW = canvasWidth_;
    const int dstH = canvasHeight_;
    const int copyW = (width  < dstW) ? width  : dstW;
    const int copyH = (height < dstH) ? height : dstH;

    // Phase 2: reuse persistent staging buffer to eliminate per-frame heap allocation.
    const size_t needed = static_cast<size_t>(dstW) * dstH * 4;
    if (videoStagingBuffer_.size() < needed) {
        videoStagingBuffer_.assign(needed, 0.0f);
    }

    // Zero only the pixels that will NOT be written by the copy loops below
    // (right/bottom borders when source is smaller than the destination).
    // This avoids zeroing the entire buffer on every frame.
    if (copyW < dstW || copyH < dstH) {
        // Zero the right border columns (all rows).
        for (int y = 0; y < copyH; y++) {
            const int rowBase = y * dstW * 4;
            for (int x = copyW; x < dstW; x++) {
                videoStagingBuffer_[rowBase + x * 4 + 0] = 0.0f;
                videoStagingBuffer_[rowBase + x * 4 + 1] = 0.0f;
                videoStagingBuffer_[rowBase + x * 4 + 2] = 0.0f;
                videoStagingBuffer_[rowBase + x * 4 + 3] = 0.0f;
            }
        }
        // Zero the bottom border rows entirely.
        for (int y = copyH; y < dstH; y++) {
            const size_t rowStart = static_cast<size_t>(y) * dstW * 4;
            std::fill(videoStagingBuffer_.begin() + static_cast<std::ptrdiff_t>(rowStart),
                      videoStagingBuffer_.begin() + static_cast<std::ptrdiff_t>(rowStart + static_cast<size_t>(dstW) * 4),
                      0.0f);
        }
    }

    for (int y = 0; y < copyH; y++) {
        for (int x = 0; x < copyW; x++) {
            const int srcIdx = (y * width + x) * 4;
            const int dstIdx = (y * dstW  + x) * 4;
            videoStagingBuffer_[dstIdx + 0] = data[srcIdx + 0] / 255.0f;
            videoStagingBuffer_[dstIdx + 1] = data[srcIdx + 1] / 255.0f;
            videoStagingBuffer_[dstIdx + 2] = data[srcIdx + 2] / 255.0f;
            videoStagingBuffer_[dstIdx + 3] = data[srcIdx + 3] / 255.0f;
        }
    }

    QueueWriteRgba(queue_.get(), readTexture_.get(), videoStagingBuffer_.data(),
                   dstW, dstH, colorFormat_, packedUploadBuffer_);
}


} // namespace pixelocity
