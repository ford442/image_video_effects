# Pixelocity C++/WASM Renderer Development Plan

## Current Status Overview

The C++ renderer (`WebGPURenderer`) is partially functional but has critical gaps that prevent it from fully replacing the JS/TS renderer. The JS/TS engine remains the primary renderer while we complete the C++ implementation.

### Architecture Comparison

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TYPESCRIPT RENDERER (Working)                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  Input Sources:          Shader Pipeline (3 slots):         Output:         │
│  ┌─────────┐            ┌─────────────────────┐            ┌─────────┐     │
│  │ Image   │──┐         │ Slot 0: liquid      │──┐         │         │     │
│  │ Video   │──┼──┐     │ Slot 1: distortion  │──┼──┐     │ Canvas  │     │
│  │ Webcam  │──┼──┼──▶  │ Slot 2: glow        │──┼──┼──▶  │         │     │
│  │ Live    │──┘  │     └─────────────────────┘  │  │     └─────────┘     │
│  │ Generative│    │     Each slot chains to next │  │                      │
│  └─────────┘     │     with independent params  │  │                      │
│                  │                              │  │                      │
│  Audio: ─────────┘  Depth: ─────────────────────┘  │                      │
│  (bass/mid/treble)  (AI depth estimation)          │                      │
│                                                    │                      │
│  Recording: Capture 8s clips (WebM) ←──────────────┘                      │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                         C++ RENDERER (Incomplete)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  Input Sources:          Shader Pipeline:                  Output:         │
│  ┌─────────┐            ┌─────────────────┐              ┌─────────┐       │
│  │ Image   │──┐         │ Single shader   │              │         │       │
│  │ Video   │──┼──▶      │ (NO chaining)   │────────────▶ │ Canvas  │       │
│  └─────────┘  │         └─────────────────┘              │         │       │
│               │                                          └─────────┘       │
│  Audio: ❌ Not implemented                                                   │
│  Depth: ❌ Not implemented                                                   │
│  Multi-slot: ❌ Not implemented                                              │
│  Recording: ❌ Not implemented                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Foundation Cleanup (Week 1)

### 1.1 Remove Dead Code
**File**: `main.cpp`

The Physarum simulation code (~250 lines) is never executed. It creates:
- Global state conflicts with `WebGPURenderer`
- Confusion about which system is active
- Maintenance burden

**Action**:
```cpp
// DELETE: Lines 25-263 (Physarum simulation globals and shaders)
// DELETE: Lines 429-566 (Dead Physarum functions)
// DELETE: Lines 568-579 (main() that starts wrong render loop)
```

### 1.2 Consolidate C API Exports
**File**: `main.cpp`

Current exports are scattered across 3 `extern "C"` blocks. Consolidate into single block with consistent naming:

```cpp
extern "C" {
    // Initialization
    EMSCRIPTEN_KEEPALIVE int wasmInit(int width, int height);
    EMSCRIPTEN_KEEPALIVE void wasmShutdown();
    EMSCRIPTEN_KEEPALIVE int wasmIsInitialized();
    
    // Shader Management  
    EMSCRIPTEN_KEEPALIVE int wasmLoadShader(const char* id, const char* wgsl);
    EMSCRIPTEN_KEEPALIVE void wasmSetShader(int slotIndex, const char* id);
    EMSCRIPTEN_KEEPALIVE void wasmClearShader(int slotIndex);
    
    // Input Sources
    EMSCRIPTEN_KEEPALIVE void wasmSetInputSource(int source); // 0=image, 1=video, 2=webcam, 3=generative
    EMSCRIPTEN_KEEPALIVE void wasmLoadImage(const uint8_t* data, int w, int h);
    EMSCRIPTEN_KEEPALIVE void wasmLoadVideoFrame(const uint8_t* data, int w, int h);
    
    // Parameters
    EMSCRIPTEN_KEEPALIVE void wasmSetTime(float time);
    EMSCRIPTEN_KEEPALIVE void wasmSetMouse(float x, float y, int down);
    EMSCRIPTEN_KEEPALIVE void wasmSetZoomParams(int slotIndex, float p1, float p2, float p3, float p4);
    EMSCRIPTEN_KEEPALIVE void wasmSetAudioData(float bass, float mid, float treble);
    EMSCRIPTEN_KEEPALIVE void wasmSetDepthMap(const float* data, int w, int h);
    
    // Effects
    EMSCRIPTEN_KEEPALIVE void wasmAddRipple(float x, float y);
    EMSCRIPTEN_KEEPALIVE void wasmClearRipples();
    
    // Rendering & Recording
    EMSCRIPTEN_KEEPALIVE void wasmRender();
    EMSCRIPTEN_KEEPALIVE void wasmStartRecording();
    EMSCRIPTEN_KEEPALIVE void wasmStopRecording();
    EMSCRIPTEN_KEEPALIVE uint8_t* wasmCaptureScreenshot(int* w, int* h);
    
    // Queries
    EMSCRIPTEN_KEEPALIVE float wasmGetFPS();
}
```

---

## Phase 2: Multi-Slot Shader Pipeline (Weeks 2-3)

### 2.1 Slot State Structure
**File**: `renderer.h`

Add per-slot state to track independent shader configurations:

```cpp
// Maximum number of shader slots (matches TypeScript)
static constexpr int MAX_SHADER_SLOTS = 3;

struct ShaderSlot {
    std::string shaderId;           // Which shader is bound to this slot
    bool enabled = false;           // Is this slot active?
    float params[9] = {0};          // zoomParam1-4, lightStrength, etc.
    float audioResponse[3] = {0};   // How much bass/mid/treble affects this slot
    // Bindings are dynamic based on slot position in chain
};

// In WebGPURenderer class:
ShaderSlot slots_[MAX_SHADER_SLOTS];
int activeSlotCount_ = 0;
```

### 2.2 Chained Render Pipeline
**File**: `renderer.cpp`

Modify `Render()` to execute slots in sequence:

```cpp
void WebGPURenderer::Render() {
    if (!initialized_) return;
    
    WGPUCommandEncoder encoder = CreateCommandEncoder();
    
    // Determine input texture for first slot
    WGPUTexture inputTexture = GetInputTexture(); // Based on inputSource_
    
    // Execute each enabled slot in sequence
    for (int i = 0; i < MAX_SHADER_SLOTS; i++) {
        if (!slots_[i].enabled || slots_[i].shaderId.empty()) continue;
        
        // Determine output texture
        // Slot 0 -> writeTexture_ (ping)
        // Slot 1 -> readTexture_ (pong)  
        // Slot 2 -> writeTexture_ (ping, final)
        WGPUTexture outputTexture = (i % 2 == 0) ? writeTexture_ : readTexture_;
        
        // Execute compute shader for this slot
        ExecuteShaderSlot(encoder, i, inputTexture, outputTexture);
        
        // Output becomes input for next slot
        inputTexture = outputTexture;
    }
    
    // Final blit to screen
    BlitToCanvas(encoder, inputTexture);
    
    Submit(encoder);
}
```

### 2.3 Dynamic Bind Group Updates
Each slot needs different texture bindings:

```cpp
void WebGPURenderer::ExecuteShaderSlot(
    WGPUCommandEncoder encoder, 
    int slotIndex,
    WGPUTexture inputTex,
    WGPUTexture outputTex
) {
    // Update bind group for this slot's specific input/output
    // (Implementation details in Phase 4)
}
```

---

## Phase 3: Input Source System (Week 4)

### 3.1 Input Source Enum & State
**File**: `renderer.h`

```cpp
enum class InputSource {
    None = 0,
    Image = 1,      // Static image from LoadImage()
    Video = 2,      // Video frames from LoadVideoFrame()
    Webcam = 3,     // Same as Video but with different UI treatment
    Generative = 4  // Procedural generation (no input texture needed)
};

// In WebGPURenderer:
InputSource inputSource_ = InputSource::None;
WGPUTexture inputImageTexture_ = nullptr;  // For Image source
bool hasInputFrame_ = false;
```

### 3.2 Texture Upload Optimization
**File**: `renderer.cpp`

Current `UploadRGBA8ToReadTexture()` allocates large vectors every frame. Optimize:

```cpp
class WebGPURenderer {
    // Add persistent staging buffer
    WGPUBuffer stagingBuffer_ = nullptr;
    size_t stagingBufferSize_ = 0;
    
    void EnsureStagingBuffer(size_t size) {
        if (stagingBufferSize_ >= size) return;
        if (stagingBuffer_) wgpuBufferRelease(stagingBuffer_);
        // Create new larger buffer
        stagingBufferSize_ = size * 1.5; // Growth factor
        // ... create buffer
    }
};

void WebGPURenderer::UploadVideoFrame(const uint8_t* data, int width, int height) {
    // Use staging buffer instead of vector allocation
    EnsureStagingBuffer(width * height * 4);
    // Map buffer, copy data, unmap, copy to texture
    // ...
}
```

### 3.3 Generative Shader Support
Some shaders don't need input (e.g., `gen-orb`, `gen-nebula`):

```cpp
WGPUTexture WebGPURenderer::GetInputTexture() {
    switch (inputSource_) {
        case InputSource::Image:
        case InputSource::Video:
        case InputSource::Webcam:
            return hasInputFrame_ ? inputImageTexture_ : emptyTexture_;
        case InputSource::Generative:
            return emptyTexture_; // Shaders sample from empty/black
        default:
            return emptyTexture_;
    }
}
```

---

## Phase 4: Audio Integration (Week 5)

### 4.1 Audio Uniform Structure
**File**: `renderer.h`

```cpp
struct AudioData {
    float bass;       // 0-1 normalized
    float mid;        // 0-1 normalized  
    float treble;     // 0-1 normalized
    float beat;       // Beat detection impulse
    float spectrum[16]; // FFT buckets for detailed shaders
};

// In WebGPURenderer:
AudioData audioData_ = {};
WGPUBuffer audioBuffer_ = nullptr; // Separate buffer for frequent updates
```

### 4.2 Audio Parameter Binding
Shaders can access audio via uniforms:

```wgsl
// In shader WGSL:
struct AudioUniforms {
    bass: f32,
    mid: f32, 
    treble: f32,
    beat: f32,
    spectrum: array<f32, 16>,
}
@group(0) @binding(13) var<uniform> audio: AudioUniforms;

// Usage in shader:
let audioIntensity = audio.bass * 2.0;
let displacedUV = uv + vec2<f32>(audio.bass * 0.1, 0.0);
```

### 4.3 Audio-Reactive Parameters
Allow slots to have audio-responsive parameters:

```cpp
struct ShaderSlot {
    // ... existing fields ...
    
    // Audio modulation: baseValue + audio[bass/mid/treble] * scale
    struct AudioMod {
        int paramIndex;     // Which parameter (0-8)
        int audioBand;      // 0=bass, 1=mid, 2=treble
        float scale;        // Multiplier
        float baseValue;    // Value when audio is 0
    };
    std::vector<AudioMod> audioMods;
};

void WebGPURenderer::UpdateSlotParams(int slotIndex) {
    ShaderSlot& slot = slots_[slotIndex];
    float finalParams[9];
    memcpy(finalParams, slot.params, sizeof(finalParams));
    
    // Apply audio modulation
    for (const auto& mod : slot.audioMods) {
        float audioVal = (mod.audioBand == 0) ? audioData_.bass :
                         (mod.audioBand == 1) ? audioData_.mid : audioData_.treble;
        finalParams[mod.paramIndex] = mod.baseValue + audioVal * mod.scale;
    }
    
    // Upload to GPU
    UpdateUniformBuffer(slotIndex, finalParams);
}
```

---

## Phase 5: Depth Map Integration (Week 6)

### 5.1 Depth Texture Upload
**File**: `renderer.cpp`

Complete the stubbed `UpdateDepthMap()`:

```cpp
void WebGPURenderer::UpdateDepthMap(const float* data, int width, int height) {
    // Upload float32 depth data to depthTextureRead_
    // Similar to UploadRGBA8ToReadTexture but:
    // - Source is float32, not uint8
    // - Single channel (R32Float), not RGBA
    // - May need resizing if AI model outputs different resolution
    
    WGPUTexelCopyTextureInfo dest = {};
    dest.texture = depthTextureRead_;
    // ... setup copy
    
    wgpuQueueWriteTexture(queue_, &dest, data, 
                          width * height * sizeof(float), 
                          &layout, &extent);
}
```

### 5.2 Depth-Aware Shaders
Shaders can use depth for parallax/displacement effects:

```wgsl
@group(0) @binding(4) var depthTexture: texture_2d<f32>;

fn getDepth(uv: vec2<f32>) -> f32 {
    return textureSample(depthTexture, nonFilteringSampler, uv).r;
}

// Parallax displacement based on depth
let depth = getDepth(uv);
let parallaxOffset = (depth - 0.5) * mouseDelta * 0.1;
```

---

## Phase 6: Screenshot & Recording (Week 7)

### 6.1 Screenshot Capture
**File**: `renderer.cpp`

```cpp
std::vector<uint8_t> WebGPURenderer::CaptureScreenshot() {
    // Create readback buffer
    size_t size = canvasWidth_ * canvasHeight_ * 4;
    WGPUBufferDescriptor bufferDesc = {};
    bufferDesc.size = size;
    bufferDesc.usage = WGPUBufferUsage_CopyDst | WGPUBufferUsage_MapRead;
    WGPUBuffer readbackBuffer = wgpuDeviceCreateBuffer(device_, &bufferDesc);
    
    // Copy current output texture to buffer
    // ... encode copy command, submit, wait for completion
    
    // Map buffer and copy to vector
    // ... mapAsync, get mapped range, copy, unmap
    
    return screenshotData;
}
```

### 6.2 Video Recording
Use browser's MediaRecorder API via Emscripten bindings:

```cpp
// In JavaScript bridge:
EM_JS(void, jsStartRecording, (), {
    const canvas = document.getElementById('render-canvas');
    const stream = canvas.captureStream(30); // 30 fps
    window.recorder = new MediaRecorder(stream, {
        mimeType: 'video/webm;codecs=vp9',
        videoBitsPerSecond: 8000000 // 8 Mbps
    });
    window.recordedChunks = [];
    window.recorder.ondataavailable = e => window.recordedChunks.push(e.data);
    window.recorder.start(100); // Collect 100ms chunks
    window.recordingStartTime = Date.now();
    
    // Auto-stop after 8 seconds
    setTimeout(() => {
        if (window.recorder && window.recorder.state === 'recording') {
            window.recorder.stop();
        }
    }, 8000);
});

EM_JS(void, jsStopRecording, (), {
    if (window.recorder && window.recorder.state === 'recording') {
        window.recorder.stop();
    }
});
```

---

## Phase 7: JS Bridge Updates (Week 8)

### 7.1 Update wasm_bridge.js
**File**: `src/wasm/wasm_bridge.js`

```javascript
// New API mapping
export const RendererAPI = {
    // Initialization
    init: () => Module.ccall('wasmInit', 'number', ['number', 'number'], [2048, 2048]),
    shutdown: () => Module.ccall('wasmShutdown', null, [], []),
    
    // Multi-slot shaders
    setSlotShader: (slot, id) => Module.ccall('wasmSetShader', null, 
        ['number', 'string'], [slot, id]),
    setSlotParams: (slot, params) => {
        const ptr = Module._malloc(9 * 4);
        Module.HEAPF32.set(params, ptr / 4);
        Module.ccall('wasmSetZoomParams', null, 
            ['number', 'number'], [slot, ptr]);
        Module._free(ptr);
    },
    
    // Input
    setInputSource: (source) => Module.ccall('wasmSetInputSource', null, 
        ['number'], [source]),
    loadImage: (rgbaData, width, height) => {
        const ptr = Module._malloc(rgbaData.length);
        Module.HEAPU8.set(rgbaData, ptr);
        Module.ccall('wasmLoadImage', null, 
            ['number', 'number', 'number'], [ptr, width, height]);
        Module._free(ptr);
    },
    
    // Audio
    updateAudio: (bass, mid, treble) => Module.ccall('wasmSetAudioData', null,
        ['number', 'number', 'number'], [bass, mid, treble]),
    
    // Recording
    startRecording: () => Module.ccall('wasmStartRecording', null, [], []),
    stopRecording: () => Module.ccall('wasmStopRecording', null, [], []),
};
```

---

## Testing Checklist

### Per-Phase Testing

| Phase | Test | Expected Result |
|-------|------|-----------------|
| 1 | Build after cleanup | No Physarum references, compiles cleanly |
| 2 | Load 3 different shaders | All 3 execute in sequence, output visible |
| 3 | Switch between Image/Video/Generative | No crashes, correct input texture bound |
| 4 | Play audio while shader active | Shader parameters visibly respond |
| 5 | Load depth map | Depth-aware shaders show parallax |
| 6 | Click "Record" | 8s video downloaded after recording stops |
| 7 | Full integration test | All TypeScript features work via C++ |

---

## Migration Strategy

### Gradual Cutover

1. **Phase 1-2**: C++ renderer optional, default to JS
   ```typescript
   const useWasm = urlParams.get('wasm') === '1';
   ```

2. **Phase 3-4**: C++ renderer default, fallback to JS
   ```typescript
   const useWasm = urlParams.get('js') !== '1'; // Default WASM
   ```

3. **Phase 5-7**: Remove JS renderer entirely
   - Delete `JSRenderer.ts`
   - Simplify `RendererManager` to only use `WASMRenderer`

---

## Performance Targets

| Metric | JS Renderer | C++ Target | Notes |
|--------|-------------|------------|-------|
| Frame time (3 shaders) | ~16ms | ~8ms | 2x faster compute |
| Memory usage | ~200MB | ~150MB | Less JS heap overhead |
| Shader load time | ~50ms | ~20ms | Direct WASM compilation |
| Video upload latency | ~5ms | ~2ms | Staging buffer reuse |

---

## Appendix: TypeScript to C++ Mapping

| TypeScript | C++ | Notes |
|------------|-----|-------|
| `RenderMode[]` | `ShaderSlot[3]` | Fixed array vs vector |
| `SlotParams` | `ShaderSlot::params[9]` | Float array |
| `updateAudioData()` | `wasmSetAudioData()` | Direct pass-through |
| `getFrameImage()` | `wasmCaptureScreenshot()` | Async readback |
| `setRecording()` | `wasmStartRecording()` | JS MediaRecorder integration |
| `updateDepthMap()` | `wasmSetDepthMap()` | Float32 upload |
