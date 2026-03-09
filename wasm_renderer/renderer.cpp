#include "renderer.h"
#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <stdio.h>
#include <math.h>
#include <string>
#include <cstring>

namespace pixelocity {

// JavaScript bridge functions
extern "C" {
    extern void jsRequestAnimationFrame(void (*callback)(double time, void* userData), void* userData);
    extern void jsConsoleLog(const char* msg);
}

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
            nullptr, adapterCallback, &adapter_, nullptr
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
            nullptr, deviceCallback, &device_, nullptr
        });

    if (!device_) {
        printf("❌ Failed to get WebGPU device\n");
        return false;
    }

    queue_ = wgpuDeviceGetQueue(device_);
    
    // Set error callback using new API
    auto errorCallback = [](WGPUDevice const* device, WGPUErrorType type, 
                            WGPUStringView message, void* userdata1, void* userdata2) {
        (void)device; (void)userdata1; (void)userdata2; // Unused
        printf("⚠️ WebGPU Error [%d]\n", type);
    };
    
    wgpuDeviceSetUncapturedErrorCallback(device_,
        WGPUUncapturedErrorCallbackInfo{
            nullptr, errorCallback, nullptr, nullptr
        });

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
    constexpr size_t uniformSize = sizeof(float) * (12 + MAX_RIPPLES * 4);
    WGPUBufferDescriptor bufferDesc = {};
    bufferDesc.nextInChain = nullptr;
    bufferDesc.label = MakeStringView("Uniform Buffer");
    bufferDesc.size = uniformSize;
    bufferDesc.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst;
    bufferDesc.mappedAtCreation = false;
    uniformBuffer_ = wgpuDeviceCreateBuffer(device_, &bufferDesc);

    // Create extra buffer (256 floats)
    bufferDesc.label = MakeStringView("Extra Buffer");
    bufferDesc.size = 256 * sizeof(float);
    bufferDesc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    extraBuffer_ = wgpuDeviceCreateBuffer(device_, &bufferDesc);

    // Create plasma buffer
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
    emptyDest.nextInChain = nullptr;
    emptyDest.texture = emptyTexture_;
    emptyDest.mipLevel = 0;
    emptyDest.origin = {0, 0, 0};
    emptyDest.aspect = WGPUTextureAspect_All;
    
    WGPUTexelCopyBufferLayout emptyDataLayout = {};
    emptyDataLayout.nextInChain = nullptr;
    emptyDataLayout.offset = 0;
    emptyDataLayout.bytesPerRow = 16;
    emptyDataLayout.rowsPerImage = 1;
    
    wgpuQueueWriteTexture(queue_, &emptyDest, black, sizeof(black), &emptyDataLayout, &texDesc.size);

    // Initialize data texture C to zeros
    std::vector<float> zeros(canvasWidth_ * canvasHeight_ * 4, 0.0f);
    
    WGPUTexelCopyTextureInfo dataDest = {};
    dataDest.nextInChain = nullptr;
    dataDest.texture = dataTextureC_;
    dataDest.mipLevel = 0;
    dataDest.origin = {0, 0, 0};
    dataDest.aspect = WGPUTextureAspect_All;
    
    WGPUTexelCopyBufferLayout dataLayout = {};
    dataLayout.nextInChain = nullptr;
    dataLayout.offset = 0;
    dataLayout.bytesPerRow = static_cast<uint32_t>(canvasWidth_ * 16);
    dataLayout.rowsPerImage = static_cast<uint32_t>(canvasHeight_);
    
    WGPUExtent3D dataExtent = {};
    dataExtent.width = static_cast<uint32_t>(canvasWidth_);
    dataExtent.height = static_cast<uint32_t>(canvasHeight_);
    dataExtent.depthOrArrayLayers = 1;
    
    wgpuQueueWriteTexture(queue_, &dataDest, zeros.data(), zeros.size() * sizeof(float), &dataLayout, &dataExtent);

    return true;
}

void WebGPURenderer::CreateBindGroupLayout() {
    // Create the universal bind group layout for compute shaders
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
    colorTarget.format = WGPUTextureFormat_BGRA8Unorm; // Standard canvas format
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
    pipelineDesc.layout = nullptr; // Auto layout
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

    WGPUComputePipeline pipeline = wgpuDeviceCreateComputePipeline(device_, &pipelineDesc);
    if (!pipeline) {
        printf("❌ Failed to create compute pipeline for '%s'\n", id);
        wgpuShaderModuleRelease(module);
        return false;
    }

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

void WebGPURenderer::SetTime(float time) {
    currentTime_ = time;
}

void WebGPURenderer::SetResolution(float width, float height) {
    // Currently fixed at initialization
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

void WebGPURenderer::Render() {
    if (!initialized_ || activeShaderId_.empty()) return;

    auto it = shaders_.find(activeShaderId_);
    if (it == shaders_.end()) return;

    // Update uniforms
    UpdateUniformBuffer();

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
    wgpuComputePassEncoderDispatchWorkgroups(
        computePass, 
        (canvasWidth_ + 7) / 8, 
        (canvasHeight_ + 7) / 8, 
        1
    );
    wgpuComputePassEncoderEnd(computePass);

    // Copy writeTexture to readTexture for next frame (ping-pong)
    WGPUImageCopyTexture srcCopy1 = {};
    srcCopy1.nextInChain = nullptr;
    srcCopy1.texture = writeTexture_;
    srcCopy1.mipLevel = 0;
    srcCopy1.origin = {0, 0, 0};
    srcCopy1.aspect = WGPUTextureAspect_All;
    
    WGPUImageCopyTexture dstCopy1 = {};
    dstCopy1.nextInChain = nullptr;
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
    WGPUImageCopyTexture srcCopy2 = {};
    srcCopy2.nextInChain = nullptr;
    srcCopy2.texture = depthTextureWrite_;
    srcCopy2.mipLevel = 0;
    srcCopy2.origin = {0, 0, 0};
    srcCopy2.aspect = WGPUTextureAspect_All;
    
    WGPUImageCopyTexture dstCopy2 = {};
    dstCopy2.nextInChain = nullptr;
    dstCopy2.texture = depthTextureRead_;
    dstCopy2.mipLevel = 0;
    dstCopy2.origin = {0, 0, 0};
    dstCopy2.aspect = WGPUTextureAspect_All;
    
    wgpuCommandEncoderCopyTextureToTexture(encoder, &srcCopy2, &dstCopy2, &extent1);

    // Also copy dataTextureA to dataTextureC for feedback effects
    WGPUImageCopyTexture srcCopy3 = {};
    srcCopy3.nextInChain = nullptr;
    srcCopy3.texture = dataTextureA_;
    srcCopy3.mipLevel = 0;
    srcCopy3.origin = {0, 0, 0};
    srcCopy3.aspect = WGPUTextureAspect_All;
    
    WGPUImageCopyTexture dstCopy3 = {};
    dstCopy3.nextInChain = nullptr;
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
    wgpuComputePassEncoderRelease(computePass);
    wgpuCommandEncoderRelease(encoder);
    wgpuCommandBufferRelease(cmdBuffer);

    // Update FPS
    frameCount_++;
    float currentTime = emscripten_get_now() / 1000.0f;
    if (currentTime - lastFrameTime_ >= 1.0f) {
        fps_ = frameCount_ / (currentTime - lastFrameTime_);
        frameCount_ = 0;
        lastFrameTime_ = currentTime;
    }
}

void WebGPURenderer::Present() {
    // Surface presentation would happen here
    // For Emscripten/WebGPU, this is handled by the browser's animation loop
}

} // namespace pixelocity
