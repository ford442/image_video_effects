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
#include <string>
#include <memory>
#include <iterator>

namespace pixelocity {

using wasm_internal::MakeStringView;
using wasm_internal::AlignUp;
using wasm_internal::CheckLimit;
using wasm_internal::ParseWorkgroupSize;
using wasm_internal::AnalyzeShaderBindings;
using wasm_internal::RewriteWgslStorageFormats;
using wasm_internal::ContainsWgslIncludeDirective;

namespace {
WGPUTextureFormat RgbaStorageFormat(policy::InternalColorFormat fmt) {
    return fmt == policy::InternalColorFormat::Rgba16Float
        ? WGPUTextureFormat_RGBA16Float
        : WGPUTextureFormat_RGBA32Float;
}

// ─── Compute binding table (group 0, bindings 0–13) ──────────────────────────
// One table drives both the bind group layout and every compute bind group,
// so the two can no longer drift. Authoritative list: docs/BINDING_CONTRACT.md.
enum class BindingKind : uint8_t {
    FilteringSampler,
    NonFilteringSampler,
    ComparisonSampler,
    SampledRgba,       // texture_2d<f32>, tier rgba format
    SampledRgbaArray,  // texture_2d_array<f32>, tier rgba format
    SampledR32,        // texture_2d<f32>, r32float
    StorageRgba,       // texture_storage_2d<tier rgba, write>
    StorageR32,        // texture_storage_2d<r32float, write>
    UniformBuffer,
    StorageBuffer,
    ReadOnlyStorageBuffer,
};

// Which renderer object fills the binding. Input/Output are per-pass (the
// slot's read/write textures); everything else is a shared global.
enum class BindingResource : uint8_t {
    FilteringSampler, NonFilteringSampler, ComparisonSampler,
    Input, Output, Uniforms, DepthRead, DepthWrite,
    DataA, DataB, DataC, Extra, Plasma, History,
};

struct ComputeBinding {
    uint32_t binding;
    BindingKind kind;
    BindingResource resource;
};

constexpr ComputeBinding kComputeBindings[] = {
    {  0, BindingKind::FilteringSampler,      BindingResource::FilteringSampler },
    {  1, BindingKind::SampledRgba,           BindingResource::Input },
    {  2, BindingKind::StorageRgba,           BindingResource::Output },
    {  3, BindingKind::UniformBuffer,         BindingResource::Uniforms },
    {  4, BindingKind::SampledR32,            BindingResource::DepthRead },
    {  5, BindingKind::NonFilteringSampler,   BindingResource::NonFilteringSampler },
    {  6, BindingKind::StorageR32,            BindingResource::DepthWrite },
    {  7, BindingKind::StorageRgba,           BindingResource::DataA },
    {  8, BindingKind::StorageRgba,           BindingResource::DataB },
    {  9, BindingKind::SampledRgba,           BindingResource::DataC },
    { 10, BindingKind::StorageBuffer,         BindingResource::Extra },
    { 11, BindingKind::ComparisonSampler,     BindingResource::ComparisonSampler },
    { 12, BindingKind::ReadOnlyStorageBuffer, BindingResource::Plasma },
    { 13, BindingKind::SampledRgbaArray,      BindingResource::History },
};
constexpr size_t kComputeBindingCount = std::size(kComputeBindings);
static_assert(kComputeBindingCount == 14, "compute bind group contract is bindings 0-13");

constexpr bool BindingsAreDense() {
    for (size_t i = 0; i < kComputeBindingCount; ++i) {
        if (kComputeBindings[i].binding != i) return false;
    }
    return true;
}
static_assert(BindingsAreDense(), "kComputeBindings must list bindings 0..13 in order");
}  // namespace

bool WebGPURenderer::CreateBindGroupLayout() {
    // Layout entries come straight from kComputeBindings (see the table above).
    std::array<WGPUBindGroupLayoutEntry, kComputeBindingCount> entries{};
    for (size_t i = 0; i < kComputeBindingCount; ++i) {
        const ComputeBinding& b = kComputeBindings[i];
        WGPUBindGroupLayoutEntry e = WGPU_BIND_GROUP_LAYOUT_ENTRY_INIT;
        e.binding = b.binding;
        e.visibility = WGPUShaderStage_Compute;
        switch (b.kind) {
            case BindingKind::FilteringSampler:
                e.sampler.type = WGPUSamplerBindingType_Filtering; break;
            case BindingKind::NonFilteringSampler:
                e.sampler.type = WGPUSamplerBindingType_NonFiltering; break;
            case BindingKind::ComparisonSampler:
                e.sampler.type = WGPUSamplerBindingType_Comparison; break;
            case BindingKind::SampledRgba:
            case BindingKind::SampledR32:
                e.texture.sampleType = WGPUTextureSampleType_Float;
                e.texture.viewDimension = WGPUTextureViewDimension_2D;
                break;
            case BindingKind::SampledRgbaArray:
                e.texture.sampleType = WGPUTextureSampleType_Float;
                e.texture.viewDimension = WGPUTextureViewDimension_2DArray;
                break;
            case BindingKind::StorageRgba:
            case BindingKind::StorageR32:
                e.storageTexture.access = WGPUStorageTextureAccess_WriteOnly;
                e.storageTexture.format = b.kind == BindingKind::StorageR32
                    ? WGPUTextureFormat_R32Float
                    : RgbaStorageFormat(colorFormat_);
                e.storageTexture.viewDimension = WGPUTextureViewDimension_2D;
                break;
            case BindingKind::UniformBuffer:
                e.buffer.type = WGPUBufferBindingType_Uniform; break;
            case BindingKind::StorageBuffer:
                e.buffer.type = WGPUBufferBindingType_Storage; break;
            case BindingKind::ReadOnlyStorageBuffer:
                e.buffer.type = WGPUBufferBindingType_ReadOnlyStorage; break;
        }
        entries[i] = e;
    }

    WGPUBindGroupLayoutDescriptor layoutDesc = WGPU_BIND_GROUP_LAYOUT_DESCRIPTOR_INIT;
    layoutDesc.nextInChain = nullptr;
    layoutDesc.label = MakeStringView("Compute Bind Group Layout");
    layoutDesc.entryCount = kComputeBindingCount;
    layoutDesc.entries = entries.data();

    computeBindGroupLayout_.reset(wgpuDeviceCreateBindGroupLayout(device_.get(), &layoutDesc));
    if (!computeBindGroupLayout_.get()) {
        printf("❌ Failed to create compute bind group layout\n");
        lastError_ = "wgpuDeviceCreateBindGroupLayout returned null";
        return false;
    }

    // Create pipeline layout
    WGPUBindGroupLayout rawLayout = computeBindGroupLayout_.get();
    WGPUPipelineLayoutDescriptor pipelineLayoutDesc = WGPU_PIPELINE_LAYOUT_DESCRIPTOR_INIT;
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

    WGPUShaderSourceWGSL wgslSource = WGPU_SHADER_SOURCE_WGSL_INIT;
    wgslSource.chain.next = nullptr;
    wgslSource.chain.sType = WGPUSType_ShaderSourceWGSL;

    WGPUShaderModuleDescriptor shaderDesc = WGPU_SHADER_MODULE_DESCRIPTOR_INIT;
    shaderDesc.nextInChain = reinterpret_cast<WGPUChainedStruct*>(&wgslSource);
    wgslSource.code = MakeStringView(vertexShaderCode);
    shaderDesc.label = MakeStringView("Vertex Shader");
    WGPUShaderModuleHandle vertexModule(wgpuDeviceCreateShaderModule(device_.get(), &shaderDesc));

    wgslSource.code = MakeStringView(fragmentShaderCode);
    shaderDesc.label = MakeStringView("Fragment Shader");
    WGPUShaderModuleHandle fragmentModule(wgpuDeviceCreateShaderModule(device_.get(), &shaderDesc));

    // Create render pipeline
    WGPUBlendState blend = WGPU_BLEND_STATE_INIT;
    blend.color.operation = WGPUBlendOperation_Add;
    blend.color.srcFactor = WGPUBlendFactor_One;
    blend.color.dstFactor = WGPUBlendFactor_Zero;
    blend.alpha.operation = WGPUBlendOperation_Add;
    blend.alpha.srcFactor = WGPUBlendFactor_One;
    blend.alpha.dstFactor = WGPUBlendFactor_Zero;

    WGPUColorTargetState colorTarget = WGPU_COLOR_TARGET_STATE_INIT;
    colorTarget.nextInChain = nullptr;
    colorTarget.format = surfaceFormat_;
    colorTarget.blend = &blend;
    colorTarget.writeMask = WGPUColorWriteMask_All;

    WGPUFragmentState fragmentState = WGPU_FRAGMENT_STATE_INIT;
    fragmentState.nextInChain = nullptr;
    fragmentState.module = fragmentModule.get();
    fragmentState.entryPoint = MakeStringView("fs_main");
    fragmentState.targetCount = 1;
    fragmentState.targets = &colorTarget;

    WGPUPrimitiveState primitiveState = WGPU_PRIMITIVE_STATE_INIT;
    primitiveState.nextInChain = nullptr;
    primitiveState.topology = WGPUPrimitiveTopology_TriangleStrip;
    primitiveState.stripIndexFormat = WGPUIndexFormat_Undefined;
    primitiveState.frontFace = WGPUFrontFace_CCW;
    primitiveState.cullMode = WGPUCullMode_None;

    WGPUMultisampleState multisampleState = WGPU_MULTISAMPLE_STATE_INIT;
    multisampleState.nextInChain = nullptr;
    multisampleState.count = 1;
    multisampleState.mask = 0xFFFFFFFF;

    WGPUVertexState vertexState = WGPU_VERTEX_STATE_INIT;
    vertexState.nextInChain = nullptr;
    vertexState.module = vertexModule.get();
    vertexState.entryPoint = MakeStringView("vs_main");
    vertexState.bufferCount = 0;
    vertexState.buffers = nullptr;

    WGPURenderPipelineDescriptor pipelineDesc = WGPU_RENDER_PIPELINE_DESCRIPTOR_INIT;
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

    // Compute bind groups are built per slot in Render() (they differ only in
    // bindings 1/2). Build one here anyway so a texture or layout mismatch
    // fails Initialize instead of the first frame.
    WGPUBindGroupHandle probe(CreateComputeBindGroup(readTexture_.get(), writeTexture_.get()));
    if (!probe.get()) {
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
    WGPUBindGroupLayoutHandle layout(
        wgpuRenderPipelineGetBindGroupLayout(renderPipeline_.get(), 0));
    if (!layout) return;

    WGPUTextureViewDescriptor viewDesc = WGPU_TEXTURE_VIEW_DESCRIPTOR_INIT;
    viewDesc.format          = RgbaStorageFormat(colorFormat_);
    viewDesc.dimension       = WGPUTextureViewDimension_2D;
    viewDesc.baseMipLevel    = 0;
    viewDesc.mipLevelCount   = 1;
    viewDesc.baseArrayLayer  = 0;
    viewDesc.arrayLayerCount = 1;
    viewDesc.aspect          = WGPUTextureAspect_All;

    WGPUTextureViewHandle texView(wgpuTextureCreateView(writeTexture_.get(), &viewDesc));

    WGPUBindGroupEntry entry = WGPU_BIND_GROUP_ENTRY_INIT;
    entry.binding     = 0;
    entry.textureView = texView;

    WGPUBindGroupDescriptor bgDesc = WGPU_BIND_GROUP_DESCRIPTOR_INIT;
    bgDesc.label      = MakeStringView("Render Bind Group");
    bgDesc.layout     = layout;
    bgDesc.entryCount = 1;
    bgDesc.entries    = &entry;

    renderBindGroup_.reset(wgpuDeviceCreateBindGroup(device_.get(), &bgDesc));
}

// ─── Surface configuration ────────────────────────────────────────────────────
//
// (Re-)configures the WebGPU swap chain with the current canvas dimensions.
// Called once during initialisation and again whenever the canvas is resized.

WGPUBindGroup WebGPURenderer::CreateComputeBindGroup(WGPUTexture readTex, WGPUTexture writeTex) {
    auto textureFor = [&](BindingResource r) -> WGPUTexture {
        switch (r) {
            case BindingResource::Input:      return readTex;
            case BindingResource::Output:     return writeTex;
            case BindingResource::DepthRead:  return depthTextureRead_.get();
            case BindingResource::DepthWrite: return depthTextureWrite_.get();
            case BindingResource::DataA:      return dataTextureA_.get();
            case BindingResource::DataB:      return dataTextureB_.get();
            case BindingResource::DataC:      return dataTextureC_.get();
            case BindingResource::History:    return historyTexture_.get();
            default:                          return nullptr;
        }
    };
    auto samplerFor = [&](BindingResource r) -> WGPUSampler {
        switch (r) {
            case BindingResource::FilteringSampler:    return filteringSampler_.get();
            case BindingResource::NonFilteringSampler: return nonFilteringSampler_.get();
            case BindingResource::ComparisonSampler:   return comparisonSampler_.get();
            default:                                   return nullptr;
        }
    };
    auto bufferFor = [&](BindingResource r) -> WGPUBuffer {
        switch (r) {
            case BindingResource::Uniforms: return uniformBuffer_.get();
            case BindingResource::Extra:    return extraBuffer_.get();
            case BindingResource::Plasma:   return plasmaBuffer_.get();
            default:                        return nullptr;
        }
    };

    std::array<WGPUBindGroupEntry, kComputeBindingCount> entries{};
    // Views only need to live until the bind group holds its own references.
    std::array<WGPUTextureViewHandle, kComputeBindingCount> views;
    for (size_t i = 0; i < kComputeBindingCount; ++i) {
        const ComputeBinding& b = kComputeBindings[i];
        WGPUBindGroupEntry e = WGPU_BIND_GROUP_ENTRY_INIT;
        e.binding = b.binding;
        switch (b.kind) {
            case BindingKind::FilteringSampler:
            case BindingKind::NonFilteringSampler:
            case BindingKind::ComparisonSampler:
                e.sampler = samplerFor(b.resource);
                break;
            case BindingKind::UniformBuffer:
            case BindingKind::StorageBuffer:
            case BindingKind::ReadOnlyStorageBuffer: {
                WGPUBuffer buf = bufferFor(b.resource);
                e.buffer = buf;
                e.offset = 0;
                e.size = buf ? wgpuBufferGetSize(buf) : 0;
                break;
            }
            case BindingKind::SampledRgba:
            case BindingKind::SampledRgbaArray:
            case BindingKind::SampledR32:
            case BindingKind::StorageRgba:
            case BindingKind::StorageR32: {
                const bool r32 = b.kind == BindingKind::SampledR32 || b.kind == BindingKind::StorageR32;
                const bool array = b.kind == BindingKind::SampledRgbaArray;
                WGPUTextureViewDescriptor view = WGPU_TEXTURE_VIEW_DESCRIPTOR_INIT;
                view.format = r32 ? WGPUTextureFormat_R32Float : RgbaStorageFormat(colorFormat_);
                view.dimension = array ? WGPUTextureViewDimension_2DArray : WGPUTextureViewDimension_2D;
                view.baseMipLevel = 0;
                view.mipLevelCount = 1;
                view.baseArrayLayer = 0;
                view.arrayLayerCount = array ? historyLayerCount_ : 1;
                view.aspect = WGPUTextureAspect_All;
                views[i].reset(wgpuTextureCreateView(textureFor(b.resource), &view));
                e.textureView = views[i];
                break;
            }
        }
        entries[i] = e;
    }

    WGPUBindGroupDescriptor bgDesc = WGPU_BIND_GROUP_DESCRIPTOR_INIT;
    bgDesc.label      = MakeStringView("Compute Bind Group");
    bgDesc.layout     = computeBindGroupLayout_.get();
    bgDesc.entryCount = kComputeBindingCount;
    bgDesc.entries    = entries.data();
    return wgpuDeviceCreateBindGroup(device_.get(), &bgDesc);
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
                                          int32_t timestampBeginIndex,
                                          int32_t timestampEndIndex) {
    if (!pipeline || !bindGroup) return;
    WGPUComputePassDescriptor cpDesc = WGPU_COMPUTE_PASS_DESCRIPTOR_INIT;
    cpDesc.label = MakeStringView("Compute Pass");
    // Browsers only support pass-descriptor timestamps (no pass.writeTimestamp).
    WGPUPassTimestampWrites stamps = WGPU_PASS_TIMESTAMP_WRITES_INIT;
    if (supportsTimestampQuery_ && timestampQuerySet_.get()
        && (timestampBeginIndex >= 0 || timestampEndIndex >= 0)) {
        stamps.querySet = timestampQuerySet_.get();
        if (timestampBeginIndex >= 0) {
            stamps.beginningOfPassWriteIndex = static_cast<uint32_t>(timestampBeginIndex);
        }
        if (timestampEndIndex >= 0) {
            stamps.endOfPassWriteIndex = static_cast<uint32_t>(timestampEndIndex);
        }
        cpDesc.timestampWrites = &stamps;
    }
    WGPUComputePassEncoderHandle cp(wgpuCommandEncoderBeginComputePass(encoder, &cpDesc));
    wgpuComputePassEncoderSetPipeline(cp, pipeline);
    wgpuComputePassEncoderSetBindGroup(cp, 0, bindGroup, 0, nullptr);
    wgpuComputePassEncoderDispatchWorkgroups(
        cp,
        (static_cast<uint32_t>(canvasWidth_)  + workgroupX - 1u) / workgroupX,
        (static_cast<uint32_t>(canvasHeight_) + workgroupY - 1u) / workgroupY,
        1);
    wgpuComputePassEncoderEnd(cp);
}

bool WebGPURenderer::LoadShader(const char* id, const char* wgslCode) {
    if (!device_.get() || deviceLost_) return false;

    // Check if already loaded
    if (shaders_.find(id) != shaders_.end()) {
        return true;
    }

    // C++ deliberately has no #include parser: every byte of WGSL arrives here
    // from src/wasm/bridge/shader.ts, which already expanded it. Growing a
    // second parser would mean two dialects to keep in sync, so instead we fail
    // loudly if a directive survived. See src/contracts/wgsl_include.json.
    if (ContainsWgslIncludeDirective(wgslCode)) {
        printf("❌ Shader '%s' still contains an unexpanded #include directive\n", id);
        lastError_ = std::string("unexpanded #include in shader: ") + id;
        return false;
    }

    const char* fmtName = colorFormat_ == policy::InternalColorFormat::Rgba16Float
        ? "rgba16float"
        : "rgba32float";
    const std::string rewritten = RewriteWgslStorageFormats(wgslCode, fmtName);
    const char* compiledWgsl = rewritten.empty() ? wgslCode : rewritten.c_str();

    // Create shader module
    WGPUShaderSourceWGSL wgslSource = WGPU_SHADER_SOURCE_WGSL_INIT;
    wgslSource.chain.next = nullptr;
    wgslSource.chain.sType = WGPUSType_ShaderSourceWGSL;
    wgslSource.code = MakeStringView(compiledWgsl);

    WGPUShaderModuleDescriptor shaderDesc = WGPU_SHADER_MODULE_DESCRIPTOR_INIT;
    shaderDesc.nextInChain = reinterpret_cast<WGPUChainedStruct*>(&wgslSource);
    shaderDesc.label = MakeStringView(id);
    WGPUShaderModuleHandle module(wgpuDeviceCreateShaderModule(device_.get(), &shaderDesc));
    if (!module.get()) {
        printf("❌ Failed to create shader module for '%s'\n", id);
        lastError_ = std::string("shader module create failed: ") + id;
        return false;
    }

    // Request compilation info to surface WGSL errors/warnings in the console.
    // This is asynchronous but the uncaptured-error callback will also fire for
    // hard errors.  We use WGPUCallbackMode_AllowSpontaneous so the messages
    // arrive whenever the browser processes them.
    //
    // `id` is borrowed from the JS bridge, which frees it as soon as the
    // loadShader ccall returns, so the callback gets its own heap copy.
    // WebGPU invokes every callback exactly once (with a cancelled status on
    // teardown), so the callback is the sole owner and frees it.
    auto* ownedLabel = new std::string(id);
    wgpuShaderModuleGetCompilationInfo(
        module.get(),
        WGPUCompilationInfoCallbackInfo{
            nullptr,
            WGPUCallbackMode_AllowSpontaneous,
            [](WGPUCompilationInfoRequestStatus /*status*/,
               WGPUCompilationInfo const* info,
               void* userdata1, void* /*userdata2*/) {
                std::unique_ptr<std::string> label(static_cast<std::string*>(userdata1));
                const char* shaderLabel = label->c_str();
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
            ownedLabel, nullptr
        });

    // Create compute pipeline. Dawn may return a non-null invalid object on
    // format mismatch — catch Validation via error scope and do not store it.
    WGPUComputePipelineDescriptor pipelineDesc = WGPU_COMPUTE_PIPELINE_DESCRIPTOR_INIT;
    pipelineDesc.nextInChain = nullptr;
    pipelineDesc.label = MakeStringView(id);
    pipelineDesc.layout = computePipelineLayout_.get();
    pipelineDesc.compute.module = module.get();
    pipelineDesc.compute.entryPoint = MakeStringView("main");

    wgpuDevicePushErrorScope(device_.get(), WGPUErrorFilter_Validation);
    WGPUComputePipelineHandle pipeline(wgpuDeviceCreateComputePipeline(device_.get(), &pipelineDesc));

    struct PopResult { bool hadError = false; };
    PopResult pop;
    auto popCb = [](WGPUPopErrorScopeStatus status, WGPUErrorType type,
                    WGPUStringView message, void* userdata1, void* /*userdata2*/) {
        auto* out = static_cast<PopResult*>(userdata1);
        const bool okStatus = status == WGPUPopErrorScopeStatus_Success;
        const bool isGpuError = type == WGPUErrorType_Validation
            || type == WGPUErrorType_OutOfMemory
            || type == WGPUErrorType_Internal;
        if (!okStatus || isGpuError) {
            out->hadError = true;
            if (message.data && message.length > 0) {
                printf("[WASM] CreateComputePipeline invalid: %.*s\n",
                       (int)message.length, message.data);
            }
        }
    };
    bool waitFailed = false;
    if (instance_.get()) {
        WGPUFuture popFuture = wgpuDevicePopErrorScope(device_.get(), WGPUPopErrorScopeCallbackInfo{
            nullptr, WGPUCallbackMode_WaitAnyOnly, popCb, &pop, nullptr
        });
        WGPUFutureWaitInfo popWait = WGPU_FUTURE_WAIT_INFO_INIT;
        popWait.future = popFuture;
        const WGPUWaitStatus waitStatus =
            wgpuInstanceWaitAny(instance_.get(), 1, &popWait, UINT64_MAX);
        if (waitStatus != WGPUWaitStatus_Success) {
            waitFailed = true;
            printf("[WASM] CreateComputePipeline error-scope WaitAny status=%d — treat as invalid\n",
                   (int)waitStatus);
        }
    } else {
        waitFailed = true;
        // Spontaneous pop outlives this frame, so it must not point at `pop`.
        wgpuDevicePopErrorScope(device_.get(), WGPUPopErrorScopeCallbackInfo{
            nullptr, WGPUCallbackMode_AllowSpontaneous,
            [](WGPUPopErrorScopeStatus, WGPUErrorType, WGPUStringView, void*, void*) {},
            nullptr, nullptr
        });
        printf("[WASM] CreateComputePipeline: no instance for WaitAny — treat as invalid\n");
    }

    if (!pipeline.get() || pop.hadError || waitFailed) {
        printf("❌ CreateComputePipeline invalid for '%s' — skip slot, do not submit\n", id);
        lastError_ = std::string("CreateComputePipeline invalid: ") + id
            + " (storage format vs bind-group layout). Slot skipped.";
        pipeline.reset();
        return false;
    }

    ShaderPipeline sp;
    sp.module   = std::move(module);
    sp.pipeline = std::move(pipeline);
    sp.id       = id;
    sp.name     = id;
    ParseWorkgroupSize(compiledWgsl, sp.workgroupX, sp.workgroupY);
    const auto usage = AnalyzeShaderBindings(compiledWgsl);
    sp.writesDataA = usage.writesDataA;
    sp.writesDataB = usage.writesDataB;
    sp.readsDataC = usage.readsDataC;
    sp.usesHistory = usage.usesHistory;
    sp.writesDepth = usage.writesDepth;
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
