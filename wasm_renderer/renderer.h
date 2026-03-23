#pragma once

#include <webgpu/webgpu.h>
#include <vector>
#include <string>
#include <unordered_map>
#include <functional>

namespace pixelocity {

// ═══════════════════════════════════════════════════════════════════════════════
// RENDERER ARCHITECTURE OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════════
// This is the C++/WASM WebGPU renderer for Pixelocity. It aims to replace the
// JavaScript renderer for better performance but is currently INCOMPLETE.
//
// See RENDERER_PLAN.md for the full development roadmap.
//
// Current Status:
//   ✅ Single shader execution works
//   ✅ Image/video upload works (basic)
//   ❌ Multi-slot shader pipeline (3 slots) - NOT IMPLEMENTED
//   ❌ Audio integration - NOT IMPLEMENTED  
//   ❌ Depth map integration - STUB ONLY
//   ❌ Recording/screenshots - NOT IMPLEMENTED
//   ❌ Generative shader support - PARTIAL
//
// When to use JS renderer vs C++ renderer:
//   - JS Renderer: Use for now (more features, stable)
//   - C++ Renderer: Experimental, use for single-shader performance testing only
//
// ═══════════════════════════════════════════════════════════════════════════════

// TODO(Phase 2): Input source enum to match TypeScript
// enum class InputSource { None = 0, Image = 1, Video = 2, Webcam = 3, Generative = 4 };

// TODO(Phase 2): Multi-slot shader state
// struct ShaderSlot {
//     std::string shaderId;      // Which shader is bound to this slot
//     bool enabled = false;      // Is this slot active?
//     float params[9] = {0};     // zoomParam1-4, lightStrength, etc.
//     float audioResponse[3] = {0}; // How bass/mid/treble affects this slot
// };
// static constexpr int MAX_SHADER_SLOTS = 3;  // Match TypeScript

// TODO(Phase 4): Audio data structure
// struct AudioData {
//     float bass, mid, treble;   // 0-1 normalized frequency bands
//     float beat;                // Beat detection impulse
//     float spectrum[16];        // FFT buckets for detailed analysis
// };

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
// ═══════════════════════════════════════════════════════════════════════════════
// WebGPURenderer Class
// 
// PURPOSE: High-performance WebGPU compute shader renderer for image/video effects
// STATUS:  Partially functional - see RENDERER_PLAN.md for completion roadmap
//
// Current Limitations:
//   - Single shader only (no multi-slot chaining like TypeScript)
//   - No audio reactivity
//   - No recording/screenshot capability
//   - Depth map is stubbed
//
// Architecture:
//   Input (Image/Video/Generative) 
//     -> Compute Shader (effect processing)
//     -> Ping-pong texture swap
//     -> Render pass (blit to canvas)
//
// For multi-slot rendering (needed for production):
//   Input -> Slot 0 -> Slot 1 -> Slot 2 -> Output
//              ↓         ↓         ↓
//           shaderA   shaderB   shaderC
// ═══════════════════════════════════════════════════════════════════════════════
class WebGPURenderer {
public:
    WebGPURenderer();
    ~WebGPURenderer();

    // ═══════════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Initialize WebGPU device, queues, and resources
    // Returns false if WebGPU is not available
    bool Initialize(int canvasWidth, int canvasHeight);
    
    // Cleanup all WebGPU resources
    void Shutdown();

    // ═══════════════════════════════════════════════════════════════════════════
    // SHADER MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Compile and load a WGSL shader into memory
    // Shader is identified by 'id' for later activation
    bool LoadShader(const char* id, const char* wgslCode);
    
    // Set the active shader for single-shader rendering
    // TODO(Phase 2): DEPRECATE - use SetSlotShader(slot, id) instead
    void SetActiveShader(const char* id);
    
    // TODO(Phase 2): Multi-slot shader API - CRITICAL FOR PRODUCTION
    // 
    // The TypeScript renderer supports chaining 3 shader slots:
    //   modes: RenderMode[] = ['liquid', 'distortion', 'glow']
    // Each slot has independent parameters and feeds into the next.
    //
    // void SetSlotShader(int slotIndex, const char* id);  // slotIndex: 0-2
    // void SetSlotEnabled(int slotIndex, bool enabled);   // Enable/disable slot
    // void SetSlotParams(int slotIndex, const float* params);  // 9 floats per slot
    // void ClearSlot(int slotIndex);  // Reset slot to empty
    //
    // Render() will then execute slots in order: Slot 0 -> Slot 1 -> Slot 2
    // Each slot reads from the previous slot's output texture.
    //
    // Status: NOT IMPLEMENTED | Priority: CRITICAL | Est. Effort: 2-3 weeks
    
    // ═══════════════════════════════════════════════════════════════════════════
    // INPUT SOURCES
    // ═══════════════════════════════════════════════════════════════════════════
    
    // TODO(Phase 3): Input source selection
    // void SetInputSource(InputSource source);
    // enum class InputSource { Image=1, Video=2, Webcam=3, Generative=4 };
    // Status: NOT IMPLEMENTED - currently always uses last loaded image/video
    
    // Upload a static image (RGBA8) to the GPU
    // The image will be used as input for shader processing
    void LoadImage(const uint8_t* data, int width, int height);
    
    // Upload a video frame (RGBA8) to the GPU
    // Call this every frame when playing video
    void UpdateVideoFrame(const uint8_t* data, int width, int height);
    
    // TODO(Phase 5): Upload depth map from AI depth estimation
    // The depth map enables parallax and 3D-aware effects
    void UpdateDepthMap(const float* data, int width, int height);  // STUB ONLY
    
    // ═══════════════════════════════════════════════════════════════════════════
    // PARAMETERS & UNIFORMS
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Set global time (in seconds) for time-based shader animations
    void SetTime(float time);
    
    // TODO: Dynamic resolution changes (currently fixed at initialization)
    void SetResolution(float width, float height);  // STUB ONLY
    
    // Update mouse position and button state for interactive shaders
    void SetMouse(float x, float y, bool down);
    
    // Set zoom/parameter values for the active shader
    // TODO(Phase 2): Should be per-slot: SetSlotParams(slot, p1, p2, p3, p4)
    void SetZoomParams(float p1, float p2, float p3, float p4);
    
    // Add a ripple effect at normalized coordinates (0-1)
    void AddRipple(float x, float y);
    void ClearRipples();
    
    // TODO(Phase 4): Audio data integration
    // 
    // Audio frequency data from Web Audio API needs to reach shaders.
    // This enables audio-reactive visual effects that pulse to the beat.
    //
    // void SetAudioData(float bass, float mid, float treble);
    // TypeScript: updateAudioData(bass, mid, treble) -> extraBuffer/uniforms
    //
    // Status: NOT IMPLEMENTED | Priority: HIGH | Est. Effort: 1 week

    // ═══════════════════════════════════════════════════════════════════════════
    // RENDERING
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Execute the render pipeline:
    //   Single shader: Input -> Compute -> Output
    //   TODO Multi shader: Input -> Slot 0 -> Slot 1 -> Slot 2 -> Output
    void Render();
    
    // Present is a no-op for WebGPU (browser handles canvas presentation)
    void Present();
    
    // ═══════════════════════════════════════════════════════════════════════════
    // SCREENSHOT & RECORDING (TODO Phase 6)
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // Capture current frame as RGBA8 data
    // std::vector<uint8_t> CaptureScreenshot();
    // TypeScript: getFrameImage() returns data URL for sharing
    // Status: NOT IMPLEMENTED | Priority: MEDIUM | Est. Effort: 2-3 days
    //
    // Start/stop video recording
    // void StartRecording();  // 8-second clip
    // void StopRecording();
    // TypeScript: Uses MediaRecorder API on canvas.captureStream()
    // Status: NOT IMPLEMENTED | Priority: MEDIUM | Est. Effort: 1 week

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE QUERIES
    // ═══════════════════════════════════════════════════════════════════════════
    
    bool IsInitialized() const { return initialized_; }
    float GetFPS() const { return fps_; }
    
    // TODO: Performance metrics
    // float GetGPUTime() const { return gpuTimeMs_; }
    // size_t GetMemoryUsage() const { return memoryUsage_; }

private:
    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════
    bool CreateDevice();           // Create WebGPU instance, adapter, device
    bool CreateResources();        // Create textures, buffers, samplers
    void CreateBindGroupLayout();  // Define shader resource bindings
    void CreateBindGroups();       // Instantiate bind groups from layout
    void CreateRenderPipeline();   // Create final blit render pipeline
    void UpdateUniformBuffer();    // Upload uniform data to GPU
    
    // TODO(Phase 2): Multi-slot pipeline setup
    // void CreateSlotPipeline(int slotIndex);  // Per-slot bind groups
    // void UpdateSlotUniforms(int slotIndex, const ShaderSlot& slot);

    // ═══════════════════════════════════════════════════════════════════════════
    // WebGPU OBJECTS
    // ═══════════════════════════════════════════════════════════════════════════
    WGPUInstance instance_ = nullptr;
    WGPUSurface surface_ = nullptr;
    WGPUAdapter adapter_ = nullptr;
    WGPUDevice device_ = nullptr;
    WGPUQueue queue_ = nullptr;
    WGPUTextureFormat surfaceFormat_ = WGPUTextureFormat_Undefined;

    // Compute pipeline (single shared layout for all compute shaders)
    WGPUBindGroupLayout computeBindGroupLayout_ = nullptr;
    WGPUPipelineLayout computePipelineLayout_ = nullptr;
    WGPUBindGroup computeBindGroup_ = nullptr;
    
    // TODO(Phase 2): Per-slot bind groups for multi-slot rendering
    // WGPUBindGroup slotBindGroups_[MAX_SHADER_SLOTS] = {};

    // Render pipeline (full-screen triangle for final output)
    WGPURenderPipeline renderPipeline_ = nullptr;
    WGPUBindGroup renderBindGroup_ = nullptr;

    // ═══════════════════════════════════════════════════════════════════════════
    // TEXTURE RESOURCES
    // ═══════════════════════════════════════════════════════════════════════════
    // TODO(Phase 3): Separate input texture from processing textures
    // WGPUTexture inputImageTexture_ = nullptr;  // User-uploaded image/video
    
    WGPUTexture imageTexture_ = nullptr;     // DEPRECATED: Use inputImageTexture_
    WGPUTexture videoTexture_ = nullptr;     // DEPRECATED: Use inputImageTexture_
    
    // Ping-pong textures for shader iteration
    WGPUTexture readTexture_ = nullptr;      // Current frame input
    WGPUTexture writeTexture_ = nullptr;     // Current frame output
    
    // Data textures for feedback effects
    WGPUTexture dataTextureA_ = nullptr;     // Shader-accessible storage
    WGPUTexture dataTextureB_ = nullptr;     // Shader-accessible storage  
    WGPUTexture dataTextureC_ = nullptr;     // Shader-accessible storage
    
    // Depth map (AI-generated from depth estimation model)
    WGPUTexture depthTextureRead_ = nullptr;
    WGPUTexture depthTextureWrite_ = nullptr;
    
    // 1x1 black texture for "empty" input
    WGPUTexture emptyTexture_ = nullptr;
    
    // TODO(Phase 6): Screenshot readback texture/buffer
    // WGPUTexture screenshotTexture_ = nullptr;
    // WGPUBuffer readbackBuffer_ = nullptr;

    // ═══════════════════════════════════════════════════════════════════════════
    // SAMPLERS
    // ═══════════════════════════════════════════════════════════════════════════
    WGPUSampler filteringSampler_ = nullptr;      // For smooth interpolation
    WGPUSampler nonFilteringSampler_ = nullptr;   // For pixel-perfect sampling
    WGPUSampler comparisonSampler_ = nullptr;     // For depth comparisons

    // ═══════════════════════════════════════════════════════════════════════════
    // BUFFERS
    // ═══════════════════════════════════════════════════════════════════════════
    WGPUBuffer uniformBuffer_ = nullptr;   // Global uniforms (time, mouse, etc.)
    WGPUBuffer extraBuffer_ = nullptr;     // Additional data (FFT spectrum, etc.)
    WGPUBuffer plasmaBuffer_ = nullptr;    // Plasma effect parameters
    
    // TODO(Phase 3): Staging buffer for efficient uploads
    // WGPUBuffer stagingBuffer_ = nullptr;   // Persistent staging memory
    // size_t stagingBufferSize_ = 0;
    
    // TODO(Phase 4): Audio buffer
    // WGPUBuffer audioBuffer_ = nullptr;     // Audio uniforms for shaders

    // ═══════════════════════════════════════════════════════════════════════════
    // SHADER STORAGE
    // ═══════════════════════════════════════════════════════════════════════════
    std::unordered_map<std::string, ShaderPipeline> shaders_;
    std::string activeShaderId_;
    
    // TODO(Phase 2): Multi-slot state
    // ShaderSlot slots_[MAX_SHADER_SLOTS];
    // int activeSlotCount_ = 0;
    // int currentWriteSlot_ = 0;  // Track ping-pong for multi-slot

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════
    void UploadRGBA8ToReadTexture(const uint8_t* data, int width, int height);
    
    // TODO(Phase 3): Optimized upload with staging buffer
    // void UploadToTextureOptimized(WGPUTexture texture, const uint8_t* data, 
    //                               int width, int height, WGPUTextureFormat format);
    
    // TODO(Phase 2): Multi-slot execution helpers
    // WGPUTexture GetSlotInputTexture(int slotIndex);
    // WGPUTexture GetSlotOutputTexture(int slotIndex);
    // void ExecuteShaderSlot(WGPUCommandEncoder encoder, int slotIndex,
    //                        WGPUTexture input, WGPUTexture output);

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════
    bool initialized_ = false;
    int canvasWidth_ = 0;
    int canvasHeight_ = 0;
    
    // TODO: Precompute workgroup counts
    // uint32_t workgroupCountX_ = 0;
    // uint32_t workgroupCountY_ = 0;
    
    // Animation/interaction state
    float currentTime_ = 0.0f;
    float mouseX_ = 0.5f;
    float mouseY_ = 0.5f;
    bool mouseDown_ = false;
    float zoomParams_[4] = {0.5f, 0.5f, 0.5f, 0.5f};
    std::vector<RipplePoint> ripples_;
    
    // TODO(Phase 3): Input source tracking
    // InputSource inputSource_ = InputSource::None;
    // bool hasInputFrame_ = false;
    
    // TODO(Phase 4): Audio state
    // AudioData audioData_ = {};
    
    // Performance metrics
    float fps_ = 0.0f;
    float lastFrameTime_ = 0.0f;
    int frameCount_ = 0;
    
    // TODO: GPU timing queries
    // float gpuTimeMs_ = 0.0f;
    // WGPUQuerySet timestampQuerySet_ = nullptr;
    
    static constexpr int MAX_RIPPLES = 50;
    static constexpr int MAX_PLASMA_BALLS = 50;
    static constexpr int MAX_SHADER_SLOTS = 3;  // TODO(Phase 2): Use this constant
};

} // namespace pixelocity
