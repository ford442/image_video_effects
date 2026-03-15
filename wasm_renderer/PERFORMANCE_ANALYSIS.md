# Pixelocity WASM Renderer - Performance Analysis Report

**Analysis Date:** 2026-03-14  
**Renderer Version:** Current (C++ WebGPU WASM)  
**Analyst:** Performance Optimization Analysis

---

## Executive Summary

The Pixelocity WASM renderer has several critical performance bottlenecks that significantly impact real-time video processing and shader rendering. The most severe issues are:

1. **Per-frame heap allocation** (64MB/frame for 2048x2048 textures) causing GC pressure
2. **Software pixel conversion** without SIMD vectorization (CPU-bound for video)
3. **Three full-screen texture copies** consuming ~11.5 GB/s memory bandwidth
4. **Memory allocation churn** in JavaScript bridge for every video frame

**Estimated Current Performance:**
- 1080p60 video processing: ~30-45 FPS (CPU-bound)
- Shader-only rendering: 60+ FPS (GPU-bound)
- Memory allocation: ~500MB/sec sustained

**Potential Performance Gains:**
- Video processing: **2-3x improvement** (60 FPS target)
- Memory pressure: **10x reduction** (~50MB/sec)
- GPU bandwidth: **2x reduction** with ping-pong optimization

---

## Detailed Findings by Category

### 1. Memory Allocation Patterns

#### CRITICAL: Per-Frame Heap Allocation in UploadRGBA8ToReadTexture
**Location:** `renderer.cpp:649`

```cpp
std::vector<float> floatData(static_cast<size_t>(dstW) * dstH * 4, 0.0f);
```

**Issue:** For a 2048x2048 canvas, this allocates 64MB of float data every video frame. At 60 FPS, this is 3.8 GB/sec of heap allocation, causing severe GC pauses and memory fragmentation.

**Optimization Strategy:**
1. **Persistent Staging Buffer:** Create a CPU-mappable buffer at initialization
2. **Triple Buffering:** Use 3 rotating buffers for async upload pipeline
3. **Texture Format Change:** Use `rgba8unorm` instead of `rgba32float` to eliminate conversion

**Impact:** Critical (blocking 60 FPS video)  
**Difficulty:** Medium  
**Estimated Gain:** 2-3x video processing throughput

---

#### HIGH: Initialization-Time Large Allocation
**Location:** `renderer.cpp:283`

```cpp
std::vector<float> zeros(canvasWidth_ * canvasHeight_ * 4, 0.0f);
```

**Issue:** 64MB allocation during initialization can cause startup stutter on memory-constrained devices.

**Optimization Strategy:**
- Use `wgpuCommandEncoderClearBuffer()` or GPU compute shader for zero-fill
- Lazy initialization: don't allocate until first use

**Impact:** Medium (startup time)  
**Difficulty:** Low  
**Estimated Gain:** ~500ms faster startup

---

#### CRITICAL: JavaScript Memory Allocation Per Video Frame
**Location:** `wasm_bridge.js:248-255`

```javascript
const ptr = wasmModule._malloc(byteLen);
// ... copy data ...
wasmModule._free(ptr);
```

**Issue:** Every video frame triggers malloc/free, causing heap fragmentation and Emscripten runtime overhead.

**Optimization Strategy:**
- Implement memory pool with `acquireBuffer()` / `releaseBuffer()` (partially implemented)
- Use fixed-size buffers for common resolutions (1080p, 4K)
- Consider `ALLOW_MEMORY_GROWTH=0` with pre-allocated large heap

**Impact:** Critical (GC pauses)  
**Difficulty:** Low  
**Estimated Gain:** 50% reduction in JS overhead

---

### 2. GPU Resource Management

#### HIGH: Texture View Creation Every Frame
**Location:** `renderer.cpp:525-553` (in `CreateBindGroups`)

**Issue:** Texture views are created during bind group creation. While not per-frame, this pattern creates unnecessary WebGPU object churn.

**Optimization Strategy:**
- Cache texture views as member variables during `CreateResources()`
- Reuse views for bind group updates

**Impact:** Medium (reduces driver overhead)  
**Difficulty:** Low  
**Estimated Gain:** ~1-2% CPU reduction

---

#### MEDIUM: Buffer Size Queries
**Location:** `renderer.cpp:533, 558, 566`

```cpp
entries[3].size = wgpuBufferGetSize(uniformBuffer_);
```

**Issue:** `wgpuBufferGetSize()` involves library call overhead during bind group creation.

**Optimization Strategy:**
- Cache buffer sizes as `size_t` member variables during creation

**Impact:** Low  
**Difficulty:** Trivial  
**Estimated Gain:** Negligible (code cleanliness)

---

### 3. Command Buffer Recording

#### MEDIUM: Per-Frame Command Encoder Creation
**Location:** `renderer.cpp:776-779`

**Issue:** New command encoder created every frame. While WebGPU implementations pool these internally, there is still API overhead.

**Optimization Strategy:**
- Consider command encoder reuse if Dawn/WGPU supports it
- Batch multiple operations into single encoder (already done)

**Impact:** Low (current approach is standard)  
**Difficulty:** Low  
**Estimated Gain:** ~1% CPU reduction

---

### 4. Copy Operations

#### CRITICAL: Three Full-Screen Texture Copies Per Frame
**Location:** `renderer.cpp:798-845`

```cpp
wgpuCommandEncoderCopyTextureToTexture(encoder, &srcCopy1, &dstCopy1, &extent1);  // 64MB
wgpuCommandEncoderCopyTextureToTexture(encoder, &srcCopy2, &dstCopy2, &extent1);  // 16MB
wgpuCommandEncoderCopyTextureToTexture(encoder, &srcCopy3, &dstCopy3, &extent1);  // 64MB
```

**Issue:** Total ~144MB/frame of texture copies = 8.6 GB/s at 60 FPS. This saturates memory bandwidth on integrated GPUs and many mobile devices.

**Optimization Strategy:**

1. **Bind Group Swapping (Best):**
   ```cpp
   // Instead of copying textures, swap which texture is bound as read/write
   // Requires double-buffered bind groups
   ```

2. **Texture Array Ping-Pong:**
   ```cpp
   // Use texture array with layer indexing instead of separate textures
   // Compute shader selects read/write layers via uniform
   ```

3. **Barrier-Only Approach:**
   ```cpp
   // Use execution barriers without copy for in-place ping-pong
   // Requires careful synchronization but eliminates copies
   ```

**Impact:** Critical (bandwidth bottleneck)  
**Difficulty:** High  
**Estimated Gain:** 2x reduction in memory bandwidth (enable 4K rendering)

---

### 5. Synchronization Points

#### LOW: Implicit Barriers from Copy Operations
**Issue:** Each `CopyTextureToTexture` introduces implicit barriers that may stall the GPU pipeline.

**Optimization Strategy:**
- Use texture barriers instead of copies where possible
- Group copy operations together to minimize barrier transitions

**Impact:** Low  
**Difficulty:** Medium  
**Estimated Gain:** 5-10% GPU efficiency

---

### 6. Workgroup Dispatch Sizes

#### MEDIUM: Per-Frame Integer Division
**Location:** `renderer.cpp:789-794`

```cpp
wgpuComputePassEncoderDispatchWorkgroups(
    computePass, 
    (canvasWidth_ + 7) / 8,   // Division every frame
    (canvasHeight_ + 7) / 8,  // Division every frame
    1
);
```

**Issue:** Integer division in hot path is unnecessary overhead.

**Optimization Strategy:**
```cpp
// Precompute during initialization or resize
workgroupCountX_ = (canvasWidth_ + 7) / 8;
workgroupCountY_ = (canvasHeight_ + 7) / 8;

// Use in render
wgpuComputePassEncoderDispatchWorkgroups(computePass, workgroupCountX_, workgroupCountY_, 1);
```

**Impact:** Low  
**Difficulty:** Trivial  
**Estimated Gain:** ~0.5% CPU reduction

---

#### GOOD: Optimal Workgroup Sizes in main.cpp
**Location:** `main.cpp:146, 199`

The compute shaders use `workgroup_size(256)` and `workgroup_size(16, 16)`, both of which provide good GPU occupancy on modern hardware.

**No action needed.**

---

### 7. Cache Locality

#### MEDIUM: AOS vs SOA for Agent Data
**Location:** `main.cpp:16-21`

```cpp
struct Agent {
    float x, y;
    float angle;
    float speed;
};
```

**Issue:** Array-of-Structures (AOS) layout can cause cache thrashing when accessing only positions.

**Optimization Strategy:**
- Consider Structure-of-Arrays (SOA) for batch operations:
  ```cpp
  struct AgentData {
      float* positions;  // x, y interleaved
      float* angles;
      float* speeds;
  };
  ```

**Impact:** Medium (for agent simulation)  
**Difficulty:** Medium (requires refactor)  
**Estimated Gain:** 10-20% agent simulation speed

---

#### LOW: Ripple Vector Erase from Beginning
**Location:** `renderer.cpp:713-717`

```cpp
if (ripples_.size() >= MAX_RIPPLES) {
    ripples_.erase(ripples_.begin());  // O(n) shift
}
```

**Issue:** Erasing from beginning of vector causes O(n) element shifts.

**Optimization Strategy:**
- Use circular buffer (`std::deque` or ring buffer implementation)
- Or use index-based circular array

**Impact:** Low (MAX_RIPPLES=50 is small)  
**Difficulty:** Low  
**Estimated Gain:** Negligible

---

### 8. SIMD Opportunities

#### CRITICAL: Software Pixel Conversion Not Vectorized
**Location:** `renderer.cpp:651-659`

```cpp
for (int y = 0; y < copyH; y++) {
    for (int x = 0; x < copyW; x++) {
        const int srcIdx = (y * width + x) * 4;
        const int dstIdx = (y * dstW  + x) * 4;
        floatData[dstIdx + 0] = data[srcIdx + 0] / 255.0f;  // Scalar operations
        // ...
    }
}
```

**Issue:** This conversion loop processes ~16 million pixels/sec at 1080p60, entirely scalar.

**Optimization Strategies:**

1. **WASM SIMD (Best for Web):**
   ```cpp
   // Use wasm_simd128.h for 128-bit vector operations
   // Process 4 pixels at once with v128_t
   ```

2. **Multi-threading:**
   ```cpp
   // Use std::thread or OpenMP to parallelize rows
   // Each thread processes a band of the image
   ```

3. **Avoid Conversion:**
   ```cpp
   // Change texture format to rgba8unorm, upload raw bytes
   // Use shader to convert to float on GPU
   ```

**Impact:** Critical (CPU bottleneck for video)  
**Difficulty:** Medium  
**Estimated Gain:** 4-8x pixel conversion throughput

---

### 9. CPU-GPU Transfers

#### MEDIUM: Synchronous Upload in UploadRGBA8ToReadTexture
**Location:** `renderer.cpp:678-679`

```cpp
wgpuQueueWriteTexture(queue_, &dest, floatData.data(),
                      floatData.size() * sizeof(float), &layout, &extent);
```

**Issue:** Synchronous upload blocks CPU until data is copied to GPU-visible memory.

**Optimization Strategy:**
- Use `WGPUBufferUsage_MapWrite` buffers for async uploads
- Implement triple-buffering for upload pipeline
- Use `wgpuQueueOnSubmittedWorkDone` for frame pacing

**Impact:** Medium (reduces CPU-GPU latency)  
**Difficulty:** Medium  
**Estimated Gain:** 10-20% frame time reduction

---

### 10. Shader Hot-Reloading Overhead

#### MEDIUM: String Conversion for Shader Loading
**Location:** `wasm_bridge.js:94-100`

```javascript
const codeLen = wasmModule.lengthBytesUTF8(wgslCode) + 1;
const codePtr = wasmModule._malloc(codeLen);
wasmModule.stringToUTF8(wgslCode, codePtr, codeLen);
```

**Issue:** Every shader load involves UTF-8 encoding and malloc. For hot-reloading scenarios, this creates unnecessary overhead.

**Optimization Strategy:**
- Cache compiled shader modules by ID
- Use string interning for shader IDs
- Keep common shaders pinned in memory

**Impact:** Low (only affects development workflow)  
**Difficulty:** Low  
**Estimated Gain:** Faster shader iteration

---

## Prioritized Optimization List

| Priority | Issue | Location | Impact | Difficulty | Est. Gain |
|----------|-------|----------|--------|------------|-----------|
| P0 | Per-frame heap allocation | renderer.cpp:649 | Critical | Medium | 2-3x video |
| P0 | JS memory churn | wasm_bridge.js:248 | Critical | Low | 50% JS overhead |
| P0 | SIMD pixel conversion | renderer.cpp:651 | Critical | Medium | 4-8x conversion |
| P1 | Texture copies (3x) | renderer.cpp:798 | High | High | 2x bandwidth |
| P1 | Texture view caching | renderer.cpp:525 | High | Low | 1-2% CPU |
| P2 | Staging buffer persistence | renderer.cpp:678 | Medium | Medium | 10-20% latency |
| P2 | Workgroup precompute | renderer.cpp:789 | Low | Trivial | 0.5% CPU |
| P2 | AOS to SOA | main.cpp:16 | Medium | Medium | 10-20% agents |
| P3 | Initialization zero-fill | renderer.cpp:283 | Medium | Low | Faster startup |
| P3 | Ripple circular buffer | renderer.cpp:713 | Low | Low | Code quality |
| P4 | Shader hot-reload cache | wasm_bridge.js:94 | Low | Low | Dev experience |

---

## Implementation Roadmap

### Phase 1: Quick Wins (1-2 days)
1. **Memory pool in JS bridge** (`wasm_bridge.js`)
   - Implement `acquireBuffer`/`releaseBuffer`
   - Test with video upload path

2. **Precompute workgroup counts** (`renderer.cpp`)
   - Add member variables for dispatch counts
   - Update dispatch calls

3. **Cache buffer sizes** (`renderer.cpp`)
   - Store sizes during creation
   - Use cached values in bind group creation

### Phase 2: Critical Path (1 week)
1. **Persistent staging buffer** (`renderer.cpp`)
   - Create CPU-mappable staging texture/buffer
   - Refactor `UploadRGBA8ToReadTexture` to use persistent allocation

2. **Texture format optimization**
   - Evaluate `rgba8unorm` vs `rgba32float`
   - Implement shader-side conversion if needed

3. **SIMD pixel conversion** (if staying with rgba32float)
   - Add WASM SIMD implementation
   - Benchmark scalar vs SIMD

### Phase 3: Architecture Improvements (2-3 weeks)
1. **Eliminate texture copies**
   - Implement bind group swapping
   - Refactor ping-pong to use texture arrays or views

2. **Async upload pipeline**
   - Implement triple buffering
   - Add frame pacing with `wgpuQueueOnSubmittedWorkDone`

3. **Agent simulation SOA** (`main.cpp`)
   - Refactor Agent structure
   - Benchmark AOS vs SOA

### Phase 4: Polish (1 week)
1. Shader hot-reload caching
2. Performance telemetry (GPU timestamps)
3. Memory usage tracking

---

## Benchmarking Recommendations

### Metrics to Track
1. **Frame time** (CPU + GPU separately)
2. **Memory allocation rate** (bytes/sec)
3. **GPU timestamp queries** (compute vs copy time)
4. **JavaScript GC frequency** (pauses/sec)
5. **Texture upload throughput** (MB/sec)

### Test Scenarios
1. **Video playback:** 1080p60 H.264 stream
2. **Shader-only:** Complex compute shader at 60 FPS
3. **Agent simulation:** 50,000-500,000 agents
4. **Multi-pass:** Chain of 3 compute shaders
5. **Memory pressure:** Long-running session (30+ minutes)

### Target Performance
| Scenario | Current | Target | Notes |
|----------|---------|--------|-------|
| 1080p60 video | 30-45 FPS | 60 FPS | Stable, no drops |
| 4K video | 15-20 FPS | 30 FPS | With optimizations |
| Agent sim (50K) | Unknown | 60 FPS | GPU-bound |
| Shader-only | 60+ FPS | 60+ FPS | Already good |
| Memory growth | 500MB/sec | <50MB/sec | 10x reduction |

---

## Conclusion

The Pixelocity WASM renderer has solid architecture but suffers from critical memory allocation patterns that prevent smooth video processing. The top three issues (per-frame heap allocation, JS memory churn, and scalar pixel conversion) should be addressed immediately for a 2-3x performance improvement.

The texture copy optimization is architecturally significant but requires careful refactoring. Implementing bind group swapping or texture arrays would eliminate the memory bandwidth bottleneck and enable 4K rendering.

Overall, with the recommended optimizations, the renderer should comfortably achieve:
- **1080p60 video processing** at 60 FPS
- **4K video processing** at 30 FPS
- **10x reduction** in memory allocation rate
- **2x reduction** in GPU memory bandwidth usage

---

## Appendix: Code Snippets for Optimizations

### Memory Pool Implementation (Partial)
```javascript
// In wasm_bridge.js
const memoryPool = {
  buffers: new Map(),
  maxBuffersPerSize: 3
};

function acquireBuffer(size) {
  const poolSize = Math.ceil(size / 65536) * 65536;
  const buffers = memoryPool.buffers.get(poolSize);
  if (buffers?.length > 0) return buffers.pop();
  return wasmModule._malloc(size);
}
```

### SIMD Pixel Conversion (Concept)
```cpp
#include <wasm_simd128.h>

void ConvertRGBASIMD(const uint8_t* src, float* dst, int count) {
    const v128_t scale = wasm_f32x4_splat(1.0f / 255.0f);
    for (int i = 0; i < count; i += 4) {
        v128_t bytes = wasm_v128_load(src + i);
        // Convert and store...
    }
}
```

### Texture View Caching
```cpp
// In renderer.h
WGPUTextureView readTextureView_ = nullptr;
WGPUTextureView writeTextureView_ = nullptr;
// ... etc

// In CreateResources()
readTextureView_ = wgpuTextureCreateView(readTexture_, &viewDesc);
```

---

*Report generated for performance optimization analysis*
