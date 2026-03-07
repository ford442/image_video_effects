#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <stdio.h>
#include <string.h>

extern "C" {

EMSCRIPTEN_KEEPALIVE
void initWasmRenderer(const char* wgslCode) {
    printf("✅ C++ WASM Renderer initialized!\n");
    printf("   Shader length: %zu characters\n", strlen(wgslCode));
    // Full Dawn C API setup will go here later (for now this proves the build works)
}

} // extern "C"

int main() {
    printf("🚀 Pixelocity WASM Renderer (C API) started\n");
    emscripten_set_main_loop([](){}, 0, true);
    return 0;
}
