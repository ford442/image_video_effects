#include "renderer.h"
#include <emscripten/emscripten.h>
#include <cstdlib>
#include <cstdio>

using namespace pixelocity;

// ═══════════════════════════════════════════════════════════════════════════════
// main.cpp - WASM JavaScript Bridge
// ═══════════════════════════════════════════════════════════════════════════════
//
// PURPOSE:
//   Provides the C API exports that JavaScript calls via Emscripten.
//   This is the glue layer between the TypeScript app and C++ WebGPURenderer.
//
// API NAMING CONVENTION:
//   - All exports use camelCase matching existing wasm_bridge.js calls
//   - Return int for boolean status: 1=success, 0=failure
//   - Use plain C types only in function signatures (no STL in exports)
//
// ═══════════════════════════════════════════════════════════════════════════════

static WebGPURenderer* g_renderer = nullptr;

extern "C" {

// ─── Lifecycle ────────────────────────────────────────────────────────────────

EMSCRIPTEN_KEEPALIVE
int initWasmRenderer(int width, int height) {
    if (!g_renderer) {
        g_renderer = new WebGPURenderer();
    }
    bool ok = g_renderer->Initialize(width, height);
    return ok ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
void shutdownWasmRenderer() {
    if (g_renderer) {
        g_renderer->Shutdown();
        delete g_renderer;
        g_renderer = nullptr;
    }
}

// ─── Shader management ────────────────────────────────────────────────────────

EMSCRIPTEN_KEEPALIVE
int loadShader(const char* id, const char* wgslCode) {
    if (!g_renderer || !id || !wgslCode) return 0;
    return g_renderer->LoadShader(id, wgslCode) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
void setActiveShader(const char* id) {
    if (g_renderer && id) {
        g_renderer->SetActiveShader(id);
    }
}

// ─── Input ────────────────────────────────────────────────────────────────────

EMSCRIPTEN_KEEPALIVE
void loadImageData(const uint8_t* data, int width, int height) {
    if (g_renderer) {
        g_renderer->LoadImage(data, width, height);
    }
}

EMSCRIPTEN_KEEPALIVE
void uploadVideoFrame(const uint8_t* data, int width, int height) {
    if (g_renderer) {
        g_renderer->UpdateVideoFrame(data, width, height);
    }
}

// ─── Uniforms / interaction ───────────────────────────────────────────────────

// Called by wasm_bridge.js every animation frame; triggers a Render() call.
EMSCRIPTEN_KEEPALIVE
void updateUniforms() {
    if (g_renderer) {
        g_renderer->Render();
    }
}

EMSCRIPTEN_KEEPALIVE
void updateMousePos(float x, float y) {
    if (g_renderer) {
        g_renderer->SetMouse(x, y, false);
    }
}

EMSCRIPTEN_KEEPALIVE
void updateAudioData(float bass, float mid, float treble) {
    if (g_renderer) {
        g_renderer->SetAudioData(bass, mid, treble);
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

// ─── Stubs / future features ──────────────────────────────────────────────────
// TODO(Phase 2): Multi-slot shader API
//   void setSlotShader(int slotIndex, const char* shaderId);
//   void setSlotMode(int slotIndex, int mode);
//   void setSlotParams(int slotIndex, float p1, float p2, float p3, float p4);
//
// TODO(Phase 3): Input source selection
//   void setInputSource(int source); // 0=image, 1=video, 2=webcam, 3=generative
//
// TODO(Phase 5): Depth map
//   void updateDepthMap(const float* data, int width, int height);
//
// TODO(Phase 6): Screenshot / recording
//   uint8_t* captureScreenshot(int* outWidth, int* outHeight);
//   void startRecording();
//   void stopRecording();

} // extern "C"

int main() {
    printf("Pixelocity WASM module loaded. Call initWasmRenderer() to start.\n");
    return 0;
}
