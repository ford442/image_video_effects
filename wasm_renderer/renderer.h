#pragma once

#include <webgpu/webgpu.h>
#include <vector>
#include <string>
#include <unordered_map>
#include <functional>

namespace pixelocity {

// Uniform structure matching the WGSL shaders
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
    
    // Resource management
    void LoadImage(const uint8_t* data, int width, int height);
    void UpdateDepthMap(const float* data, int width, int height);
    
    // Uniform updates
    void SetTime(float time);
    void SetResolution(float width, float height);
    void SetMouse(float x, float y, bool down);
    void SetZoomParams(float p1, float p2, float p3, float p4);
    void AddRipple(float x, float y);
    void ClearRipples();

    // Rendering
    void Render();
    void Present();

    // State queries
    bool IsInitialized() const { return initialized_; }
    float GetFPS() const { return fps_; }

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
    WGPUSwapChain swapChain_ = nullptr;
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

    // Shader storage
    std::unordered_map<std::string, ShaderPipeline> shaders_;
    std::string activeShaderId_;

    // State
    bool initialized_ = false;
    int canvasWidth_ = 0;
    int canvasHeight_ = 0;
    float currentTime_ = 0.0f;
    float mouseX_ = 0.5f;
    float mouseY_ = 0.5f;
    bool mouseDown_ = false;
    float zoomParams_[4] = {0.5f, 0.5f, 0.5f, 0.5f};
    std::vector<RipplePoint> ripples_;
    float fps_ = 0.0f;
    float lastFrameTime_ = 0.0f;
    int frameCount_ = 0;
    
    static constexpr int MAX_RIPPLES = 50;
    static constexpr int MAX_PLASMA_BALLS = 50;
};

} // namespace pixelocity
