#include <webgpu/webgpu_cpp.h>
#include <emscripten/emscripten.h>
#include <string>
#include <cstdio>

wgpu::Device device;
wgpu::Queue queue;
wgpu::RenderPipeline pipeline;
std::string currentShader;

extern "C" EMSCRIPTEN_KEEPALIVE
void initWasmRenderer(const char* wgslCode) {
  currentShader = wgslCode ? wgslCode : "";
  
  // Create WebGPU instance
  wgpu::Instance instance = wgpu::CreateInstance();
  
  // Request adapter
  wgpu::RequestAdapterOptions adapterOpts{};
  adapterOpts.powerPreference = wgpu::PowerPreference::HighPerformance;
  
  instance.RequestAdapter(
    &adapterOpts,
    [](WGPURequestAdapterStatus status, WGPUAdapter adapter, const char* message, void* userdata) {
      if (status == WGPURequestAdapterStatus_Success) {
        wgpu::Adapter a = wgpu::Adapter::Acquire(adapter);
        
        // Request device
        wgpu::DeviceDescriptor deviceDesc{};
        a.RequestDevice(
          &deviceDesc,
          [](WGPURequestDeviceStatus status, WGPUDevice device, const char* message, void* userdata) {
            if (status == WGPURequestDeviceStatus_Success) {
              printf("✅ C++ WASM Renderer initialized\n");
            }
          },
          nullptr
        );
      }
    },
    nullptr
  );
  
  printf("✅ C++ WASM Renderer loaded shader (%zu chars)\n", currentShader.size());
}

void renderLoop() {
  // Render loop implementation
}

int main() {
  emscripten_set_main_loop(renderLoop, 0, true);
  return 0;
}
