#include "renderer.h"
#include "performance_policy.h"
#include "wasm_internal.h"
#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <array>
#include <algorithm>
#include <vector>

namespace pixelocity {

using wasm_internal::MakeStringView;
using wasm_internal::AlignUp;
using wasm_internal::CheckLimit;
using wasm_internal::ParseWorkgroupSize;
using wasm_internal::AnalyzeShaderBindings;

namespace {
WGPUTextureFormat RgbaStorageFormat(policy::InternalColorFormat fmt) {
    return fmt == policy::InternalColorFormat::Rgba16Float
        ? WGPUTextureFormat_RGBA16Float
        : WGPUTextureFormat_RGBA32Float;
}
}  // namespace

bool WebGPURenderer::CreateBindGroupLayout() {
    // 14 bindings (0–13) matching the universal compute shader layout.
    // See docs/BINDING_CONTRACT.md for the authoritative list.
    static constexpr uint32_t BINDING_COUNT = 14;
    WGPUBindGroupLayoutEntry entries[BINDING_COUNT] = {};
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
    entries[2].storageTexture.format = RgbaStorageFormat(colorFormat_);
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
    entries[7].storageTexture.format = RgbaStorageFormat(colorFormat_);
    entries[7].storageTexture.viewDimension = WGPUTextureViewDimension_2D;
    
    // Binding 8: Data texture B (write)
    entries[8].binding = 8;
    entries[8].visibility = WGPUShaderStage_Compute;
    entries[8].storageTexture.access = WGPUStorageTextureAccess_WriteOnly;
    entries[8].storageTexture.format = RgbaStorageFormat(colorFormat_);
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

    // Binding 13: History ring (2d-array texture, opt-in temporal shaders)
    entries[13].binding = 13;
    entries[13].visibility = WGPUShaderStage_Compute;
    entries[13].texture.sampleType = WGPUTextureSampleType_Float;
    entries[13].texture.viewDimension = WGPUTextureViewDimension_2DArray;

    WGPUBindGroupLayoutDescriptor layoutDesc = {};
    layoutDesc.nextInChain = nullptr;
    layoutDesc.label = MakeStringView("Compute Bind Group Layout");
    layoutDesc.entryCount = BINDING_COUNT;
    layoutDesc.entries = entries;

    computeBindGroupLayout_.reset(wgpuDeviceCreateBindGroupLayout(device_.get(), &layoutDesc));
    if (!computeBindGroupLayout_.get()) {
        printf("❌ Failed to create compute bind group layout\n");
        lastError_ = "wgpuDeviceCreateBindGroupLayout returned null";
        return false;
    }

    // Create pipeline layout
    WGPUBindGroupLayout rawLayout = computeBindGroupLayout_.get();
    WGPUPipelineLayoutDescriptor pipelineLayoutDesc = {};
    pipelineLayoutDesc.nextInChain = nullptr;
    pipelineLayoutDesc.label = MakeStringView("Compute Pipeline Layout");
    pipelineLayoutDesc.bindGroupLayoutCount = 1;
    pipelineLayoutDesc.bindGroupLayouts = &rawLayout;

    computePipelineLayout_.reset(wgpuDeviceCreatePipelineLayout(device_.get(), &pipelineLayoutDesc));
    if (!computePipelineLayout_.get()) {
        printf("❌ Failed to create compute pipeline layout\n");
        lastError_ = "wgpuDeviceCreatePipelineLayout returned null";
        return false;
    }
    return true;
}

bool WebGPURenderer::CreateRenderPipeline() {
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

    // Fragment shader to blit the write texture to the swapchain.
    // Uses textureLoad (integer coordinates) instead of textureSample so that
    // we avoid the 'float32-filterable' device feature requirement — RGBA32Float
    // textures are storage-only by default in WebGPU.
    const char* fragmentShaderCode = R"(
        @group(0) @binding(0) var u_texture: texture_2d<f32>;

        @fragment
        fn fs_main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
            let coord = vec2<i32>(fragCoord.xy);
            return textureLoad(u_texture, coord, 0);
        }
    )";

    WGPUShaderSourceWGSL wgslSource = {};
    wgslSource.chain.next = nullptr;
    wgslSource.chain.sType = WGPUSType_ShaderSourceWGSL;

    WGPUShaderModuleDescriptor shaderDesc = {};
    shaderDesc.nextInChain = reinterpret_cast<WGPUChainedStruct*>(&wgslSource);
    wgslSource.code = MakeStringView(vertexShaderCode);
    shaderDesc.label = MakeStringView("Vertex Shader");
    WGPUShaderModuleHandle vertexModule(wgpuDeviceCreateShaderModule(device_.get(), &shaderDesc));

    wgslSource.code = MakeStringView(fragmentShaderCode);
    shaderDesc.label = MakeStringView("Fragment Shader");
    WGPUShaderModuleHandle fragmentModule(wgpuDeviceCreateShaderModule(device_.get(), &shaderDesc));

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
    colorTarget.format = surfaceFormat_;
    colorTarget.blend = &blend;
    colorTarget.writeMask = WGPUColorWriteMask_All;

    WGPUFragmentState fragmentState = {};
    fragmentState.nextInChain = nullptr;
    fragmentState.module = fragmentModule.get();
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
    vertexState.module = vertexModule.get();
    vertexState.entryPoint = MakeStringView("vs_main");
    vertexState.bufferCount = 0;
    vertexState.buffers = nullptr;

    WGPURenderPipelineDescriptor pipelineDesc = {};
    pipelineDesc.nextInChain = nullptr;
    pipelineDesc.label = MakeStringView("Render Pipeline");
    pipelineDesc.layout = nullptr;  // auto layout (inferred from shader)
    pipelineDesc.vertex = vertexState;
    pipelineDesc.primitive = primitiveState;
    pipelineDesc.depthStencil = nullptr;
    pipelineDesc.multisample = multisampleState;
    pipelineDesc.fragment = &fragmentState;

    renderPipeline_.reset(wgpuDeviceCreateRenderPipeline(device_.get(), &pipelineDesc));
    // vertexModule and fragmentModule are released automatically via RAII
    if (!renderPipeline_.get()) {
        printf("❌ Failed to create render pipeline\n");
        lastError_ = "wgpuDeviceCreateRenderPipeline returned null";
        return false;
    }
    return true;
}

bool WebGPURenderer::CreateBindGroups() {
    if (!writeTexture_.get() || !uniformBuffer_.get()) {
        lastError_ = "CreateBindGroups called before textures/buffers were created";
        return false;
    }

    static constexpr uint32_t BINDING_COUNT = 14;
    WGPUTextureViewDescriptor viewDesc = {};
    viewDesc.nextInChain = nullptr;
    viewDesc.label = MakeStringView(nullptr);
    viewDesc.format = RgbaStorageFormat(colorFormat_);
    viewDesc.dimension = WGPUTextureViewDimension_2D;
    viewDesc.baseMipLevel = 0;
    viewDesc.mipLevelCount = 1;
    viewDesc.baseArrayLayer = 0;
    viewDesc.arrayLayerCount = 1;
    viewDesc.aspect = WGPUTextureAspect_All;

    WGPUBindGroupEntry entries[BINDING_COUNT] = {};
    entries[0].binding = 0;
    entries[0].sampler = filteringSampler_.get();

    entries[1].binding = 1;
    entries[1].textureView = wgpuTextureCreateView(readTexture_.get(), &viewDesc);

    entries[2].binding = 2;
    entries[2].textureView = wgpuTextureCreateView(writeTexture_.get(), &viewDesc);

    entries[3].binding = 3;
    entries[3].buffer = uniformBuffer_.get();
    entries[3].offset = 0;
    entries[3].size = wgpuBufferGetSize(uniformBuffer_.get());

    entries[4].binding = 4;
    viewDesc.format = WGPUTextureFormat_R32Float;
    entries[4].textureView = wgpuTextureCreateView(depthTextureRead_.get(), &viewDesc);

    entries[5].binding = 5;
    entries[5].sampler = nonFilteringSampler_.get();

    entries[6].binding = 6;
    entries[6].textureView = wgpuTextureCreateView(depthTextureWrite_.get(), &viewDesc);

    entries[7].binding = 7;
    viewDesc.format = RgbaStorageFormat(colorFormat_);
    entries[7].textureView = wgpuTextureCreateView(dataTextureA_.get(), &viewDesc);

    entries[8].binding = 8;
    entries[8].textureView = wgpuTextureCreateView(dataTextureB_.get(), &viewDesc);

    entries[9].binding = 9;
    entries[9].textureView = wgpuTextureCreateView(dataTextureC_.get(), &viewDesc);

    entries[10].binding = 10;
    entries[10].buffer = extraBuffer_.get();
    entries[10].offset = 0;
    entries[10].size = wgpuBufferGetSize(extraBuffer_.get());

    entries[11].binding = 11;
    entries[11].sampler = comparisonSampler_.get();

    entries[12].binding = 12;
    entries[12].buffer = plasmaBuffer_.get();
    entries[12].offset = 0;
    entries[12].size = wgpuBufferGetSize(plasmaBuffer_.get());

    entries[13].binding = 13;
    WGPUTextureViewDescriptor historyView = {};
    historyView.format = RgbaStorageFormat(colorFormat_);
    historyView.dimension = WGPUTextureViewDimension_2DArray;
    historyView.baseMipLevel = 0;
    historyView.mipLevelCount = 1;
    historyView.baseArrayLayer = 0;
    historyView.arrayLayerCount = HISTORY_DEPTH;
    historyView.aspect = WGPUTextureAspect_All;
    entries[13].textureView = wgpuTextureCreateView(historyTexture_.get(), &historyView);

    WGPUBindGroupDescriptor bindGroupDesc = {};
    bindGroupDesc.nextInChain = nullptr;
    bindGroupDesc.label = MakeStringView("Compute Bind Group");
    bindGroupDesc.layout = computeBindGroupLayout_.get();
    bindGroupDesc.entryCount = BINDING_COUNT;
    bindGroupDesc.entries = entries;

    computeBindGroup_.reset(wgpuDeviceCreateBindGroup(device_.get(), &bindGroupDesc));

    // Release texture views (bind group holds its own references)
    for (uint32_t i = 0; i < BINDING_COUNT; i++) {
        if (entries[i].textureView) {
            wgpuTextureViewRelease(entries[i].textureView);
        }
    }

    if (!computeBindGroup_.get()) {
        printf("❌ Failed to create compute bind group\n");
        lastError_ = "wgpuDeviceCreateBindGroup (compute) returned null";
        return false;
    }

    // Create the render bind group used for surface presentation.
    CreateRenderBindGroup();
    if (!renderBindGroup_.get()) {
        printf("❌ Failed to create render bind group\n");
        lastError_ = "CreateRenderBindGroup failed (null render bind group)";
        return false;
    }
    return true;
}

// ─── Render bind group for surface presentation ───────────────────────────────
//
// The render pipeline's fragment shader only binds one texture (writeTexture_)
// at group 0, binding 0.  We derive the layout automatically from the pipeline
// so we never need to maintain a separate WGPUBindGroupLayout for it.

void WebGPURenderer::CreateRenderBindGroup() {
    if (!renderPipeline_.get() || !writeTexture_.get()) return;

    // Derive the auto-layout from the pipeline's group 0.
    WGPUBindGroupLayout layout =
        wgpuRenderPipelineGetBindGroupLayout(renderPipeline_.get(), 0);
    if (!layout) return;

    WGPUTextureViewDescriptor viewDesc = {};
    viewDesc.format          = RgbaStorageFormat(colorFormat_);
    viewDesc.dimension       = WGPUTextureViewDimension_2D;
    viewDesc.baseMipLevel    = 0;
    viewDesc.mipLevelCount   = 1;
    viewDesc.baseArrayLayer  = 0;
    viewDesc.arrayLayerCount = 1;
    viewDesc.aspect          = WGPUTextureAspect_All;

    WGPUTextureView texView =
        wgpuTextureCreateView(writeTexture_.get(), &viewDesc);

    WGPUBindGroupEntry entry = {};
    entry.binding     = 0;
    entry.textureView = texView;

    WGPUBindGroupDescriptor bgDesc = {};
    bgDesc.label      = MakeStringView("Render Bind Group");
    bgDesc.layout     = layout;
    bgDesc.entryCount = 1;
    bgDesc.entries    = &entry;

    renderBindGroup_.reset(wgpuDeviceCreateBindGroup(device_.get(), &bgDesc));

    wgpuTextureViewRelease(texView);
    wgpuBindGroupLayoutRelease(layout);
}

// ─── Surface configuration ────────────────────────────────────────────────────
//
// (Re-)configures the WebGPU swap chain with the current canvas dimensions.
// Called once during initialisation and again whenever the canvas is resized.

WGPUBindGroup WebGPURenderer::CreateComputeBindGroup(WGPUTexture readTex, WGPUTexture writeTex) {
    static constexpr uint32_t BINDING_COUNT = 14;
    WGPUTextureViewDescriptor rgbaView = {};
    rgbaView.format          = RgbaStorageFormat(colorFormat_);
    rgbaView.dimension       = WGPUTextureViewDimension_2D;
    rgbaView.baseMipLevel    = 0;
    rgbaView.mipLevelCount   = 1;
    rgbaView.baseArrayLayer  = 0;
    rgbaView.arrayLayerCount = 1;
    rgbaView.aspect          = WGPUTextureAspect_All;

    WGPUTextureViewDescriptor r32View = rgbaView;
    r32View.format = WGPUTextureFormat_R32Float;

    WGPUBindGroupEntry entries[BINDING_COUNT] = {};

    entries[0].binding = 0;
    entries[0].sampler = filteringSampler_.get();

    entries[1].binding     = 1;
    entries[1].textureView = wgpuTextureCreateView(readTex, &rgbaView);

    entries[2].binding     = 2;
    entries[2].textureView = wgpuTextureCreateView(writeTex, &rgbaView);

    entries[3].binding = 3;
    entries[3].buffer  = uniformBuffer_.get();
    entries[3].offset  = 0;
    entries[3].size    = wgpuBufferGetSize(uniformBuffer_.get());

    entries[4].binding     = 4;
    entries[4].textureView = wgpuTextureCreateView(depthTextureRead_.get(), &r32View);

    entries[5].binding = 5;
    entries[5].sampler = nonFilteringSampler_.get();

    entries[6].binding     = 6;
    entries[6].textureView = wgpuTextureCreateView(depthTextureWrite_.get(), &r32View);

    entries[7].binding     = 7;
    entries[7].textureView = wgpuTextureCreateView(dataTextureA_.get(), &rgbaView);

    entries[8].binding     = 8;
    entries[8].textureView = wgpuTextureCreateView(dataTextureB_.get(), &rgbaView);

    entries[9].binding     = 9;
    entries[9].textureView = wgpuTextureCreateView(dataTextureC_.get(), &rgbaView);

    entries[10].binding = 10;
    entries[10].buffer  = extraBuffer_.get();
    entries[10].offset  = 0;
    entries[10].size    = wgpuBufferGetSize(extraBuffer_.get());

    entries[11].binding = 11;
    entries[11].sampler = comparisonSampler_.get();

    entries[12].binding = 12;
    entries[12].buffer  = plasmaBuffer_.get();
    entries[12].offset  = 0;
    entries[12].size    = wgpuBufferGetSize(plasmaBuffer_.get());

    entries[13].binding = 13;
    WGPUTextureViewDescriptor historyView = rgbaView;
    historyView.dimension = WGPUTextureViewDimension_2DArray;
    historyView.arrayLayerCount = HISTORY_DEPTH;
    entries[13].textureView = wgpuTextureCreateView(historyTexture_.get(), &historyView);

    WGPUBindGroupDescriptor bgDesc = {};
    bgDesc.label      = MakeStringView("Compute Bind Group");
    bgDesc.layout     = computeBindGroupLayout_.get();
    bgDesc.entryCount = BINDING_COUNT;
    bgDesc.entries    = entries;

    WGPUBindGroup bg = wgpuDeviceCreateBindGroup(device_.get(), &bgDesc);

    // Release texture views — the bind group holds its own references.
    for (uint32_t i = 0; i < BINDING_COUNT; i++) {
        if (entries[i].textureView) wgpuTextureViewRelease(entries[i].textureView);
    }
    return bg;
}

// Overwrite only the zoom_params portion (bytes 32-47) of the uniform buffer.
void WebGPURenderer::WriteSlotParams(const float* params) {
    if (!uniformBuffer_.get()) return;
    wgpuQueueWriteBuffer(queue_.get(), uniformBuffer_.get(), 32, params, 4 * sizeof(float));
}

// Dispatch a compute pass over the full canvas using the given workgroup dimensions.
void WebGPURenderer::DispatchComputePass(WGPUCommandEncoder encoder,
                                          WGPUComputePipeline pipeline,
                                          WGPUBindGroup bindGroup,
                                          uint32_t workgroupX,
                                          uint32_t workgroupY,
                                          int32_t timestampStartIndex,
                                          int32_t timestampEndIndexA,
                                          int32_t timestampEndIndexB) {
    WGPUComputePassDescriptor cpDesc = {};
    cpDesc.label = MakeStringView("Compute Pass");
    WGPUComputePassEncoder cp = wgpuCommandEncoderBeginComputePass(encoder, &cpDesc);
#ifdef WGPUFeatureName_TimestampQuery
    if (supportsTimestampQuery_ && timestampQuerySet_.get() && timestampStartIndex >= 0) {
        wgpuComputePassEncoderWriteTimestamp(cp, timestampQuerySet_.get(),
                                             static_cast<uint32_t>(timestampStartIndex));
    }
#endif
    wgpuComputePassEncoderSetPipeline(cp, pipeline);
    wgpuComputePassEncoderSetBindGroup(cp, 0, bindGroup, 0, nullptr);
    wgpuComputePassEncoderDispatchWorkgroups(
        cp,
        (static_cast<uint32_t>(canvasWidth_)  + workgroupX - 1u) / workgroupX,
        (static_cast<uint32_t>(canvasHeight_) + workgroupY - 1u) / workgroupY,
        1);
#ifdef WGPUFeatureName_TimestampQuery
    if (supportsTimestampQuery_ && timestampQuerySet_.get()) {
        if (timestampEndIndexA >= 0) {
            wgpuComputePassEncoderWriteTimestamp(cp, timestampQuerySet_.get(),
                                                 static_cast<uint32_t>(timestampEndIndexA));
        }
        if (timestampEndIndexB >= 0) {
            wgpuComputePassEncoderWriteTimestamp(cp, timestampQuerySet_.get(),
                                                 static_cast<uint32_t>(timestampEndIndexB));
        }
    }
#endif
    wgpuComputePassEncoderEnd(cp);
    wgpuComputePassEncoderRelease(cp);
}

bool WebGPURenderer::LoadShader(const char* id, const char* wgslCode) {
    if (!device_.get() || deviceLost_) return false;

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
    // which is not currently set up.
    WGPUShaderModuleHandle module(wgpuDeviceCreateShaderModule(device_.get(), &shaderDesc));
    if (!module.get()) {
        printf("❌ Failed to create shader module for '%s'\n", id);
        return false;
    }

    // Request compilation info to surface WGSL errors/warnings in the console.
    // This is asynchronous but the uncaptured-error callback will also fire for
    // hard errors.  We use WGPUCallbackMode_AllowSpontaneous so the messages
    // arrive whenever the browser processes them.
    wgpuShaderModuleGetCompilationInfo(
        module.get(),
        WGPUCompilationInfoCallbackInfo{
            nullptr,
            WGPUCallbackMode_AllowSpontaneous,
            [](WGPUCompilationInfoRequestStatus /*status*/,
               WGPUCompilationInfo const* info,
               void* userdata1, void* /*userdata2*/) {
                const char* shaderLabel = static_cast<const char*>(userdata1);
                if (!info) return;
                for (size_t i = 0; i < info->messageCount; i++) {
                    const WGPUCompilationMessage& msg = info->messages[i];
                    const char* sev = "info";
                    if (msg.type == WGPUCompilationMessageType_Error)   sev = "error";
                    if (msg.type == WGPUCompilationMessageType_Warning) sev = "warning";
                    printf("[Shader %s] %s at line %llu: %.*s\n",
                           shaderLabel, sev,
                           static_cast<unsigned long long>(msg.lineNum),
                           static_cast<int>(msg.message.length),
                           msg.message.data ? msg.message.data : "");
                }
            },
            // userdata1 points to the id string which remains valid for the lifetime of the module.
            const_cast<char*>(id), nullptr
        });

    // Create compute pipeline
    WGPUComputePipelineDescriptor pipelineDesc = {};
    pipelineDesc.nextInChain = nullptr;
    pipelineDesc.label = MakeStringView(id);
    pipelineDesc.layout = computePipelineLayout_.get();
    pipelineDesc.compute.module = module.get();
    pipelineDesc.compute.entryPoint = MakeStringView("main");

    WGPUComputePipelineHandle pipeline(wgpuDeviceCreateComputePipeline(device_.get(), &pipelineDesc));
    if (!pipeline.get()) {
        printf("❌ Failed to create compute pipeline for '%s'\n", id);
        return false;
    }

    ShaderPipeline sp;
    sp.module   = std::move(module);
    sp.pipeline = std::move(pipeline);
    sp.id       = id;
    sp.name     = id;
    ParseWorkgroupSize(wgslCode, sp.workgroupX, sp.workgroupY);
    const auto usage = AnalyzeShaderBindings(wgslCode);
    sp.writesDataA = usage.writesDataA;
    sp.writesDataB = usage.writesDataB;
    sp.readsDataC = usage.readsDataC;
    sp.usesHistory = usage.usesHistory;
    shaders_[id] = std::move(sp);

    printf("✅ Loaded shader: %s (workgroup: %ux%u)\n", id,
           shaders_[id].workgroupX, shaders_[id].workgroupY);
    return true;
}

bool WebGPURenderer::ReloadShader(const char* id, const char* wgslCode) {
    if (!device_.get() || deviceLost_ || !id || !wgslCode) return false;

    auto it = shaders_.find(id);
    if (it != shaders_.end()) {
        printf("♻️  Reloading shader: %s\n", id);
        shaders_.erase(it);
    }
    return LoadShader(id, wgslCode);
}


} // namespace pixelocity
