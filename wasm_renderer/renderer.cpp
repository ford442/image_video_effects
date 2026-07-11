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

WebGPURenderer::WebGPURenderer() = default;

void WebGPURenderer::MarkDeviceLostFromCallback(void* userdata) {
    if (userdata) {
        static_cast<WebGPURenderer*>(userdata)->deviceLost_ = true;
    }
}

WebGPURenderer::~WebGPURenderer() {
    Shutdown();
}

bool WebGPURenderer::Initialize(int canvasWidth, int canvasHeight,
                                const char* canvasSelector) {
    if (initialized_) return true;
    
    canvasWidth_ = canvasWidth;
    canvasHeight_ = canvasHeight;
    if (canvasSelector && *canvasSelector) {
        canvasSelector_ = canvasSelector;
    }

    failedStage_ = InitStage::None;
    lastError_.clear();

    // ARCH: [Low] Using printf for logging. Consider abstracting behind
    // a Logger interface to allow different output targets (console, file, etc.)
    printf("🚀 Pixelocity WASM Renderer initializing...\n");
    printf("   Canvas: %dx%d\n", canvasWidth_, canvasHeight_);

    if (!CreateDevice()) {
        // CreateDevice() sets failedStage_/lastError_ at its specific failure
        // point; fall back to a generic message if it somehow didn't.
        if (failedStage_ == InitStage::None) failedStage_ = InitStage::Device;
        if (lastError_.empty()) lastError_ = "CreateDevice() failed: see console for details";
        printf("❌ Failed to create WebGPU device\n");
        Shutdown();
        return false;
    }

    if (!CreateResources()) {
        failedStage_ = InitStage::Resources;
        lastError_ = "CreateResources() failed: see console for details";
        printf("❌ Failed to create resources\n");
        Shutdown();
        return false;
    }

    if (!CreateBindGroupLayout()) {
        if (failedStage_ == InitStage::None) failedStage_ = InitStage::BindGroups;
        if (lastError_.empty()) lastError_ = "CreateBindGroupLayout() failed: see console for details";
        printf("❌ Failed to create bind group layout\n");
        Shutdown();
        return false;
    }

    if (!CreateRenderPipeline()) {
        if (failedStage_ == InitStage::None) failedStage_ = InitStage::Pipeline;
        if (lastError_.empty()) lastError_ = "CreateRenderPipeline() failed: see console for details";
        printf("❌ Failed to create render pipeline\n");
        Shutdown();
        return false;
    }

    if (!CreateBindGroups()) {
        if (failedStage_ == InitStage::None) failedStage_ = InitStage::BindGroups;
        if (lastError_.empty()) lastError_ = "CreateBindGroups() failed: see console for details";
        printf("❌ Failed to create bind groups\n");
        Shutdown();
        return false;
    }

    initialized_ = true;
    failedStage_ = InitStage::Ready;
    printf("✅ WebGPU Renderer initialized successfully\n");
    return true;
}

void WebGPURenderer::Shutdown() {
    // No early-return on !initialized_: Shutdown() must also clean up after a
    // failed Initialize() (e.g. CreateDevice() succeeded but CreateResources()
    // failed). All .reset() calls below are null-safe, so running this on a
    // partially-initialized (or already-shutdown) renderer is harmless.

    // Cancel any in-progress frame capture before releasing the readback buffer.
    if (readbackBuffer_.get() && captureState_ == CaptureState::Pending) {
        wgpuBufferUnmap(readbackBuffer_.get());
    }
    captureState_        = CaptureState::Idle;
    readbackBufferSize_  = 0;
    readbackBytesPerRow_ = 0;

    // Shaders hold RAII handles — clear the map to release all pipelines/modules.
    shaders_.clear();

    // All other GPU objects are RAII handles — they release on assignment/destruction.
    // Explicit reset in reverse-creation order ensures proper GPU object lifetime.
    computeBindGroup_.reset();
    renderBindGroup_.reset();
    renderPipeline_.reset();
    computePipelineLayout_.reset();
    computeBindGroupLayout_.reset();

    readbackBuffer_.reset();
    uniformBuffer_.reset();
    extraBuffer_.reset();
    plasmaBuffer_.reset();

    filteringSampler_.reset();
    nonFilteringSampler_.reset();
    comparisonSampler_.reset();

    readTexture_.reset();
    writeTexture_.reset();
    pingPong0_.reset();
    pingPong1_.reset();
    dataTextureA_.reset();
    dataTextureB_.reset();
    dataTextureC_.reset();
    depthTextureRead_.reset();
    depthTextureWrite_.reset();
    emptyTexture_.reset();

    queue_.reset();
    device_.reset();
    adapter_.reset();
    surface_.reset();
    instance_.reset();

    initialized_ = false;
    deviceLost_ = false;
    presentFailureCount_ = 0;
    printf("🛑 WebGPU Renderer shutdown\n");
}

void WebGPURenderer::SetActiveShader(const char* id) {
    activeShaderId_ = id;
    // Also configure slot 0 for backwards compatibility with callers that
    // still use the single-shader API.
    if (id && *id) {
        slots_[0].shaderId = id;
        slots_[0].enabled  = true;
    }
}

// ─── Multi-slot shader API ────────────────────────────────────────────────────

void WebGPURenderer::SetSlotShader(int slotIndex, const char* id) {
    if (slotIndex < 0 || slotIndex >= MAX_SHADER_SLOTS) return;
    if (id && *id) {
        slots_[slotIndex].shaderId = id;
        slots_[slotIndex].enabled  = true;
    } else {
        slots_[slotIndex].shaderId.clear();
        slots_[slotIndex].enabled = false;
    }
}

void WebGPURenderer::SetSlotParams(int slotIndex, float p1, float p2, float p3, float p4) {
    if (slotIndex < 0 || slotIndex >= MAX_SHADER_SLOTS) return;
    slots_[slotIndex].params[0] = p1;
    slots_[slotIndex].params[1] = p2;
    slots_[slotIndex].params[2] = p3;
    slots_[slotIndex].params[3] = p4;
}

void WebGPURenderer::SetSlotMode(int slotIndex, int mode) {
    if (slotIndex < 0 || slotIndex >= MAX_SHADER_SLOTS) return;
    slots_[slotIndex].mode = (mode == 1) ? SlotMode::Parallel : SlotMode::Chained;
}

void WebGPURenderer::SetTime(float time) {
    currentTime_ = time;
}

void WebGPURenderer::SetResolution(float width, float height) {
    if (width > 0.0f && height > 0.0f) {
        ResizeCanvas(static_cast<int>(width), static_cast<int>(height));
    }
}

// ─── Phase 2: Canvas resize ───────────────────────────────────────────────────

void WebGPURenderer::SetMouse(float x, float y, bool down) {
    mouseX_ = x;
    mouseY_ = y;
    mouseDown_ = down;
}

void WebGPURenderer::SetMouseDown(bool down) {
    mouseDown_ = down;
}

void WebGPURenderer::SetZoomParams(float p1, float p2, float p3, float p4) {
    zoomParams_[0] = p1;
    zoomParams_[1] = p2;
    zoomParams_[2] = p3;
    zoomParams_[3] = p4;
}

void WebGPURenderer::AddRipple(float x, float y) {
    if (ripples_.size() >= MAX_RIPPLES) {
        ripples_.erase(ripples_.begin());
    }
    RipplePoint rp = {x, y, currentTime_, 0.0f};
    ripples_.push_back(rp);
}

void WebGPURenderer::ClearRipples() {
    ripples_.clear();
}

const char* WebGPURenderer::GetSlotShaderId(int slotIndex) const {
    if (slotIndex < 0 || slotIndex >= MAX_SHADER_SLOTS) return "";
    return slots_[slotIndex].shaderId.c_str();
}

int WebGPURenderer::GetSlotEnabled(int slotIndex) const {
    if (slotIndex < 0 || slotIndex >= MAX_SHADER_SLOTS) return 0;
    return slots_[slotIndex].enabled ? 1 : 0;
}

int WebGPURenderer::GetSlotMode(int slotIndex) const {
    if (slotIndex < 0 || slotIndex >= MAX_SHADER_SLOTS) return 0;
    return (slots_[slotIndex].mode == SlotMode::Parallel) ? 1 : 0;
}

void WebGPURenderer::GetGPUTimings(float* parallelMs, float* chainedMs, float* totalMs, int* available) const {
    const bool gpuReady = supportsTimestampQuery_ && gpuTimingsResolved_;
    if (parallelMs) *parallelMs = gpuReady ? gpuParallelTimeMs_ : lastParallelTimeMs_;
    if (chainedMs)  *chainedMs  = gpuReady ? gpuChainedTimeMs_  : lastChainedTimeMs_;
    if (totalMs)    *totalMs    = gpuReady ? gpuTotalTimeMs_    : lastTotalTimeMs_;
    if (available)  *available  = gpuReady ? 1 : 0;
}

void WebGPURenderer::SetRecording(bool recording) {
    isRecording_ = recording;
}

} // namespace pixelocity
