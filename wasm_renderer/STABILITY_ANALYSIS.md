# WASM Renderer Stability Analysis

**Date:** 2026-03-14  
**Scope:** C++ WASM Renderer for Pixelocity WebGPU Shader Effects  
**Analyzed Files:**
- `renderer.h`
- `renderer.cpp`
- `main.cpp`
- `wasm_bridge.js`

---

## Executive Summary

The WASM renderer has **significant stability risks** that could lead to crashes, memory corruption, and resource leaks in production. The codebase lacks proper error handling for WebGPU async operations, missing null checks on memory allocations, and has no device-lost recovery mechanisms.

### Critical Statistics

| Severity | Count | Description |
|----------|-------|-------------|
| **Critical** | 6 | Memory corruption, race conditions, null dereferences |
| **High** | 18 | Resource leaks, missing validation, crash scenarios |
| **Medium** | 25 | Poor error handling, design issues, edge cases |
| **Low** | 16 | Code quality, maintainability concerns |
| **Total** | **65** | Issues identified across all files |

### Key Risks

1. **Race Conditions in Async WebGPU Initialization** - Device/adapter requests are not properly synchronized
2. **WASM Memory Allocation Failures** - No null checks on `_malloc` results lead to memory corruption
3. **No Device Lost Handling** - GPU reset causes undefined behavior
4. **Missing Resource Cleanup** - Partial initialization failures leak resources
5. **No Shader Compilation Error Reporting** - Silent failures make debugging impossible

---

## Prioritized Fix List

### 🔴 Critical Priority (Fix Immediately)

#### 1. Fix Async WebGPU Initialization Race Condition
**File:** `renderer.cpp` - `CreateDevice()`  
**Issue:** Callback-based adapter/device requests complete asynchronously, but code checks results synchronously.  
**Fix:** 
```cpp
// Option 1: Use synchronous APIs if available
// Option 2: Block until callback completes using a completion flag
std::atomic<bool> adapterReady{false};
wgpuInstanceRequestAdapter(instance_, &adapterOpts,
    WGPURequestAdapterCallbackInfo{
        nullptr, WGPUCallbackMode_AllowProcessEvents,
        [](WGPURequestAdapterStatus status, WGPUAdapter adapter, ...) {
            // ... set adapter ...
            adapterReady.store(true);
        }, &adapter_, nullptr
    });
// Pump events until callback completes
while (!adapterReady.load()) {
    wgpuInstanceProcessEvents(instance_);
}
```

#### 2. Add WASM Memory Allocation Null Checks
**File:** `wasm_bridge.js` - All functions using `_malloc`  
**Issue:** `wasmModule._malloc()` returns 0 on OOM, causing memory corruption when used.  
**Fix:**
```javascript
const ptr = wasmModule._malloc(size);
if (ptr === 0) {
    console.error('WASM memory allocation failed - out of memory');
    return false;
}
// Use ptr safely...
```

#### 3. Implement WebGPU Error Callback
**File:** `renderer.cpp` - After device creation  
**Issue:** No visibility into shader compilation or validation errors.  
**Fix:**
```cpp
auto errorCallback = [](WGPUErrorType type, WGPUStringView message, void*) {
    printf("WebGPU Error [%d]: %.*s\n", type, 
           static_cast<int>(message.length), message.data);
};
wgpuDeviceSetUncapturedErrorCallback(device_, errorCallback, nullptr);
```

#### 4. Fix UploadRGBA8ToReadTexture Null Data Check
**File:** `renderer.cpp` - `UploadRGBA8ToReadTexture()`  
**Issue:** No null check on `data` parameter from JavaScript.  
**Fix:**
```cpp
void WebGPURenderer::UploadRGBA8ToReadTexture(const uint8_t* data, int width, int height) {
    if (!data || !queue_ || !readTexture_) return;
    if (width <= 0 || height <= 0) return;
    // ... rest of function
}
```

#### 5. Add Integer Overflow Protection in Buffer Allocation
**File:** `renderer.cpp` - `CreateResources()`  
**Issue:** `canvasWidth_ * canvasHeight_ * 4` can overflow.  
**Fix:**
```cpp
#include <limits>
#include <cstddef>

size_t pixelCount = static_cast<size_t>(canvasWidth_) * canvasHeight_;
size_t floatCount = pixelCount * 4;
if (floatCount > std::numeric_limits<size_t>::max() / sizeof(float)) {
    printf("❌ Buffer size overflow\n");
    return false;
}
std::vector<float> zeros(floatCount, 0.0f);
```

#### 6. Fix renderLoop Null Pipeline Usage
**File:** `main.cpp` - `renderLoop()`  
**Issue:** Uses `agentPipeline` and `trailPipeline` without checking if shader compilation succeeded.  
**Fix:**
```cpp
void renderLoop() {
    if (!wasmMode || !device || !agentPipeline || !trailPipeline) return;
    // ... rest of function
}
```

---

### 🟠 High Priority (Fix Before Production)

#### 7. Implement Device Lost Recovery
**File:** `renderer.h`, `renderer.cpp`  
**Issue:** No handling for GPU reset/device loss.  
**Fix:**
```cpp
// In renderer.h
enum class DeviceState {
    Uninitialized,
    Ready,
    Lost,
    Error
};
DeviceState deviceState_ = DeviceState::Uninitialized;

// In CreateDevice()
auto deviceLostCallback = [](WGPUDeviceLostReason reason, WGPUStringView message, void* userdata) {
    auto* renderer = static_cast<WebGPURenderer*>(userdata);
    renderer->deviceState_ = DeviceState::Lost;
    printf("Device lost: %.*s\n", static_cast<int>(message.length), message.data);
};
wgpuDeviceSetDeviceLostCallback(device_, deviceLostCallback, this);
```

#### 8. Add Parameter Validation to Public API
**File:** `renderer.cpp` - All public methods  
**Issue:** No validation of width/height/pointer parameters.  
**Fix:**
```cpp
bool WebGPURenderer::Initialize(int canvasWidth, int canvasHeight) {
    if (canvasWidth <= 0 || canvasHeight <= 0) {
        printf("❌ Invalid canvas dimensions: %dx%d\n", canvasWidth, canvasHeight);
        return false;
    }
    if (canvasWidth > 16384 || canvasHeight > 16384) {
        printf("❌ Canvas dimensions exceed maximum (16384)\n");
        return false;
    }
    // ... rest of initialization
}
```

#### 9. Fix Initialization Failure Resource Cleanup
**File:** `renderer.cpp` - `Initialize()`  
**Issue:** Partial failures don't clean up already-created resources.  
**Fix:**
```cpp
bool WebGPURenderer::Initialize(int canvasWidth, int canvasHeight) {
    // Use RAII guard or explicit cleanup on failure
    bool success = false;
    
    if (!CreateDevice()) goto cleanup;
    if (!CreateResources()) goto cleanup;
    // ... more init steps
    
    success = true;
    
cleanup:
    if (!success) {
        Shutdown(); // Ensure cleanup of partial state
    }
    return success;
}
```

#### 10. Add Type Validation in JS Bridge
**File:** `wasm_bridge.js` - `uploadImageData()`, `uploadVideoFrame()`  
**Issue:** No validation of pixel buffer type and size.  
**Fix:**
```javascript
export function uploadImageData(rgbaPixels, width, height) {
    if (!state.initialized || !wasmModule) return;
    
    if (!(rgbaPixels instanceof Uint8Array) && !(rgbaPixels instanceof Uint8ClampedArray)) {
        console.error('Invalid pixel data type - expected Uint8Array or Uint8ClampedArray');
        return;
    }
    
    const expectedSize = width * height * 4;
    if (rgbaPixels.length !== expectedSize) {
        console.error(`Invalid pixel data size: ${rgbaPixels.length}, expected ${expectedSize}`);
        return;
    }
    
    // ... proceed with upload
}
```

#### 11. Fix Delete Copy Operations
**File:** `renderer.h` - `WebGPURenderer` class  
**Issue:** Class can be copied, leading to double-free.  
**Fix:**
```cpp
class WebGPURenderer {
public:
    WebGPURenderer();
    ~WebGPURenderer();
    
    // Disable copy
    WebGPURenderer(const WebGPURenderer&) = delete;
    WebGPURenderer& operator=(const WebGPURenderer&) = delete;
    
    // Enable move (if needed)
    WebGPURenderer(WebGPURenderer&&) = default;
    WebGPURenderer& operator=(WebGPURenderer&&) = default;
    
    // ... rest of class
};
```

#### 12. Add Exception Safety to JS Bridge
**File:** `wasm_bridge.js` - All functions with malloc/free  
**Issue:** Exceptions cause memory leaks.  
**Fix:**
```javascript
export function loadShader(id, wgslCode) {
    if (!state.initialized || !wasmModule) return false;
    
    let idPtr = 0, codePtr = 0;
    try {
        const idLen = wasmModule.lengthBytesUTF8(id) + 1;
        idPtr = wasmModule._malloc(idLen);
        if (idPtr === 0) throw new Error('OOM');
        wasmModule.stringToUTF8(id, idPtr, idLen);
        
        const codeLen = wasmModule.lengthBytesUTF8(wgslCode) + 1;
        codePtr = wasmModule._malloc(codeLen);
        if (codePtr === 0) throw new Error('OOM');
        wasmModule.stringToUTF8(wgslCode, codePtr, codeLen);
        
        return wasmModule.ccall('loadShader', 'number', ['number', 'number'], [idPtr, codePtr]) === 0;
    } finally {
        if (idPtr) wasmModule._free(idPtr);
        if (codePtr) wasmModule._free(codePtr);
    }
}
```

#### 13. Fix Global Renderer Pointer Safety
**File:** `main.cpp` - `g_renderer`  
**Issue:** Raw pointer with no thread-safety or lifetime management.  
**Fix:**
```cpp
// Use smart pointer with initialization flag
#include <memory>
#include <atomic>

std::unique_ptr<WebGPURenderer> g_renderer;
std::atomic<bool> g_rendererInitializing{false};

EMSCRIPTEN_KEEPALIVE
void initWasmRenderer(int width, int height, int agentCount) {
    if (g_renderer || g_rendererInitializing.exchange(true)) {
        printf("Renderer already initialized or initializing\n");
        return;
    }
    
    g_renderer = std::make_unique<WebGPURenderer>();
    if (!g_renderer->Initialize(width, height)) {
        g_renderer.reset();
        g_rendererInitializing = false;
        return;
    }
    // ... rest of init
    g_rendererInitializing = false;
}
```

#### 14. Fix createPipelines Error Handling
**File:** `main.cpp` - `createPipelines()`  
**Issue:** No error checking on shader module creation.  
**Fix:**
```cpp
void createPipelines() {
    if (!device) {
        printf("Cannot create pipelines - no device\n");
        return;
    }
    
    wgpu::ShaderSourceWGSL wgslDesc{};
    wgpu::ShaderModuleDescriptor shaderDesc{};
    shaderDesc.nextInChain = &wgslDesc;
    
    wgslDesc.code = COMPUTE_WGSL;
    computeShader = device.CreateShaderModule(&shaderDesc);
    if (!computeShader) {
        printf("Failed to create compute shader\n");
        return;
    }
    
    wgslDesc.code = RENDER_WGSL;
    renderShader = device.CreateShaderModule(&shaderDesc);
    if (!renderShader) {
        printf("Failed to create render shader\n");
        return;
    }
    
    printf("WASM Renderer: Pipelines created\n");
}
```

#### 15-24. Additional High Priority Items
See inline `// STABILITY:` comments in source files for:
- Add canvas element type validation (wasm_bridge.js)
- Fix updateUniforms mouseX bug (wasm_bridge.js)
- Add SetActiveShader existence check (renderer.h)
- Fix resource release order in Shutdown (renderer.cpp)
- Add null device check in CreateBindGroupLayout (renderer.cpp)
- Add bounds validation in uploadImageData (wasm_bridge.js)
- Implement UpdateDepthMap or remove declaration (renderer.h)
- Fix initWasmRenderer return value handling (main.cpp)
- Fix agent initialization failure cleanup (main.cpp)
- Add device lost check in renderLoop (main.cpp)

---

## Defensive Programming Patterns

### Pattern 1: RAII for WebGPU Resources

```cpp
template<typename T, void (*Deleter)(T)>
class WebGPUHandle {
    T handle_ = nullptr;
public:
    WebGPUHandle() = default;
    explicit WebGPUHandle(T h) : handle_(h) {}
    ~WebGPUHandle() { if (handle_) Deleter(handle_); }
    
    // Disable copy
    WebGPUHandle(const WebGPUHandle&) = delete;
    WebGPUHandle& operator=(const WebGPUHandle&) = delete;
    
    // Enable move
    WebGPUHandle(WebGPUHandle&& other) : handle_(other.handle_) {
        other.handle_ = nullptr;
    }
    WebGPUHandle& operator=(WebGPUHandle&& other) {
        if (this != &other) {
            if (handle_) Deleter(handle_);
            handle_ = other.handle_;
            other.handle_ = nullptr;
        }
        return *this;
    }
    
    T get() const { return handle_; }
    T* ptr() { return &handle_; }
    explicit operator bool() const { return handle_ != nullptr; }
    void reset() { if (handle_) { Deleter(handle_); handle_ = nullptr; } }
};

// Usage
using DeviceHandle = WebGPUHandle<WGPUDevice, wgpuDeviceRelease>;
using BufferHandle = WebGPUHandle<WGPUBuffer, wgpuBufferRelease>;
using TextureHandle = WebGPUHandle<WGPUTexture, wgpuTextureRelease>;
```

### Pattern 2: Result Type for Error Handling

```cpp
template<typename T, typename E = std::string>
class Result {
    std::variant<T, E> data_;
    bool isOk_;
    
public:
    Result(T value) : data_(std::move(value)), isOk_(true) {}
    Result(E error) : data_(std::move(error)), isOk_(false) {}
    
    bool isOk() const { return isOk_; }
    bool isErr() const { return !isOk_; }
    
    T& value() & { return std::get<T>(data_); }
    const T& value() const & { return std::get<T>(data_); }
    T&& value() && { return std::get<T>(std::move(data_)); }
    
    const E& error() const { return std::get<E>(data_); }
    
    T valueOr(T defaultValue) const {
        return isOk_ ? value() : defaultValue;
    }
};

// Usage
Result<bool> WebGPURenderer::Initialize(int w, int h) {
    if (w <= 0 || h <= 0) {
        return Result<bool>{"Invalid dimensions"};
    }
    // ... initialization
    return Result<bool>{true};
}
```

### Pattern 3: Guard Objects for Cleanup

```cpp
class ScopeGuard {
    std::function<void()> cleanup_;
    bool active_ = true;
    
public:
    explicit ScopeGuard(std::function<void()> cleanup) : cleanup_(std::move(cleanup)) {}
    ~ScopeGuard() { if (active_) cleanup_(); }
    
    void dismiss() { active_ = false; }
    ScopeGuard(const ScopeGuard&) = delete;
    ScopeGuard& operator=(const ScopeGuard&) = delete;
};

// Usage
bool WebGPURenderer::Initialize(int w, int h) {
    bool success = false;
    ScopeGuard cleanupGuard([&]() {
        if (!success) Shutdown();
    });
    
    if (!CreateDevice()) return false;
    if (!CreateResources()) return false;
    // ... more init
    
    success = true;
    return true;
}
```

### Pattern 4: Safe WASM Memory Management in JS

```javascript
class WasmMemoryScope {
    constructor(wasmModule) {
        this.wasm = wasmModule;
        this.allocations = [];
    }
    
    malloc(size) {
        const ptr = this.wasm._malloc(size);
        if (ptr === 0) {
            throw new Error(`WASM memory allocation failed for ${size} bytes`);
        }
        this.allocations.push(ptr);
        return ptr;
    }
    
    stringToUTF8(str, maxBytes) {
        const len = this.wasm.lengthBytesUTF8(str) + 1;
        if (len > maxBytes) {
            throw new Error(`String too long: ${len} > ${maxBytes}`);
        }
        const ptr = this.malloc(len);
        this.wasm.stringToUTF8(str, ptr, len);
        return ptr;
    }
    
    dispose() {
        for (const ptr of this.allocations) {
            this.wasm._free(ptr);
        }
        this.allocations = [];
    }
    
    [Symbol.dispose]() {
        this.dispose();
    }
}

// Usage with explicit resource management
export function loadShader(id, wgslCode) {
    if (!state.initialized || !wasmModule) return false;
    
    const mem = new WasmMemoryScope(wasmModule);
    try {
        const idPtr = mem.stringToUTF8(id, 256);
        const codePtr = mem.stringToUTF8(wgslCode, 1024 * 1024); // 1MB limit
        
        return wasmModule.ccall('loadShader', 'number', 
            ['number', 'number'], [idPtr, codePtr]) === 0;
    } finally {
        mem.dispose();
    }
}
```

### Pattern 5: State Machine for Lifecycle Management

```cpp
enum class RendererState {
    Uninitialized,
    Initializing,
    Ready,
    DeviceLost,
    Error,
    ShuttingDown
};

class WebGPURenderer {
    std::atomic<RendererState> state_{RendererState::Uninitialized};
    
public:
    bool Initialize(int w, int h) {
        RendererState expected = RendererState::Uninitialized;
        if (!state_.compare_exchange_strong(expected, RendererState::Initializing)) {
            printf("Initialize called in wrong state\n");
            return false;
        }
        
        // ... initialization logic
        
        state_ = RendererState::Ready;
        return true;
    }
    
    void Render() {
        if (state_.load() != RendererState::Ready) {
            return; // Or log warning
        }
        // ... render logic
    }
    
    void OnDeviceLost() {
        state_ = RendererState::DeviceLost;
        // Schedule reinitialization or notify caller
    }
};
```

---

## Testing Recommendations

### Unit Tests (C++ with Emscripten)

```cpp
// Test resource cleanup on failure
TEST(WebGPURendererTest, CleanupOnInitFailure) {
    WebGPURenderer renderer;
    // Force failure by passing invalid dimensions
    EXPECT_FALSE(renderer.Initialize(-1, 100));
    EXPECT_FALSE(renderer.IsInitialized());
    // Verify no resources leaked (check browser dev tools)
}

// Test double initialization
TEST(WebGPURendererTest, DoubleInitialize) {
    WebGPURenderer renderer;
    EXPECT_TRUE(renderer.Initialize(100, 100));
    EXPECT_TRUE(renderer.Initialize(100, 100)); // Should be idempotent
}

// Test null parameter handling
TEST(WebGPURendererTest, NullDataUpload) {
    WebGPURenderer renderer;
    renderer.Initialize(100, 100);
    // Should not crash
    renderer.LoadImage(nullptr, 10, 10);
}
```

### Integration Tests (JavaScript)

```javascript
// Test memory allocation failure handling
async function testMemoryAllocationFailure() {
    // Fill WASM memory first
    const largeBuffers = [];
    try {
        while (true) {
            largeBuffers.push(new Uint8Array(1024 * 1024));
        }
    } catch (e) {
        // OOM expected
    }
    
    // Now try to load shader - should handle gracefully
    const result = loadShader('test', 'small shader');
    console.assert(result === false, 'Should fail gracefully on OOM');
    
    // Cleanup
    largeBuffers.length = 0;
}

// Test device lost simulation
async function testDeviceLost() {
    await initWasmRenderer(canvas);
    
    // Simulate GPU process crash (browser DevTools)
    // Or use WebGPU API to force device loss in test environment
    
    // Renderer should detect loss and either:
    // 1. Auto-recover
    // 2. Enter error state
    // 3. Return meaningful error
    
    const isReady = isRendererInitialized();
    console.log('Renderer state after device lost:', isReady);
}

// Test rapid init/shutdown cycles
async function testRapidInitShutdown() {
    for (let i = 0; i < 100; i++) {
        await initWasmRenderer(canvas);
        shutdownWasmRenderer();
    }
    // Check for memory leaks in browser DevTools
}

// Test shader compilation failure
async function testInvalidShader() {
    await initWasmRenderer(canvas);
    const result = loadShader('invalid', 'invalid wgsl syntax {{}');
    console.assert(result === false, 'Should reject invalid shader');
}
```

### Fuzzing Targets

```cpp
// Fuzz parameter validation
extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    WebGPURenderer renderer;
    
    // Fuzz Initialize parameters
    if (size >= 8) {
        int w = *reinterpret_cast<const int*>(data);
        int h = *reinterpret_cast<const int*>(data + 4);
        renderer.Initialize(w, h); // Should not crash on any input
    }
    
    // Fuzz LoadImage
    if (size >= 16) {
        int w = *reinterpret_cast<const int*>(data);
        int h = *reinterpret_cast<const int*>(data + 4);
        renderer.LoadImage(data + 8, w, h); // Should not crash
    }
    
    return 0;
}
```

### Stress Tests

1. **Memory Pressure Test**
   - Load 1000 different shaders sequentially
   - Upload 4K video frames at 60fps for 10 minutes
   - Monitor WASM memory growth

2. **Device Stress Test**
   - Rapid shader switching (1000 switches/second)
   - Extreme canvas sizes (1x1 to 8192x8192)
   - Concurrent render calls from multiple callbacks

3. **Error Recovery Test**
   - Inject invalid WGSL every 10th shader load
   - Randomize all parameters in valid/invalid ranges
   - Verify renderer remains usable after errors

---

## Summary

The WASM renderer requires significant stabilization work before production deployment. The critical issues around async initialization, memory allocation, and error handling must be addressed first. Following the defensive programming patterns and testing recommendations will significantly improve reliability.

### Recommended Development Priorities

1. **Week 1:** Fix Critical issues (6 items)
2. **Week 2:** Fix High priority issues (18 items)
3. **Week 3:** Implement defensive patterns (RAII, Result types)
4. **Week 4:** Comprehensive testing (unit, integration, stress)
5. **Week 5:** Address Medium/Low priority issues and code review

---

## Appendix: Issue Count by File

| File | Critical | High | Medium | Low | Total |
|------|----------|------|--------|-----|-------|
| `renderer.cpp` | 4 | 8 | 12 | 3 | 27 |
| `renderer.h` | 0 | 3 | 6 | 4 | 13 |
| `main.cpp` | 1 | 4 | 5 | 5 | 15 |
| `wasm_bridge.js` | 1 | 3 | 2 | 4 | 10 |
| **Total** | **6** | **18** | **25** | **16** | **65** |
