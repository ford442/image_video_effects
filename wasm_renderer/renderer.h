#pragma once

#include <webgpu/webgpu.h>
#include <array>
#include <vector>
#include <string>
#include <unordered_map>

namespace pixelocity {

// ═══════════════════════════════════════════════════════════════════════════════
// RENDERER ARCHITECTURE OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════════
// This is the C++/WASM WebGPU renderer for Pixelocity.
//
// Status (Phase 3):
//   ✅ Single shader execution
//   ✅ Image/video upload
//   ✅ Multi-slot shader pipeline (3 slots, chained/parallel)
//   ✅ Audio integration (bass/mid/treble -> extraBuffer + plasmaBuffer)
//   ✅ Depth map integration
//   ✅ Generative shader support
//   ✅ Canvas resize
//   ✅ Frame capture (async GPU readback)
//   ✅ RAII wrappers for all WebGPU handles
//   ✅ Device-lost and uncaptured-error callbacks
//
// ═══════════════════════════════════════════════════════════════════════════════

// ─── RAII Handle Template ─────────────────────────────────────────────────────
//
// WGPUHandle<T, Release> is a move-only wrapper that calls Release(ptr) on
// destruction.  Use the type aliases below for concrete WebGPU objects.
//
// Usage:
//   WGPUTextureHandle tex;
//   tex.reset(wgpuDeviceCreateTexture(device, &desc));
//   // tex is auto-released when it goes out of scope
//
template<typename T, void (*Release)(T)>
struct WGPUHandle {
    T ptr = nullptr;

    WGPUHandle() = default;
    explicit WGPUHandle(T p) : ptr(p) {}
    ~WGPUHandle() { if (ptr) Release(ptr); }

    // Non-copyable
    WGPUHandle(const WGPUHandle&) = delete;
    WGPUHandle& operator=(const WGPUHandle&) = delete;

    // Movable
    WGPUHandle(WGPUHandle&& o) noexcept : ptr(o.ptr) { o.ptr = nullptr; }
    WGPUHandle& operator=(WGPUHandle&& o) noexcept {
        if (this != &o) { if (ptr) Release(ptr); ptr = o.ptr; o.ptr = nullptr; }
        return *this;
    }

    // Implicit conversion to raw pointer for API calls
    operator T() const { return ptr; }
    // Returns true when the handle is null (no object managed)
    bool operator!() const { return !ptr; }

    // Replace managed object (releases old pointer)
    void reset(T new_ptr = nullptr) {
        if (ptr) Release(ptr);
        ptr = new_ptr;
    }

    // Release ownership without destroying
    T release() { T tmp = ptr; ptr = nullptr; return tmp; }

    T get() const { return ptr; }
};

// Convenience type aliases for the most commonly used WebGPU objects
using WGPUInstanceHandle         = WGPUHandle<WGPUInstance,         wgpuInstanceRelease>;
using WGPUAdapterHandle          = WGPUHandle<WGPUAdapter,          wgpuAdapterRelease>;
using WGPUDeviceHandle           = WGPUHandle<WGPUDevice,           wgpuDeviceRelease>;
using WGPUSurfaceHandle          = WGPUHandle<WGPUSurface,          wgpuSurfaceRelease>;
using WGPUQueueHandle            = WGPUHandle<WGPUQueue,            wgpuQueueRelease>;
using WGPUTextureHandle          = WGPUHandle<WGPUTexture,          wgpuTextureRelease>;
using WGPUSamplerHandle          = WGPUHandle<WGPUSampler,          wgpuSamplerRelease>;
using WGPUBufferHandle           = WGPUHandle<WGPUBuffer,           wgpuBufferRelease>;
using WGPUBindGroupLayoutHandle  = WGPUHandle<WGPUBindGroupLayout,  wgpuBindGroupLayoutRelease>;
using WGPUPipelineLayoutHandle   = WGPUHandle<WGPUPipelineLayout,   wgpuPipelineLayoutRelease>;
using WGPUBindGroupHandle        = WGPUHandle<WGPUBindGroup,        wgpuBindGroupRelease>;
using WGPUComputePipelineHandle  = WGPUHandle<WGPUComputePipeline,  wgpuComputePipelineRelease>;
using WGPURenderPipelineHandle   = WGPUHandle<WGPURenderPipeline,   wgpuRenderPipelineRelease>;
using WGPUShaderModuleHandle     = WGPUHandle<WGPUShaderModule,     wgpuShaderModuleRelease>;

// Slot execution mode: chained feeds output of slot N into slot N+1;
// parallel makes every slot read from the same original source texture.
enum class SlotMode { Chained = 0, Parallel = 1 };

// Input source for the renderer.  Generative shaders use a black texture.
enum class InputSource { None = 0, Image = 1, Video = 2, Webcam = 3, Generative = 4 };

// Per-slot state: shader selection, parameters, and execution mode.
struct ShaderSlot {
    std::string shaderId;
    bool        enabled = false;
    float       params[4] = {0.5f, 0.5f, 0.5f, 0.5f};  // zoom_params
    SlotMode    mode = SlotMode::Chained;
};

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
    WGPUShaderModuleHandle    module;
    WGPUComputePipelineHandle pipeline;
    std::string id;
    std::string name;
    // Workgroup dimensions parsed from @workgroup_size in WGSL source.
    // Defaults to (16, 16) to match the TypeScript renderer.
    uint32_t workgroupX = 16;
    uint32_t workgroupY = 16;
};

// ═══════════════════════════════════════════════════════════════════════════════
// WebGPURenderer Class
//
// Multi-slot pipeline architecture:
//   Input (readTexture_) -> Slot 0 -> pingPong0_
//                        -> Slot 1 -> pingPong1_
//                        -> Slot 2 -> writeTexture_
//   Then: writeTexture_ -> readTexture_ (ping-pong for next frame)
// ═══════════════════════════════════════════════════════════════════════════════
class WebGPURenderer {
public:
    WebGPURenderer();
    ~WebGPURenderer();

    // Non-copyable, non-movable (manages GPU resources)
    WebGPURenderer(const WebGPURenderer&) = delete;
    WebGPURenderer& operator=(const WebGPURenderer&) = delete;
    WebGPURenderer(WebGPURenderer&&) = delete;
    WebGPURenderer& operator=(WebGPURenderer&&) = delete;

    // ═══════════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Initialize WebGPU device, queues, and resources.
    // Sets up device-lost and uncaptured-error callbacks.
    // canvasSelector: CSS selector for the HTMLCanvasElement to present to,
    //   e.g. "#my-canvas".  Pass nullptr to skip surface/presentation setup.
    // Returns false if WebGPU is not available.
    bool Initialize(int canvasWidth, int canvasHeight,
                    const char* canvasSelector = nullptr);
    
    // Cleanup all WebGPU resources
    void Shutdown();

    // ═══════════════════════════════════════════════════════════════════════════
    // SHADER MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    // Compile and load a WGSL shader into memory.
    // Retrieves and logs compilation messages via wgpuShaderModuleGetCompilationInfo.
    // @workgroup_size is parsed from wgslCode for correct dispatch.
    bool LoadShader(const char* id, const char* wgslCode);

    // Set the active shader for single-shader (legacy) rendering.
    // Also enables slot 0 with this shader for backwards compatibility.
    void SetActiveShader(const char* id);

    // ── Multi-slot API ────────────────────────────────────────────────────────
    // Assign a previously loaded shader to a slot (0-2).
    void SetSlotShader(int slotIndex, const char* id);
    // Set the four zoom parameters for a specific slot.
    void SetSlotParams(int slotIndex, float p1, float p2, float p3, float p4);
    // Set execution mode: 0 = chained (default), 1 = parallel.
    void SetSlotMode(int slotIndex, int mode);

    // ═══════════════════════════════════════════════════════════════════════════
    // INPUT SOURCES
    // ═══════════════════════════════════════════════════════════════════════════

    // Upload a static image (RGBA8) to the GPU.
    void LoadImage(const uint8_t* data, int width, int height);

    // Upload a video frame (RGBA8) to the GPU (call every frame).
    void UpdateVideoFrame(const uint8_t* data, int width, int height);

    // Upload a depth map (R32Float, one float per pixel) from the AI model.
    void UpdateDepthMap(const float* data, int width, int height);

    // Set the current input source so the renderer knows how to feed shaders.
    void SetInputSource(InputSource source);

    // ═══════════════════════════════════════════════════════════════════════════
    // PARAMETERS & UNIFORMS
    // ═══════════════════════════════════════════════════════════════════════════

    // Set global time (seconds) for time-based shader animations.
    void SetTime(float time);

    // Dynamic resolution changes are not yet supported (fixed at init).
    void SetResolution(float width, float height);  // delegates to ResizeCanvas

    // Phase 2: Dynamically resize the canvas and recreate all size-dependent GPU resources.
    // Safe to call at any time after Initialize(); no-op if dimensions are unchanged.
    void ResizeCanvas(int newWidth, int newHeight);

    // Update mouse position and button state for interactive shaders.
    void SetMouse(float x, float y, bool down);

    // Update only the mouse button state (preserves existing x/y).
    void SetMouseDown(bool down);

    // Set global zoom/parameter values (used when no slot is configured).
    void SetZoomParams(float p1, float p2, float p3, float p4);

    // Add a ripple effect at normalised coordinates (0-1).
    void AddRipple(float x, float y);
    void ClearRipples();

    // Audio frequency bands from Web Audio API.
    // Data is written to both extraBuffer_ (binding 10) and plasmaBuffer_
    // (binding 12, vec4(bass, mid, treble, 0) at index 0) so that all
    // audio-reactive shader conventions are satisfied.
    void SetAudioData(float bass, float mid, float treble);

    // ═══════════════════════════════════════════════════════════════════════════
    // RENDERING
    // ═══════════════════════════════════════════════════════════════════════════

    // Execute one frame: update uniforms, dispatch compute passes for all
    // enabled slots in order, then blit to the canvas.
    void Render();

    // Present is a no-op for WebGPU (browser handles canvas presentation).
    void Present();

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE QUERIES
    // ═══════════════════════════════════════════════════════════════════════════

    bool IsInitialized() const { return initialized_; }
    float GetFPS() const { return fps_; }
    int GetCanvasWidth()  const { return canvasWidth_; }
    int GetCanvasHeight() const { return canvasHeight_; }

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 2: FRAME CAPTURE (async GPU readback for screenshots / recording)
    // ═══════════════════════════════════════════════════════════════════════════

    // Initiate an asynchronous readback of the current frame (writeTexture_).
    // Call GetFrameCaptureState() to poll for completion.
    void BeginFrameCapture();

    // Returns capture state: 0=idle, 1=pending, 2=ready, 3=error.
    int GetFrameCaptureState() const { return static_cast<int>(captureState_); }

    // When state==2 (ready): copy RGBA8 pixels into outRGBA8 (must be >= W*H*4 bytes).
    // Returns the number of bytes written, or 0 on failure.
    int ReadCapturedFrame(uint8_t* outRGBA8, int maxBytes);

    // Release the mapped readback buffer.  Call after ReadCapturedFrame().
    void EndFrameCapture();

private:
    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════
    bool CreateDevice();
    bool CreateResources();
    void CreateBindGroupLayout();
    void CreateBindGroups();
    void CreateRenderPipeline();
    void CreateRenderBindGroup();
    void ConfigureSurface();
    void PresentToSurface();
    void UpdateUniformBuffer();

    // Release and recreate all canvas-size-dependent textures.
    // Called by ResizeCanvas().
    void RecreateTextures();

    // Create a temporary compute bind group that uses the supplied read/write
    // textures for bindings 1 and 2; all other bindings are shared globals.
    // Caller is responsible for releasing the returned WGPUBindGroup.
    WGPUBindGroup CreateComputeBindGroup(WGPUTexture readTex, WGPUTexture writeTex);

    // Overwrite only the zoom_params portion (bytes 32-47) of the uniform buffer.
    void WriteSlotParams(const float* params);

    // Dispatch one compute pass using the given pipeline, bind group, and
    // texture dimensions.  The caller owns encoder/bind-group lifetime.
    // workgroupX/Y default to 16 (parsed from WGSL source in LoadShader).
    void DispatchComputePass(WGPUCommandEncoder encoder,
                             WGPUComputePipeline pipeline,
                             WGPUBindGroup bindGroup,
                             uint32_t workgroupX = 16,
                             uint32_t workgroupY = 16);

    // ═══════════════════════════════════════════════════════════════════════════
    // WebGPU OBJECTS  (RAII-managed via WGPUHandle<> wrappers)
    // ═══════════════════════════════════════════════════════════════════════════
    WGPUInstanceHandle instance_;
    WGPUSurfaceHandle  surface_;
    WGPUAdapterHandle  adapter_;
    WGPUDeviceHandle   device_;
    WGPUQueueHandle    queue_;
    WGPUTextureFormat  surfaceFormat_ = WGPUTextureFormat_Undefined;

    // Compute pipeline (single shared layout for all compute shaders)
    WGPUBindGroupLayoutHandle computeBindGroupLayout_;
    WGPUPipelineLayoutHandle  computePipelineLayout_;
    WGPUBindGroupHandle       computeBindGroup_;

    // Render pipeline (full-screen triangle for final blit)
    WGPURenderPipelineHandle renderPipeline_;
    WGPUBindGroupHandle      renderBindGroup_;

    // ═══════════════════════════════════════════════════════════════════════════
    // TEXTURE RESOURCES  (RAII-managed)
    // ═══════════════════════════════════════════════════════════════════════════

    // Primary ping-pong textures (source → compute → feedback for next frame)
    WGPUTextureHandle readTexture_;   // Previous-frame output / source image
    WGPUTextureHandle writeTexture_;  // Final composed output this frame

    // Intermediate ping-pong textures for multi-slot chaining
    WGPUTextureHandle pingPong0_;  // Output of slot 0 / input of slot 1
    WGPUTextureHandle pingPong1_;  // Output of slot 1 / input of slot 2

    // Data textures for feedback / multi-pass effects
    WGPUTextureHandle dataTextureA_;  // write-only storage (binding 7)
    WGPUTextureHandle dataTextureB_;  // write-only storage (binding 8)
    WGPUTextureHandle dataTextureC_;  // read-only texture  (binding 9)

    // Depth map (AI-generated from depth estimation model)
    WGPUTextureHandle depthTextureRead_;
    WGPUTextureHandle depthTextureWrite_;

    // 1×1 black texture used as placeholder input for generative shaders
    WGPUTextureHandle emptyTexture_;

    // ═══════════════════════════════════════════════════════════════════════════
    // SAMPLERS  (RAII-managed)
    // ═══════════════════════════════════════════════════════════════════════════
    WGPUSamplerHandle filteringSampler_;
    WGPUSamplerHandle nonFilteringSampler_;
    WGPUSamplerHandle comparisonSampler_;

    // ═══════════════════════════════════════════════════════════════════════════
    // BUFFERS  (RAII-managed)
    // ═══════════════════════════════════════════════════════════════════════════
    WGPUBufferHandle uniformBuffer_;  // Uniforms: time, mouse, params, ripples
    WGPUBufferHandle extraBuffer_;    // Extra data: audio FFT, misc floats
    WGPUBufferHandle plasmaBuffer_;   // Plasma / audio data (vec4 array)

    // Audio frequency data (written by SetAudioData, flushed in UpdateUniformBuffer)
    float audioBass_   = 0.0f;
    float audioMid_    = 0.0f;
    float audioTreble_ = 0.0f;

    // ═══════════════════════════════════════════════════════════════════════════
    // PERSISTENT STAGING BUFFER (avoids per-frame heap allocation)
    // ═══════════════════════════════════════════════════════════════════════════
    // Reused across frames for UploadRGBA8ToReadTexture().
    // Grows on demand but never shrinks.
    std::vector<float> videoStagingBuffer_;

    // ═══════════════════════════════════════════════════════════════════════════
    // ASYNC FRAME CAPTURE STATE
    // ═══════════════════════════════════════════════════════════════════════════
    enum class CaptureState { Idle = 0, Pending = 1, Ready = 2, Error = 3 };
    CaptureState     captureState_       = CaptureState::Idle;
    WGPUBufferHandle readbackBuffer_;
    size_t           readbackBufferSize_ = 0;
    // Aligned bytes-per-row used when copying texture → readback buffer.
    uint32_t         readbackBytesPerRow_ = 0;

    // ═══════════════════════════════════════════════════════════════════════════
    // SHADER STORAGE
    // ═══════════════════════════════════════════════════════════════════════════
    std::unordered_map<std::string, ShaderPipeline> shaders_;
    std::string activeShaderId_;  // legacy single-shader mode

    // Multi-slot state
    static constexpr int MAX_SHADER_SLOTS = 3;
    ShaderSlot slots_[MAX_SHADER_SLOTS];

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════
    void UploadRGBA8ToReadTexture(const uint8_t* data, int width, int height);

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════
    bool        initialized_  = false;
    int         canvasWidth_  = 0;
    int         canvasHeight_ = 0;

    // CSS selector of the target HTMLCanvasElement, e.g. "#my-canvas".
    // Empty string means no surface / presentation path.
    std::string canvasSelector_;

    // Animation/interaction state
    float currentTime_ = 0.0f;
    float mouseX_      = 0.5f;
    float mouseY_      = 0.5f;
    bool  mouseDown_   = false;
    float zoomParams_[4] = {0.5f, 0.5f, 0.5f, 0.5f};
    std::vector<RipplePoint> ripples_;

    // Input source (generative shaders use black placeholder)
    InputSource inputSource_ = InputSource::None;

    // Performance metrics
    float fps_           = 0.0f;
    float lastFrameTime_ = 0.0f;
    int   frameCount_    = 0;

    static constexpr int MAX_RIPPLES     = 50;
    static constexpr int MAX_PLASMA_BALLS = 50;
};

} // namespace pixelocity
