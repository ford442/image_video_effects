#include "renderer.h"
#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <stdio.h>
#include <math.h>
#include <string>
#include <cstring>
#include <algorithm>

// ═══════════════════════════════════════════════════════════════════════════════
// renderer.cpp - WebGPU Compute Shader Renderer Implementation
// ═══════════════════════════════════════════════════════════════════════════════
//
// PURPOSE:
//   This file implements the WebGPURenderer class for high-performance GPU
//   image/video processing using WebGPU compute shaders.
//
// STATUS:
//   ⚠️  INCOMPLETE - This renderer is NOT production ready
//   
//   Working features:
//     ✅ WebGPU device initialization
//     ✅ Single shader execution
//     ✅ Basic image/video upload
//     ✅ Uniform updates (time, mouse, params)
//     ✅ Ping-pong texture for feedback effects
//
//   Missing features (blocking production use):
//     ❌ Multi-slot shader pipeline (3 slots like TypeScript)
//     ❌ Audio reactivity (bass/mid/treble uniforms)
//     ❌ Depth map integration (AI depth estimation)
//     ❌ Recording/screenshot capture
//     ❌ Generative shader support (no-input shaders)
//     ❌ Efficient video upload (currently allocates per-frame)
//
// ARCHITECTURE:
//   The renderer uses a ping-pong texture approach:
//     readTexture_  -> Compute Shader -> writeTexture_
//     Then swap: writeTexture_ becomes input for next frame
//
//   For multi-slot support (TODO Phase 2), this becomes:
//     Input -> Slot 0 (read->write) -> Slot 1 (read->write) -> Slot 2 -> Output
//
// DEVELOPMENT ROADMAP:
//   See RENDERER_PLAN.md for the 8-week development plan
//
// CURRENT LIMITATIONS:
//   1. Single shader only - can't chain multiple effects
//   2. No audio input - shaders can't react to music
//   3. Video upload allocates memory every frame (slow)
//   4. No way to capture output (screenshots/recording)
//   5. Depth map stubbed but non-functional
//
// RECOMMENDATION:
//   Keep using the JS/TS renderer for production. This C++ renderer is for
//   development/testing only until Phase 2+ features are complete.
//
// ═══════════════════════════════════════════════════════════════════════════════

namespace pixelocity {

// JavaScript bridge functions
extern "C" {
    // ARCH: [High] These extern declarations duplicate interface in main.cpp.
    // Consider a single header file for JS/C++ interface contracts.
    extern void jsRequestAnimationFrame(void (*callback)(double time, void* userData), void* userData);
    extern void jsConsoleLog(const char* msg);
}

// ARCH: [Medium] MakeStringView is a helper that belongs in a utility header.
// Consider WebGPUUtils.h for API adaptation helpers.
// Helper for WGPUStringView (new API uses this instead of const char*)
static WGPUStringView MakeStringView(const char* str) {
    WGPUStringView view;
    view.data = str;
    view.length = str ? strlen(str) : 0;
    return view;
}

// Phase 2: Round `value` up to the nearest multiple of `align` (which must be a power-of-2).
static inline uint32_t AlignUp(uint32_t value, uint32_t align) {
    return (value + align - 1u) & ~(align - 1u);
}

// Phase 2: Parse @workgroup_size(x, y) from WGSL source.
// Searches for the first @compute directive and then @workgroup_size after it.
// Falls back to (16, 16) if parsing fails — matching the TypeScript renderer default.
static void ParseWorkgroupSize(const char* wgslCode, uint32_t& x, uint32_t& y) {
    x = 16; y = 16;
    if (!wgslCode) return;

    // Locate @compute
    const char* p = strstr(wgslCode, "@compute");
    if (!p) return;

    // Locate @workgroup_size after @compute
    const char* ws = strstr(p + 8, "@workgroup_size");
    if (!ws) return;

    // Skip to '('
    const char* r = ws + 15;
    while (*r == ' ' || *r == '\t' || *r == '\n' || *r == '\r') r++;
    if (*r != '(') return;
    r++;

    // Skip whitespace, parse first integer
    while (*r == ' ' || *r == '\t') r++;
    if (*r < '0' || *r > '9') return;
    uint32_t nx = 0;
    while (*r >= '0' && *r <= '9') nx = nx * 10 + static_cast<uint32_t>(*r++ - '0');

    // Skip whitespace, expect ','
    while (*r == ' ' || *r == '\t') r++;
    if (*r != ',') {
        // Only one dimension specified — treat as 1-D workgroup
        x = nx; y = 1;
        return;
    }
    r++;

    // Skip whitespace, parse second integer
    while (*r == ' ' || *r == '\t') r++;
    if (*r < '0' || *r > '9') {
        x = nx; // partial success
        return;
    }
    uint32_t ny = 0;
    while (*r >= '0' && *r <= '9') ny = ny * 10 + static_cast<uint32_t>(*r++ - '0');

    x = nx; y = ny;
}

WebGPURenderer::WebGPURenderer() = default;

WebGPURenderer::~WebGPURenderer() {
    Shutdown();
}

bool WebGPURenderer::Initialize(int canvasWidth, int canvasHeight) {
    if (initialized_) return true;
    
    canvasWidth_ = canvasWidth;
    canvasHeight_ = canvasHeight;
    
    // ARCH: [Low] Using printf for logging. Consider abstracting behind
    // a Logger interface to allow different output targets (console, file, etc.)
    printf("🚀 Pixelocity WASM Renderer initializing...\n");
    printf("   Canvas: %dx%d\n", canvasWidth_, canvasHeight_);

    if (!CreateDevice()) {
        printf("❌ Failed to create WebGPU device\n");
        return false;
    }

    if (!CreateResources()) {
        printf("❌ Failed to create resources\n");
        return false;
    }

    CreateBindGroupLayout();
    CreateRenderPipeline();
    CreateBindGroups();

    initialized_ = true;
    printf("✅ WebGPU Renderer initialized successfully\n");
    return true;
}

void WebGPURenderer::Shutdown() {
    if (!initialized_) return;

    // Clean up shaders
    for (auto& [id, pipeline] : shaders_) {
        if (pipeline.pipeline) wgpuComputePipelineRelease(pipeline.pipeline);
        if (pipeline.module) wgpuShaderModuleRelease(pipeline.module);
    }
    shaders_.clear();

    // Clean up textures
    if (imageTexture_) wgpuTextureRelease(imageTexture_);
    if (videoTexture_) wgpuTextureRelease(videoTexture_);
    if (readTexture_) wgpuTextureRelease(readTexture_);
    if (writeTexture_) wgpuTextureRelease(writeTexture_);
    if (pingPong0_) wgpuTextureRelease(pingPong0_);
    if (pingPong1_) wgpuTextureRelease(pingPong1_);
    if (depthTextureRead_) wgpuTextureRelease(depthTextureRead_);
    if (depthTextureWrite_) wgpuTextureRelease(depthTextureWrite_);
    if (dataTextureA_) wgpuTextureRelease(dataTextureA_);
    if (dataTextureB_) wgpuTextureRelease(dataTextureB_);
    if (dataTextureC_) wgpuTextureRelease(dataTextureC_);
    if (emptyTexture_) wgpuTextureRelease(emptyTexture_);

    // Clean up samplers
    if (filteringSampler_) wgpuSamplerRelease(filteringSampler_);
    if (nonFilteringSampler_) wgpuSamplerRelease(nonFilteringSampler_);
    if (comparisonSampler_) wgpuSamplerRelease(comparisonSampler_);

    // Clean up buffers
    if (uniformBuffer_) wgpuBufferRelease(uniformBuffer_);
    if (extraBuffer_) wgpuBufferRelease(extraBuffer_);
    if (plasmaBuffer_) wgpuBufferRelease(plasmaBuffer_);

    // Phase 2: release readback buffer used for frame capture.
    if (readbackBuffer_) {
        if (captureState_ == CaptureState::Pending) {
            wgpuBufferUnmap(readbackBuffer_);
        }
        wgpuBufferRelease(readbackBuffer_);
        readbackBuffer_ = nullptr;
        readbackBufferSize_ = 0;
    }
    captureState_ = CaptureState::Idle;

    // Clean up layouts and pipelines
    if (computeBindGroup_) wgpuBindGroupRelease(computeBindGroup_);
    if (renderBindGroup_) wgpuBindGroupRelease(renderBindGroup_);
    if (renderPipeline_) wgpuRenderPipelineRelease(renderPipeline_);
    if (computePipelineLayout_) wgpuPipelineLayoutRelease(computePipelineLayout_);
    if (computeBindGroupLayout_) wgpuBindGroupLayoutRelease(computeBindGroupLayout_);

    // Clean up device and surface
    if (device_) wgpuDeviceRelease(device_);
    if (surface_) wgpuSurfaceRelease(surface_);
    if (instance_) wgpuInstanceRelease(instance_);

    initialized_ = false;
    printf("🛑 WebGPU Renderer shutdown\n");
}

bool WebGPURenderer::CreateDevice() {
    // Create instance
    WGPUInstanceDescriptor instanceDesc = {};
    instanceDesc.nextInChain = nullptr;
    instance_ = wgpuCreateInstance(&instanceDesc);
    
    if (!instance_) {
        printf("❌ Failed to create WebGPU instance\n");
        return false;
    }

    // Request adapter using callback-based API
    WGPURequestAdapterOptions adapterOpts = {};
    adapterOpts.nextInChain = nullptr;
    adapterOpts.compatibleSurface = nullptr;
    
    adapter_ = nullptr;
    
    // ARCH: [Medium] Lambda captures by reference but stores pointer to adapter_.
    // This works but is fragile - callback lifetime must outlive the call.
    auto adapterCallback = [](WGPURequestAdapterStatus status, WGPUAdapter adapter, 
                               WGPUStringView message, void* userdata1, void* userdata2) {
        (void)userdata2; // Unused
        if (status == WGPURequestAdapterStatus_Success) {
            *static_cast<WGPUAdapter*>(userdata1) = adapter;
        } else {
            printf("❌ Adapter request failed\n");
        }
    };
    
    // Capture the future so we can block on it via wgpuInstanceWaitAny.
    // WGPUCallbackMode_WaitAnyOnly is required for wgpuInstanceWaitAny.
    // Build must include -sASYNCIFY so that wgpuInstanceWaitAny can yield
    // to the browser event loop while the Promise resolves.
    WGPUFuture adapterFuture = wgpuInstanceRequestAdapter(instance_, &adapterOpts,
        WGPURequestAdapterCallbackInfo{
            nullptr, WGPUCallbackMode_WaitAnyOnly, adapterCallback, &adapter_, nullptr
        });

    WGPUFutureWaitInfo adapterWait = {};
    adapterWait.future = adapterFuture;
    wgpuInstanceWaitAny(instance_, 1, &adapterWait, UINT64_MAX);

    if (!adapter_) {
        printf("❌ Failed to get WebGPU adapter\n");
        return false;
    }

    // Request device using callback-based API
    WGPUDeviceDescriptor deviceDesc = {};
    deviceDesc.nextInChain = nullptr;
    deviceDesc.label = MakeStringView("Pixelocity Device");
    deviceDesc.requiredFeatureCount = 0;
    deviceDesc.requiredLimits = nullptr;
    
    device_ = nullptr;
    
    auto deviceCallback = [](WGPURequestDeviceStatus status, WGPUDevice device,
                              WGPUStringView message, void* userdata1, void* userdata2) {
        (void)userdata2; // Unused
        if (status == WGPURequestDeviceStatus_Success) {
            *static_cast<WGPUDevice*>(userdata1) = device;
        } else {
            printf("❌ Device request failed\n");
        }
    };
    
    WGPUFuture deviceFuture = wgpuAdapterRequestDevice(adapter_, &deviceDesc,
        WGPURequestDeviceCallbackInfo{
            nullptr, WGPUCallbackMode_WaitAnyOnly, deviceCallback, &device_, nullptr
        });

    WGPUFutureWaitInfo deviceWait = {};
    deviceWait.future = deviceFuture;
    wgpuInstanceWaitAny(instance_, 1, &deviceWait, UINT64_MAX);

    if (!device_) {
        printf("❌ Failed to get WebGPU device\n");
        return false;
    }

    queue_ = wgpuDeviceGetQueue(device_);
    
    // ARCH: [High] Error handling is TODO but never implemented.
    // Device errors (shader compilation failures, etc.) will go unreported.
    // This makes debugging shaders extremely difficult.
    // TODO: Implement proper error handling for emdawnwebgpu

    return true;
}

bool WebGPURenderer::CreateResources() {
    // Create samplers
    WGPUSamplerDescriptor samplerDesc = {};
    samplerDesc.nextInChain = nullptr;
    samplerDesc.label = MakeStringView("Filtering Sampler");
    samplerDesc.magFilter = WGPUFilterMode_Linear;
    samplerDesc.minFilter = WGPUFilterMode_Linear;
    samplerDesc.mipmapFilter = WGPUMipmapFilterMode_Linear;
    samplerDesc.addressModeU = WGPUAddressMode_Repeat;
    samplerDesc.addressModeV = WGPUAddressMode_Repeat;
    samplerDesc.addressModeW = WGPUAddressMode_Repeat;
    filteringSampler_ = wgpuDeviceCreateSampler(device_, &samplerDesc);

    samplerDesc.label = MakeStringView("Non-filtering Sampler");
    samplerDesc.magFilter = WGPUFilterMode_Nearest;
    samplerDesc.minFilter = WGPUFilterMode_Nearest;
    samplerDesc.mipmapFilter = WGPUMipmapFilterMode_Nearest;
    nonFilteringSampler_ = wgpuDeviceCreateSampler(device_, &samplerDesc);

    samplerDesc.label = MakeStringView("Comparison Sampler");
    samplerDesc.compare = WGPUCompareFunction_Less;
    comparisonSampler_ = wgpuDeviceCreateSampler(device_, &samplerDesc);

    // Create uniform buffer (size: 12 floats base + 50*4 floats for ripples)
    // ARCH: [Medium] Magic number 12 should be named constant.
    // Also, size calculation should use sizeof(Uniforms) for consistency.
    constexpr size_t uniformSize = sizeof(float) * (12 + MAX_RIPPLES * 4);
    WGPUBufferDescriptor bufferDesc = {};
    bufferDesc.nextInChain = nullptr;
    bufferDesc.label = MakeStringView("Uniform Buffer");
    bufferDesc.size = uniformSize;
    bufferDesc.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst;
    bufferDesc.mappedAtCreation = false;
    uniformBuffer_ = wgpuDeviceCreateBuffer(device_, &bufferDesc);

    // Create extra buffer (256 floats)
    // ARCH: [Medium] Magic number 256 - document what this buffer is for
    // or use named constant.
    bufferDesc.label = MakeStringView("Extra Buffer");
    bufferDesc.size = 256 * sizeof(float);
    bufferDesc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    extraBuffer_ = wgpuDeviceCreateBuffer(device_, &bufferDesc);

    // Create plasma buffer
    // ARCH: [Medium] Magic number 48 = sizeof(vec4<f32>) * 3? Document this.
    bufferDesc.label = MakeStringView("Plasma Buffer");
    bufferDesc.size = MAX_PLASMA_BALLS * 48;
    bufferDesc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    plasmaBuffer_ = wgpuDeviceCreateBuffer(device_, &bufferDesc);

    // Create textures
    WGPUTextureDescriptor texDesc = {};
    texDesc.nextInChain = nullptr;
    texDesc.dimension = WGPUTextureDimension_2D;
    texDesc.size = {static_cast<uint32_t>(canvasWidth_), static_cast<uint32_t>(canvasHeight_), 1};
    texDesc.mipLevelCount = 1;
    texDesc.sampleCount = 1;

    // Ping-pong textures (rgba32float)
    texDesc.format = WGPUTextureFormat_RGBA32Float;
    texDesc.usage = WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding | WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc;
    texDesc.label = MakeStringView("Read Texture");
    readTexture_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Write Texture");
    writeTexture_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Ping-Pong 0");
    pingPong0_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Ping-Pong 1");
    pingPong1_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Data Texture A");
    dataTextureA_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Data Texture B");
    dataTextureB_ = wgpuDeviceCreateTexture(device_, &texDesc);
    
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Data Texture C");
    dataTextureC_ = wgpuDeviceCreateTexture(device_, &texDesc);

    // Depth textures (r32float)
    texDesc.format = WGPUTextureFormat_R32Float;
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Depth Texture Read");
    depthTextureRead_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Depth Texture Write");
    depthTextureWrite_ = wgpuDeviceCreateTexture(device_, &texDesc);

    // Empty texture (1x1)
    texDesc.size = {1, 1, 1};
    texDesc.label = MakeStringView("Empty Texture");
    emptyTexture_ = wgpuDeviceCreateTexture(device_, &texDesc);

    // Initialize empty texture to black
    float black[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    
    WGPUTexelCopyTextureInfo emptyDest = {};
    emptyDest.texture = emptyTexture_;
    emptyDest.mipLevel = 0;
    emptyDest.origin = {0, 0, 0};
    emptyDest.aspect = WGPUTextureAspect_All;
    
    WGPUTexelCopyBufferLayout emptyDataLayout = {};
    emptyDataLayout.offset = 0;
    emptyDataLayout.bytesPerRow = 16;
    emptyDataLayout.rowsPerImage = 1;
    
    wgpuQueueWriteTexture(queue_, &emptyDest, black, sizeof(black), &emptyDataLayout, &texDesc.size);

    // Initialize data texture C to zeros
    std::vector<float> zeros(canvasWidth_ * canvasHeight_ * 4, 0.0f);
    
    WGPUTexelCopyTextureInfo dataDest = {};
    dataDest.texture = dataTextureC_;
    dataDest.mipLevel = 0;
    dataDest.origin = {0, 0, 0};
    dataDest.aspect = WGPUTextureAspect_All;
    
    WGPUTexelCopyBufferLayout dataLayout = {};
    dataLayout.offset = 0;
    dataLayout.bytesPerRow = static_cast<uint32_t>(canvasWidth_ * 16);
    dataLayout.rowsPerImage = static_cast<uint32_t>(canvasHeight_);
    
    WGPUExtent3D dataExtent = {};
    dataExtent.width = static_cast<uint32_t>(canvasWidth_);
    dataExtent.height = static_cast<uint32_t>(canvasHeight_);
    dataExtent.depthOrArrayLayers = 1;
    
    wgpuQueueWriteTexture(queue_, &dataDest, zeros.data(), zeros.size() * sizeof(float), &dataLayout, &dataExtent);

    // Initialize readTexture_ to zeros so generative shaders receive a black
    // placeholder rather than uninitialised GPU memory.
    dataDest.texture = readTexture_;
    wgpuQueueWriteTexture(queue_, &dataDest, zeros.data(), zeros.size() * sizeof(float), &dataLayout, &dataExtent);

    return true;
}

void WebGPURenderer::CreateBindGroupLayout() {
    // Create the universal bind group layout for compute shaders
    // ARCH: [Medium] Magic number 13 should be named constant (BindingCount).
    WGPUBindGroupLayoutEntry entries[13] = {};
    
    // Binding 0: Filtering sampler
    entries[0].binding = 0;
    entries[0].visibility = WGPUShaderStage_Compute;
    entries[0].sampler.type = WGPUSamplerBindingType_Filtering;
    
    // Binding 1: Read texture
    entries[1].binding = 1;
    entries[1].visibility = WGPUShaderStage_Compute;
    entries[1].texture.sampleType = WGPUTextureSampleType_Float;
    entries[1].texture.viewDimension = WGPUTextureViewDimension_2D;
    
    // Binding 2: Write texture (storage)
    entries[2].binding = 2;
    entries[2].visibility = WGPUShaderStage_Compute;
    entries[2].storageTexture.access = WGPUStorageTextureAccess_WriteOnly;
    entries[2].storageTexture.format = WGPUTextureFormat_RGBA32Float;
    entries[2].storageTexture.viewDimension = WGPUTextureViewDimension_2D;
    
    // Binding 3: Uniform buffer
    entries[3].binding = 3;
    entries[3].visibility = WGPUShaderStage_Compute;
    entries[3].buffer.type = WGPUBufferBindingType_Uniform;
    
    // Binding 4: Depth texture (read)
    entries[4].binding = 4;
    entries[4].visibility = WGPUShaderStage_Compute;
    entries[4].texture.sampleType = WGPUTextureSampleType_Float;
    entries[4].texture.viewDimension = WGPUTextureViewDimension_2D;
    
    // Binding 5: Non-filtering sampler
    entries[5].binding = 5;
    entries[5].visibility = WGPUShaderStage_Compute;
    entries[5].sampler.type = WGPUSamplerBindingType_NonFiltering;
    
    // Binding 6: Depth texture (write)
    entries[6].binding = 6;
    entries[6].visibility = WGPUShaderStage_Compute;
    entries[6].storageTexture.access = WGPUStorageTextureAccess_WriteOnly;
    entries[6].storageTexture.format = WGPUTextureFormat_R32Float;
    entries[6].storageTexture.viewDimension = WGPUTextureViewDimension_2D;
    
    // Binding 7: Data texture A (write)
    entries[7].binding = 7;
    entries[7].visibility = WGPUShaderStage_Compute;
    entries[7].storageTexture.access = WGPUStorageTextureAccess_WriteOnly;
    entries[7].storageTexture.format = WGPUTextureFormat_RGBA32Float;
    entries[7].storageTexture.viewDimension = WGPUTextureViewDimension_2D;
    
    // Binding 8: Data texture B (write)
    entries[8].binding = 8;
    entries[8].visibility = WGPUShaderStage_Compute;
    entries[8].storageTexture.access = WGPUStorageTextureAccess_WriteOnly;
    entries[8].storageTexture.format = WGPUTextureFormat_RGBA32Float;
    entries[8].storageTexture.viewDimension = WGPUTextureViewDimension_2D;
    
    // Binding 9: Data texture C (read)
    entries[9].binding = 9;
    entries[9].visibility = WGPUShaderStage_Compute;
    entries[9].texture.sampleType = WGPUTextureSampleType_Float;
    entries[9].texture.viewDimension = WGPUTextureViewDimension_2D;
    
    // Binding 10: Extra buffer (storage)
    entries[10].binding = 10;
    entries[10].visibility = WGPUShaderStage_Compute;
    entries[10].buffer.type = WGPUBufferBindingType_Storage;
    
    // Binding 11: Comparison sampler
    entries[11].binding = 11;
    entries[11].visibility = WGPUShaderStage_Compute;
    entries[11].sampler.type = WGPUSamplerBindingType_Comparison;
    
    // Binding 12: Plasma buffer (read-only storage)
    entries[12].binding = 12;
    entries[12].visibility = WGPUShaderStage_Compute;
    entries[12].buffer.type = WGPUBufferBindingType_ReadOnlyStorage;

    WGPUBindGroupLayoutDescriptor layoutDesc = {};
    layoutDesc.nextInChain = nullptr;
    layoutDesc.label = MakeStringView("Compute Bind Group Layout");
    layoutDesc.entryCount = 13;
    layoutDesc.entries = entries;
    
    computeBindGroupLayout_ = wgpuDeviceCreateBindGroupLayout(device_, &layoutDesc);

    // Create pipeline layout
    WGPUPipelineLayoutDescriptor pipelineLayoutDesc = {};
    pipelineLayoutDesc.nextInChain = nullptr;
    pipelineLayoutDesc.label = MakeStringView("Compute Pipeline Layout");
    pipelineLayoutDesc.bindGroupLayoutCount = 1;
    pipelineLayoutDesc.bindGroupLayouts = &computeBindGroupLayout_;
    
    computePipelineLayout_ = wgpuDeviceCreatePipelineLayout(device_, &pipelineLayoutDesc);
}

void WebGPURenderer::CreateRenderPipeline() {
    // Simple vertex shader for full-screen quad
    const char* vertexShaderCode = R"(
        @vertex
        fn vs_main(@builtin(vertex_index) vertexIndex: u32) -> @builtin(position) vec4<f32> {
            var pos = array<vec2<f32>, 4>(
                vec2<f32>(-1.0, -1.0),
                vec2<f32>( 1.0, -1.0),
                vec2<f32>(-1.0,  1.0),
                vec2<f32>( 1.0,  1.0)
            );
            return vec4<f32>(pos[vertexIndex], 0.0, 1.0);
        }
    )";

    // Fragment shader to sample the write texture
    const char* fragmentShaderCode = R"(
        @group(0) @binding(0) var u_sampler: sampler;
        @group(0) @binding(1) var u_texture: texture_2d<f32>;
        
        @fragment
        fn fs_main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
            let uv = fragCoord.xy / vec2<f32>(textureDimensions(u_texture));
            return textureSample(u_texture, u_sampler, uv);
        }
    )";

    // Create shader modules using WGPUShaderSourceWGSL chained struct
    WGPUShaderSourceWGSL wgslSource = {};
    wgslSource.chain.next = nullptr;
    wgslSource.chain.sType = WGPUSType_ShaderSourceWGSL;
    
    WGPUShaderModuleDescriptor shaderDesc = {};
    // ARCH: [Low] C-style cast to WGPUChainedStruct* - technically safe but
    // consider using C++ style static_cast for consistency.
    shaderDesc.nextInChain = reinterpret_cast<WGPUChainedStruct*>(&wgslSource);
    
    wgslSource.code = MakeStringView(vertexShaderCode);
    shaderDesc.label = MakeStringView("Vertex Shader");
    WGPUShaderModule vertexModule = wgpuDeviceCreateShaderModule(device_, &shaderDesc);
    
    wgslSource.code = MakeStringView(fragmentShaderCode);
    shaderDesc.label = MakeStringView("Fragment Shader");
    WGPUShaderModule fragmentModule = wgpuDeviceCreateShaderModule(device_, &shaderDesc);

    // Create render pipeline
    WGPUBlendState blend = {};
    blend.color.operation = WGPUBlendOperation_Add;
    blend.color.srcFactor = WGPUBlendFactor_One;
    blend.color.dstFactor = WGPUBlendFactor_Zero;
    blend.alpha.operation = WGPUBlendOperation_Add;
    blend.alpha.srcFactor = WGPUBlendFactor_One;
    blend.alpha.dstFactor = WGPUBlendFactor_Zero;

    WGPUColorTargetState colorTarget = {};
    colorTarget.nextInChain = nullptr;
    // ARCH: [High] Hardcoded BGRA8Unorm assumes canvas format.
    // Should query actual surface format for portability.
    colorTarget.format = WGPUTextureFormat_BGRA8Unorm;
    colorTarget.blend = &blend;
    colorTarget.writeMask = WGPUColorWriteMask_All;

    WGPUFragmentState fragmentState = {};
    fragmentState.nextInChain = nullptr;
    fragmentState.module = fragmentModule;
    fragmentState.entryPoint = MakeStringView("fs_main");
    fragmentState.targetCount = 1;
    fragmentState.targets = &colorTarget;

    WGPUPrimitiveState primitiveState = {};
    primitiveState.nextInChain = nullptr;
    primitiveState.topology = WGPUPrimitiveTopology_TriangleStrip;
    primitiveState.stripIndexFormat = WGPUIndexFormat_Undefined;
    primitiveState.frontFace = WGPUFrontFace_CCW;
    primitiveState.cullMode = WGPUCullMode_None;

    WGPUMultisampleState multisampleState = {};
    multisampleState.nextInChain = nullptr;
    multisampleState.count = 1;
    multisampleState.mask = 0xFFFFFFFF;

    WGPUVertexState vertexState = {};
    vertexState.nextInChain = nullptr;
    vertexState.module = vertexModule;
    vertexState.entryPoint = MakeStringView("vs_main");
    vertexState.bufferCount = 0;
    vertexState.buffers = nullptr;

    WGPURenderPipelineDescriptor pipelineDesc = {};
    pipelineDesc.nextInChain = nullptr;
    pipelineDesc.label = MakeStringView("Render Pipeline");
    // ARCH: [Medium] Using auto layout (nullptr) instead of explicit layout.
    // This works but is less efficient as layout is inferred at runtime.
    pipelineDesc.layout = nullptr;
    pipelineDesc.vertex = vertexState;
    pipelineDesc.primitive = primitiveState;
    pipelineDesc.depthStencil = nullptr;
    pipelineDesc.multisample = multisampleState;
    pipelineDesc.fragment = &fragmentState;

    renderPipeline_ = wgpuDeviceCreateRenderPipeline(device_, &pipelineDesc);

    wgpuShaderModuleRelease(vertexModule);
    wgpuShaderModuleRelease(fragmentModule);
}

void WebGPURenderer::CreateBindGroups() {
    // Create compute bind group
    if (!writeTexture_ || !uniformBuffer_) return;

    WGPUTextureViewDescriptor viewDesc = {};
    viewDesc.nextInChain = nullptr;
    viewDesc.label = MakeStringView(nullptr);
    viewDesc.format = WGPUTextureFormat_RGBA32Float;
    viewDesc.dimension = WGPUTextureViewDimension_2D;
    viewDesc.baseMipLevel = 0;
    viewDesc.mipLevelCount = 1;
    viewDesc.baseArrayLayer = 0;
    viewDesc.arrayLayerCount = 1;
    viewDesc.aspect = WGPUTextureAspect_All;

    // ARCH: [Medium] Array size 13 is hardcoded.
    // Should use constexpr or std::array for type safety.
    WGPUBindGroupEntry entries[13] = {};
    
    entries[0].binding = 0;
    entries[0].sampler = filteringSampler_;
    
    entries[1].binding = 1;
    entries[1].textureView = wgpuTextureCreateView(readTexture_, &viewDesc);
    
    entries[2].binding = 2;
    entries[2].textureView = wgpuTextureCreateView(writeTexture_, &viewDesc);
    
    entries[3].binding = 3;
    entries[3].buffer = uniformBuffer_;
    entries[3].offset = 0;
    entries[3].size = wgpuBufferGetSize(uniformBuffer_);
    
    entries[4].binding = 4;
    viewDesc.format = WGPUTextureFormat_R32Float;
    entries[4].textureView = wgpuTextureCreateView(depthTextureRead_, &viewDesc);
    
    entries[5].binding = 5;
    entries[5].sampler = nonFilteringSampler_;
    
    entries[6].binding = 6;
    entries[6].textureView = wgpuTextureCreateView(depthTextureWrite_, &viewDesc);
    
    entries[7].binding = 7;
    viewDesc.format = WGPUTextureFormat_RGBA32Float;
    entries[7].textureView = wgpuTextureCreateView(dataTextureA_, &viewDesc);
    
    entries[8].binding = 8;
    entries[8].textureView = wgpuTextureCreateView(dataTextureB_, &viewDesc);
    
    entries[9].binding = 9;
    entries[9].textureView = wgpuTextureCreateView(dataTextureC_, &viewDesc);
    
    entries[10].binding = 10;
    entries[10].buffer = extraBuffer_;
    entries[10].offset = 0;
    entries[10].size = wgpuBufferGetSize(extraBuffer_);
    
    entries[11].binding = 11;
    entries[11].sampler = comparisonSampler_;
    
    entries[12].binding = 12;
    entries[12].buffer = plasmaBuffer_;
    entries[12].offset = 0;
    entries[12].size = wgpuBufferGetSize(plasmaBuffer_);

    WGPUBindGroupDescriptor bindGroupDesc = {};
    bindGroupDesc.nextInChain = nullptr;
    bindGroupDesc.label = MakeStringView("Compute Bind Group");
    bindGroupDesc.layout = computeBindGroupLayout_;
    bindGroupDesc.entryCount = 13;
    bindGroupDesc.entries = entries;
    
    computeBindGroup_ = wgpuDeviceCreateBindGroup(device_, &bindGroupDesc);

    // Release texture views (bind group keeps references)
    for (int i = 0; i < 13; i++) {
        if (entries[i].textureView) {
            wgpuTextureViewRelease(entries[i].textureView);
        }
    }
}

bool WebGPURenderer::LoadShader(const char* id, const char* wgslCode) {
    if (!device_) return false;
    
    // Check if already loaded
    if (shaders_.find(id) != shaders_.end()) {
        return true;
    }

    // Create shader module
    WGPUShaderSourceWGSL wgslSource = {};
    wgslSource.chain.next = nullptr;
    wgslSource.chain.sType = WGPUSType_ShaderSourceWGSL;
    wgslSource.code = MakeStringView(wgslCode);

    WGPUShaderModuleDescriptor shaderDesc = {};
    shaderDesc.nextInChain = reinterpret_cast<WGPUChainedStruct*>(&wgslSource);
    shaderDesc.label = MakeStringView(id);

    // ARCH: [High] No shader validation before creating module.
    // Compilation errors will only be caught via device error callback
    // which is not currently set up.
    WGPUShaderModule module = wgpuDeviceCreateShaderModule(device_, &shaderDesc);
    if (!module) {
        printf("❌ Failed to create shader module for '%s'\n", id);
        return false;
    }

    // Create compute pipeline
    WGPUComputePipelineDescriptor pipelineDesc = {};
    pipelineDesc.nextInChain = nullptr;
    pipelineDesc.label = MakeStringView(id);
    pipelineDesc.layout = computePipelineLayout_;
    pipelineDesc.compute.module = module;
    pipelineDesc.compute.entryPoint = MakeStringView("main");

    // ARCH: [Critical] Pipeline creation can fail if WGSL doesn't match
    // the bind group layout. No error handling here.
    WGPUComputePipeline pipeline = wgpuDeviceCreateComputePipeline(device_, &pipelineDesc);
    if (!pipeline) {
        printf("❌ Failed to create compute pipeline for '%s'\n", id);
        wgpuShaderModuleRelease(module);
        return false;
    }

    // ARCH: [Low] ShaderPipeline could use constructor instead of field-by-field assignment.
    ShaderPipeline sp;
    sp.module = module;
    sp.pipeline = pipeline;
    sp.id = id;
    sp.name = id;
    // Phase 2: parse and store workgroup dimensions so Render() can dispatch correctly.
    ParseWorkgroupSize(wgslCode, sp.workgroupX, sp.workgroupY);
    shaders_[id] = sp;

    printf("✅ Loaded shader: %s (workgroup: %ux%u)\n", id, sp.workgroupX, sp.workgroupY);
    return true;
}

void WebGPURenderer::SetActiveShader(const char* id) {
    activeShaderId_ = id;
    // Also configure slot 0 for backwards compatibility with callers that
    // still use the single-shader API.
    if (id && *id) {
        slots_[0].shaderId = id;
        slots_[0].enabled  = true;
    }
}

// ─── Multi-slot shader API ────────────────────────────────────────────────────

void WebGPURenderer::SetSlotShader(int slotIndex, const char* id) {
    if (slotIndex < 0 || slotIndex >= MAX_SHADER_SLOTS) return;
    if (id && *id) {
        slots_[slotIndex].shaderId = id;
        slots_[slotIndex].enabled  = true;
    } else {
        slots_[slotIndex].shaderId.clear();
        slots_[slotIndex].enabled = false;
    }
}

void WebGPURenderer::SetSlotParams(int slotIndex, float p1, float p2, float p3, float p4) {
    if (slotIndex < 0 || slotIndex >= MAX_SHADER_SLOTS) return;
    slots_[slotIndex].params[0] = p1;
    slots_[slotIndex].params[1] = p2;
    slots_[slotIndex].params[2] = p3;
    slots_[slotIndex].params[3] = p4;
}

void WebGPURenderer::SetSlotMode(int slotIndex, int mode) {
    if (slotIndex < 0 || slotIndex >= MAX_SHADER_SLOTS) return;
    slots_[slotIndex].mode = (mode == 1) ? SlotMode::Parallel : SlotMode::Chained;
}

void WebGPURenderer::SetInputSource(InputSource source) {
    inputSource_ = source;
}

// ─── CreateComputeBindGroup ───────────────────────────────────────────────────

WGPUBindGroup WebGPURenderer::CreateComputeBindGroup(WGPUTexture readTex, WGPUTexture writeTex) {
    WGPUTextureViewDescriptor rgbaView = {};
    rgbaView.format          = WGPUTextureFormat_RGBA32Float;
    rgbaView.dimension       = WGPUTextureViewDimension_2D;
    rgbaView.baseMipLevel    = 0;
    rgbaView.mipLevelCount   = 1;
    rgbaView.baseArrayLayer  = 0;
    rgbaView.arrayLayerCount = 1;
    rgbaView.aspect          = WGPUTextureAspect_All;

    WGPUTextureViewDescriptor r32View = rgbaView;
    r32View.format = WGPUTextureFormat_R32Float;

    WGPUBindGroupEntry entries[13] = {};

    entries[0].binding = 0;
    entries[0].sampler = filteringSampler_;

    entries[1].binding     = 1;
    entries[1].textureView = wgpuTextureCreateView(readTex, &rgbaView);

    entries[2].binding     = 2;
    entries[2].textureView = wgpuTextureCreateView(writeTex, &rgbaView);

    entries[3].binding = 3;
    entries[3].buffer  = uniformBuffer_;
    entries[3].offset  = 0;
    entries[3].size    = wgpuBufferGetSize(uniformBuffer_);

    entries[4].binding     = 4;
    entries[4].textureView = wgpuTextureCreateView(depthTextureRead_, &r32View);

    entries[5].binding = 5;
    entries[5].sampler = nonFilteringSampler_;

    entries[6].binding     = 6;
    entries[6].textureView = wgpuTextureCreateView(depthTextureWrite_, &r32View);

    entries[7].binding     = 7;
    entries[7].textureView = wgpuTextureCreateView(dataTextureA_, &rgbaView);

    entries[8].binding     = 8;
    entries[8].textureView = wgpuTextureCreateView(dataTextureB_, &rgbaView);

    entries[9].binding     = 9;
    entries[9].textureView = wgpuTextureCreateView(dataTextureC_, &rgbaView);

    entries[10].binding = 10;
    entries[10].buffer  = extraBuffer_;
    entries[10].offset  = 0;
    entries[10].size    = wgpuBufferGetSize(extraBuffer_);

    entries[11].binding = 11;
    entries[11].sampler = comparisonSampler_;

    entries[12].binding = 12;
    entries[12].buffer  = plasmaBuffer_;
    entries[12].offset  = 0;
    entries[12].size    = wgpuBufferGetSize(plasmaBuffer_);

    WGPUBindGroupDescriptor bgDesc = {};
    bgDesc.label      = MakeStringView("Compute Bind Group");
    bgDesc.layout     = computeBindGroupLayout_;
    bgDesc.entryCount = 13;
    bgDesc.entries    = entries;

    WGPUBindGroup bg = wgpuDeviceCreateBindGroup(device_, &bgDesc);

    // Release texture views — the bind group holds its own references.
    for (int i = 0; i < 13; i++) {
        if (entries[i].textureView) wgpuTextureViewRelease(entries[i].textureView);
    }
    return bg;
}

// Overwrite only the zoom_params portion (bytes 32-47) of the uniform buffer.
void WebGPURenderer::WriteSlotParams(const float* params) {
    if (!uniformBuffer_) return;
    wgpuQueueWriteBuffer(queue_, uniformBuffer_, 32, params, 4 * sizeof(float));
}

// Dispatch a compute pass over the full canvas using the given workgroup dimensions.
void WebGPURenderer::DispatchComputePass(WGPUCommandEncoder encoder,
                                          WGPUComputePipeline pipeline,
                                          WGPUBindGroup bindGroup,
                                          uint32_t workgroupX,
                                          uint32_t workgroupY) {
    WGPUComputePassDescriptor cpDesc = {};
    cpDesc.label = MakeStringView("Compute Pass");
    WGPUComputePassEncoder cp = wgpuCommandEncoderBeginComputePass(encoder, &cpDesc);
    wgpuComputePassEncoderSetPipeline(cp, pipeline);
    wgpuComputePassEncoderSetBindGroup(cp, 0, bindGroup, 0, nullptr);
    // Phase 2: use the shader's actual workgroup size instead of hardcoded 16.
    wgpuComputePassEncoderDispatchWorkgroups(
        cp,
        (static_cast<uint32_t>(canvasWidth_)  + workgroupX - 1u) / workgroupX,
        (static_cast<uint32_t>(canvasHeight_) + workgroupY - 1u) / workgroupY,
        1);
    wgpuComputePassEncoderEnd(cp);
    wgpuComputePassEncoderRelease(cp);
}

void WebGPURenderer::UploadRGBA8ToReadTexture(const uint8_t* data, int width, int height) {
    if (!queue_ || !readTexture_) return;

    // Convert uint8 RGBA to float RGBA, fitting within canvas bounds.
    // Pixels outside the source image remain black.
    const int dstW = canvasWidth_;
    const int dstH = canvasHeight_;
    const int copyW = (width  < dstW) ? width  : dstW;
    const int copyH = (height < dstH) ? height : dstH;

    // Phase 2: reuse persistent staging buffer to eliminate per-frame heap allocation.
    const size_t needed = static_cast<size_t>(dstW) * dstH * 4;
    if (videoStagingBuffer_.size() < needed) {
        videoStagingBuffer_.assign(needed, 0.0f);
    }

    // Zero only the pixels that will NOT be written by the copy loops below
    // (right/bottom borders when source is smaller than the destination).
    // This avoids zeroing the entire buffer on every frame.
    if (copyW < dstW || copyH < dstH) {
        // Zero the right border columns (all rows).
        for (int y = 0; y < copyH; y++) {
            const int rowBase = y * dstW * 4;
            for (int x = copyW; x < dstW; x++) {
                videoStagingBuffer_[rowBase + x * 4 + 0] = 0.0f;
                videoStagingBuffer_[rowBase + x * 4 + 1] = 0.0f;
                videoStagingBuffer_[rowBase + x * 4 + 2] = 0.0f;
                videoStagingBuffer_[rowBase + x * 4 + 3] = 0.0f;
            }
        }
        // Zero the bottom border rows entirely.
        for (int y = copyH; y < dstH; y++) {
            const size_t rowStart = static_cast<size_t>(y) * dstW * 4;
            std::fill(videoStagingBuffer_.begin() + static_cast<std::ptrdiff_t>(rowStart),
                      videoStagingBuffer_.begin() + static_cast<std::ptrdiff_t>(rowStart + static_cast<size_t>(dstW) * 4),
                      0.0f);
        }
    }

    for (int y = 0; y < copyH; y++) {
        for (int x = 0; x < copyW; x++) {
            const int srcIdx = (y * width + x) * 4;
            const int dstIdx = (y * dstW  + x) * 4;
            videoStagingBuffer_[dstIdx + 0] = data[srcIdx + 0] / 255.0f;
            videoStagingBuffer_[dstIdx + 1] = data[srcIdx + 1] / 255.0f;
            videoStagingBuffer_[dstIdx + 2] = data[srcIdx + 2] / 255.0f;
            videoStagingBuffer_[dstIdx + 3] = data[srcIdx + 3] / 255.0f;
        }
    }

    WGPUTexelCopyTextureInfo dest = {};
    dest.texture = readTexture_;
    dest.mipLevel = 0;
    dest.origin = {0, 0, 0};
    dest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout layout = {};
    layout.offset = 0;
    layout.bytesPerRow = static_cast<uint32_t>(dstW) * 16;  // 4 floats × 4 bytes
    layout.rowsPerImage = static_cast<uint32_t>(dstH);

    WGPUExtent3D extent = {};
    extent.width  = static_cast<uint32_t>(dstW);
    extent.height = static_cast<uint32_t>(dstH);
    extent.depthOrArrayLayers = 1;

    wgpuQueueWriteTexture(queue_, &dest, videoStagingBuffer_.data(),
                          needed * sizeof(float), &layout, &extent);
}

void WebGPURenderer::LoadImage(const uint8_t* data, int width, int height) {
    printf("📷 Loading image: %dx%d\n", width, height);
    UploadRGBA8ToReadTexture(data, width, height);
}

void WebGPURenderer::UpdateVideoFrame(const uint8_t* data, int width, int height) {
    UploadRGBA8ToReadTexture(data, width, height);
}

void WebGPURenderer::UpdateDepthMap(const float* data, int width, int height) {
    if (!queue_ || !depthTextureRead_ || !data) return;

    // Clamp copy dimensions to the texture size.
    const int dstW = canvasWidth_;
    const int dstH = canvasHeight_;
    const int copyW = (width  < dstW) ? width  : dstW;
    const int copyH = (height < dstH) ? height : dstH;

    // Build a full-size float buffer (zeros for any uncovered region).
    std::vector<float> buf(static_cast<size_t>(dstW) * dstH, 0.0f);
    for (int y = 0; y < copyH; y++) {
        for (int x = 0; x < copyW; x++) {
            buf[y * dstW + x] = data[y * width + x];
        }
    }

    WGPUTexelCopyTextureInfo dest = {};
    dest.texture  = depthTextureRead_;
    dest.mipLevel = 0;
    dest.origin   = {0, 0, 0};
    dest.aspect   = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout layout = {};
    layout.offset       = 0;
    layout.bytesPerRow  = static_cast<uint32_t>(dstW) * sizeof(float);
    layout.rowsPerImage = static_cast<uint32_t>(dstH);

    WGPUExtent3D extent = {};
    extent.width              = static_cast<uint32_t>(dstW);
    extent.height             = static_cast<uint32_t>(dstH);
    extent.depthOrArrayLayers = 1;

    wgpuQueueWriteTexture(queue_, &dest, buf.data(), buf.size() * sizeof(float), &layout, &extent);
}

void WebGPURenderer::SetTime(float time) {
    currentTime_ = time;
}

void WebGPURenderer::SetResolution(float width, float height) {
    if (width > 0.0f && height > 0.0f) {
        ResizeCanvas(static_cast<int>(width), static_cast<int>(height));
    }
}

// ─── Phase 2: Canvas resize ───────────────────────────────────────────────────

void WebGPURenderer::RecreateTextures() {
    // Release size-dependent textures.
    // samplers, uniform/extra/plasma buffers, and the 1×1 emptyTexture_ are size-independent
    // and do NOT need to be recreated.
    auto releaseIfValid = [](WGPUTexture& tex) {
        if (tex) { wgpuTextureRelease(tex); tex = nullptr; }
    };
    releaseIfValid(readTexture_);
    releaseIfValid(writeTexture_);
    releaseIfValid(pingPong0_);
    releaseIfValid(pingPong1_);
    releaseIfValid(dataTextureA_);
    releaseIfValid(dataTextureB_);
    releaseIfValid(dataTextureC_);
    releaseIfValid(depthTextureRead_);
    releaseIfValid(depthTextureWrite_);

    // Release old bind group since it references the old texture views.
    if (computeBindGroup_) {
        wgpuBindGroupRelease(computeBindGroup_);
        computeBindGroup_ = nullptr;
    }

    // Create new textures at the current canvas dimensions.
    WGPUTextureDescriptor texDesc = {};
    texDesc.nextInChain = nullptr;
    texDesc.dimension = WGPUTextureDimension_2D;
    texDesc.size = {static_cast<uint32_t>(canvasWidth_), static_cast<uint32_t>(canvasHeight_), 1};
    texDesc.mipLevelCount = 1;
    texDesc.sampleCount = 1;

    // Ping-pong textures (rgba32float)
    texDesc.format = WGPUTextureFormat_RGBA32Float;
    texDesc.usage = WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding
                  | WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc;
    texDesc.label = MakeStringView("Read Texture");
    readTexture_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Write Texture");
    writeTexture_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Ping-Pong 0");
    pingPong0_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Ping-Pong 1");
    pingPong1_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Data Texture A");
    dataTextureA_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Data Texture B");
    dataTextureB_ = wgpuDeviceCreateTexture(device_, &texDesc);

    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Data Texture C");
    dataTextureC_ = wgpuDeviceCreateTexture(device_, &texDesc);

    // Depth textures (r32float)
    texDesc.format = WGPUTextureFormat_R32Float;
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Depth Texture Read");
    depthTextureRead_ = wgpuDeviceCreateTexture(device_, &texDesc);
    texDesc.label = MakeStringView("Depth Texture Write");
    depthTextureWrite_ = wgpuDeviceCreateTexture(device_, &texDesc);

    // Zero-initialise textures that must start black.
    // Reuse videoStagingBuffer_ (rgba32float sized) to avoid a separate allocation.
    const size_t floatCount = static_cast<size_t>(canvasWidth_) * canvasHeight_ * 4;
    if (videoStagingBuffer_.size() < floatCount) {
        videoStagingBuffer_.assign(floatCount, 0.0f);
    } else {
        std::fill(videoStagingBuffer_.begin(),
                  videoStagingBuffer_.begin() + static_cast<std::ptrdiff_t>(floatCount),
                  0.0f);
    }

    WGPUTexelCopyTextureInfo dest = {};
    dest.mipLevel = 0;
    dest.origin = {0, 0, 0};
    dest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout layout = {};
    layout.offset = 0;
    layout.bytesPerRow  = static_cast<uint32_t>(canvasWidth_) * 16;  // rgba32float
    layout.rowsPerImage = static_cast<uint32_t>(canvasHeight_);

    WGPUExtent3D extent = {};
    extent.width  = static_cast<uint32_t>(canvasWidth_);
    extent.height = static_cast<uint32_t>(canvasHeight_);
    extent.depthOrArrayLayers = 1;

    dest.texture = dataTextureC_;
    wgpuQueueWriteTexture(queue_, &dest, videoStagingBuffer_.data(),
                          floatCount * sizeof(float), &layout, &extent);

    dest.texture = readTexture_;
    wgpuQueueWriteTexture(queue_, &dest, videoStagingBuffer_.data(),
                          floatCount * sizeof(float), &layout, &extent);

    // Rebuild the bind group with the new texture views.
    CreateBindGroups();
}

void WebGPURenderer::ResizeCanvas(int newWidth, int newHeight) {
    if (newWidth <= 0 || newHeight <= 0) return;
    if (newWidth == canvasWidth_ && newHeight == canvasHeight_) return;
    if (!initialized_) return;

    printf("🔄 Resizing canvas: %dx%d → %dx%d\n",
           canvasWidth_, canvasHeight_, newWidth, newHeight);

    canvasWidth_  = newWidth;
    canvasHeight_ = newHeight;

    // Recreate all size-dependent GPU resources.
    RecreateTextures();

    // Invalidate the persistent staging buffer so it gets resized on next upload.
    videoStagingBuffer_.clear();

    // Release the readback buffer; it will be recreated at the new size on next capture.
    if (readbackBuffer_) {
        if (captureState_ == CaptureState::Pending) {
            // A capture was in progress — cancel it.
            wgpuBufferUnmap(readbackBuffer_);
        }
        wgpuBufferRelease(readbackBuffer_);
        readbackBuffer_ = nullptr;
        readbackBufferSize_ = 0;
        readbackBytesPerRow_ = 0;
    }
    captureState_ = CaptureState::Idle;

    printf("✅ Canvas resized successfully\n");
}

void WebGPURenderer::SetMouse(float x, float y, bool down) {
    mouseX_ = x;
    mouseY_ = y;
    mouseDown_ = down;
}

void WebGPURenderer::SetMouseDown(bool down) {
    mouseDown_ = down;
}

void WebGPURenderer::SetZoomParams(float p1, float p2, float p3, float p4) {
    zoomParams_[0] = p1;
    zoomParams_[1] = p2;
    zoomParams_[2] = p3;
    zoomParams_[3] = p4;
}

void WebGPURenderer::AddRipple(float x, float y) {
    if (ripples_.size() >= MAX_RIPPLES) {
        ripples_.erase(ripples_.begin());
    }
    RipplePoint rp = {x, y, currentTime_, 0.0f};
    ripples_.push_back(rp);
}

void WebGPURenderer::ClearRipples() {
    ripples_.clear();
}

void WebGPURenderer::SetAudioData(float bass, float mid, float treble) {
    audioBass_   = bass;
    audioMid_    = mid;
    audioTreble_ = treble;
}
void WebGPURenderer::UpdateUniformBuffer() {
    if (!uniformBuffer_) return;

    float uniformData[12 + MAX_RIPPLES * 4] = {};

    // config: time, rippleCount, resolutionX, resolutionY
    uniformData[0] = currentTime_;
    uniformData[1] = static_cast<float>(ripples_.size());
    uniformData[2] = static_cast<float>(canvasWidth_);
    uniformData[3] = static_cast<float>(canvasHeight_);

    // zoom_config: time, mouseX, mouseY, mouseDown
    uniformData[4] = currentTime_;
    uniformData[5] = mouseX_;
    uniformData[6] = mouseY_;
    uniformData[7] = mouseDown_ ? 1.0f : 0.0f;

    // zoom_params (global defaults; per-slot params are patched via WriteSlotParams)
    uniformData[8]  = zoomParams_[0];
    uniformData[9]  = zoomParams_[1];
    uniformData[10] = zoomParams_[2];
    uniformData[11] = zoomParams_[3];

    // ripples
    for (size_t i = 0; i < MAX_RIPPLES; i++) {
        if (i < ripples_.size()) {
            uniformData[12 + i * 4 + 0] = ripples_[i].x;
            uniformData[12 + i * 4 + 1] = ripples_[i].y;
            uniformData[12 + i * 4 + 2] = ripples_[i].startTime;
            uniformData[12 + i * 4 + 3] = 0.0f;
        } else {
            uniformData[12 + i * 4 + 0] = 0.0f;
            uniformData[12 + i * 4 + 1] = 0.0f;
            uniformData[12 + i * 4 + 2] = 0.0f;
            uniformData[12 + i * 4 + 3] = 0.0f;
        }
    }

    wgpuQueueWriteBuffer(queue_, uniformBuffer_, 0, uniformData, sizeof(uniformData));

    // Upload audio to extraBuffer_ (binding 10).
    // Some shaders read bass/mid/treble from the first three floats here.
    if (extraBuffer_) {
        float audioData[3] = { audioBass_, audioMid_, audioTreble_ };
        wgpuQueueWriteBuffer(queue_, extraBuffer_, 0, audioData, sizeof(audioData));
    }

    // Upload audio to plasmaBuffer_ (binding 12) as vec4(bass, mid, treble, 0)
    // at index 0.  Shaders using the AGENTS.md audio convention read from here:
    //   let bass = plasmaBuffer[0].x;
    //   let mids = plasmaBuffer[0].y;
    //   let treble = plasmaBuffer[0].z;
    if (plasmaBuffer_) {
        float audioVec4[4] = { audioBass_, audioMid_, audioTreble_, 0.0f };
        wgpuQueueWriteBuffer(queue_, plasmaBuffer_, 0, audioVec4, sizeof(audioVec4));
    }
}

// ─── Render ──────────────────────────────────────────────────────────────────
//
// Multi-slot rendering pipeline (Phase 1):
//
//   source (readTexture_)
//     -> Slot 0 compute -> pingPong0_
//     -> Slot 1 compute -> pingPong1_
//     -> Slot 2 compute -> writeTexture_
//   Then: writeTexture_ -> readTexture_  (temporal feedback for next frame)
//         depthWrite_   -> depthRead_
//         dataTextureA_ -> dataTextureC_  (data-texture feedback)
//
// Each slot submission is a separate wgpuQueueSubmit so that per-slot
// zoom_params can be patched in the shared uniform buffer between passes
// while preserving queue FIFO ordering.
//
// Slots that reference the same texture as their output and the next slot's
// input are safe because wgpuQueueSubmit flushes operations in order.

// Helper: copy one texture to another within an already-open encoder.
static void CopyTex(WGPUCommandEncoder enc,
                    WGPUTexture src, WGPUTexture dst,
                    uint32_t w, uint32_t h) {
    WGPUTexelCopyTextureInfo s = {};
    s.texture = src; s.mipLevel = 0; s.origin = {0,0,0}; s.aspect = WGPUTextureAspect_All;
    WGPUTexelCopyTextureInfo d = {};
    d.texture = dst; d.mipLevel = 0; d.origin = {0,0,0}; d.aspect = WGPUTextureAspect_All;
    WGPUExtent3D ext = { w, h, 1 };
    wgpuCommandEncoderCopyTextureToTexture(enc, &s, &d, &ext);
}

void WebGPURenderer::Render() {
    if (!initialized_) return;

    // Upload all per-frame global uniforms (time, mouse, ripples, audio).
    UpdateUniformBuffer();

    const uint32_t W = static_cast<uint32_t>(canvasWidth_);
    const uint32_t H = static_cast<uint32_t>(canvasHeight_);

    // Fixed output texture per slot index.
    WGPUTexture slotOutput[MAX_SHADER_SLOTS] = { pingPong0_, pingPong1_, writeTexture_ };

    // Determine the first enabled slot and the last enabled slot.
    // If no slot is configured, fall back to the legacy activeShaderId_.
    int firstEnabled = -1;
    int lastEnabled  = -1;
    for (int i = 0; i < MAX_SHADER_SLOTS; i++) {
        if (slots_[i].enabled && !slots_[i].shaderId.empty() &&
            shaders_.find(slots_[i].shaderId) != shaders_.end()) {
            if (firstEnabled < 0) firstEnabled = i;
            lastEnabled = i;
        }
    }

    // ── Legacy single-shader fallback ────────────────────────────────────────
    if (firstEnabled < 0) {
        if (!activeShaderId_.empty()) {
            auto it = shaders_.find(activeShaderId_);
            if (it != shaders_.end()) {
                // Single pass: readTexture_ -> writeTexture_
                WriteSlotParams(zoomParams_);
                WGPUBindGroup bg = CreateComputeBindGroup(readTexture_, writeTexture_);

                WGPUCommandEncoderDescriptor encDesc = {};
                encDesc.label = MakeStringView("Single Encoder");
                WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_, &encDesc);

                DispatchComputePass(enc, it->second.pipeline, bg,
                                    it->second.workgroupX, it->second.workgroupY);
                wgpuBindGroupRelease(bg);

                CopyTex(enc, writeTexture_, readTexture_, W, H);
                CopyTex(enc, depthTextureWrite_, depthTextureRead_, W, H);
                CopyTex(enc, dataTextureA_, dataTextureC_, W, H);

                WGPUCommandBufferDescriptor cbDesc = {};
                cbDesc.label = MakeStringView("Single CmdBuf");
                WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
                wgpuQueueSubmit(queue_, 1, &cb);
                wgpuCommandBufferRelease(cb);
                wgpuCommandEncoderRelease(enc);
            }
        }
    } else {
        // ── Multi-slot pipeline ───────────────────────────────────────────────
        // The "chain input" starts as readTexture_ (previous frame output).
        WGPUTexture chainInput = readTexture_;

        for (int i = 0; i < MAX_SHADER_SLOTS; i++) {
            if (!slots_[i].enabled || slots_[i].shaderId.empty()) continue;
            auto it = shaders_.find(slots_[i].shaderId);
            if (it == shaders_.end()) continue;

            // Which texture does this slot read from?
            WGPUTexture readFrom = (slots_[i].mode == SlotMode::Parallel)
                                   ? readTexture_   // parallel: always from source
                                   : chainInput;    // chained: previous slot output

            // Which texture does this slot write to?
            WGPUTexture writeTo = slotOutput[i];

            // Patch per-slot zoom_params before submitting this slot's pass.
            WriteSlotParams(slots_[i].params);

            WGPUBindGroup bg = CreateComputeBindGroup(readFrom, writeTo);

            WGPUCommandEncoderDescriptor encDesc = {};
            encDesc.label = MakeStringView("Slot Encoder");
            WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_, &encDesc);

            DispatchComputePass(enc, it->second.pipeline, bg,
                                it->second.workgroupX, it->second.workgroupY);
            wgpuBindGroupRelease(bg);

            WGPUCommandBufferDescriptor cbDesc = {};
            cbDesc.label = MakeStringView("Slot CmdBuf");
            WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
            // Submit this slot separately so the next WriteSlotParams (called
            // before the next slot's encoder) takes effect on the GPU.
            wgpuQueueSubmit(queue_, 1, &cb);
            wgpuCommandBufferRelease(cb);
            wgpuCommandEncoderRelease(enc);

            // Update chain input for the next slot (if chained).
            chainInput = writeTo;
        }

        // If the last slot did not write directly to writeTexture_, copy its
        // output there so the render pipeline always reads from writeTexture_.
        if (slotOutput[lastEnabled] != writeTexture_) {
            WGPUCommandEncoderDescriptor encDesc = {};
            encDesc.label = MakeStringView("Copy Encoder");
            WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_, &encDesc);
            CopyTex(enc, slotOutput[lastEnabled], writeTexture_, W, H);
            WGPUCommandBufferDescriptor cbDesc = {};
            cbDesc.label = MakeStringView("Copy CmdBuf");
            WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
            wgpuQueueSubmit(queue_, 1, &cb);
            wgpuCommandBufferRelease(cb);
            wgpuCommandEncoderRelease(enc);
        }

        // End-of-frame texture copies for temporal feedback.
        {
            WGPUCommandEncoderDescriptor encDesc = {};
            encDesc.label = MakeStringView("Feedback Encoder");
            WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_, &encDesc);
            CopyTex(enc, writeTexture_,       readTexture_,      W, H);
            CopyTex(enc, depthTextureWrite_,  depthTextureRead_, W, H);
            CopyTex(enc, dataTextureA_,       dataTextureC_,     W, H);
            WGPUCommandBufferDescriptor cbDesc = {};
            cbDesc.label = MakeStringView("Feedback CmdBuf");
            WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
            wgpuQueueSubmit(queue_, 1, &cb);
            wgpuCommandBufferRelease(cb);
            wgpuCommandEncoderRelease(enc);
        }
    }

    // Update FPS counter
    frameCount_++;
    float currentTime = emscripten_get_now() / 1000.0f;
    if (currentTime - lastFrameTime_ >= 1.0f) {
        fps_ = frameCount_ / (currentTime - lastFrameTime_);
        frameCount_ = 0;
        lastFrameTime_ = currentTime;
    }
}

void WebGPURenderer::Present() {
    // WebGPU surface presentation is handled by the browser's animation loop.
}

// ─── Phase 2: Frame Capture ───────────────────────────────────────────────────

void WebGPURenderer::BeginFrameCapture() {
    if (captureState_ == CaptureState::Pending) return;  // already in flight
    if (!initialized_ || !writeTexture_ || !queue_ || !device_) {
        captureState_ = CaptureState::Error;
        return;
    }

    const uint32_t W = static_cast<uint32_t>(canvasWidth_);
    const uint32_t H = static_cast<uint32_t>(canvasHeight_);

    // WebGPU requires bytesPerRow to be a multiple of 256.
    // writeTexture_ is RGBA32Float: 4 channels × 4 bytes = 16 bytes per pixel.
    const uint32_t bytesPerRow = AlignUp(W * 16u, 256u);
    const size_t   needed      = static_cast<size_t>(bytesPerRow) * H;

    // (Re)create the readback buffer if the size has changed.
    if (!readbackBuffer_ || readbackBufferSize_ < needed) {
        if (readbackBuffer_) wgpuBufferRelease(readbackBuffer_);
        WGPUBufferDescriptor bufDesc = {};
        bufDesc.label            = MakeStringView("Readback Buffer");
        bufDesc.size             = needed;
        bufDesc.usage            = WGPUBufferUsage_CopyDst | WGPUBufferUsage_MapRead;
        bufDesc.mappedAtCreation = false;
        readbackBuffer_    = wgpuDeviceCreateBuffer(device_, &bufDesc);
        readbackBufferSize_ = needed;
    }
    readbackBytesPerRow_ = bytesPerRow;

    // Encode CopyTextureToBuffer: writeTexture_ → readbackBuffer_
    WGPUCommandEncoderDescriptor encDesc = {};
    encDesc.label = MakeStringView("Readback Encoder");
    WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_, &encDesc);

    WGPUTexelCopyTextureInfo src = {};
    src.texture  = writeTexture_;
    src.mipLevel = 0;
    src.origin   = {0, 0, 0};
    src.aspect   = WGPUTextureAspect_All;

    WGPUTexelCopyBufferInfo dst = {};
    dst.buffer             = readbackBuffer_;
    dst.layout.offset      = 0;
    dst.layout.bytesPerRow = bytesPerRow;
    dst.layout.rowsPerImage = H;

    WGPUExtent3D extent = { W, H, 1 };
    wgpuCommandEncoderCopyTextureToBuffer(enc, &src, &dst, &extent);

    WGPUCommandBufferDescriptor cbDesc = {};
    cbDesc.label = MakeStringView("Readback CmdBuf");
    WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
    wgpuQueueSubmit(queue_, 1, &cb);
    wgpuCommandBufferRelease(cb);
    wgpuCommandEncoderRelease(enc);

    captureState_ = CaptureState::Pending;

    // Request async mapping.  The callback fires when the browser has finished
    // copying the GPU data to the CPU-accessible buffer.
    wgpuBufferMapAsync(
        readbackBuffer_,
        WGPUMapMode_Read, 0, needed,
        WGPUBufferMapCallbackInfo{
            nullptr,
            WGPUCallbackMode_AllowSpontaneous,
            [](WGPUMapAsyncStatus status, WGPUStringView /*message*/,
               void* userdata1, void* /*userdata2*/) {
                WebGPURenderer* self = static_cast<WebGPURenderer*>(userdata1);
                if (status == WGPUMapAsyncStatus_Success) {
                    self->captureState_ = CaptureState::Ready;
                } else {
                    printf("❌ Frame readback map failed (status=%d)\n",
                           static_cast<int>(status));
                    self->captureState_ = CaptureState::Error;
                }
            },
            this, nullptr
        });
}

int WebGPURenderer::ReadCapturedFrame(uint8_t* outRGBA8, int maxBytes) {
    if (captureState_ != CaptureState::Ready) return 0;
    if (!readbackBuffer_ || !outRGBA8) return 0;

    const uint32_t W = static_cast<uint32_t>(canvasWidth_);
    const uint32_t H = static_cast<uint32_t>(canvasHeight_);
    const int required = static_cast<int>(W * H * 4);
    if (maxBytes < required) return 0;

    const void* mapped = wgpuBufferGetConstMappedRange(readbackBuffer_, 0,
                                                        readbackBufferSize_);
    if (!mapped) {
        captureState_ = CaptureState::Error;
        return 0;
    }

    const float* src = static_cast<const float*>(mapped);
    // readbackBytesPerRow_ is in bytes; divide by 4 to get float stride.
    const uint32_t floatStride = readbackBytesPerRow_ / 4u;

    for (uint32_t y = 0; y < H; y++) {
        const float*  rowSrc = src + static_cast<size_t>(y) * floatStride;
        uint8_t*      rowDst = outRGBA8 + static_cast<size_t>(y) * W * 4;
        for (uint32_t x = 0; x < W; x++) {
            // Clamp float [0,1] to uint8 [0,255].
            const float r = rowSrc[x * 4 + 0];
            const float g = rowSrc[x * 4 + 1];
            const float b = rowSrc[x * 4 + 2];
            const float a = rowSrc[x * 4 + 3];
            rowDst[x * 4 + 0] = static_cast<uint8_t>(std::min(1.0f, std::max(0.0f, r)) * 255.0f);
            rowDst[x * 4 + 1] = static_cast<uint8_t>(std::min(1.0f, std::max(0.0f, g)) * 255.0f);
            rowDst[x * 4 + 2] = static_cast<uint8_t>(std::min(1.0f, std::max(0.0f, b)) * 255.0f);
            rowDst[x * 4 + 3] = static_cast<uint8_t>(std::min(1.0f, std::max(0.0f, a)) * 255.0f);
        }
    }
    return required;
}

void WebGPURenderer::EndFrameCapture() {
    if (readbackBuffer_ && captureState_ == CaptureState::Ready) {
        wgpuBufferUnmap(readbackBuffer_);
    }
    captureState_ = CaptureState::Idle;
}

} // namespace pixelocity
