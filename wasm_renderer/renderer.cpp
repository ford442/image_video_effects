#include "renderer.h"
#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <stdio.h>
#include <math.h>
#include <string>
#include <cstring>

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
    // ARCH: [High] Manual resource cleanup is error-prone.
    // This pattern repeats for every resource type.
    // Refactor using RAII wrappers: wgpu::Texture, wgpu::Buffer, etc.
    if (imageTexture_) wgpuTextureRelease(imageTexture_);
    if (videoTexture_) wgpuTextureRelease(videoTexture_);
    if (readTexture_) wgpuTextureRelease(readTexture_);
    if (writeTexture_) wgpuTextureRelease(writeTexture_);
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
    
    wgpuInstanceRequestAdapter(instance_, &adapterOpts, 
        WGPURequestAdapterCallbackInfo{
            nullptr, WGPUCallbackMode_AllowProcessEvents, adapterCallback, &adapter_, nullptr
        });

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
    
    wgpuAdapterRequestDevice(adapter_, &deviceDesc,
        WGPURequestDeviceCallbackInfo{
            nullptr, WGPUCallbackMode_AllowProcessEvents, deviceCallback, &device_, nullptr
        });

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
    // ARCH: [High] Allocating large vector every initialization.
    // Consider using wgpuCommandEncoderClearBuffer if available
    // or reusing a static zero buffer.
    std::vector<float> zeros(canvasWidth_ * canvasHeight_ * 4, 0.0f);
    
    WGPUTexelCopyTextureInfo dataDest = {};
    dataDest.texture = dataTextureC_;
    dataDest.mipLevel = 0;
    dataDest.origin = {0, 0, 0};
    dataDest.aspect = WGPUTextureAspect_All;
    
    WGPUTexelCopyBufferLayout dataLayout = {};
    dataLayout.offset = 0;
    // ARCH: [Medium] Magic number 16 = sizeof(float) * 4 (RGBA)
    // Use named constant for clarity.
    dataLayout.bytesPerRow = static_cast<uint32_t>(canvasWidth_ * 16);
    dataLayout.rowsPerImage = static_cast<uint32_t>(canvasHeight_);
    
    WGPUExtent3D dataExtent = {};
    dataExtent.width = static_cast<uint32_t>(canvasWidth_);
    dataExtent.height = static_cast<uint32_t>(canvasHeight_);
    dataExtent.depthOrArrayLayers = 1;
    
    wgpuQueueWriteTexture(queue_, &dataDest, zeros.data(), zeros.size() * sizeof(float), &dataLayout, &dataExtent);

    // ARCH: [Critical] No validation that resources were created successfully.
    // If device is lost or OOM, nullptrs will cause crashes later.
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
    shaders_[id] = sp;

    printf("✅ Loaded shader: %s\n", id);
    return true;
}

void WebGPURenderer::SetActiveShader(const char* id) {
    activeShaderId_ = id;
}

void WebGPURenderer::UploadRGBA8ToReadTexture(const uint8_t* data, int width, int height) {
    if (!queue_ || !readTexture_) return;

    // Convert uint8 RGBA to float RGBA, fitting within canvas bounds.
    // Pixels outside the source image remain black.
    const int dstW = canvasWidth_;
    const int dstH = canvasHeight_;
    // ARCH: [Low] Could use std::min instead of ternary for clarity.
    const int copyW = (width  < dstW) ? width  : dstW;
    const int copyH = (height < dstH) ? height : dstH;

    // ARCH: [High] Large allocation every frame for video updates.
    // Consider using a persistent staging buffer or texture pool.
    std::vector<float> floatData(static_cast<size_t>(dstW) * dstH * 4, 0.0f);

    // ARCH: [Medium] Nested loops could be optimized with SIMD or
    // GPU-based conversion using a compute shader.
    for (int y = 0; y < copyH; y++) {
        for (int x = 0; x < copyW; x++) {
            const int srcIdx = (y * width + x) * 4;
            const int dstIdx = (y * dstW  + x) * 4;
            // ARCH: [Medium] Magic number 255.0f should be constant.
            floatData[dstIdx + 0] = data[srcIdx + 0] / 255.0f;
            floatData[dstIdx + 1] = data[srcIdx + 1] / 255.0f;
            floatData[dstIdx + 2] = data[srcIdx + 2] / 255.0f;
            floatData[dstIdx + 3] = data[srcIdx + 3] / 255.0f;
        }
    }

    WGPUTexelCopyTextureInfo dest = {};
    dest.texture = readTexture_;
    dest.mipLevel = 0;
    dest.origin = {0, 0, 0};
    dest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout layout = {};
    layout.offset = 0;
    // ARCH: [Medium] Magic number 16 = sizeof(float) * 4
    layout.bytesPerRow = static_cast<uint32_t>(dstW) * 16;
    layout.rowsPerImage = static_cast<uint32_t>(dstH);

    WGPUExtent3D extent = {};
    extent.width  = static_cast<uint32_t>(dstW);
    extent.height = static_cast<uint32_t>(dstH);
    extent.depthOrArrayLayers = 1;

    wgpuQueueWriteTexture(queue_, &dest, floatData.data(),
                          floatData.size() * sizeof(float), &layout, &extent);
}

void WebGPURenderer::LoadImage(const uint8_t* data, int width, int height) {
    printf("📷 Loading image: %dx%d\n", width, height);
    UploadRGBA8ToReadTexture(data, width, height);
}

void WebGPURenderer::UpdateVideoFrame(const uint8_t* data, int width, int height) {
    UploadRGBA8ToReadTexture(data, width, height);
}

// ARCH: [Medium] UpdateDepthMap is declared in header but not implemented.
// This will cause linker errors if called.
void WebGPURenderer::UpdateDepthMap(const float* data, int width, int height) {
    // TODO: Implement depth map upload to depthTextureRead_
    (void)data;
    (void)width;
    (void)height;
}

void WebGPURenderer::SetTime(float time) {
    currentTime_ = time;
}

void WebGPURenderer::SetResolution(float width, float height) {
    // ARCH: [Medium] Stubs should log warning or have [[deprecated]] attribute.
    // Silent no-op can confuse developers expecting dynamic resolution changes.
    (void)width;
    (void)height;
}

void WebGPURenderer::SetMouse(float x, float y, bool down) {
    mouseX_ = x;
    mouseY_ = y;
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

void WebGPURenderer::UpdateUniformBuffer() {
    if (!uniformBuffer_) return;

    // Build uniform data
    // ARCH: [Critical] VLA (Variable Length Array) - non-standard C++.
    // Use std::vector or std::array for portability.
    float uniformData[12 + MAX_RIPPLES * 4];
    
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
    
    // zoom_params
    uniformData[8] = zoomParams_[0];
    uniformData[9] = zoomParams_[1];
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
}

// MISSING: Multi-slot render pipeline
// The TypeScript renderer supports chaining 3 shader slots:
//   Slot 0 (e.g., 'liquid') -> pingPongTexture1
//   Slot 1 (e.g., 'distortion') -> pingPongTexture2  
//   Slot 2 (e.g., 'glow') -> writeTexture -> screen
//
// Each slot has its own:
//   - Shader selection
//   - Parameters (zoomParam1-4, lightStrength, etc.)
//   - Texture bindings (read from previous slot)
//
// Current implementation only supports single shader execution.
// Need to add:
//   - Slot state array (3 slots)
//   - Chained compute pass execution
//   - Per-slot parameter binding
// Priority: CRITICAL
// Effort: 2-3 weeks

void WebGPURenderer::Render() {
    if (!initialized_ || activeShaderId_.empty()) return;

    auto it = shaders_.find(activeShaderId_);
    if (it == shaders_.end()) return;

    // Update uniforms
    UpdateUniformBuffer();
    
    // MISSING: Audio data integration
    // Audio analyzer data (bass, mid, treble) should be uploaded to
    // extraBuffer_ or added to uniform structure for shader access.
    // TypeScript: updateAudioData(bass, mid, treble) -> uniform/extraBuffer
    // Priority: HIGH

    // Create command encoder
    WGPUCommandEncoderDescriptor encoderDesc = {};
    encoderDesc.nextInChain = nullptr;
    encoderDesc.label = MakeStringView("Render Encoder");
    WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(device_, &encoderDesc);

    // Begin compute pass
    WGPUComputePassDescriptor computeDesc = {};
    computeDesc.nextInChain = nullptr;
    computeDesc.label = MakeStringView("Compute Pass");
    WGPUComputePassEncoder computePass = wgpuCommandEncoderBeginComputePass(encoder, &computeDesc);

    wgpuComputePassEncoderSetPipeline(computePass, it->second.pipeline);
    wgpuComputePassEncoderSetBindGroup(computePass, 0, computeBindGroup_, 0, nullptr);
    
    // ARCH: [Medium] Magic numbers 7 and 8 for workgroup size calculation.
    // Use named constants: constexpr int WorkgroupSize = 8;
    wgpuComputePassEncoderDispatchWorkgroups(
        computePass, 
        (canvasWidth_ + 7) / 8, 
        (canvasHeight_ + 7) / 8, 
        1
    );
    wgpuComputePassEncoderEnd(computePass);

    // Copy writeTexture to readTexture for next frame (ping-pong)
    // ARCH: [High] Code duplication for texture copying.
    // Refactor into helper method: CopyTexture(encoder, src, dst, extent)
    WGPUTexelCopyTextureInfo srcCopy1 = {};
    srcCopy1.texture = writeTexture_;
    srcCopy1.mipLevel = 0;
    srcCopy1.origin = {0, 0, 0};
    srcCopy1.aspect = WGPUTextureAspect_All;
    
    WGPUTexelCopyTextureInfo dstCopy1 = {};
    dstCopy1.texture = readTexture_;
    dstCopy1.mipLevel = 0;
    dstCopy1.origin = {0, 0, 0};
    dstCopy1.aspect = WGPUTextureAspect_All;
    
    WGPUExtent3D extent1 = {};
    extent1.width = static_cast<uint32_t>(canvasWidth_);
    extent1.height = static_cast<uint32_t>(canvasHeight_);
    extent1.depthOrArrayLayers = 1;
    
    wgpuCommandEncoderCopyTextureToTexture(encoder, &srcCopy1, &dstCopy1, &extent1);

    // Also copy depth texture
    WGPUTexelCopyTextureInfo srcCopy2 = {};
    srcCopy2.texture = depthTextureWrite_;
    srcCopy2.mipLevel = 0;
    srcCopy2.origin = {0, 0, 0};
    srcCopy2.aspect = WGPUTextureAspect_All;
    
    WGPUTexelCopyTextureInfo dstCopy2 = {};
    dstCopy2.texture = depthTextureRead_;
    dstCopy2.mipLevel = 0;
    dstCopy2.origin = {0, 0, 0};
    dstCopy2.aspect = WGPUTextureAspect_All;
    
    wgpuCommandEncoderCopyTextureToTexture(encoder, &srcCopy2, &dstCopy2, &extent1);

    // Also copy dataTextureA to dataTextureC for feedback effects
    WGPUTexelCopyTextureInfo srcCopy3 = {};
    srcCopy3.texture = dataTextureA_;
    srcCopy3.mipLevel = 0;
    srcCopy3.origin = {0, 0, 0};
    srcCopy3.aspect = WGPUTextureAspect_All;
    
    WGPUTexelCopyTextureInfo dstCopy3 = {};
    dstCopy3.texture = dataTextureC_;
    dstCopy3.mipLevel = 0;
    dstCopy3.origin = {0, 0, 0};
    dstCopy3.aspect = WGPUTextureAspect_All;
    
    wgpuCommandEncoderCopyTextureToTexture(encoder, &srcCopy3, &dstCopy3, &extent1);
    
    WGPUCommandBufferDescriptor cmdBufferDesc = {};
    cmdBufferDesc.nextInChain = nullptr;
    cmdBufferDesc.label = MakeStringView("Command Buffer");
    WGPUCommandBuffer cmdBuffer = wgpuCommandEncoderFinish(encoder, &cmdBufferDesc);
    
    wgpuQueueSubmit(queue_, 1, &cmdBuffer);

    // Cleanup
    // ARCH: [High] Releasing encoder before cmdBuffer is questionable ordering.
    // Typically release cmdBuffer after submit, then encoder.
    wgpuComputePassEncoderRelease(computePass);
    wgpuCommandEncoderRelease(encoder);
    wgpuCommandBufferRelease(cmdBuffer);

    // Update FPS
    frameCount_++;
    // ARCH: [Low] emscripten_get_now() returns time in milliseconds.
    // Magic number 1000.0f should be named constant.
    float currentTime = emscripten_get_now() / 1000.0f;
    if (currentTime - lastFrameTime_ >= 1.0f) {
        fps_ = frameCount_ / (currentTime - lastFrameTime_);
        frameCount_ = 0;
        lastFrameTime_ = currentTime;
    }
}

void WebGPURenderer::Present() {
    // ARCH: [Low] Method documented as no-op should have comment explaining why.
    // WebGPU surface presentation is handled by browser's animation loop.
}

} // namespace pixelocity
