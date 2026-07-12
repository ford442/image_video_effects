#include "renderer.h"
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

bool WebGPURenderer::CreateResources() {
    // Create samplers
    WGPUSamplerDescriptor samplerDesc = {};
    samplerDesc.nextInChain = nullptr;
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

    // Create textures
    WGPUTextureDescriptor texDesc = {};
    texDesc.nextInChain = nullptr;
    texDesc.dimension = WGPUTextureDimension_2D;
    texDesc.size = {static_cast<uint32_t>(canvasWidth_), static_cast<uint32_t>(canvasHeight_), 1};
    texDesc.mipLevelCount = 1;
    texDesc.sampleCount = 1;

    // Ping-pong textures (rgba32float)
    texDesc.format = WGPUTextureFormat_RGBA32Float;
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

    // Depth textures (r32float)
    texDesc.format = WGPUTextureFormat_R32Float;
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Depth Texture Read");
    depthTextureRead_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Depth Texture Write");
    depthTextureWrite_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    // Empty texture (1x1) used as placeholder for generative shaders
    texDesc.size = {1, 1, 1};
    texDesc.label = MakeStringView("Empty Texture");
    emptyTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    // Initialize empty texture to black
    float black[4] = {0.0f, 0.0f, 0.0f, 1.0f};

    WGPUTexelCopyTextureInfo emptyDest = {};
    emptyDest.texture = emptyTexture_.get();
    emptyDest.mipLevel = 0;
    emptyDest.origin = {0, 0, 0};
    emptyDest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout emptyDataLayout = {};
    emptyDataLayout.offset = 0;
    emptyDataLayout.bytesPerRow = sizeof(float) * 4;  // 1 pixel × 4 floats × 4 bytes
    emptyDataLayout.rowsPerImage = 1;

    wgpuQueueWriteTexture(queue_.get(), &emptyDest, black, sizeof(black), &emptyDataLayout, &texDesc.size);

    // Initialize data texture C and readTexture_ to zeros (avoids uninitialised GPU memory).
    std::vector<float> zeros(static_cast<size_t>(canvasWidth_) * canvasHeight_ * 4, 0.0f);

    WGPUTexelCopyTextureInfo dataDest = {};
    dataDest.mipLevel = 0;
    dataDest.origin = {0, 0, 0};
    dataDest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout dataLayout = {};
    dataLayout.offset = 0;
    dataLayout.bytesPerRow = static_cast<uint32_t>(canvasWidth_) * sizeof(float) * 4;
    dataLayout.rowsPerImage = static_cast<uint32_t>(canvasHeight_);

    WGPUExtent3D dataExtent = {};
    dataExtent.width = static_cast<uint32_t>(canvasWidth_);
    dataExtent.height = static_cast<uint32_t>(canvasHeight_);
    dataExtent.depthOrArrayLayers = 1;

    dataDest.texture = dataTextureC_.get();
    wgpuQueueWriteTexture(queue_.get(), &dataDest, zeros.data(), zeros.size() * sizeof(float), &dataLayout, &dataExtent);

    dataDest.texture = readTexture_.get();
    wgpuQueueWriteTexture(queue_.get(), &dataDest, zeros.data(), zeros.size() * sizeof(float), &dataLayout, &dataExtent);

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
    depthTextureRead_.reset();
    depthTextureWrite_.reset();

    // Release old bind group — it holds views into the old textures.
    computeBindGroup_.reset();

    // Create new textures at the current canvas dimensions.
    WGPUTextureDescriptor texDesc = {};
    texDesc.nextInChain = nullptr;
    texDesc.dimension = WGPUTextureDimension_2D;
    texDesc.size = {static_cast<uint32_t>(canvasWidth_), static_cast<uint32_t>(canvasHeight_), 1};
    texDesc.mipLevelCount = 1;
    texDesc.sampleCount = 1;

    // Ping-pong textures (rgba32float)
    texDesc.format = WGPUTextureFormat_RGBA32Float;
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

    // Depth textures (r32float)
    texDesc.format = WGPUTextureFormat_R32Float;
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
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

    WGPUTexelCopyTextureInfo dest = {};
    dest.mipLevel = 0;
    dest.origin = {0, 0, 0};
    dest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout layout = {};
    layout.offset = 0;
    layout.bytesPerRow  = static_cast<uint32_t>(canvasWidth_) * sizeof(float) * 4;  // rgba32float
    layout.rowsPerImage = static_cast<uint32_t>(canvasHeight_);

    WGPUExtent3D extent = {};
    extent.width  = static_cast<uint32_t>(canvasWidth_);
    extent.height = static_cast<uint32_t>(canvasHeight_);
    extent.depthOrArrayLayers = 1;

    dest.texture = dataTextureC_.get();
    wgpuQueueWriteTexture(queue_.get(), &dest, videoStagingBuffer_.data(),
                          floatCount * sizeof(float), &layout, &extent);

    dest.texture = readTexture_.get();
    wgpuQueueWriteTexture(queue_.get(), &dest, videoStagingBuffer_.data(),
                          floatCount * sizeof(float), &layout, &extent);

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

    WGPUTexelCopyTextureInfo dest = {};
    dest.texture = readTexture_.get();
    dest.mipLevel = 0;
    dest.origin = {0, 0, 0};
    dest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout layout = {};
    layout.offset = 0;
    layout.bytesPerRow = static_cast<uint32_t>(canvasWidth_) * sizeof(float) * 4;
    layout.rowsPerImage = static_cast<uint32_t>(canvasHeight_);

    WGPUExtent3D extent = {};
    extent.width = static_cast<uint32_t>(canvasWidth_);
    extent.height = static_cast<uint32_t>(canvasHeight_);
    extent.depthOrArrayLayers = 1;

    wgpuQueueWriteTexture(queue_.get(), &dest, videoStagingBuffer_.data(),
                          floatCount * sizeof(float), &layout, &extent);
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

    WGPUTexelCopyTextureInfo dest = {};
    dest.texture = readTexture_;
    dest.mipLevel = 0;
    dest.origin = {0, 0, 0};
    dest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout layout = {};
    layout.offset = 0;
    layout.bytesPerRow = static_cast<uint32_t>(dstW) * 16;  // 4 floats × 4 bytes
    layout.rowsPerImage = static_cast<uint32_t>(dstH);

    WGPUExtent3D extent = {};
    extent.width  = static_cast<uint32_t>(dstW);
    extent.height = static_cast<uint32_t>(dstH);
    extent.depthOrArrayLayers = 1;

    wgpuQueueWriteTexture(queue_, &dest, videoStagingBuffer_.data(),
                          needed * sizeof(float), &layout, &extent);
}


} // namespace pixelocity
