#include "renderer.h"

// ARCH: [Critical] Inconsistent API usage: includes both C webgpu.h and C++ webgpu_cpp.h.
// renderer.cpp uses C API (WGPU* types), this file uses C++ API (wgpu:: namespace).
// This creates confusion and prevents code sharing between the two implementations.
#include <webgpu/webgpu_cpp.h>

#include <emscripten/emscripten.h>
#include <emscripten/html5.h>
// ARCH: [Low] Commented include remains in code. Remove dead code.
// #include <emscripten/html5_webgpu.h>

#include <string>
#include <vector>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <stdio.h>

// ARCH: [Low] Inconsistent header style mixing C (<stdio.h>) and C++ (<string>).
// Prefer C++ headers: <cstdio>

using namespace pixelocity;

// ═══════════════════════════════════════════════════════════════════════════════
// PHYSARUM SIMULATION - DEAD CODE / ALTERNATE IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
// ARCH: [Critical] This entire section (lines 20-248) is DEAD CODE.
// The Physarum simulation is never used because:
// 1. WebGPURenderer class (defined in renderer.h/cpp) is used instead
// 2. Global state below conflicts with WebGPURenderer's internal state
// 3. createPipelines(), renderLoop(), etc. are never called
// 
// This appears to be an alternative implementation that was abandoned
// but not removed. It adds 200+ lines of maintenance burden.
// 
// REFACTOR: Remove all Physarum code OR merge it as an optional
// simulation mode within WebGPURenderer class.
// ═══════════════════════════════════════════════════════════════════════════════

// Physarum 3.0 Agent Structure
struct Agent {
    float x, y;      // Position
    float angle;     // Heading angle
    float speed;     // Movement speed
};

// Uniforms for compute shader
struct SimParams {
    float sensorAngle;
    float sensorDist;
    float turnSpeed;
    float decayRate;
    float depositAmount;
    float videoFoodStrength;
    float audioPulseStrength;
    float mouseAttraction;
    float mouseX, mouseY;
    float audioBass, audioMid, audioTreble;
    float time;
    uint32_t agentCount;
    uint32_t width;
    uint32_t height;
};

// ARCH: [Critical] Global state for Physarum - never initialized or used.
// These globals shadow/conflict with WebGPURenderer's member variables.
wgpu::Device device;
wgpu::Queue queue;
wgpu::Buffer agentBuffer[2];  // Double buffer
wgpu::Buffer paramsBuffer;
wgpu::Buffer stagingBuffer;
wgpu::Texture trailMap;
wgpu::TextureView trailView;
wgpu::Sampler trailSampler;
wgpu::ComputePipeline agentPipeline;
wgpu::ComputePipeline trailPipeline;
wgpu::RenderPipeline displayPipeline;
wgpu::BindGroup agentBindGroup[2];
wgpu::BindGroupLayout agentBindLayout;
wgpu::ShaderModule computeShader;
wgpu::ShaderModule renderShader;

// Video texture (imported from JS)
WGPUTexture videoTexture = nullptr;
WGPUTextureView videoView = nullptr;

// ARCH: [High] Global state with 15+ magic number initializers.
// These should be named constants or loaded from config.
int currentBuffer = 0;
SimParams params = {
    0.785f,  // sensorAngle (PI/4) - MAGIC NUMBER
    9.0f,    // sensorDist - MAGIC NUMBER
    0.1f,    // turnSpeed - MAGIC NUMBER
    0.95f,   // decayRate - MAGIC NUMBER
    0.5f,    // depositAmount - MAGIC NUMBER
    0.3f,    // videoFoodStrength - MAGIC NUMBER
    0.5f,    // audioPulseStrength - MAGIC NUMBER
    0.5f,    // mouseAttraction - MAGIC NUMBER
    0.5f, 0.5f, // mouseX, mouseY
    0.0f, 0.0f, 0.0f, // audio bands
    0.0f,    // time
    50000,   // agentCount - MAGIC NUMBER
    1920,    // width - MAGIC NUMBER
    1080     // height - MAGIC NUMBER
};

std::vector<Agent> agents;
bool wasmMode = true;

// ARCH: [Medium] Global renderer pointer is raw - potential memory leak
// if exception thrown during initialization. Use std::unique_ptr.
WebGPURenderer* g_renderer = nullptr;

// Compute shader WGSL (embedded)
// ARCH: [High] 200+ lines of embedded WGSL makes this file unmaintainable.
// Shaders should be in separate .wgsl files loaded at runtime
// or at least in separate header files.
const char* COMPUTE_WGSL = R"(
struct Agent {
    pos: vec2<f32>,
    angle: f32,
    speed: f32,
}

struct SimParams {
    sensorAngle: f32,
    sensorDist: f32,
    turnSpeed: f32,
    decayRate: f32,
    depositAmount: f32,
    videoFoodStrength: f32,
    audioPulseStrength: f32,
    mouseAttraction: f32,
    mouseX: f32,
    mouseY: f32,
    audioBass: f32,
    audioMid: f32,
    audioTreble: f32,
    time: f32,
    agentCount: u32,
    width: u32,
    height: u32,
}

@binding(0) @group(0) var<uniform> params: SimParams;
@binding(1) @group(0) var<storage, read> agentsIn: array<Agent>;
@binding(2) @group(0) var<storage, read_write> agentsOut: array<Agent>;
@binding(3) @group(0) var trailMap: texture_storage_2d<rgba8unorm, read_write>;
@binding(4) @group(0) var videoMap: texture_2d<f32>;
@binding(5) @group(0) var videoSampler: sampler;

fn sense(agent: Agent, angle: f32) -> f32 {
    let sensorDir = vec2<f32>(cos(agent.angle + angle), sin(agent.angle + angle));
    let sensorPos = agent.pos + sensorDir * params.sensorDist;
    let uv = sensorPos / vec2<f32>(f32(params.width), f32(params.height));

    // Sample trail map
    let trail = textureLoad(trailMap, vec2<i32>(sensorPos)).r;

    // Sample video brightness as food
    let videoColor = textureSample(videoMap, videoSampler, uv);
    let brightness = dot(videoColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    return trail + brightness * params.videoFoodStrength;
}

fn hash(n: u32) -> f32 {
    var x = n;
    x = (x ^ 61u) ^ (x >> 16u);
    x = x + (x << 3u);
    x = x ^ (x >> 4u);
    x = x * 0x27d4eb2du;
    x = x ^ (x >> 15u);
    return f32(x) / 4294967295.0;
}

@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let idx = id.x;
    if (idx >= params.agentCount) { return; }

    var agent = agentsIn[idx];

    // Audio pulse affects speed
    let audioBoost = 1.0 + params.audioBass * params.audioPulseStrength;

    // Sense left, center, right
    let senseL = sense(agent, -params.sensorAngle);
    let senseC = sense(agent, 0.0);
    let senseR = sense(agent, params.sensorAngle);

    // Steer based on sensor readings
    var turn = 0.0;
    if (senseC > senseL && senseC > senseR) {
        turn = 0.0;
    } else if (senseC < senseL && senseC < senseR) {
        turn = (hash(idx + u32(params.time * 1000.0)) - 0.5) * 2.0 * params.turnSpeed;
    } else if (senseL > senseR) {
        turn = -params.turnSpeed;
    } else {
        turn = params.turnSpeed;
    }

    // Mouse attraction/repulsion
    let mousePos = vec2<f32>(params.mouseX * f32(params.width), params.mouseY * f32(params.height));
    let toMouse = mousePos - agent.pos;
    let mouseAngle = atan2(toMouse.y, toMouse.x);
    let angleDiff = mouseAngle - agent.angle;
    turn += angleDiff * params.mouseAttraction * 0.1;

    // Update angle and position
    agent.angle += turn;
    let dir = vec2<f32>(cos(agent.angle), sin(agent.angle));
    agent.pos += dir * agent.speed * audioBoost;

    // Wrap around edges
    if (agent.pos.x < 0.0) { agent.pos.x = f32(params.width); }
    if (agent.pos.x > f32(params.width)) { agent.pos.x = 0.0; }
    if (agent.pos.y < 0.0) { agent.pos.y = f32(params.height); }
    if (agent.pos.y > f32(params.height)) { agent.pos.y = 0.0; }

    agentsOut[idx] = agent;

    // Deposit trail
    let pixelPos = vec2<i32>(agent.pos);
    let current = textureLoad(trailMap, pixelPos);
    textureStore(trailMap, pixelPos, current + vec4<f32>(params.depositAmount * audioBoost, 0.0, 0.0, 1.0));
}

@compute @workgroup_size(16, 16)
fn diffuse(@builtin(global_invocation_id) id: vec3<u32>) {
    let pos = vec2<i32>(id.xy);
    if (pos.x >= i32(params.width) || pos.y >= i32(params.height)) { return; }

    var sum = vec4<f32>(0.0);
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let samplePos = pos + vec2<i32>(dx, dy);
            sum += textureLoad(trailMap, samplePos);
        }
    }
    let avg = sum / 9.0;
    let current = textureLoad(trailMap, pos);
    let diffused = mix(current, avg, 0.1) * params.decayRate;

    textureStore(trailMap, pos, diffused);
}
)";

// Render shader WGSL
const char* RENDER_WGSL = R"(
struct VertexOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOut {
    var out: VertexOut;
    let uv = vec2<f32>(f32(idx % 2u), f32(idx / 2u));
    out.pos = vec4<f32>(uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv = uv;
    return out;
}

@group(0) @binding(0) var trailSampler: sampler;
@group(0) @binding(1) var trailTexture: texture_2d<f32>;
@group(0) @binding(2) var videoTexture: texture_2d<f32>;

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let trail = textureSample(trailTexture, trailSampler, in.uv);
    let video = textureSample(videoTexture, trailSampler, in.uv);

    // Blend trail with video
    let color = mix(video.rgb, vec3<f32>(0.1, 0.8, 0.3), trail.r * 2.0);
    return vec4<f32>(color, 1.0);
}
)";

// Forward declarations
// ARCH: [High] These functions are declared but implemented after being needed.
// Organize code to avoid forward declarations where possible.
void createPipelines();
void onAdapterRequest(wgpu::RequestAdapterStatus status, wgpu::Adapter adapter, wgpu::StringView message);
void onDeviceRequest(wgpu::RequestDeviceStatus status, wgpu::Device dev, wgpu::StringView message);

// ═══════════════════════════════════════════════════════════════════════════════
// C API EXPORTS - These are the actual working functions
// ═══════════════════════════════════════════════════════════════════════════════

extern "C" {
    // ARCH: [Medium] Inconsistent naming convention:
    // - Some functions use camelCase: initWasmRenderer, loadShader
    // - Some use PascalCase: SetActiveShader (not exported here)
    // Standardize on one convention for C API exports.

    EMSCRIPTEN_KEEPALIVE
    void initWasmRenderer(int width, int height, int agentCount) {
        // ARCH: [High] Using raw new without try-catch. If WebGPURenderer
        // constructor throws, program terminates.
        if (!g_renderer) {
            g_renderer = new WebGPURenderer();
        }
        g_renderer->Initialize(width, height);

        // ARCH: [Critical] These params are for the DEAD Physarum code,
        // not for WebGPURenderer. Confusing and misleading.
        params.width = width;
        params.height = height;
        params.agentCount = agentCount;

        // Initialize agents for Physarum (dead code)
        agents.resize(agentCount);
        for (uint32_t i = 0; i < agentCount; i++) {
            agents[i].x = (float)(rand() % width);
            agents[i].y = (float)(rand() % height);
            // ARCH: [Low] Magic number 6.28318f = 2*PI. Use constant: constexpr float TWO_PI = 6.28318530718f;
            agents[i].angle = ((float)rand() / (float)RAND_MAX) * 6.28318f;
            agents[i].speed = 1.0f;
        }
    }

    EMSCRIPTEN_KEEPALIVE
    void updateVideoFrame(EMSCRIPTEN_WEBGL_CONTEXT_HANDLE ctx) {
        // ARCH: [High] Function is STUB - doesn't actually update video frame.
        // The working implementation is uploadVideoFrame() below.
        // This function appears to be for WebGL texture import which was never completed.
        (void)ctx;
    }

    EMSCRIPTEN_KEEPALIVE
    void updateAudioData(float bass, float mid, float treble) {
        // ARCH: [High] Updates dead Physarum params, not WebGPURenderer.
        // WebGPURenderer has no audio support currently.
        params.audioBass = bass;
        params.audioMid = mid;
        params.audioTreble = treble;
    }

    EMSCRIPTEN_KEEPALIVE
    void updateMousePos(float x, float y) {
        // ARCH: [High] Updates dead Physarum params, not WebGPURenderer.
        // The JS bridge calls setActiveShader path instead.
        params.mouseX = x;
        params.mouseY = y;
    }

    EMSCRIPTEN_KEEPALIVE
    void toggleRenderer(int useWasm) {
        // ARCH: [Medium] wasmMode is only checked in DEAD renderLoop().
        // This toggle has no effect on actual rendering.
        wasmMode = useWasm != 0;
    }

    EMSCRIPTEN_KEEPALIVE
    void shutdownWasmRenderer() {
        if (g_renderer) {
            g_renderer->Shutdown();
            delete g_renderer;
            g_renderer = nullptr;
        }
    }

    EMSCRIPTEN_KEEPALIVE
    int loadShader(const char* id, const char* wgslCode) {
        // ARCH: [High] No validation of input pointers.
        // Null id or wgslCode will crash.
        if (!g_renderer) return 0;
        return g_renderer->LoadShader(id, wgslCode) ? 1 : 0;
    }

    EMSCRIPTEN_KEEPALIVE
    void setActiveShader(const char* id) {
        if (g_renderer) {
            g_renderer->SetActiveShader(id);
        }
    }

    EMSCRIPTEN_KEEPALIVE
    void addRipple(float x, float y) {
        if (g_renderer) {
            g_renderer->AddRipple(x, y);
        }
    }

    EMSCRIPTEN_KEEPALIVE
    void clearRipples() {
        if (g_renderer) {
            g_renderer->ClearRipples();
        }
    }

    EMSCRIPTEN_KEEPALIVE
    int isRendererInitialized() {
        return g_renderer && g_renderer->IsInitialized() ? 1 : 0;
    }

    // ARCH: [Critical] Function name is misleading - it calls Render(),
    // not updateUniforms(). This suggests confusion in design.
    EMSCRIPTEN_KEEPALIVE
    void updateUniforms() {
        if (g_renderer) {
            g_renderer->Render();
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEAD CODE - Physarum simulation functions never called
// ═══════════════════════════════════════════════════════════════════════════════

void onAdapterRequest(wgpu::RequestAdapterStatus status, wgpu::Adapter adapter, wgpu::StringView message) {
    // ARCH: [Critical] DEAD CODE - Never called because WebGPURenderer
    // creates its own device in CreateDevice().
    if (status != wgpu::RequestAdapterStatus::Success) {
        printf("Adapter failed: %s\n", message.data ? message.data : "");
        return;
    }

    wgpu::DeviceDescriptor devDesc{};
    adapter.RequestDevice(&devDesc, wgpu::CallbackMode::AllowSpontaneous, onDeviceRequest);
}

extern "C" {
    // ARCH: [Medium] Why is this EMSCRIPTEN_KEEPALIVE block separate from above?
    // Consolidate all exports in one location for maintainability.

    EMSCRIPTEN_KEEPALIVE
    void loadImageData(const uint8_t* data, int width, int height) {
        if (!g_renderer) return;
        g_renderer->LoadImage(data, width, height);
    }

    EMSCRIPTEN_KEEPALIVE
    void uploadVideoFrame(const uint8_t* data, int width, int height) {
        // ARCH: [Medium] This is the actual working video frame function,
        // but named inconsistently with updateVideoFrame() stub above.
        if (!g_renderer) return;
        g_renderer->UpdateVideoFrame(data, width, height);
    }

    EMSCRIPTEN_KEEPALIVE
    float getFPS() {
        if (!g_renderer) return 0.0f;
        return g_renderer->GetFPS();
    }
}

void createPipelines() {
    // ARCH: [Critical] DEAD CODE - Never called. WebGPURenderer creates
    // its own pipelines in CreateRenderPipeline().
    wgpu::ShaderSourceWGSL wgslDesc{};
    wgpu::ShaderModuleDescriptor shaderDesc{};
    shaderDesc.nextInChain = &wgslDesc;

    wgslDesc.code = COMPUTE_WGSL;
    computeShader = device.CreateShaderModule(&shaderDesc);

    wgslDesc.code = RENDER_WGSL;
    renderShader = device.CreateShaderModule(&shaderDesc);

    printf("WASM Renderer: Pipelines created\n");
}

void onDeviceRequest(wgpu::RequestDeviceStatus status, wgpu::Device dev, wgpu::StringView message) {
    // ARCH: [Critical] DEAD CODE - Never called.
    if (status != wgpu::RequestDeviceStatus::Success) {
        printf("Device failed: %s\n", message.data ? message.data : "");
        return;
    }

    device = std::move(dev);
    queue = device.GetQueue();

    createPipelines();

    printf("C++ WASM Renderer ready — %zu agents initialized\n", agents.size());
}

void renderLoop() {
    // ARCH: [Critical] DEAD CODE - This is the Physarum render loop.
    // Never called because main() sets up a different loop or
    // JavaScript drives rendering via updateUniforms().
    if (!wasmMode || !device) return;

    // ARCH: [Low] Magic number 0.016f assumes 60 FPS. Use delta time.
    params.time += 0.016f;

    // Update uniform buffer
    queue.WriteBuffer(paramsBuffer, 0, &params, sizeof(params));

    // Compute pass: agent update
    wgpu::CommandEncoder encoder = device.CreateCommandEncoder();

    {
        wgpu::ComputePassEncoder pass = encoder.BeginComputePass();
        pass.SetPipeline(agentPipeline);
        pass.SetBindGroup(0, agentBindGroup[currentBuffer]);
        // ARCH: [Medium] Magic numbers 255 and 256.
        // Use named constants: constexpr uint32_t WorkgroupSize = 256;
        pass.DispatchWorkgroups((params.agentCount + 255) / 256);
        pass.End();
    }

    // Compute pass: diffusion
    {
        wgpu::ComputePassEncoder pass = encoder.BeginComputePass();
        pass.SetPipeline(trailPipeline);
        pass.SetBindGroup(0, agentBindGroup[currentBuffer]);
        // ARCH: [Medium] Magic numbers 15 and 16.
        pass.DispatchWorkgroups((params.width + 15) / 16, (params.height + 15) / 16);
        pass.End();
    }

    wgpu::CommandBuffer commands = encoder.Finish();
    queue.Submit(1, &commands);

    // Swap buffers
    currentBuffer = 1 - currentBuffer;
}

int main() {
    // ARCH: [Medium] main() is called during WASM initialization but
    // doesn't actually initialize the renderer. JavaScript must call
    // initWasmRenderer() separately. This split initialization is confusing.
    printf("Pixelocity WASM Renderer initialized\n");
    
    // ARCH: [Critical] This sets up renderLoop() which is DEAD CODE
    // that uses Physarum simulation, not the WebGPURenderer.
    // The actual rendering is driven by JavaScript calling updateUniforms().
    emscripten_set_main_loop(renderLoop, 0, true);
    return 0;
}

// ARCH: OVERALL SUMMARY FOR main.cpp:
// This file has severe architectural issues:
// 1. Contains two completely separate rendering systems that don't interact
// 2. ~60% of the code is dead/unreachable
// 3. Mixes C and C++ WebGPU APIs inconsistently
// 4. Global state management is error-prone
// 5. EMSCRIPTEN_KEEPALIVE exports are scattered across multiple blocks
//
// RECOMMENDATION: Complete rewrite. Remove all Physarum code to a separate
// optional module, consolidate C API exports, use consistent WebGPU API style.
