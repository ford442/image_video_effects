#include "renderer.h"
#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <emscripten/html5.h>
#include <stdio.h>
#include <string>

// Global renderer instance
static pixelocity::WebGPURenderer* g_renderer = nullptr;
static bool g_running = false;

// JavaScript-exposed functions
extern "C" {

EMSCRIPTEN_KEEPALIVE
int initWasmRenderer(int canvasWidth, int canvasHeight) {
    printf("🚀 WASM Renderer: initWasmRenderer called\n");
    printf("   Canvas size: %dx%d\n", canvasWidth, canvasHeight);
    
    if (g_renderer) {
        printf("⚠️ Renderer already initialized, shutting down first\n");
        delete g_renderer;
    }
    
    g_renderer = new pixelocity::WebGPURenderer();
    
    if (!g_renderer->Initialize(canvasWidth, canvasHeight)) {
        printf("❌ Failed to initialize renderer\n");
        delete g_renderer;
        g_renderer = nullptr;
        return -1;
    }
    
    g_running = true;
    printf("✅ WASM Renderer initialized successfully\n");
    return 0;
}

EMSCRIPTEN_KEEPALIVE
void shutdownWasmRenderer() {
    printf("🛑 WASM Renderer: shutdownWasmRenderer called\n");
    g_running = false;
    if (g_renderer) {
        delete g_renderer;
        g_renderer = nullptr;
    }
    printf("✅ WASM Renderer shutdown complete\n");
}

EMSCRIPTEN_KEEPALIVE
int loadShader(const char* id, const char* wgslCode) {
    if (!g_renderer) {
        printf("❌ Renderer not initialized\n");
        return -1;
    }
    
    printf("📥 Loading shader: %s\n", id);
    if (!g_renderer->LoadShader(id, wgslCode)) {
        printf("❌ Failed to load shader: %s\n", id);
        return -1;
    }
    
    return 0;
}

EMSCRIPTEN_KEEPALIVE
void setActiveShader(const char* id) {
    if (!g_renderer) return;
    g_renderer->SetActiveShader(id);
    printf("🎯 Active shader set to: %s\n", id);
}

EMSCRIPTEN_KEEPALIVE
void updateUniforms(float time, float mouseX, float mouseY, int mouseDown,
                   float p1, float p2, float p3, float p4) {
    if (!g_renderer) return;
    
    g_renderer->SetTime(time);
    g_renderer->SetMouse(mouseX, mouseY, mouseDown != 0);
    g_renderer->SetZoomParams(p1, p2, p3, p4);
}

EMSCRIPTEN_KEEPALIVE
void addRipple(float x, float y) {
    if (!g_renderer) return;
    g_renderer->AddRipple(x, y);
}

EMSCRIPTEN_KEEPALIVE
void clearRipples() {
    if (!g_renderer) return;
    g_renderer->ClearRipples();
}

EMSCRIPTEN_KEEPALIVE
float getFPS() {
    if (!g_renderer) return 0.0f;
    return g_renderer->GetFPS();
}

EMSCRIPTEN_KEEPALIVE
int isRendererInitialized() {
    return (g_renderer && g_renderer->IsInitialized()) ? 1 : 0;
}

} // extern "C"

// Main render loop
static void renderLoop() {
    if (!g_running || !g_renderer) return;
    g_renderer->Render();
}

// Emscripten main loop callback
static void mainLoop() {
    renderLoop();
}

int main() {
    printf("🚀 Pixelocity WASM Renderer (C++ WebGPU) v1.0\n");
    printf("   Built with Emscripten + WebGPU\n");
    
    // Set up the main loop
    emscripten_set_main_loop(mainLoop, 0, 1);
    
    return 0;
}
