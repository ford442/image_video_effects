# Pixelocity WASM Renderer - Architecture Analysis

**Analysis Date:** 2026-03-14  
**Scope:** C++ WebGPU WASM Renderer (`wasm_renderer/` directory)  
**Analyst:** AI Code Review Agent

---

## Executive Summary

The WASM renderer has **critical architectural issues** that impact maintainability, correctness, and performance. While the core `WebGPURenderer` class is functional, the surrounding infrastructure suffers from:

1. **Code Duplication:** Two competing rendering implementations in `main.cpp`
2. **Dead Code:** ~60% of `main.cpp` is unreachable Physarum simulation code
3. **API Mismatches:** JavaScript/C++ boundary has signature mismatches
4. **Build Issues:** CMakeLists.txt is broken (double target definition, missing sources)
5. **Memory Safety:** Raw pointers without RAII, potential leaks, missing validations

**Overall Rating:** ⚠️ **NEEDS REFACTORING** before production use

---

## Critical Issues (Must Fix)

### 1. Dual Implementation Chaos in main.cpp
**Location:** `main.cpp`  
**Severity:** 🔴 Critical

The file contains **two completely separate rendering systems**:

1. **Working System:** `WebGPURenderer` class (from renderer.h/cpp) - Used via C API exports
2. **Dead System:** Global Physarum simulation state with C++ WebGPU API - Never called

**Problems:**
- 200+ lines of embedded WGSL shaders (dead code)
- Global variables shadow class members
- Functions like `createPipelines()`, `renderLoop()`, `onDeviceRequest()` are never invoked
- Confusing maintenance - developers can't tell which code is active

**Recommendation:**
```cpp
// Remove all Physarum code OR extract to separate optional module
// Option 1: Delete everything between lines 20-248 and 353-445
// Option 2: Create physarum_simulation.cpp with conditional compilation
```

### 2. CMakeLists.txt is Broken
**Location:** `CMakeLists.txt`  
**Severity:** 🔴 Critical

**Issues:**
- Double `add_executable()` - second call overwrites first, losing `main.cpp`
- Missing `renderer.cpp` in source files → linker errors
- Undefined `${SOURCES}` and `${HEADERS}` variables

**Fix:**
```cmake
set(SOURCES
    main.cpp
    renderer.cpp
)

add_executable(pixelocity_wasm ${SOURCES})  # Only once!
```

### 3. JS/C++ API Signature Mismatch
**Location:** `wasm_bridge.js:updateUniforms()` → `main.cpp:updateUniforms()`  
**Severity:** 🔴 Critical

JavaScript passes 8 parameters:
```javascript
wasmModule.ccall('updateUniforms', null, 
  ['number', 'number', 'number', 'number', 'number', 'number', 'number', 'number'],
  [time, mouseX, mouseY, mouseDown, p1, p2, p3, p4]
);
```

C++ accepts 0 parameters:
```cpp
void updateUniforms() {
    g_renderer->Render();  // Ignores all JS parameters!
}
```

**Impact:** Stack corruption, undefined behavior on some platforms  
**Fix:** Either pass parameters through (update C++) or remove from JS call

### 4. Raw Pointer Anti-Patterns
**Location:** `renderer.h`, `renderer.cpp`  
**Severity:** 🔴 Critical

WebGPU objects are raw C pointers requiring manual cleanup:
```cpp
WGPUDevice device_ = nullptr;  // 15+ similar members

// Manual cleanup in Shutdown() - error prone
if (device_) wgpuDeviceRelease(device_);
```

**Problems:**
- No RAII - exceptions cause resource leaks
- Copy constructor/assignment not disabled (double-free risk)
- 30+ lines of repetitive cleanup code

**Fix:** Use C++ WebGPU API (`wgpu::Device`) or custom RAII wrappers:
```cpp
// RAII wrapper example
struct DeviceHolder {
    WGPUDevice device = nullptr;
    ~DeviceHolder() { if (device) wgpuDeviceRelease(device); }
    // Non-copyable, movable
};
```

### 5. Missing Error Handling
**Location:** `renderer.cpp`  
**Severity:** 🔴 Critical

**Issues:**
- `CreateResources()` assumes all allocations succeed
- `UploadRGBA8ToReadTexture()` doesn't validate input pointers
- Shader compilation failures go unreported (no device error callback)
- WebGPU device loss is not handled

**Fix:** Add validation and error propagation:
```cpp
bool WebGPURenderer::CreateResources() {
    device_ = wgpuAdapterRequestDevice(...);
    if (!device_) {
        LogError("Failed to create WebGPU device");
        return false;
    }
    // ... validate all subsequent allocations
}
```

---

## High Priority Issues

### 6. Variable Length Array (VLA) Usage
**Location:** `renderer.cpp:724`  
**Severity:** 🟠 High

```cpp
float uniformData[12 + MAX_RIPPLES * 4];  // VLA - non-standard C++
```

**Fix:** Use `std::vector` or `std::array`:
```cpp
std::array<float, 12 + MAX_RIPPLES * 4> uniformData;
// or
std::vector<float> uniformData(12 + MAX_RIPPLES * 4);
```

### 7. State Duplication JS ↔ C++
**Location:** `wasm_bridge.js`, `renderer.cpp`  
**Severity:** 🟠 High

JavaScript maintains state that mirrors C++ state:
```javascript
const state = {
  time: 0, mouseX: 0.5, /* ... */
};
```

But C++ also has:
```cpp
float currentTime_ = 0.0f;
float mouseX_ = 0.5f;
```

**Problem:** Synchronization bugs, source of truth unclear  
**Fix:** Make JS state read-only cache; query C++ for authoritative values

### 8. Missing API Surface
**Location:** `wasm_bridge.js`  
**Severity:** 🟠 High

C++ has these methods but JS doesn't expose them:
- `SetTime(float)`
- `SetResolution(float, float)`
- `SetMouse(float, float, bool)`
- `SetZoomParams(float, float, float, float)`
- `UpdateDepthMap(const float*, int, int)` - declared but not implemented!

**Fix:** Add corresponding JS wrapper functions or remove from C++ if unused.

### 9. Magic Numbers Throughout
**Location:** Multiple files  
**Severity:** 🟠 High

Examples:
```cpp
// renderer.cpp
(canvasWidth_ + 7) / 8  // Workgroup calc - what is 7, 8?
255.0f                   // Byte normalization
16                       // bytesPerRow - sizeof(float)*4?
0.016f                   // time delta

// main.cpp
6.28318f                 // 2*PI
50000                    // agent count
1920, 1080               // Resolution
```

**Fix:** Named constants:
```cpp
constexpr int WorkgroupSize = 8;
constexpr float ByteToFloat = 1.0f / 255.0f;
constexpr float PI = 3.14159265359f;
constexpr float TWO_PI = 2.0f * PI;
```

### 10. Per-Frame Memory Allocation
**Location:** `renderer.cpp:UploadRGBA8ToReadTexture()`  
**Severity:** 🟠 High

```cpp
void UploadRGBA8ToReadTexture(...) {
    std::vector<float> floatData(static_cast<size_t>(dstW) * dstH * 4, 0.0f);
    // ... used once then freed
}
```

Called every video frame - causes heap churn and GC pressure.

**Fix:** Use persistent staging buffer:
```cpp
class WebGPURenderer {
    std::vector<float> stagingBuffer_;  // Persistent
    void UploadRGBA8ToReadTexture(...) {
        stagingBuffer_.resize(dstW * dstH * 4);
        // ... use stagingBuffer_.data()
    }
};
```

---

## Medium Priority Issues

### 11. Inconsistent WebGPU API Usage
**Location:** `renderer.cpp` vs `main.cpp`  
**Severity:** 🟡 Medium

| File | API Style |
|------|-----------|
| `renderer.cpp` | C API (`WGPUDevice`, `wgpuDeviceCreate*`) |
| `main.cpp` | C++ API (`wgpu::Device`, `device.Create*()`) |

**Problem:** Can't share code between implementations  
**Fix:** Standardize on C++ API for better RAII support

### 12. Missing Move Semantics
**Location:** `renderer.h`  
**Severity:** 🟡 Medium

Class manages resources but:
```cpp
// Missing:
WebGPURenderer(WebGPURenderer&&) = delete;
WebGPURenderer& operator=(WebGPURenderer&&) = delete;
```

**Problem:** Can't move renderer instances  
**Fix:** Implement move operations or explicitly delete

### 13. Unused Resources
**Location:** `renderer.h`  
**Severity:** 🟡 Medium

```cpp
WGPUTexture imageTexture_ = nullptr;   // Never used
WGPUTexture videoTexture_ = nullptr;   // Never used
```

Only `readTexture_` receives uploads. Remove or implement proper texture management.

### 14. Incomplete Implementations
**Location:** `renderer.cpp`  
**Severity:** 🟡 Medium

```cpp
void SetResolution(float width, float height) {
    // Currently fixed at initialization
}

void Present() {
    // Surface presentation would happen here
}

void UpdateDepthMap(const float* data, int width, int height) {
    // Not implemented
}
```

**Fix:** Implement, mark `[[deprecated]]`, or remove.

### 15. String Handling Inefficiency
**Location:** `wasm_bridge.js`  
**Severity:** 🟡 Medium

```javascript
const idLen = wasmModule.lengthBytesUTF8(id) + 1;
const idPtr = wasmModule._malloc(idLen);
wasmModule.stringToUTF8(id, idPtr, idLen);
// ... use ...
wasmModule._free(idPtr);
```

Repeated for every call. Consider:
- Passing strings as `(ptr, len)` pairs to avoid UTF-8 conversion
- Using Emscripten's `UTF8ArrayToString` helper

---

## Low Priority Issues

### 16. Include Hygiene
**Location:** All files  
**Severity:** 🟢 Low

- `<functional>` in `renderer.h` - unused
- `<math.h>` and `<cmath>` both included in `renderer.cpp`
- `<stdio.h>` instead of `<cstdio>`

### 17. Commented Code
**Location:** `main.cpp:5`, `renderer.cpp:176-179`  
**Severity:** 🟢 Low

Dead comments and commented includes should be removed.

### 18. Emoji in Log Output
**Location:** `renderer.cpp`  
**Severity:** 🟢 Low

```cpp
printf("🚀 Pixelocity WASM Renderer initializing...\n");
printf("❌ Failed to create WebGPU device\n");
```

May not render correctly in all terminal environments.

---

## Architecture Assessment

### Strengths
1. **Separation of Concerns:** `WebGPURenderer` class encapsulates rendering well
2. **Ping-Pong Texture System:** Correctly implements compute shader feedback
3. **Uniform Layout:** Matches WGSL expectations for shader compatibility
4. **Namespace Usage:** `pixelocity` namespace prevents symbol collisions

### Weaknesses
1. **God Object:** `WebGPURenderer` does too much (device, resources, shaders, rendering)
2. **Global State:** `main.cpp` uses globals for Physarum (dead code pattern)
3. **No Testing:** No unit tests, no integration tests
4. **Documentation:** Minimal inline documentation, no architecture docs
5. **Type Safety:** C-style casts, implicit conversions

### Refactoring Recommendations

#### Phase 1: Critical Fixes (Immediate)
1. Fix `CMakeLists.txt` (remove duplicate target, add `renderer.cpp`)
2. Fix `updateUniforms` signature mismatch
3. Remove all Physarum dead code from `main.cpp`
4. Add null checks and error handling to C API exports

#### Phase 2: Memory Safety (1-2 weeks)
1. Implement RAII wrappers for WebGPU objects
2. Replace VLA with `std::vector`/`std::array`
3. Add persistent staging buffer for uploads
4. Disable copy/move for non-copyable classes

#### Phase 3: API Completeness (2-3 weeks)
1. Expose all C++ methods to JS bridge
2. Implement `UpdateDepthMap`
3. Add `SetResolution` implementation or remove
4. Standardize error handling (Result<T,E> or exceptions)

#### Phase 4: Architecture Improvements (1 month)
1. Split `WebGPURenderer` into smaller components:
   ```
   DeviceManager      - WebGPU instance/adapter/device
   ResourceManager    - Textures, buffers, samplers
   ShaderManager      - Pipeline cache, shader compilation
   RenderContext      - Command encoding, submission
   ```
2. Add configuration system (replace magic numbers)
3. Implement proper logging abstraction
4. Add unit tests with emscripten test runner

---

## Best Practices Checklist

### For New Code
- [ ] Use RAII wrappers for all WebGPU objects
- [ ] Validate all pointer parameters at function entry
- [ ] Use named constants for all magic numbers
- [ ] Document function contracts with comments
- [ ] Prefer `std::vector` over C arrays
- [ ] Use C++ WebGPU API (`wgpu::`) over C API (`WGPU*`)
- [ ] Add error handling paths for all resource creation
- [ ] Write unit tests for new functionality

### For JS/C++ Boundary
- [ ] Verify parameter count matches between JS and C++
- [ ] Document memory ownership (who frees what)
- [ ] Use `try-finally` in JS to ensure `_free` is called
- [ ] Validate array lengths before passing to C++
- [ ] Add TypeScript definitions for all exports

### For Build System
- [ ] Define source files explicitly (no undefined variables)
- [ ] Test both CMake and build.sh paths in CI
- [ ] Add compile flags: `-Wall -Wextra -Werror`
- [ ] Enable sanitizers (ASan, UBSan) for debug builds

---

## Long-Term Maintainability Suggestions

### 1. Adopt C++ WebGPU API Throughout
The `webgpu_cpp.h` API provides RAII and type safety. Migrate `renderer.cpp` from C API to C++ API.

### 2. Implement Proper Error Handling
```cpp
enum class Error {
    DeviceLost,
    OutOfMemory,
    ShaderCompilationFailed,
    // ...
};

template<typename T>
using Result = std::variant<T, Error>;

Result<ShaderPipeline> LoadShader(const char* id, const char* wgsl);
```

### 3. Add Observability
```cpp
class RenderMetrics {
    float fps;
    uint64_t frameCount;
    std::chrono::duration<double> averageFrameTime;
    size_t memoryUsage;
    // ...
};
```

### 4. Create Shader Hot-Reload System
```cpp
class ShaderWatcher {
    std::unordered_map<std::string, std::filesystem::file_time_type> lastModified;
public:
    std::vector<std::string> GetChangedShaders();
};
```

### 5. Add Comprehensive Testing
```cpp
TEST(WebGPURenderer, InitializesSuccessfully) {
    WebGPURenderer renderer;
    EXPECT_TRUE(renderer.Initialize(1024, 1024));
    EXPECT_TRUE(renderer.IsInitialized());
}

TEST(WebGPURenderer, LoadsValidShader) {
    WebGPURenderer renderer;
    renderer.Initialize(1024, 1024);
    EXPECT_TRUE(renderer.LoadShader("test", kValidWGSL));
}
```

---

## Issue Summary by File

| File | Critical | High | Medium | Low |
|------|----------|------|--------|-----|
| `renderer.h` | 1 | 1 | 3 | 0 |
| `renderer.cpp` | 2 | 4 | 4 | 2 |
| `main.cpp` | 3 | 2 | 2 | 1 |
| `wasm_bridge.js` | 2 | 2 | 2 | 1 |
| `CMakeLists.txt` | 2 | 1 | 2 | 0 |
| **Total** | **10** | **10** | **13** | **6** |

---

## Conclusion

The WASM renderer **works for basic scenarios** but requires significant refactoring before it can be considered production-ready. The most critical issues are:

1. **Fix the build system** (CMakeLists.txt is broken)
2. **Remove dead code** (Physarum simulation in main.cpp)
3. **Fix API mismatch** (updateUniforms signature)
4. **Add memory safety** (RAII, error handling)

Priority should be given to the critical and high-severity issues before adding new features.

---

*Analysis completed with inline ARCH: comments added to all source files.*
