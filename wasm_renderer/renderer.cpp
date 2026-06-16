#include "renderer.h"
#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <emscripten/em_js.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <array>
#include <algorithm>

// ═══════════════════════════════════════════════════════════════════════════════
// renderer.cpp - WebGPU Compute Shader Renderer Implementation
// ═══════════════════════════════════════════════════════════════════════════════
//
// PURPOSE:
//   Implements the WebGPURenderer class for high-performance GPU image/video
//   processing using WebGPU compute shaders.
//
// STATUS (Phase 3):
//   ✅ WebGPU device initialization with device-lost and uncaptured-error callbacks
//   ✅ Single and multi-slot shader execution
//   ✅ Image/video upload with persistent staging buffer
//   ✅ Audio reactivity (bass/mid/treble uniforms)
//   ✅ Depth map integration
//   ✅ Canvas resize
//   ✅ Frame capture (async GPU→CPU readback)
//   ✅ RAII resource management via WGPUHandle<> wrappers
//   ✅ Shader compilation error reporting via GetCompilationInfo
//
// ARCHITECTURE:
//   Multi-pass ping-pong texture pipeline:
//     readTexture_ → Slot 0 → pingPong0_ → Slot 1 → pingPong1_ → Slot 2 → writeTexture_
//   Then: writeTexture_ → readTexture_ (temporal feedback for next frame)
//
// ═══════════════════════════════════════════════════════════════════════════════

namespace pixelocity {

// ─── JavaScript bridge: create a WebGPU surface from a canvas selector ────────
//
// Runs inside the WASM module's JS scope, so it has access to the internal
// WebGPU object (which manages JS↔WASM handle mapping).
//
// Returns the WASM surface handle (pointer-sized integer) on success, 0 on failure.
// The caller must cast the return value to WGPUSurface.
EM_JS(uint32_t, JS_CreateSurfaceFromCanvas, (const char* selectorPtr, WGPUDevice deviceHandle), {
    var selector = UTF8ToString(selectorPtr);
    var canvasEl = document.querySelector(selector);
    if (!canvasEl) {
        console.error('[WASM] Canvas not found for selector:', selector);
        return 0;
    }
    var ctx = canvasEl.getContext('webgpu');
    if (!ctx) {
        console.error('[WASM] Failed to get WebGPU canvas context');
        return 0;
    }
    var preferredFormat = (typeof navigator !== 'undefined' && navigator.gpu &&
                           typeof navigator.gpu.getPreferredCanvasFormat === 'function')
        ? navigator.gpu.getPreferredCanvasFormat()
        : 'bgra8unorm';
    var jsDevice = WebGPU.Internals.jsObjects[deviceHandle >>> 0];
    if (!jsDevice) {
        console.error('[WASM] Device JS object not found at handle', deviceHandle);
        return 0;
    }
    try {
        ctx.configure({
            device: jsDevice,
            format: preferredFormat,
            alphaMode: 'opaque',
            usage: GPUTextureUsage.RENDER_ATTACHMENT
        });
    } catch (err) {
        console.error('[WASM] Canvas context configure failed:', err);
        return 0;
    }
    var surfacePtr = WebGPU.importJsSurface(ctx);
    console.log('[WASM] \u2705 Canvas surface created, handle=', surfacePtr, ', format=', preferredFormat);
    return surfacePtr;
});

// \u2500\u2500\u2500 JavaScript bridge: query the browser's preferred canvas format \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
//
// Mirrors the `navigator.gpu.getPreferredCanvasFormat()` call made inside
// JS_CreateSurfaceFromCanvas above, so C++ can set surfaceFormat_ to match
// what ctx.configure() actually negotiated \u2014 *before* the surface is created.
// Returns 0=bgra8unorm, 1=rgba8unorm, -1=unknown.
EM_JS(int, JS_GetPreferredCanvasFormat, (), {
    var f = (navigator.gpu && navigator.gpu.getPreferredCanvasFormat)
        ? navigator.gpu.getPreferredCanvasFormat() : 'bgra8unorm';
    if (f === 'bgra8unorm') return 0;
    if (f === 'rgba8unorm') return 1;
    return -1;
});

// Helper for WGPUStringView (emdawnwebgpu uses this instead of const char*)
static WGPUStringView MakeStringView(const char* str) {
    WGPUStringView view;
    view.data = str;
    view.length = str ? strlen(str) : 0;
    return view;
}

// WGPU_DEPTH_SLICE_UNDEFINED was added in the 2024 WebGPU spec update; provide
// a fallback if the installed header predates the addition.
#ifndef WGPU_DEPTH_SLICE_UNDEFINED
static constexpr uint32_t WGPU_DEPTH_SLICE_UNDEFINED = 0xFFFFFFFFu;
#endif

// Round `value` up to the nearest multiple of `align` (must be a power-of-2).
static inline uint32_t AlignUp(uint32_t value, uint32_t align) {
    return (value + align - 1u) & ~(align - 1u);
}

// ── Adapter/device limit validation ────────────────────────────────────────
// Logs `name`, the reported value (`have`), and the minimum this renderer
// needs (`need`). If `have < need`, clears `ok` to false so the caller can
// fail CreateDevice() early with an actionable message instead of hitting
// cryptic resource-creation errors deep in CreateResources().
static bool CheckLimit(const char* name, uint64_t have, uint64_t need, bool& ok) {
    printf("[WASM]   %-40s have=%llu need=%llu %s\n", name,
           (unsigned long long)have, (unsigned long long)need,
           have >= need ? "OK" : "INSUFFICIENT");
    if (have < need) ok = false;
    return have >= need;
}

// Parse @workgroup_size(x, y) from WGSL source.
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

bool WebGPURenderer::Initialize(int canvasWidth, int canvasHeight,
                                const char* canvasSelector) {
    if (initialized_) return true;
    
    canvasWidth_ = canvasWidth;
    canvasHeight_ = canvasHeight;
    if (canvasSelector && *canvasSelector) {
        canvasSelector_ = canvasSelector;
    }

    failedStage_ = InitStage::None;
    lastError_.clear();

    // ARCH: [Low] Using printf for logging. Consider abstracting behind
    // a Logger interface to allow different output targets (console, file, etc.)
    printf("🚀 Pixelocity WASM Renderer initializing...\n");
    printf("   Canvas: %dx%d\n", canvasWidth_, canvasHeight_);

    if (!CreateDevice()) {
        // CreateDevice() sets failedStage_/lastError_ at its specific failure
        // point; fall back to a generic message if it somehow didn't.
        if (failedStage_ == InitStage::None) failedStage_ = InitStage::Device;
        if (lastError_.empty()) lastError_ = "CreateDevice() failed: see console for details";
        printf("❌ Failed to create WebGPU device\n");
        Shutdown();
        return false;
    }

    if (!CreateResources()) {
        failedStage_ = InitStage::Resources;
        lastError_ = "CreateResources() failed: see console for details";
        printf("❌ Failed to create resources\n");
        Shutdown();
        return false;
    }

    if (!CreateBindGroupLayout()) {
        if (failedStage_ == InitStage::None) failedStage_ = InitStage::BindGroups;
        if (lastError_.empty()) lastError_ = "CreateBindGroupLayout() failed: see console for details";
        printf("❌ Failed to create bind group layout\n");
        Shutdown();
        return false;
    }

    if (!CreateRenderPipeline()) {
        if (failedStage_ == InitStage::None) failedStage_ = InitStage::Pipeline;
        if (lastError_.empty()) lastError_ = "CreateRenderPipeline() failed: see console for details";
        printf("❌ Failed to create render pipeline\n");
        Shutdown();
        return false;
    }

    if (!CreateBindGroups()) {
        if (failedStage_ == InitStage::None) failedStage_ = InitStage::BindGroups;
        if (lastError_.empty()) lastError_ = "CreateBindGroups() failed: see console for details";
        printf("❌ Failed to create bind groups\n");
        Shutdown();
        return false;
    }

    initialized_ = true;
    failedStage_ = InitStage::Ready;
    printf("✅ WebGPU Renderer initialized successfully\n");
    return true;
}

void WebGPURenderer::Shutdown() {
    // No early-return on !initialized_: Shutdown() must also clean up after a
    // failed Initialize() (e.g. CreateDevice() succeeded but CreateResources()
    // failed). All .reset() calls below are null-safe, so running this on a
    // partially-initialized (or already-shutdown) renderer is harmless.

    // Cancel any in-progress frame capture before releasing the readback buffer.
    if (readbackBuffer_.get() && captureState_ == CaptureState::Pending) {
        wgpuBufferUnmap(readbackBuffer_.get());
    }
    captureState_        = CaptureState::Idle;
    readbackBufferSize_  = 0;
    readbackBytesPerRow_ = 0;

    // Shaders hold RAII handles — clear the map to release all pipelines/modules.
    shaders_.clear();

    // All other GPU objects are RAII handles — they release on assignment/destruction.
    // Explicit reset in reverse-creation order ensures proper GPU object lifetime.
    computeBindGroup_.reset();
    renderBindGroup_.reset();
    renderPipeline_.reset();
    computePipelineLayout_.reset();
    computeBindGroupLayout_.reset();

    readbackBuffer_.reset();
    uniformBuffer_.reset();
    extraBuffer_.reset();
    plasmaBuffer_.reset();

    filteringSampler_.reset();
    nonFilteringSampler_.reset();
    comparisonSampler_.reset();

    readTexture_.reset();
    writeTexture_.reset();
    pingPong0_.reset();
    pingPong1_.reset();
    dataTextureA_.reset();
    dataTextureB_.reset();
    dataTextureC_.reset();
    depthTextureRead_.reset();
    depthTextureWrite_.reset();
    emptyTexture_.reset();

    queue_.reset();
    device_.reset();
    adapter_.reset();
    surface_.reset();
    instance_.reset();

    initialized_ = false;
    deviceLost_ = false;
    presentFailureCount_ = 0;
    printf("🛑 WebGPU Renderer shutdown\n");
}

bool WebGPURenderer::CreateDevice() {
    // Create instance
    WGPUInstanceDescriptor instanceDesc = {};
    instanceDesc.nextInChain = nullptr;
    instance_.reset(wgpuCreateInstance(&instanceDesc));

    if (!instance_) {
        printf("❌ Failed to create WebGPU instance\n");
        failedStage_ = InitStage::Instance;
        lastError_ = "Failed to create WebGPU instance (wgpuCreateInstance returned null)";
        return false;
    }

    // Request adapter using callback-based API.
    // On Windows + Chrome/Edge, crbug.com/369219127 reports powerPreference is ignored
    // for requestAdapter() and emdawnwebgpu can return Unavailable despite JS WebGPU
    // succeeding. We therefore try a broader fallback ladder:
    //   1) HighPerformance (preferred)
    //   2) Undefined       (browser default)
    //   3) LowPower        (alternate hardware path)
    //   4) Undefined + forceFallbackAdapter=true (software adapter last resort)
    struct AdapterAttempt {
        WGPUPowerPreference powerPreference;
        bool forceFallbackAdapter;
    };
    const AdapterAttempt adapterAttempts[] = {
        { WGPUPowerPreference_HighPerformance, false },
        { WGPUPowerPreference_Undefined,       false },
        { WGPUPowerPreference_LowPower,        false },
        { WGPUPowerPreference_Undefined,       true  }
    };
    constexpr size_t kAdapterAttemptCount = sizeof(adapterAttempts) / sizeof(adapterAttempts[0]);

    WGPUAdapter rawAdapter = nullptr;

    for (size_t attempt = 0; attempt < kAdapterAttemptCount && rawAdapter == nullptr; ++attempt) {
        WGPUPowerPreference pref = adapterAttempts[attempt].powerPreference;
        bool useFallbackAdapter = adapterAttempts[attempt].forceFallbackAdapter;
        const char* prefName = (pref == WGPUPowerPreference_HighPerformance) ? "HighPerformance" :
                               (pref == WGPUPowerPreference_Undefined)       ? "Undefined"       :
                               "LowPower";

        printf("[WASM] Requesting WebGPU adapter (attempt %zu/%zu, powerPreference=%s, fallbackAdapter=%s)...\n",
               attempt + 1,
               kAdapterAttemptCount,
               prefName,
               useFallbackAdapter ? "true" : "false");

        WGPURequestAdapterOptions adapterOpts = {};
        adapterOpts.nextInChain = nullptr;
        // compatibleSurface is intentionally left null: JS_CreateSurfaceFromCanvas
        // (below) creates the surface via WebGPU.importJsSurface(ctx) *after*
        // ctx.configure({device: ...}), which itself requires a device — and the
        // device requires this adapter. Creating the surface before the adapter
        // would need importJsSurface to accept an unconfigured GPUCanvasContext,
        // which is not guaranteed across emdawn versions. In the browser-emdawn
        // path the adapter comes from the browser's own navigator.gpu, so the
        // canvas's WebGPU context is guaranteed compatible by construction —
        // there is no second physical device to be incompatible with.
        adapterOpts.compatibleSurface = nullptr;
        adapterOpts.powerPreference = pref;
        adapterOpts.forceFallbackAdapter = useFallbackAdapter;

        WGPUAdapter adapterFromCallback = nullptr;

        auto adapterCallback = [](WGPURequestAdapterStatus status, WGPUAdapter adapter,
                                   WGPUStringView message, void* userdata1, void* /*userdata2*/) {
            auto* outAdapter = static_cast<WGPUAdapter*>(userdata1);
            if (status == WGPURequestAdapterStatus_Success && adapter) {
                *outAdapter = adapter;
            } else {
                printf("❌ Adapter request failed (status=%d)\n", (int)status);
                if (message.data && message.length > 0) {
                    printf("   Message: %.*s\n", (int)message.length, message.data);
                }
            }
        };

        // WGPUCallbackMode_WaitAnyOnly + ASYNCIFY is required for wgpuInstanceWaitAny.
        WGPUFuture adapterFuture = wgpuInstanceRequestAdapter(instance_.get(), &adapterOpts,
            WGPURequestAdapterCallbackInfo{
                nullptr, WGPUCallbackMode_WaitAnyOnly, adapterCallback, &adapterFromCallback, nullptr
            });

        WGPUFutureWaitInfo adapterWait = {};
        adapterWait.future = adapterFuture;
        wgpuInstanceWaitAny(instance_.get(), 1, &adapterWait, UINT64_MAX);

        if (adapterFromCallback) {
            rawAdapter = adapterFromCallback;
            printf("[WASM] Successfully obtained adapter on attempt %zu (powerPref=%s, fallbackAdapter=%s)\n",
                   attempt + 1, prefName, useFallbackAdapter ? "true" : "false");
        } else {
            printf("[WASM] Adapter attempt %zu failed.\n", attempt + 1);
        }
    }

    adapter_.reset(rawAdapter);

    if (!adapter_) {
        printf("❌ Failed to get WebGPU adapter after all fallback attempts.\n");
        printf("   This commonly happens on Windows with Chrome/Edge when using emdawnwebgpu.\n");
        printf("   The JS WebGPU renderer is unaffected. Consider using ?renderer=webgpu or the UI toggle.\n");
        failedStage_ = InitStage::Adapter;
        lastError_ = "Failed to obtain a WebGPU adapter after all fallback attempts "
                      "(HighPerformance/Undefined/LowPower/forceFallbackAdapter)";
        return false;
    }

    // ── Adapter info ──────────────────────────────────────────────────────
    // Logs vendor/architecture/device/description so "works on my machine"
    // reports are diagnosable from console output alone.
    WGPUAdapterInfo adapterInfo = {};
    wgpuAdapterGetInfo(adapter_.get(), &adapterInfo);

    const char* backendStr = "Unknown";
    switch (adapterInfo.backendType) {
        case WGPUBackendType_WebGPU:   backendStr = "WebGPU";   break;
        case WGPUBackendType_D3D11:    backendStr = "D3D11";    break;
        case WGPUBackendType_D3D12:    backendStr = "D3D12";    break;
        case WGPUBackendType_Metal:    backendStr = "Metal";    break;
        case WGPUBackendType_Vulkan:   backendStr = "Vulkan";   break;
        case WGPUBackendType_OpenGL:   backendStr = "OpenGL";   break;
        case WGPUBackendType_OpenGLES: backendStr = "OpenGLES"; break;
        default: break;
    }
    const char* adapterTypeStr = "Unknown";
    switch (adapterInfo.adapterType) {
        case WGPUAdapterType_DiscreteGPU:   adapterTypeStr = "DiscreteGPU";   break;
        case WGPUAdapterType_IntegratedGPU: adapterTypeStr = "IntegratedGPU"; break;
        case WGPUAdapterType_CPU:           adapterTypeStr = "CPU";           break;
        case WGPUAdapterType_Unknown:        adapterTypeStr = "Unknown";       break;
        default: break;
    }

    printf("[WASM] Adapter: vendor=%.*s architecture=%.*s device=%.*s desc=%.*s\n",
           (int)adapterInfo.vendor.length, adapterInfo.vendor.data ? adapterInfo.vendor.data : "",
           (int)adapterInfo.architecture.length, adapterInfo.architecture.data ? adapterInfo.architecture.data : "",
           (int)adapterInfo.device.length, adapterInfo.device.data ? adapterInfo.device.data : "",
           (int)adapterInfo.description.length, adapterInfo.description.data ? adapterInfo.description.data : "");
    printf("[WASM]   backendType=%s adapterType=%s vendorID=0x%04x deviceID=0x%04x\n",
           backendStr, adapterTypeStr, adapterInfo.vendorID, adapterInfo.deviceID);

    // ── Adapter limits ────────────────────────────────────────────────────
    // Validate against the minimums implied by the 13-binding compute shader
    // contract (see AGENTS.md "Shader Bindings (IMMUTABLE)") so that a weak
    // adapter fails here with an actionable message instead of deep inside
    // CreateResources() with a cryptic bind-group-layout error.
    WGPULimits limits = {};
    wgpuAdapterGetLimits(adapter_.get(), &limits);

    bool limitsOk = true;
    const uint64_t maxCanvasDim = (uint64_t)std::max(canvasWidth_, canvasHeight_);
    printf("[WASM] Adapter limits (validating against 13-binding compute contract):\n");
    CheckLimit("maxTextureDimension2D",              limits.maxTextureDimension2D,              maxCanvasDim, limitsOk);
    CheckLimit("maxBindingsPerBindGroup",            limits.maxBindingsPerBindGroup,            13,  limitsOk);
    CheckLimit("maxSampledTexturesPerShaderStage",   limits.maxSampledTexturesPerShaderStage,    3,  limitsOk);
    CheckLimit("maxSamplersPerShaderStage",          limits.maxSamplersPerShaderStage,           3,  limitsOk);
    CheckLimit("maxStorageTexturesPerShaderStage",   limits.maxStorageTexturesPerShaderStage,    4,  limitsOk);
    CheckLimit("maxStorageBuffersPerShaderStage",    limits.maxStorageBuffersPerShaderStage,     2,  limitsOk);
    CheckLimit("maxUniformBuffersPerShaderStage",    limits.maxUniformBuffersPerShaderStage,     1,  limitsOk);
    CheckLimit("maxComputeWorkgroupSizeX",           limits.maxComputeWorkgroupSizeX,            16, limitsOk);
    CheckLimit("maxComputeWorkgroupSizeY",           limits.maxComputeWorkgroupSizeY,            16, limitsOk);
    CheckLimit("maxComputeInvocationsPerWorkgroup",  limits.maxComputeInvocationsPerWorkgroup,   256, limitsOk);

    printf("[WASM] Adapter limits: maxTex2D=%u, storageTex=%u, sampledTex=%u, computeInvocations=%u (%s)\n",
           limits.maxTextureDimension2D, limits.maxStorageTexturesPerShaderStage,
           limits.maxSampledTexturesPerShaderStage, limits.maxComputeInvocationsPerWorkgroup,
           limitsOk ? "sufficient" : "INSUFFICIENT");

    // ── Feature checks ────────────────────────────────────────────────────
    // rgba32float storage textures (bindings 2/7/8) require float32-filterable/
    // blendable support on some backends; log so it's visible in diagnostics.
    bool hasFloat32Filterable = wgpuAdapterHasFeature(adapter_.get(), WGPUFeatureName_Float32Filterable);
    bool hasFloat32Blendable  = wgpuAdapterHasFeature(adapter_.get(), WGPUFeatureName_Float32Blendable);
    bool hasBGRA8Storage      = wgpuAdapterHasFeature(adapter_.get(), WGPUFeatureName_BGRA8UnormStorage);
    printf("[WASM] Adapter features: Float32Filterable=%s Float32Blendable=%s BGRA8UnormStorage=%s\n",
           hasFloat32Filterable ? "yes" : "no",
           hasFloat32Blendable  ? "yes" : "no",
           hasBGRA8Storage      ? "yes" : "no");

    if (!limitsOk) {
        printf("❌ Adapter does not meet the minimum WebGPU limits required by Pixelocity's\n");
        printf("   13-binding compute shader contract (see entries marked INSUFFICIENT above).\n");
        printf("   This adapter/browser combination is too weak to run the WASM renderer.\n");
        printf("   Consider ?renderer=webgpu (JS renderer) or a different GPU/browser.\n");
        adapterSummary_ = "INSUFFICIENT adapter limits — see console for details";
        failedStage_ = InitStage::Adapter;
        lastError_ = adapterSummary_;
        wgpuAdapterInfoFreeMembers(adapterInfo);
        return false;
    }

    // Seed the summary now; device limits and surface format are appended below.
    {
        char buf[768];
        snprintf(buf, sizeof(buf),
            "Adapter: %.*s | %.*s%s%.*s | backend=%s type=%s | "
            "limits: maxTex2D=%u storageTex=%u sampledTex=%u computeInvocations=%u (sufficient)",
            (int)adapterInfo.vendor.length, adapterInfo.vendor.data ? adapterInfo.vendor.data : "unknown",
            (int)adapterInfo.device.length, adapterInfo.device.data ? adapterInfo.device.data : "unknown device",
            adapterInfo.architecture.length > 0 ? " | " : "",
            (int)adapterInfo.architecture.length, adapterInfo.architecture.data ? adapterInfo.architecture.data : "",
            backendStr, adapterTypeStr,
            limits.maxTextureDimension2D, limits.maxStorageTexturesPerShaderStage,
            limits.maxSampledTexturesPerShaderStage, limits.maxComputeInvocationsPerWorkgroup);
        adapterSummary_.assign(buf);
    }

    wgpuAdapterInfoFreeMembers(adapterInfo);

    // ── Required limits ──────────────────────────────────────────────────
    // Explicitly request the minimums this renderer needs (see the
    // CheckLimit() table above) instead of leaving requiredLimits null.
    // All other fields stay WGPU_LIMIT_*_UNDEFINED (via WGPU_LIMITS_INIT) so
    // we don't over-request anything the adapter doesn't already offer.
    WGPULimits requiredLimits = WGPU_LIMITS_INIT;
    requiredLimits.maxTextureDimension2D             = (uint32_t)maxCanvasDim;
    requiredLimits.maxBindingsPerBindGroup           = 13;
    requiredLimits.maxSampledTexturesPerShaderStage  = 3;
    requiredLimits.maxSamplersPerShaderStage         = 3;
    requiredLimits.maxStorageTexturesPerShaderStage  = 4;
    requiredLimits.maxStorageBuffersPerShaderStage   = 2;
    requiredLimits.maxUniformBuffersPerShaderStage   = 1;
    requiredLimits.maxUniformBufferBindingSize       = sizeof(Uniforms);
    requiredLimits.maxComputeWorkgroupSizeX          = 16;
    requiredLimits.maxComputeWorkgroupSizeY          = 16;
    requiredLimits.maxComputeInvocationsPerWorkgroup = 256;

    // Request device using callback-based API
    WGPUDeviceDescriptor deviceDesc = {};
    deviceDesc.nextInChain = nullptr;
    deviceDesc.label = MakeStringView("Pixelocity Device");
    deviceDesc.requiredFeatureCount = 0;
    deviceDesc.requiredLimits = &requiredLimits;

    // ── Device-lost callback ─────────────────────────────────────────────────
    // Fired when the GPU device is lost (tab hidden, driver crash, etc.).
    // Logs the reason so developers know why rendering stopped.
    deviceDesc.deviceLostCallbackInfo = WGPUDeviceLostCallbackInfo{
        nullptr,
        WGPUCallbackMode_AllowSpontaneous,
        [](WGPUDevice const* /*device*/, WGPUDeviceLostReason reason,
           WGPUStringView message, void* userdata1, void* /*userdata2*/) {
            const char* reasonStr = "Unknown";
            switch (reason) {
                case WGPUDeviceLostReason_Unknown:     reasonStr = "Unknown";     break;
                case WGPUDeviceLostReason_Destroyed:   reasonStr = "Destroyed";   break;
#ifdef WGPUDeviceLostReason_InstanceDropped
                case WGPUDeviceLostReason_InstanceDropped: reasonStr = "InstanceDropped"; break;
#endif
#ifdef WGPUDeviceLostReason_FailedCreation
                case WGPUDeviceLostReason_FailedCreation: reasonStr = "FailedCreation";  break;
#endif
                default: break;
            }
            printf("[WebGPU] Device lost (%s): %.*s\n", reasonStr,
                   static_cast<int>(message.length), message.data ? message.data : "");
            if (auto* self = static_cast<WebGPURenderer*>(userdata1)) {
                self->deviceLost_ = true;
            }
        },
        this, nullptr
    };

    // ── Uncaptured-error callback ────────────────────────────────────────────
    // Fired for validation errors, shader compilation failures, etc.
    // Without this, GPU errors are silently swallowed.
    deviceDesc.uncapturedErrorCallbackInfo = WGPUUncapturedErrorCallbackInfo{
        nullptr,
        [](WGPUDevice const* /*device*/, WGPUErrorType type,
           WGPUStringView message, void* /*userdata1*/, void* /*userdata2*/) {
            const char* typeStr = "Unknown";
            switch (type) {
                case WGPUErrorType_Validation:  typeStr = "Validation";  break;
                case WGPUErrorType_OutOfMemory: typeStr = "OutOfMemory"; break;
                case WGPUErrorType_Internal:    typeStr = "Internal";    break;
                case WGPUErrorType_Unknown:     typeStr = "Unknown";     break;
                default: break;
            }
            printf("[WebGPU Error] %s: %.*s\n", typeStr,
                   static_cast<int>(message.length), message.data ? message.data : "");
        },
        nullptr, nullptr
    };

    WGPUDevice rawDevice = nullptr;
    auto deviceCallback = [](WGPURequestDeviceStatus status, WGPUDevice device,
                              WGPUStringView message, void* userdata1, void* /*userdata2*/) {
        if (status == WGPURequestDeviceStatus_Success) {
            *static_cast<WGPUDevice*>(userdata1) = device;
        } else {
            printf("❌ Device request failed! Status: %d\n", status);
            if (message.data && message.length > 0) {
                printf("   Message: %.*s\n", (int)message.length, message.data);
            }
        }
    };

    WGPUFuture deviceFuture = wgpuAdapterRequestDevice(adapter_.get(), &deviceDesc,
        WGPURequestDeviceCallbackInfo{
            nullptr, WGPUCallbackMode_WaitAnyOnly, deviceCallback, &rawDevice, nullptr
        });

    WGPUFutureWaitInfo deviceWait = {};
    deviceWait.future = deviceFuture;
    wgpuInstanceWaitAny(instance_.get(), 1, &deviceWait, UINT64_MAX);

    device_.reset(rawDevice);

    if (!device_) {
        printf("❌ Failed to get WebGPU device after adapter was obtained.\n");
        failedStage_ = InitStage::Device;
        lastError_ = "Failed to obtain a WebGPU device from the adapter (wgpuAdapterRequestDevice failed)";
        return false;
    }

    printf("[WASM] Successfully created WebGPU device and queue.\n");

    queue_.reset(wgpuDeviceGetQueue(device_.get()));

    // ── Device limits ─────────────────────────────────────────────────────
    // Re-check against the same minimums as the adapter: a device can clamp
    // limits below what the adapter advertised (e.g. due to requiredLimits
    // negotiation), so this catches that case even though we don't currently
    // request explicit requiredLimits.
    {
        WGPULimits deviceLimits = {};
        wgpuDeviceGetLimits(device_.get(), &deviceLimits);
        bool deviceLimitsOk = true;
        const uint64_t maxCanvasDim = (uint64_t)std::max(canvasWidth_, canvasHeight_);
        printf("[WASM] Device limits (post-creation, catches clamping):\n");
        CheckLimit("maxTextureDimension2D",             deviceLimits.maxTextureDimension2D,             maxCanvasDim, deviceLimitsOk);
        CheckLimit("maxBindingsPerBindGroup",           deviceLimits.maxBindingsPerBindGroup,           13,  deviceLimitsOk);
        CheckLimit("maxSampledTexturesPerShaderStage",  deviceLimits.maxSampledTexturesPerShaderStage,  3,   deviceLimitsOk);
        CheckLimit("maxSamplersPerShaderStage",         deviceLimits.maxSamplersPerShaderStage,         3,   deviceLimitsOk);
        CheckLimit("maxStorageTexturesPerShaderStage",  deviceLimits.maxStorageTexturesPerShaderStage,  4,   deviceLimitsOk);
        CheckLimit("maxStorageBuffersPerShaderStage",   deviceLimits.maxStorageBuffersPerShaderStage,   2,   deviceLimitsOk);
        CheckLimit("maxUniformBuffersPerShaderStage",   deviceLimits.maxUniformBuffersPerShaderStage,   1,   deviceLimitsOk);
        CheckLimit("maxComputeInvocationsPerWorkgroup", deviceLimits.maxComputeInvocationsPerWorkgroup, 256, deviceLimitsOk);
        if (!deviceLimitsOk) {
            printf("⚠️  Device limits were clamped below the adapter's reported limits and no\n");
            printf("   longer meet the 13-binding compute contract minimums. Rendering may fail.\n");
        }
    }

    // Create the WebGPU surface from the canvas, if a selector was provided.
    if (!canvasSelector_.empty()) {
        // Query the browser's preferred canvas format *before* creating the
        // surface, so surfaceFormat_ matches what JS_CreateSurfaceFromCanvas's
        // ctx.configure() negotiates (it queries the same
        // navigator.gpu.getPreferredCanvasFormat()), keeping the two consistent.
        int fmt = JS_GetPreferredCanvasFormat();
        surfaceFormat_ = (fmt == 1) ? WGPUTextureFormat_RGBA8Unorm
                                     : WGPUTextureFormat_BGRA8Unorm; // default + unknown
        printf("[WASM] Negotiated canvas format: %s\n", fmt == 1 ? "rgba8unorm" : "bgra8unorm");

        uint32_t surfHandle = JS_CreateSurfaceFromCanvas(
            canvasSelector_.c_str(), device_.get());
        if (!surfHandle) {
            // Surface creation failed (no canvas at selector / getContext('webgpu')
            // failed / ctx.configure threw). Without a surface there is no way to
            // present, so treat this as a fatal init failure instead of silently
            // returning true and leaving the user with a permanent black canvas.
            printf("❌ [WASM] Surface creation failed for canvas '%s' — fatal init failure.\n"
                   "   (no canvas at selector / getContext('webgpu') failed / ctx.configure threw)\n",
                   canvasSelector_.c_str());
            adapterSummary_ = "Surface creation failed for canvas '";
            adapterSummary_ += canvasSelector_;
            adapterSummary_ += "'";
            failedStage_ = InitStage::Surface;
            lastError_ = adapterSummary_;
            return false;
        }
        surface_.reset(reinterpret_cast<WGPUSurface>(surfHandle));
        ConfigureSurface();
    }

    // Append the negotiated surface format to the adapter summary so one
    // diagnostics block shows the entire chosen-settings picture.
    {
        const char* fmtStr = (surfaceFormat_ == WGPUTextureFormat_BGRA8Unorm) ? "bgra8unorm" :
                             (surfaceFormat_ == WGPUTextureFormat_RGBA8Unorm) ? "rgba8unorm" :
                             (surfaceFormat_ == WGPUTextureFormat_Undefined)  ? "undefined (no surface)" :
                             "other";
        adapterSummary_ += " | surfaceFormat=";
        adapterSummary_ += fmtStr;
    }
    printf("[WASM] %s\n", adapterSummary_.c_str());

    // chosen settings validation added 2026-06
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
    filteringSampler_.reset(wgpuDeviceCreateSampler(device_.get(), &samplerDesc));

    samplerDesc.label = MakeStringView("Non-filtering Sampler");
    samplerDesc.magFilter = WGPUFilterMode_Nearest;
    samplerDesc.minFilter = WGPUFilterMode_Nearest;
    samplerDesc.mipmapFilter = WGPUMipmapFilterMode_Nearest;
    nonFilteringSampler_.reset(wgpuDeviceCreateSampler(device_.get(), &samplerDesc));

    samplerDesc.label = MakeStringView("Comparison Sampler");
    samplerDesc.compare = WGPUCompareFunction_Less;
    comparisonSampler_.reset(wgpuDeviceCreateSampler(device_.get(), &samplerDesc));

    // Uniform buffer layout:
    //   [0..11]   = 12 floats: config(4) + zoom_config(4) + zoom_params(4)
    //   [12..211] = 200 floats: 50 ripples × 4 floats each
    constexpr size_t UNIFORM_BASE_FLOATS = 12;
    constexpr size_t uniformSize = sizeof(float) * (UNIFORM_BASE_FLOATS + MAX_RIPPLES * 4);
    WGPUBufferDescriptor bufferDesc = {};
    bufferDesc.nextInChain = nullptr;
    bufferDesc.label = MakeStringView("Uniform Buffer");
    bufferDesc.size = uniformSize;
    bufferDesc.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst;
    bufferDesc.mappedAtCreation = false;
    uniformBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &bufferDesc));

    // Extra buffer: 256 floats of general-purpose shader data (audio FFT, etc.)
    constexpr size_t EXTRA_BUFFER_FLOATS = 256;
    bufferDesc.label = MakeStringView("Extra Buffer");
    bufferDesc.size = EXTRA_BUFFER_FLOATS * sizeof(float);
    bufferDesc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    extraBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &bufferDesc));

    // Plasma buffer: MAX_PLASMA_BALLS × sizeof(vec4<f32>) = MAX_PLASMA_BALLS × 16 bytes
    constexpr size_t PLASMA_ENTRY_BYTES = 16;  // sizeof(vec4<f32>)
    bufferDesc.label = MakeStringView("Plasma Buffer");
    bufferDesc.size = MAX_PLASMA_BALLS * PLASMA_ENTRY_BYTES;
    bufferDesc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    plasmaBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &bufferDesc));

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
    readTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Write Texture");
    writeTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Ping-Pong 0");
    pingPong0_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Ping-Pong 1");
    pingPong1_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Data Texture A");
    dataTextureA_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Data Texture B");
    dataTextureB_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Data Texture C");
    dataTextureC_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    // Depth textures (r32float)
    texDesc.format = WGPUTextureFormat_R32Float;
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Depth Texture Read");
    depthTextureRead_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Depth Texture Write");
    depthTextureWrite_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    // Empty texture (1x1) used as placeholder for generative shaders
    texDesc.size = {1, 1, 1};
    texDesc.label = MakeStringView("Empty Texture");
    emptyTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    // Initialize empty texture to black
    float black[4] = {0.0f, 0.0f, 0.0f, 1.0f};

    WGPUTexelCopyTextureInfo emptyDest = {};
    emptyDest.texture = emptyTexture_.get();
    emptyDest.mipLevel = 0;
    emptyDest.origin = {0, 0, 0};
    emptyDest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout emptyDataLayout = {};
    emptyDataLayout.offset = 0;
    emptyDataLayout.bytesPerRow = sizeof(float) * 4;  // 1 pixel × 4 floats × 4 bytes
    emptyDataLayout.rowsPerImage = 1;

    wgpuQueueWriteTexture(queue_.get(), &emptyDest, black, sizeof(black), &emptyDataLayout, &texDesc.size);

    // Initialize data texture C and readTexture_ to zeros (avoids uninitialised GPU memory).
    std::vector<float> zeros(static_cast<size_t>(canvasWidth_) * canvasHeight_ * 4, 0.0f);

    WGPUTexelCopyTextureInfo dataDest = {};
    dataDest.mipLevel = 0;
    dataDest.origin = {0, 0, 0};
    dataDest.aspect = WGPUTextureAspect_All;

    WGPUTexelCopyBufferLayout dataLayout = {};
    dataLayout.offset = 0;
    dataLayout.bytesPerRow = static_cast<uint32_t>(canvasWidth_) * sizeof(float) * 4;
    dataLayout.rowsPerImage = static_cast<uint32_t>(canvasHeight_);

    WGPUExtent3D dataExtent = {};
    dataExtent.width = static_cast<uint32_t>(canvasWidth_);
    dataExtent.height = static_cast<uint32_t>(canvasHeight_);
    dataExtent.depthOrArrayLayers = 1;

    dataDest.texture = dataTextureC_.get();
    wgpuQueueWriteTexture(queue_.get(), &dataDest, zeros.data(), zeros.size() * sizeof(float), &dataLayout, &dataExtent);

    dataDest.texture = readTexture_.get();
    wgpuQueueWriteTexture(queue_.get(), &dataDest, zeros.data(), zeros.size() * sizeof(float), &dataLayout, &dataExtent);

    return true;
}

bool WebGPURenderer::CreateBindGroupLayout() {
    // 13 fixed bindings matching the universal compute shader layout.
    // See AGENTS.md "Shader Bindings (IMMUTABLE)" for the authoritative list.
    static constexpr uint32_t BINDING_COUNT = 13;
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

    static constexpr uint32_t BINDING_COUNT = 13;
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
    viewDesc.format = WGPUTextureFormat_RGBA32Float;
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
    viewDesc.format          = WGPUTextureFormat_RGBA32Float;
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

void WebGPURenderer::ConfigureSurface() {
    if (!surface_.get() || !device_.get()) return;

    WGPUSurfaceConfiguration config = {};
    config.device      = device_.get();
    config.format      = surfaceFormat_;          // negotiated via JS_GetPreferredCanvasFormat()
    config.usage       = WGPUTextureUsage_RenderAttachment;
    config.alphaMode   = WGPUCompositeAlphaMode_Opaque;
    config.width       = static_cast<uint32_t>(canvasWidth_);
    config.height      = static_cast<uint32_t>(canvasHeight_);
    config.presentMode = WGPUPresentMode_Fifo;

    wgpuSurfaceConfigure(surface_.get(), &config);
    printf("✅ WebGPU surface configured (%dx%d)\n", canvasWidth_, canvasHeight_);
}

// ─── Present to canvas ────────────────────────────────────────────────────────
//
// Issues a full-screen render pass that blits writeTexture_ (RGBA32Float) to
// the current swap-chain texture (format: surfaceFormat_), then presents it.
// The GPU automatically tone-maps float→unorm8 (values clamped to [0,1]).

void WebGPURenderer::PresentToSurface() {
    if (!surface_.get() || !renderPipeline_.get() || !renderBindGroup_.get()) return;
    if (deviceLost_ || !device_.get() || !queue_.get()) return;

    // Acquire the current swap-chain texture.
    WGPUSurfaceTexture surfaceTex = {};
    wgpuSurfaceGetCurrentTexture(surface_.get(), &surfaceTex);

    // Accept both SuccessOptimal (emdawnwebgpu ≥ 2024) and SuccessSuboptimal.
    // Older emdawnwebgpu headers use the single WGPUSurfaceGetCurrentTextureStatus_Success
    // enum value (= 0) instead; the #else branch handles that case by name so the code
    // compiles correctly with either header generation.
#if defined(WGPU_SURFACE_TEXTURE_INIT)
    const bool ok = (surfaceTex.status == WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal ||
                     surfaceTex.status == WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal);
#else
    const bool ok = (surfaceTex.status == WGPUSurfaceGetCurrentTextureStatus_Success);
#endif
    if (!ok) {
        if (surfaceTex.texture) wgpuTextureRelease(surfaceTex.texture);
        presentFailureCount_++;
        if (presentFailureCount_ <= 5) {
            printf("⚠️  PresentToSurface: GetCurrentTexture failed (status=%d), attempt %d\n",
                   (int)surfaceTex.status, presentFailureCount_);
            if (presentFailureCount_ == 5) {
                printf("⚠️  PresentToSurface: suppressing further failure logs until next success or resize\n");
            }
        }
        return;
    }
    presentFailureCount_ = 0;

    // Create a view of the swap-chain texture to use as the render attachment.
    WGPUTextureView surfaceView = wgpuTextureCreateView(surfaceTex.texture, nullptr);

    WGPURenderPassColorAttachment colorAttach = {};
    colorAttach.view       = surfaceView;
    colorAttach.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;  // required for 2-D attachments
    colorAttach.loadOp     = WGPULoadOp_Clear;
    colorAttach.storeOp    = WGPUStoreOp_Store;
    colorAttach.clearValue = {0.0, 0.0, 0.0, 1.0};

    WGPURenderPassDescriptor rpDesc = {};
    rpDesc.label                  = MakeStringView("Present Pass");
    rpDesc.colorAttachmentCount   = 1;
    rpDesc.colorAttachments       = &colorAttach;
    rpDesc.depthStencilAttachment = nullptr;

    WGPUCommandEncoderDescriptor encDesc = {};
    encDesc.label = MakeStringView("Present Encoder");
    WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);

    WGPURenderPassEncoder rp = wgpuCommandEncoderBeginRenderPass(enc, &rpDesc);
    wgpuRenderPassEncoderSetPipeline(rp, renderPipeline_.get());
    wgpuRenderPassEncoderSetBindGroup(rp, 0, renderBindGroup_.get(), 0, nullptr);
    wgpuRenderPassEncoderDraw(rp, 4, 1, 0, 0);  // 4 verts for TriangleStrip quad
    wgpuRenderPassEncoderEnd(rp);
    wgpuRenderPassEncoderRelease(rp);

    WGPUCommandBufferDescriptor cbDesc = {};
    cbDesc.label = MakeStringView("Present CmdBuf");
    WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
    wgpuQueueSubmit(queue_.get(), 1, &cb);
    wgpuCommandBufferRelease(cb);
    wgpuCommandEncoderRelease(enc);

    wgpuTextureViewRelease(surfaceView);
    wgpuTextureRelease(surfaceTex.texture);

    // In browser WebGPU, wgpuSurfacePresent is typically a no-op — the browser
    // presents automatically at the end of the animation frame.
    wgpuSurfacePresent(surface_.get());
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
    shaders_[id] = std::move(sp);

    printf("✅ Loaded shader: %s (workgroup: %ux%u)\n", id,
           shaders_[id].workgroupX, shaders_[id].workgroupY);
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
    static constexpr uint32_t BINDING_COUNT = 13;
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
    if (!queue_.get() || !readTexture_.get() || deviceLost_) return;

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
    if (!queue_.get() || !depthTextureRead_.get() || !data || deviceLost_) return;

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
    // Release size-dependent textures using RAII handles.
    // Size-independent objects (samplers, uniform/extra/plasma buffers, 1×1 emptyTexture_)
    // do NOT need to be recreated.
    readTexture_.reset();
    writeTexture_.reset();
    pingPong0_.reset();
    pingPong1_.reset();
    dataTextureA_.reset();
    dataTextureB_.reset();
    dataTextureC_.reset();
    depthTextureRead_.reset();
    depthTextureWrite_.reset();

    // Release old bind group — it holds views into the old textures.
    computeBindGroup_.reset();

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
    readTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Write Texture");
    writeTexture_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Ping-Pong 0");
    pingPong0_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Ping-Pong 1");
    pingPong1_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Data Texture A");
    dataTextureA_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Data Texture B");
    dataTextureB_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Data Texture C");
    dataTextureC_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

    // Depth textures (r32float)
    texDesc.format = WGPUTextureFormat_R32Float;
    texDesc.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst | WGPUTextureUsage_StorageBinding;
    texDesc.label = MakeStringView("Depth Texture Read");
    depthTextureRead_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));
    texDesc.label = MakeStringView("Depth Texture Write");
    depthTextureWrite_.reset(wgpuDeviceCreateTexture(device_.get(), &texDesc));

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
    layout.bytesPerRow  = static_cast<uint32_t>(canvasWidth_) * sizeof(float) * 4;  // rgba32float
    layout.rowsPerImage = static_cast<uint32_t>(canvasHeight_);

    WGPUExtent3D extent = {};
    extent.width  = static_cast<uint32_t>(canvasWidth_);
    extent.height = static_cast<uint32_t>(canvasHeight_);
    extent.depthOrArrayLayers = 1;

    dest.texture = dataTextureC_.get();
    wgpuQueueWriteTexture(queue_.get(), &dest, videoStagingBuffer_.data(),
                          floatCount * sizeof(float), &layout, &extent);

    dest.texture = readTexture_.get();
    wgpuQueueWriteTexture(queue_.get(), &dest, videoStagingBuffer_.data(),
                          floatCount * sizeof(float), &layout, &extent);

    // Rebuild the bind groups with the new texture views.
    // CreateBindGroups() already calls CreateRenderBindGroup() internally.
    CreateBindGroups();

    // Reconfigure the surface swap-chain for the new canvas dimensions.
    if (surface_.get()) {
        ConfigureSurface();
    }
}

void WebGPURenderer::ResizeCanvas(int newWidth, int newHeight) {
    if (newWidth <= 0 || newHeight <= 0) return;
    if (newWidth == canvasWidth_ && newHeight == canvasHeight_) return;
    if (!initialized_ || deviceLost_) return;

    printf("🔄 Resizing canvas: %dx%d → %dx%d\n",
           canvasWidth_, canvasHeight_, newWidth, newHeight);

    canvasWidth_  = newWidth;
    canvasHeight_ = newHeight;

    // Recreate all size-dependent GPU resources.
    RecreateTextures();

    // Invalidate the persistent staging buffer so it gets resized on next upload.
    videoStagingBuffer_.clear();

    // Release the readback buffer; it will be recreated at the new size on next capture.
    if (readbackBuffer_.get()) {
        if (captureState_ == CaptureState::Pending) {
            wgpuBufferUnmap(readbackBuffer_.get());
        }
        readbackBuffer_.reset();
        readbackBufferSize_  = 0;
        readbackBytesPerRow_ = 0;
    }
    captureState_ = CaptureState::Idle;

    // A resize gives presentation a fresh start at the new size.
    presentFailureCount_ = 0;

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
    if (!uniformBuffer_.get()) return;

    // Use std::array to avoid VLA (non-standard extension) and ensure stack allocation.
    static constexpr size_t UNIFORM_FLOAT_COUNT = 12 + MAX_RIPPLES * 4;
    std::array<float, UNIFORM_FLOAT_COUNT> uniformData = {};

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

    wgpuQueueWriteBuffer(queue_.get(), uniformBuffer_.get(), 0, uniformData.data(), uniformData.size() * sizeof(float));

    // Upload audio to extraBuffer_ (binding 10).
    // Some shaders read bass/mid/treble from the first three floats here.
    if (extraBuffer_.get()) {
        float audioData[3] = { audioBass_, audioMid_, audioTreble_ };
        wgpuQueueWriteBuffer(queue_.get(), extraBuffer_.get(), 0, audioData, sizeof(audioData));
    }

    // Upload audio to plasmaBuffer_ (binding 12) as vec4(bass, mid, treble, 0).
    // Shaders using the AGENTS.md audio convention read from here:
    //   let bass   = plasmaBuffer[0].x;
    //   let mids   = plasmaBuffer[0].y;
    //   let treble = plasmaBuffer[0].z;
    if (plasmaBuffer_.get()) {
        float audioVec4[4] = { audioBass_, audioMid_, audioTreble_, 0.0f };
        wgpuQueueWriteBuffer(queue_.get(), plasmaBuffer_.get(), 0, audioVec4, sizeof(audioVec4));
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
    if (!initialized_ || deviceLost_ || !device_.get() || !queue_.get()) return;

    // Upload all per-frame global uniforms (time, mouse, ripples, audio).
    UpdateUniformBuffer();

    const uint32_t W = static_cast<uint32_t>(canvasWidth_);
    const uint32_t H = static_cast<uint32_t>(canvasHeight_);

    // Fixed output texture per slot index.
    WGPUTexture slotOutput[MAX_SHADER_SLOTS] = { pingPong0_.get(), pingPong1_.get(), writeTexture_.get() };

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
                WGPUBindGroup bg = CreateComputeBindGroup(readTexture_.get(), writeTexture_.get());

                WGPUCommandEncoderDescriptor encDesc = {};
                encDesc.label = MakeStringView("Single Encoder");
                WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);

                DispatchComputePass(enc, it->second.pipeline.get(), bg,
                                    it->second.workgroupX, it->second.workgroupY);
                wgpuBindGroupRelease(bg);

                CopyTex(enc, writeTexture_.get(), readTexture_.get(), W, H);
                CopyTex(enc, depthTextureWrite_.get(), depthTextureRead_.get(), W, H);
                CopyTex(enc, dataTextureA_.get(), dataTextureC_.get(), W, H);

                WGPUCommandBufferDescriptor cbDesc = {};
                cbDesc.label = MakeStringView("Single CmdBuf");
                WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
                wgpuQueueSubmit(queue_.get(), 1, &cb);
                wgpuCommandBufferRelease(cb);
                wgpuCommandEncoderRelease(enc);
            }
        }
    } else {
        // ── Multi-slot pipeline ───────────────────────────────────────────────
        // The "chain input" starts as readTexture_ (previous frame output).
        WGPUTexture chainInput = readTexture_.get();

        for (int i = 0; i < MAX_SHADER_SLOTS; i++) {
            if (!slots_[i].enabled || slots_[i].shaderId.empty()) continue;
            auto it = shaders_.find(slots_[i].shaderId);
            if (it == shaders_.end()) continue;

            // Which texture does this slot read from?
            WGPUTexture readFrom = (slots_[i].mode == SlotMode::Parallel)
                                   ? readTexture_.get()   // parallel: always from source
                                   : chainInput;          // chained: previous slot output

            // Which texture does this slot write to?
            WGPUTexture writeTo = slotOutput[i];

            // Patch per-slot zoom_params before submitting this slot's pass.
            WriteSlotParams(slots_[i].params);

            WGPUBindGroup bg = CreateComputeBindGroup(readFrom, writeTo);

            WGPUCommandEncoderDescriptor encDesc = {};
            encDesc.label = MakeStringView("Slot Encoder");
            WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);

            DispatchComputePass(enc, it->second.pipeline.get(), bg,
                                it->second.workgroupX, it->second.workgroupY);
            wgpuBindGroupRelease(bg);

            WGPUCommandBufferDescriptor cbDesc = {};
            cbDesc.label = MakeStringView("Slot CmdBuf");
            WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
            // Submit this slot separately so the next WriteSlotParams (called
            // before the next slot's encoder) takes effect on the GPU.
            wgpuQueueSubmit(queue_.get(), 1, &cb);
            wgpuCommandBufferRelease(cb);
            wgpuCommandEncoderRelease(enc);

            // Update chain input for the next slot (if chained).
            chainInput = writeTo;
        }

        // If the last slot did not write directly to writeTexture_, copy its
        // output there so the render pipeline always reads from writeTexture_.
        if (slotOutput[lastEnabled] != writeTexture_.get()) {
            WGPUCommandEncoderDescriptor encDesc = {};
            encDesc.label = MakeStringView("Copy Encoder");
            WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);
            CopyTex(enc, slotOutput[lastEnabled], writeTexture_.get(), W, H);
            WGPUCommandBufferDescriptor cbDesc = {};
            cbDesc.label = MakeStringView("Copy CmdBuf");
            WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
            wgpuQueueSubmit(queue_.get(), 1, &cb);
            wgpuCommandBufferRelease(cb);
            wgpuCommandEncoderRelease(enc);
        }

        // End-of-frame texture copies for temporal feedback.
        {
            WGPUCommandEncoderDescriptor encDesc = {};
            encDesc.label = MakeStringView("Feedback Encoder");
            WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);
            CopyTex(enc, writeTexture_.get(),       readTexture_.get(),      W, H);
            CopyTex(enc, depthTextureWrite_.get(),  depthTextureRead_.get(), W, H);
            CopyTex(enc, dataTextureA_.get(),       dataTextureC_.get(),     W, H);
            WGPUCommandBufferDescriptor cbDesc = {};
            cbDesc.label = MakeStringView("Feedback CmdBuf");
            WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
            wgpuQueueSubmit(queue_.get(), 1, &cb);
            wgpuCommandBufferRelease(cb);
            wgpuCommandEncoderRelease(enc);
        }
    }

    // Present the final composed frame to the canvas (if surface is configured).
    PresentToSurface();

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
    if (!initialized_ || deviceLost_ || !writeTexture_.get() || !queue_.get() || !device_.get()) {
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
    if (!readbackBuffer_.get() || readbackBufferSize_ < needed) {
        WGPUBufferDescriptor bufDesc = {};
        bufDesc.label            = MakeStringView("Readback Buffer");
        bufDesc.size             = needed;
        bufDesc.usage            = WGPUBufferUsage_CopyDst | WGPUBufferUsage_MapRead;
        bufDesc.mappedAtCreation = false;
        readbackBuffer_.reset(wgpuDeviceCreateBuffer(device_.get(), &bufDesc));
        readbackBufferSize_ = needed;
    }
    readbackBytesPerRow_ = bytesPerRow;

    // Encode CopyTextureToBuffer: writeTexture_ → readbackBuffer_
    WGPUCommandEncoderDescriptor encDesc = {};
    encDesc.label = MakeStringView("Readback Encoder");
    WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(device_.get(), &encDesc);

    WGPUTexelCopyTextureInfo src = {};
    src.texture  = writeTexture_.get();
    src.mipLevel = 0;
    src.origin   = {0, 0, 0};
    src.aspect   = WGPUTextureAspect_All;

    WGPUTexelCopyBufferInfo dst = {};
    dst.buffer             = readbackBuffer_.get();
    dst.layout.offset      = 0;
    dst.layout.bytesPerRow = bytesPerRow;
    dst.layout.rowsPerImage = H;

    WGPUExtent3D extent = { W, H, 1 };
    wgpuCommandEncoderCopyTextureToBuffer(enc, &src, &dst, &extent);

    WGPUCommandBufferDescriptor cbDesc = {};
    cbDesc.label = MakeStringView("Readback CmdBuf");
    WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, &cbDesc);
    wgpuQueueSubmit(queue_.get(), 1, &cb);
    wgpuCommandBufferRelease(cb);
    wgpuCommandEncoderRelease(enc);

    captureState_ = CaptureState::Pending;

    // Request async mapping.  The callback fires when the browser has finished
    // copying the GPU data to the CPU-accessible buffer.
    wgpuBufferMapAsync(
        readbackBuffer_.get(),
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
    if (!readbackBuffer_.get() || !outRGBA8) return 0;

    const uint32_t W = static_cast<uint32_t>(canvasWidth_);
    const uint32_t H = static_cast<uint32_t>(canvasHeight_);
    const int required = static_cast<int>(W * H * 4);
    if (maxBytes < required) return 0;

    const void* mapped = wgpuBufferGetConstMappedRange(readbackBuffer_.get(), 0,
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
    if (readbackBuffer_.get() && captureState_ == CaptureState::Ready) {
        wgpuBufferUnmap(readbackBuffer_.get());
    }
    captureState_ = CaptureState::Idle;
}

} // namespace pixelocity
