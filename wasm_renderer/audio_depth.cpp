#include "renderer.h"
#include "wasm_internal.h"
#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <emscripten/em_js.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <array>
#include <algorithm>
#include <vector>

namespace pixelocity {

// ─── JavaScript bridge: GPU still ingest ────────────────────────────────────────────────────
//
// TS parity: WebGPUMediaInput.copyExternalToSource. The bridge (capture.ts
// uploadImageSource) parks an HTMLImageElement / HTMLCanvasElement / ImageBitmap
// on Module.pixelocityPendingImage; this copies it into the destination texture
// at the origin, clipped to copyW x copyH. No getImageData round-trip.
// Returns 1 on success, 0 when the API is missing or the copy throws.
EM_JS(int, JS_CopyExternalImageToTexture,
      (WGPUQueue queueHandle, WGPUTexture textureHandle, int copyW, int copyH), {
    var source = Module['pixelocityPendingImage'];
    delete Module['pixelocityPendingImage'];
    var queue = WebGPU.getJsObject(queueHandle);
    var texture = WebGPU.getJsObject(textureHandle);
    if (!source || !queue || !texture || typeof queue.copyExternalImageToTexture !== 'function') {
        return 0;
    }
    try {
        queue.copyExternalImageToTexture(
            { source: source, origin: [0, 0], flipY: false },
            { texture: texture, origin: [0, 0], premultipliedAlpha: false },
            [copyW, copyH]);
        return 1;
    } catch (err) {
        console.warn('[WASM] copyExternalImageToTexture failed, falling back to CPU upload:', err);
        return 0;
    }
});

using wasm_internal::MakeStringView;
using wasm_internal::AlignUp;
using wasm_internal::CheckLimit;
using wasm_internal::ParseWorkgroupSize;

void WebGPURenderer::SetInputSource(InputSource source) {
    inputSource_ = source;
    printf("[WASM] Input source set to %d\n", static_cast<int>(source));
    if (source == InputSource::Generative || source == InputSource::None) {
        ClearReadTexture();
    }
}

void WebGPURenderer::LoadImage(const uint8_t* data, int width, int height) {
    printf("📷 Loading image: %dx%d\n", width, height);
    UploadRGBA8ToReadTexture(data, width, height);
}

bool WebGPURenderer::LoadImageExternal(int width, int height) {
    if (!queue_.get() || !readTexture_.get() || deviceLost_ || width <= 0 || height <= 0) {
        return false;
    }
    const int copyW = std::min(width, canvasWidth_);
    const int copyH = std::min(height, canvasHeight_);
    if (copyW <= 0 || copyH <= 0) return false;
    // Same geometry as UploadRGBA8ToReadTexture: top-left, black outside the image.
    if (copyW < canvasWidth_ || copyH < canvasHeight_) ClearReadTexture();
    if (!JS_CopyExternalImageToTexture(queue_.get(), readTexture_.get(), copyW, copyH)) {
        return false;
    }
    printf("📷 Loading image (GPU copy): %dx%d\n", width, height);
    return true;
}

void WebGPURenderer::UpdateVideoFrame(const uint8_t* data, int width, int height) {
    if (inputSource_ != InputSource::Video &&
        inputSource_ != InputSource::Webcam &&
        inputSource_ != InputSource::Live) {
        return;
    }
    UploadRGBA8ToReadTexture(data, width, height);
}

void WebGPURenderer::UpdateDepthMap(const float* data, int width, int height) {
    if (!queue_.get() || !depthTextureRead_.get() || !data || deviceLost_) return;

    // Depth stays r32float (not colorFormat_). bytesPerRow is width * sizeof(float).
    // RGBA color uploads use QueueWriteRgba / format_pack in resources.cpp.

    // Clamp copy dimensions to the texture size.
    const int dstW = canvasWidth_;
    const int dstH = canvasHeight_;
    const int copyW = (width  < dstW) ? width  : dstW;
    const int copyH = (height < dstH) ? height : dstH;

    // Build a full-size float buffer (zeros for any uncovered region).
    std::vector<float> buf(static_cast<size_t>(dstW) * dstH, 0.0f);
    for (int y = 0; y < copyH; y++) {
        for (int x = 0; x < copyW; x++) {
            buf[y * dstW + x] = data[y * width + x];
        }
    }

    WGPUTexelCopyTextureInfo dest = {};
    dest.texture  = depthTextureRead_;
    dest.mipLevel = 0;
    dest.origin   = {0, 0, 0};
    dest.aspect   = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout layout = {};
    layout.offset       = 0;
    layout.bytesPerRow  = static_cast<uint32_t>(dstW) * sizeof(float);
    layout.rowsPerImage = static_cast<uint32_t>(dstH);

    WGPUExtent3D extent = {};
    extent.width              = static_cast<uint32_t>(dstW);
    extent.height             = static_cast<uint32_t>(dstH);
    extent.depthOrArrayLayers = 1;

    wgpuQueueWriteTexture(queue_, &dest, buf.data(), buf.size() * sizeof(float), &layout, &extent);
}

void WebGPURenderer::SetAudioData(float bass, float mid, float treble) {
    audioBass_   = bass;
    audioMid_    = mid;
    audioTreble_ = treble;
}

void WebGPURenderer::SetAudioFrequencyBins(const float* bins, int count) {
    if (!bins || count <= 0) return;
    const int n = (count < AUDIO_FFT_BINS) ? count : AUDIO_FFT_BINS;
    for (int i = 0; i < n; ++i) {
        audioFreqBins_[i] = bins[i];
    }
    for (int i = n; i < AUDIO_FFT_BINS; ++i) {
        audioFreqBins_[i] = 0.0f;
    }
}


} // namespace pixelocity
