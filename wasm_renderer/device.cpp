#include "renderer.h"
#include "wasm_internal.h"
#include <webgpu/webgpu.h>
#include <emscripten/emscripten.h>
#include <emscripten/em_js.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <algorithm>

namespace pixelocity {

using wasm_internal::MakeStringView;
using wasm_internal::CheckLimit;


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


bool WebGPURenderer::CreateDevice() {
    // Adapter ladder, limit validation, and requiredLimits must stay in sync with
    // src/renderer/webgpuDevicePolicy.ts (TypeScript WebGPU path).
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
    // Validate against the minimums implied by the 14-entry compute bind group
    // contract (bindings 0–13; see docs/BINDING_CONTRACT.md) so that a weak
    // adapter fails here with an actionable message instead of deep inside
    // CreateResources() with a cryptic bind-group-layout error.
    WGPULimits limits = {};
    wgpuAdapterGetLimits(adapter_.get(), &limits);

    bool limitsOk = true;
    const uint64_t maxCanvasDim = (uint64_t)std::max(canvasWidth_, canvasHeight_);
    printf("[WASM] Adapter limits (validating against 14-entry compute contract):\n");
    CheckLimit("maxTextureDimension2D",              limits.maxTextureDimension2D,              maxCanvasDim, limitsOk);
    CheckLimit("maxBindingsPerBindGroup",            limits.maxBindingsPerBindGroup,            14,  limitsOk);
    CheckLimit("maxSampledTexturesPerShaderStage",   limits.maxSampledTexturesPerShaderStage,    3,  limitsOk);
    CheckLimit("maxSamplersPerShaderStage",          limits.maxSamplersPerShaderStage,           3,  limitsOk);
    CheckLimit("maxStorageTexturesPerShaderStage",   limits.maxStorageTexturesPerShaderStage,    4,  limitsOk);
    CheckLimit("maxStorageBuffersPerShaderStage",    limits.maxStorageBuffersPerShaderStage,     2,  limitsOk);
    CheckLimit("maxUniformBuffersPerShaderStage",    limits.maxUniformBuffersPerShaderStage,     1,  limitsOk);
    CheckLimit("maxComputeWorkgroupSizeX",           limits.maxComputeWorkgroupSizeX,            16, limitsOk);
    CheckLimit("maxComputeWorkgroupSizeY",           limits.maxComputeWorkgroupSizeY,            16, limitsOk);
    CheckLimit("maxComputeInvocationsPerWorkgroup",  limits.maxComputeInvocationsPerWorkgroup,   256, limitsOk);

    maxComputeInvocations_ = limits.maxComputeInvocationsPerWorkgroup;
    supportsDeepWorkgroup_ = maxComputeInvocations_ >= 1024;
    printf("[WASM] Adapter limits: maxTex2D=%u, storageTex=%u, sampledTex=%u, computeInvocations=%u (%s)\n",
           limits.maxTextureDimension2D, limits.maxStorageTexturesPerShaderStage,
           limits.maxSampledTexturesPerShaderStage, limits.maxComputeInvocationsPerWorkgroup,
           limitsOk ? "sufficient" : "INSUFFICIENT");
    printf("[WASM] Deep-workgroup (1024 invocations): %s\n",
           supportsDeepWorkgroup_ ? "supported" : "NOT supported");

    // ── Feature checks ────────────────────────────────────────────────────
    // rgba32float storage textures (bindings 2/7/8) require float32-filterable/
    // blendable support on some backends; log so it's visible in diagnostics.
    bool hasFloat32Filterable = wgpuAdapterHasFeature(adapter_.get(), WGPUFeatureName_Float32Filterable);
    bool hasFloat32Blendable  = wgpuAdapterHasFeature(adapter_.get(), WGPUFeatureName_Float32Blendable);
    bool hasBGRA8Storage      = wgpuAdapterHasFeature(adapter_.get(), WGPUFeatureName_BGRA8UnormStorage);
#ifdef WGPUFeatureName_TimestampQuery
    bool hasTimestampQuery    = wgpuAdapterHasFeature(adapter_.get(), WGPUFeatureName_TimestampQuery);
#else
    bool hasTimestampQuery    = false;
#endif
    printf("[WASM] Adapter features: Float32Filterable=%s Float32Blendable=%s BGRA8UnormStorage=%s TimestampQuery=%s\n",
           hasFloat32Filterable ? "yes" : "no",
           hasFloat32Blendable  ? "yes" : "no",
           hasBGRA8Storage      ? "yes" : "no",
           hasTimestampQuery    ? "yes" : "no");

    if (!limitsOk) {
        printf("❌ Adapter does not meet the minimum WebGPU limits required by Pixelocity's\n");
        printf("   14-entry compute bind group contract (see entries marked INSUFFICIENT above).\n");
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
    requiredLimits.maxBindingsPerBindGroup           = 14;
    requiredLimits.maxSampledTexturesPerShaderStage  = 3;
    requiredLimits.maxSamplersPerShaderStage         = 3;
    requiredLimits.maxStorageTexturesPerShaderStage  = 4;
    requiredLimits.maxStorageBuffersPerShaderStage   = 2;
    requiredLimits.maxUniformBuffersPerShaderStage   = 1;
    requiredLimits.maxUniformBufferBindingSize       = sizeof(Uniforms);
    requiredLimits.maxComputeWorkgroupSizeX          = 16;
    requiredLimits.maxComputeWorkgroupSizeY          = 16;
    requiredLimits.maxComputeInvocationsPerWorkgroup = 256;

    // Optional features: request float32-filterable when the adapter offers it
    // (matches TypeScript webgpuDevicePolicy / WebGPURenderer.init()).
    WGPUFeatureName requiredFeatures[2] = {};
    size_t requiredFeatureCount = 0;
    if (hasFloat32Filterable) {
        requiredFeatures[requiredFeatureCount++] = WGPUFeatureName_Float32Filterable;
        printf("[WASM] Requesting device feature: Float32Filterable\n");
    }
#ifdef WGPUFeatureName_TimestampQuery
    if (hasTimestampQuery) {
        requiredFeatures[requiredFeatureCount++] = WGPUFeatureName_TimestampQuery;
        printf("[WASM] Requesting device feature: TimestampQuery\n");
    }
#endif

    // Request device using callback-based API
    WGPUDeviceDescriptor deviceDesc = {};
    deviceDesc.nextInChain = nullptr;
    deviceDesc.label = MakeStringView("Pixelocity Device");
    deviceDesc.requiredFeatureCount = requiredFeatureCount;
    deviceDesc.requiredFeatures = requiredFeatureCount > 0 ? requiredFeatures : nullptr;
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
            if (userdata1) {
                WebGPURenderer::MarkDeviceLostFromCallback(userdata1);
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
        CheckLimit("maxBindingsPerBindGroup",           deviceLimits.maxBindingsPerBindGroup,           14,  deviceLimitsOk);
        CheckLimit("maxSampledTexturesPerShaderStage",  deviceLimits.maxSampledTexturesPerShaderStage,  3,   deviceLimitsOk);
        CheckLimit("maxSamplersPerShaderStage",         deviceLimits.maxSamplersPerShaderStage,         3,   deviceLimitsOk);
        CheckLimit("maxStorageTexturesPerShaderStage",  deviceLimits.maxStorageTexturesPerShaderStage,  4,   deviceLimitsOk);
        CheckLimit("maxStorageBuffersPerShaderStage",   deviceLimits.maxStorageBuffersPerShaderStage,   2,   deviceLimitsOk);
        CheckLimit("maxUniformBuffersPerShaderStage",   deviceLimits.maxUniformBuffersPerShaderStage,   1,   deviceLimitsOk);
        CheckLimit("maxComputeInvocationsPerWorkgroup", deviceLimits.maxComputeInvocationsPerWorkgroup, 256, deviceLimitsOk);
        if (!deviceLimitsOk) {
            printf("⚠️  Device limits were clamped below the adapter's reported limits and no\n");
            printf("   longer meet the 14-entry compute contract minimums. Rendering may fail.\n");
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
#ifdef WGPUFeatureName_TimestampQuery
    if (supportsTimestampQuery_ && timestampQuerySet_.get()) {
        wgpuRenderPassEncoderWriteTimestamp(rp, timestampQuerySet_.get(),
                                            static_cast<uint32_t>(wasm_internal::kTsPresentStart));
    }
#endif
    wgpuRenderPassEncoderSetPipeline(rp, renderPipeline_.get());
    wgpuRenderPassEncoderSetBindGroup(rp, 0, renderBindGroup_.get(), 0, nullptr);
    wgpuRenderPassEncoderDraw(rp, 4, 1, 0, 0);  // 4 verts for TriangleStrip quad
#ifdef WGPUFeatureName_TimestampQuery
    if (supportsTimestampQuery_ && timestampQuerySet_.get()) {
        wgpuRenderPassEncoderWriteTimestamp(rp, timestampQuerySet_.get(),
                                            static_cast<uint32_t>(wasm_internal::kTsPresentEnd));
    }
#endif
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


} // namespace pixelocity
