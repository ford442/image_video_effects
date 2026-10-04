#include "renderer.h"
#include <emscripten/emscripten.h>
#include <cstdlib>
#include <cstdio>
#include <memory>

using namespace pixelocity;

// ═══════════════════════════════════════════════════════════════════════════════
// main.cpp - WASM JavaScript Bridge
// ═══════════════════════════════════════════════════════════════════════════════

// Owned here; every export null-checks it. Spontaneous WebGPU callbacks never
// hold this pointer directly (see CallbackToken), so reset() is safe while a
// map or device-lost callback is still pending.
static std::unique_ptr<WebGPURenderer> g_renderer;

extern "C" {

// ─── Lifecycle ────────────────────────────────────────────────────────────────

EMSCRIPTEN_KEEPALIVE
int initWasmRenderer(int width, int height, const char* canvasSelector) {
    if (!g_renderer) {
        g_renderer = std::make_unique<WebGPURenderer>();
    }
    bool ok = g_renderer->Initialize(width, height, canvasSelector);
    return ok ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
void shutdownWasmRenderer() {
    if (g_renderer) {
        g_renderer->Shutdown();
        g_renderer.reset();
    }
}

// ─── Shader management ────────────────────────────────────────────────────────

EMSCRIPTEN_KEEPALIVE
int loadShader(const char* id, const char* wgslCode) {
    if (!g_renderer || !id || !wgslCode) return 0;
    return g_renderer->LoadShader(id, wgslCode) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
int reloadShader(const char* id, const char* wgslCode) {
    if (!g_renderer || !id || !wgslCode) return 0;
    return g_renderer->ReloadShader(id, wgslCode) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
void setActiveShader(const char* id) {
    if (g_renderer && id) {
        g_renderer->SetActiveShader(id);
    }
}

// ── Multi-slot shader API ─────────────────────────────────────────────────────

EMSCRIPTEN_KEEPALIVE
void setSlotShader(int slotIndex, const char* id) {
    if (g_renderer && id) {
        g_renderer->SetSlotShader(slotIndex, id);
    }
}

EMSCRIPTEN_KEEPALIVE
void setSlotParams(int slotIndex, float p1, float p2, float p3, float p4) {
    if (g_renderer) {
        g_renderer->SetSlotParams(slotIndex, p1, p2, p3, p4);
    }
}

EMSCRIPTEN_KEEPALIVE
void setSlotMode(int slotIndex, int mode) {
    if (g_renderer) {
        g_renderer->SetSlotMode(slotIndex, mode);
    }
}

EMSCRIPTEN_KEEPALIVE
void setColorFormat(int formatEnum) {
    if (g_renderer) {
        g_renderer->SetColorFormat(formatEnum);
    }
}

EMSCRIPTEN_KEEPALIVE
int getColorFormat() {
    return g_renderer ? g_renderer->GetColorFormat() : 0;
}

// ─── Input ────────────────────────────────────────────────────────────────────

EMSCRIPTEN_KEEPALIVE
void loadImageData(const uint8_t* data, int width, int height) {
    if (g_renderer) {
        g_renderer->LoadImage(data, width, height);
    }
}

// GPU still ingest. The JS source is parked on Module.pixelocityPendingImage by
// the bridge (capture.ts uploadImageSource). Returns 1 on success; 0 means the
// caller should fall back to loadImageData.
EMSCRIPTEN_KEEPALIVE
int loadImageExternal(int width, int height) {
    return (g_renderer && g_renderer->LoadImageExternal(width, height)) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
void uploadVideoFrame(const uint8_t* data, int width, int height) {
    if (g_renderer) {
        g_renderer->UpdateVideoFrame(data, width, height);
    }
}

EMSCRIPTEN_KEEPALIVE
void updateDepthMap(const float* data, int width, int height) {
    if (g_renderer && data) {
        g_renderer->UpdateDepthMap(data, width, height);
    }
}

// Set the active input source (0=none, 1=image, 2=video, 3=webcam, 4=generative, 5=live).
// Generative clears readTexture_ to black.
EMSCRIPTEN_KEEPALIVE
void setInputSource(int source) {
    if (g_renderer) {
        g_renderer->SetInputSource(static_cast<InputSource>(source));
    }
}

// ─── Uniforms / interaction ───────────────────────────────────────────────────

// Trigger one Render() call from the JavaScript animation loop.
EMSCRIPTEN_KEEPALIVE
void updateUniforms() {
    if (g_renderer) {
        g_renderer->Render();
    }
}

// Set current time (seconds).  Must be called before updateUniforms().
EMSCRIPTEN_KEEPALIVE
void setTime(float time) {
    if (g_renderer) {
        g_renderer->SetTime(time);
    }
}

// Set global zoom parameters (used when no per-slot params are configured).
EMSCRIPTEN_KEEPALIVE
void setZoomParams(float p1, float p2, float p3, float p4) {
    if (g_renderer) {
        g_renderer->SetZoomParams(p1, p2, p3, p4);
    }
}

EMSCRIPTEN_KEEPALIVE
void updateMousePos(float x, float y) {
    // Position only: the bridge calls this on every pointer move without a
    // button state, so it must not clear mouseDown_ mid-drag.
    if (g_renderer) {
        g_renderer->SetMousePos(x, y);
    }
}

// Update mouse button state.  1 = pressed, 0 = released.
EMSCRIPTEN_KEEPALIVE
void setMouseDown(int down) {
    if (g_renderer) {
        g_renderer->SetMouseDown(down != 0);
    }
}

EMSCRIPTEN_KEEPALIVE
void updateAudioData(float bass, float mid, float treble) {
    if (g_renderer) {
        g_renderer->SetAudioData(bass, mid, treble);
    }
}

// Upload normalised FFT magnitude bins to extraBuffer_[5..132] (max 128 bins).
EMSCRIPTEN_KEEPALIVE
void updateAudioFrequencyBins(const float* bins, int count) {
    if (g_renderer && bins) {
        g_renderer->SetAudioFrequencyBins(bins, count);
    }
}

EMSCRIPTEN_KEEPALIVE
void addRipple(float x, float y) {
    if (g_renderer) {
        g_renderer->AddRipple(x, y);
    }
}

EMSCRIPTEN_KEEPALIVE
void clearRipples() {
    if (g_renderer) {
        g_renderer->ClearRipples();
    }
}

// ─── State queries ────────────────────────────────────────────────────────────

EMSCRIPTEN_KEEPALIVE
int isRendererInitialized() {
    return (g_renderer && g_renderer->IsInitialized()) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
float getFPS() {
    return g_renderer ? g_renderer->GetFPS() : 0.0f;
}

EMSCRIPTEN_KEEPALIVE
int getSupportsDeepWorkgroup() {
    return (g_renderer && g_renderer->GetSupportsDeepWorkgroup()) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
const char* getSlotShaderId(int slotIndex) {
    return g_renderer ? g_renderer->GetSlotShaderId(slotIndex) : "";
}

EMSCRIPTEN_KEEPALIVE
int getSlotEnabled(int slotIndex) {
    return g_renderer ? g_renderer->GetSlotEnabled(slotIndex) : 0;
}

EMSCRIPTEN_KEEPALIVE
int getSlotMode(int slotIndex) {
    return g_renderer ? g_renderer->GetSlotMode(slotIndex) : 0;
}

// Physical slot ceiling compiled into this artifact (MAX_SHADER_SLOTS; must equal
// slot_limits.json maxPhysicalSlots). Needs no renderer, so wasm:validate can
// read it from a stale binary without a GPU.
EMSCRIPTEN_KEEPALIVE
int getMaxShaderSlots() {
    return WebGPURenderer::GetMaxShaderSlots();
}

// Canvas COPY_SRC opt-in (canvas_configure.json optIn.copySrc).
EMSCRIPTEN_KEEPALIVE
int getCanvasCopySrcSupported() {
    return (g_renderer && g_renderer->IsCanvasCopySrcSupported()) ? 1 : 0;
}

// Reconfigures the swapchain with RENDER_ATTACHMENT | COPY_SRC (1) or back to
// render-only (0). Returns 1 on success, 0 when unsupported or no surface.
EMSCRIPTEN_KEEPALIVE
int setCanvasCopySrc(int enabled) {
    return (g_renderer && g_renderer->SetCanvasCopySrc(enabled != 0)) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
void getGPUTimings(float* parallelMs, float* chainedMs, float* totalMs, int* available) {
    if (g_renderer) {
        g_renderer->GetGPUTimings(parallelMs, chainedMs, totalMs, available);
    } else if (available) {
        *available = 0;
    }
}

// ─── Measurement / diagnostics (#1314 D) ─────────────────────────────────────

// JSON array of smoothed per-pass GPU timings from the last timestamp
// readback: [{"slot","shaderId","label","gpuMs","iterations"}, ...]. slot -1
// is the legacy single-shader path. "[]" until timestamps resolve or when the
// device has no timestamp-query. Valid until the next call.
EMSCRIPTEN_KEEPALIVE
const char* getPassTimingsJson() {
    return g_renderer ? g_renderer->GetPassTimingsJson() : "[]";
}

// Most recent uncaptured WebGPU error or device-lost message ("" if none).
// The ring is process-wide, so it also answers before init / after shutdown.
EMSCRIPTEN_KEEPALIVE
const char* getLastError() {
    return WebGPURenderer::ErrorRing().Last();
}

// {"count":<messages ever pushed>,"messages":[up to 16, oldest first]}.
EMSCRIPTEN_KEEPALIVE
const char* getErrorRingJson() {
    return WebGPURenderer::ErrorRingJson();
}

// Drop the held messages; count keeps counting.
EMSCRIPTEN_KEEPALIVE
void clearErrorRing() {
    WebGPURenderer::ErrorRing().Clear();
}

EMSCRIPTEN_KEEPALIVE
void setRecording(int recording) {
    if (g_renderer) {
        g_renderer->SetRecording(recording != 0);
    }
}

EMSCRIPTEN_KEEPALIVE
int isRecording() {
    return (g_renderer && g_renderer->IsRecording()) ? 1 : 0;
}

// Human-readable adapter/device/limits/format summary, built during
// CreateDevice(). Returns an empty string if not yet initialized.
EMSCRIPTEN_KEEPALIVE
const char* getAdapterSummary() {
    return g_renderer ? g_renderer->GetAdapterSummary().c_str() : "";
}

// Which Initialize() stage failed (see WebGPURenderer::InitStage), or
// InitStage::Ready (8) on success, or InitStage::None (0) before any
// Initialize() attempt / if no renderer exists yet.
EMSCRIPTEN_KEEPALIVE
int getLastInitErrorStage() {
    return g_renderer ? g_renderer->GetLastInitErrorStage() : 0;
}

// Human-readable reason for the last Initialize() failure. Empty string if
// init has not failed (or not been attempted yet).
EMSCRIPTEN_KEEPALIVE
const char* getLastInitErrorMessage() {
    return g_renderer ? g_renderer->GetLastInitErrorMessage().c_str() : "";
}

// ─── Phase 2: Canvas resize ───────────────────────────────────────────────────

// Resize the canvas and recreate all size-dependent GPU resources.
// Safe to call at any time after initialization.
EMSCRIPTEN_KEEPALIVE
void resizeCanvas(int newWidth, int newHeight) {
    if (g_renderer) {
        g_renderer->ResizeCanvas(newWidth, newHeight);
    }
}

// ─── Phase 2: Frame capture (screenshot readback) ────────────────────────────

// Initiate an asynchronous GPU readback of the current frame.
// Poll getFrameCaptureState() until it returns 2 (ready), then call
// readCapturedFrame() to retrieve the RGBA8 pixel data.
EMSCRIPTEN_KEEPALIVE
void beginFrameCapture() {
    if (g_renderer) {
        g_renderer->BeginFrameCapture();
    }
}

// Returns: 0=idle, 1=pending, 2=ready, 3=error.
EMSCRIPTEN_KEEPALIVE
int getFrameCaptureState() {
    return g_renderer ? g_renderer->GetFrameCaptureState() : 0;
}

// Copy RGBA8 pixel data into the buffer pointed to by outPtr (must be >= w*h*4 bytes).
// Returns the number of bytes written, or 0 on failure.
EMSCRIPTEN_KEEPALIVE
int readCapturedFrame(uint8_t* outPtr, int maxBytes) {
    if (!g_renderer || !outPtr) return 0;
    return g_renderer->ReadCapturedFrame(outPtr, maxBytes);
}

// Release the mapped readback buffer.  Must be called after readCapturedFrame().
EMSCRIPTEN_KEEPALIVE
void endFrameCapture() {
    if (g_renderer) {
        g_renderer->EndFrameCapture();
    }
}

// Convenience: returns the current canvas width (needed by JS to allocate the read buffer).
EMSCRIPTEN_KEEPALIVE
int getCanvasWidth() {
    return g_renderer ? g_renderer->GetCanvasWidth() : 0;
}

// Convenience: returns the current canvas height.
EMSCRIPTEN_KEEPALIVE
int getCanvasHeight() {
    return g_renderer ? g_renderer->GetCanvasHeight() : 0;
}

} // extern "C"

int main() {
    printf("Pixelocity WASM module loaded. Call initWasmRenderer() to start.\n");
    return 0;
}
