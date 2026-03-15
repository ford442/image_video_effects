#pragma once

#include <webgpu/webgpu.h>
#include <vector>
#include <string>
#include <unordered_map>
#include <functional>

namespace pixelocity {

// Uniform structure matching the WGSL shaders
// PERF: MEDIUM - Structure is 848 bytes (212 floats). Consider alignment hints
// to ensure GPU layout matches exactly. Add static_assert for size validation.
struct Uniforms {
    float config[4];       // time, rippleCount, resolutionX, resolutionY
    float zoom_config[4];  // time, mouseX, mouseY, mouseDown
    float zoom_params[4];  // param1, param2, param3, param4
    float ripples[50][4];  // x, y, startTime, unused
};

struct RipplePoint {
    float x, y;
    float startTime;
    float padding;
};

struct ShaderPipeline {
    WGPUShaderModule module = nullptr;
    WGPUComputePipeline pipeline = nullptr;
    std::string id;
    std::string name;
};

// PERF: HIGH - Consider adding performance monitoring members:
// - Frame time histogram for adaptive quality
// - GPU timestamp queries for accurate GPU timing
// - Memory usage tracking for leak detection
class WebGPURenderer {
public:
    WebGPURenderer();
    ~WebGPURenderer();

    // Initialization
    bool Initialize(int canvasWidth, int canvasHeight);
    void Shutdown();

    // Shader management
    bool LoadShader(const char* id, const char* wgslCode);
    void SetActiveShader(const char* id);
    
    // MISSING: Multi-slot shader management (CRITICAL)
    // The TypeScript Renderer supports 3 shader slots that can be chained:
    //   modes: RenderMode[] = ['liquid', 'distortion', 'glow']
    // Each slot has independent parameters and feeds into the next.
    // Implementation needed:
    //   void SetSlotShader(int slotIndex, const char* id);  // slotIndex: 0-2
    //   void SetSlotParams(int slotIndex, const float* params);  // 9 params per slot
    //   void ExecuteSlotChain();  // Execute slots 0->1->2 in sequence
    // Priority: CRITICAL | Effort: 2-3 weeks
    
    // Resource management
    void LoadImage(const uint8_t* data, int width, int height);
    void UpdateVideoFrame(const uint8_t* data, int width, int height);
    void UpdateDepthMap(const float* data, int width, int height);
    
    // Uniform updates
    void SetTime(float time);
    void SetResolution(float width, float height);
    void SetMouse(float x, float y, bool down);
    void SetZoomParams(float p1, float p2, float p3, float p4);
    void AddRipple(float x, float y);
    void ClearRipples();
    
    // MISSING: Audio analyzer integration (HIGH)
    // void SetAudioData(float bass, float mid, float treble);
    // Audio frequency data from Web Audio API needs to reach shaders.
    // TS Renderer: updateAudioData(bass, mid, treble) -> extraBuffer/uniforms
    // Priority: HIGH | Effort: 1 week

    // Rendering
    void Render();
    void Present();
    
    // MISSING: Screenshot functionality (MEDIUM)
    // std::vector<uint8_t> CaptureScreenshot();  // Returns RGBA8 data
    // TypeScript: getFrameImage() returns data URL for sharing
    // Priority: MEDIUM | Effort: 2-3 days

    // State queries
    bool IsInitialized() const { return initialized_; }
    float GetFPS() const { return fps_; }
    
    // PERF: LOW - Add performance query methods:
    // float GetGPUTime() const { return gpuTimeMs_; }
    // size_t GetMemoryUsage() const { return memoryUsage_; }

private:
    bool CreateDevice();
    bool CreateResources();
    void CreateBindGroupLayout();
    void CreateBindGroups();
    void CreateRenderPipeline();
    void UpdateUniformBuffer();

    // WebGPU objects
    WGPUInstance instance_ = nullptr;
    WGPUSurface surface_ = nullptr;
    WGPUAdapter adapter_ = nullptr;
    WGPUDevice device_ = nullptr;
    WGPUQueue queue_ = nullptr;
    // Note: SwapChain deprecated in new WebGPU API, using Surface directly
    WGPUTextureFormat surfaceFormat_ = WGPUTextureFormat_Undefined;

    // Bind group layout (universal for all compute shaders)
    WGPUBindGroupLayout computeBindGroupLayout_ = nullptr;
    WGPUPipelineLayout computePipelineLayout_ = nullptr;
    WGPUBindGroup computeBindGroup_ = nullptr;

    // Render pipeline for final blit
    WGPURenderPipeline renderPipeline_ = nullptr;
    WGPUBindGroup renderBindGroup_ = nullptr;

    // Resources
    WGPUTexture imageTexture_ = nullptr;
    WGPUTexture videoTexture_ = nullptr;
    WGPUTexture readTexture_ = nullptr;      // Ping-pong read
    WGPUTexture writeTexture_ = nullptr;     // Ping-pong write
    WGPUTexture depthTextureRead_ = nullptr;
    WGPUTexture depthTextureWrite_ = nullptr;
    WGPUTexture dataTextureA_ = nullptr;
    WGPUTexture dataTextureB_ = nullptr;
    WGPUTexture dataTextureC_ = nullptr;
    WGPUTexture emptyTexture_ = nullptr;

    // Samplers
    WGPUSampler filteringSampler_ = nullptr;
    WGPUSampler nonFilteringSampler_ = nullptr;
    WGPUSampler comparisonSampler_ = nullptr;

    // Buffers
    WGPUBuffer uniformBuffer_ = nullptr;
    WGPUBuffer extraBuffer_ = nullptr;
    WGPUBuffer plasmaBuffer_ = nullptr;
    
    // PERF: HIGH - Add staging buffer for async uploads:
    // WGPUBuffer stagingBuffer_ = nullptr;
    // void* mappedStagingPtr_ = nullptr;

    // Shader storage
    std::unordered_map<std::string, ShaderPipeline> shaders_;
    std::string activeShaderId_;

    // Helpers
    void UploadRGBA8ToReadTexture(const uint8_t* data, int width, int height);

    // State
    bool initialized_ = false;
    int canvasWidth_ = 0;
    int canvasHeight_ = 0;
    
    // PERF: MEDIUM - Precompute workgroup dispatch counts to avoid per-frame division:
    // uint32_t workgroupCountX_ = 0;
    // uint32_t workgroupCountY_ = 0;
    
    float currentTime_ = 0.0f;
    float mouseX_ = 0.5f;
    float mouseY_ = 0.5f;
    bool mouseDown_ = false;
    float zoomParams_[4] = {0.5f, 0.5f, 0.5f, 0.5f};
    std::vector<RipplePoint> ripples_;
    float fps_ = 0.0f;
    float lastFrameTime_ = 0.0f;
    int frameCount_ = 0;
    
    // PERF: LOW - Performance tracking:
    // float gpuTimeMs_ = 0.0f;
    // WGPUQuerySet timestampQuerySet_ = nullptr;
    
    static constexpr int MAX_RIPPLES = 50;
    static constexpr int MAX_PLASMA_BALLS = 50;
};

} // namespace pixelocity
