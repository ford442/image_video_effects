#include "renderer.h"
#include <emscripten/emscripten.h>
#include <cstdlib>
#include <cstdio>

using namespace pixelocity;

// ═══════════════════════════════════════════════════════════════════════════════
// main.cpp - WASM JavaScript Bridge
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

// ── Multi-slot shader API (Phase 1) ──────────────────────────────────────────

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

EMSCRIPTEN_KEEPALIVE
void updateDepthMap(const float* data, int width, int height) {
    if (g_renderer && data) {
        g_renderer->UpdateDepthMap(data, width, height);
    }
}

// Set the active input source (0=none/generative, 1=image, 2=video, 3=webcam, 4=generative).
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
    if (g_renderer) {
        g_renderer->SetMouse(x, y, false);
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

} // extern "C"

int main() {
    printf("Pixelocity WASM module loaded. Call initWasmRenderer() to start.\n");
    return 0;
}
