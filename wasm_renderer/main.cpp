#include <webgpu/webgpu_cpp.h>
#include <emscripten/emscripten.h>
#include <emscripten/html5.h>
// #include <emscripten/html5_webgpu.h>
#include <string>
#include <vector>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <stdio.h>

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

// Global state
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

// Simulation state
int currentBuffer = 0;
SimParams params = {
    0.785f,  // sensorAngle (PI/4)
    9.0f,    // sensorDist
    0.1f,    // turnSpeed
    0.95f,   // decayRate
    0.5f,    // depositAmount
    0.3f,    // videoFoodStrength
    0.5f,    // audioPulseStrength
    0.5f,    // mouseAttraction
    0.5f, 0.5f, // mouseX, mouseY
    0.0f, 0.0f, 0.0f, // audio bands
    0.0f,    // time
    50000,   // agentCount
    1920,    // width
    1080     // height
};

std::vector<Agent> agents;
bool wasmMode = true;

// Compute shader WGSL (embedded)
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

// Callbacks
void onAdapterRequest(WGPURequestAdapterStatus status, WGPUAdapter adapter, const char* message, void* userdata);
void onDeviceRequest(WGPURequestDeviceStatus status, WGPUDevice dev, const char* message, void* userdata);

extern "C" {
    EMSCRIPTEN_KEEPALIVE
    void initWasmRenderer(int width, int height, int agentCount) {
        params.width = width;
        params.height = height;
        params.agentCount = agentCount;

        // Initialize agents
        agents.resize(agentCount);
        for (uint32_t i = 0; i < agentCount; i++) {
            agents[i].x = (float)(rand() % width);
            agents[i].y = (float)(rand() % height);
            agents[i].angle = ((float)rand() / (float)RAND_MAX) * 6.28318f;
            agents[i].speed = 1.0f;
        }
        
        wgpu::Instance instance = wgpu::CreateInstance(nullptr);
        wgpu::RequestAdapterOptions opts{};
        opts.powerPreference = wgpu::PowerPreference::HighPerformance;
        instance.RequestAdapter(&opts, wgpu::CallbackMode::AllowSpontaneous, onAdapterRequest, nullptr);
    }

    EMSCRIPTEN_KEEPALIVE
    void updateVideoFrame(EMSCRIPTEN_WEBGL_CONTEXT_HANDLE ctx) {
        // Video frame update from JS
        // Import external texture from video element
        // videoTexture = emscripten_webgpu_import_texture(ctx);
        // Note: External texture import needs proper WebGL context handling
        (void)ctx; // Suppress unused warning for now
    }

    EMSCRIPTEN_KEEPALIVE
    void updateAudioData(float bass, float mid, float treble) {
        params.audioBass = bass;
        params.audioMid = mid;
        params.audioTreble = treble;
    }

    EMSCRIPTEN_KEEPALIVE
    void updateMousePos(float x, float y) {
        params.mouseX = x;
        params.mouseY = y;
    }

    EMSCRIPTEN_KEEPALIVE
    void toggleRenderer(int useWasm) {
        wasmMode = useWasm != 0;
    }
}

void onAdapterRequest(WGPURequestAdapterStatus status, WGPUAdapter cAdapter, const char* message, void* userdata) {
    if (status != WGPURequestAdapterStatus_Success) {
        printf("❌ Adapter failed: %s\n", message);
        return;
    }

    wgpu::Adapter adapter = wgpu::Adapter::Acquire(cAdapter);

    wgpu::DeviceDescriptor devDesc{};
    adapter.RequestDevice(&devDesc, wgpu::CallbackMode::AllowSpontaneous, onDeviceRequest, nullptr);
}

EMSCRIPTEN_KEEPALIVE
void loadImageData(const uint8_t* data, int width, int height) {
    if (!g_renderer) {
        printf("❌ Renderer not initialized\n");
        return;
    }
    g_renderer->LoadImage(data, width, height);
}

EMSCRIPTEN_KEEPALIVE
void uploadVideoFrame(const uint8_t* data, int width, int height) {
    if (!g_renderer) return;
    g_renderer->UpdateVideoFrame(data, width, height);
}

EMSCRIPTEN_KEEPALIVE
float getFPS() {
    if (!g_renderer) return 0.0f;
    return g_renderer->GetFPS();
}

void createPipelines() {
    // Create shader modules
    wgpu::ShaderModuleWGSLDescriptor wgslDesc{};
    wgpu::ShaderModuleDescriptor shaderDesc{};
    shaderDesc.nextInChain = (const wgpu::ChainedStruct*)&wgslDesc;

    wgslDesc.code = COMPUTE_WGSL;
    computeShader = device.CreateShaderModule(&shaderDesc);

    wgslDesc.code = RENDER_WGSL;
    renderShader = device.CreateShaderModule(&shaderDesc);

    printf("✅ WASM Renderer: Pipelines created\n");
}

void onDeviceRequest(WGPURequestDeviceStatus status, WGPUDevice cDevice, const char* message, void* userdata) {
    if (status != WGPURequestDeviceStatus_Success) {
        printf("❌ Device failed: %s\n", message);
        return;
    }

    device = wgpu::Device::Acquire(cDevice);
    queue = device.GetQueue();

    createPipelines();

    printf("✅ C++ WASM Renderer ready — %zu agents initialized\n", agents.size());
}

void renderLoop() {
    if (!wasmMode || !device) return;

    params.time += 0.016f;

    // Update uniform buffer
    queue.WriteBuffer(paramsBuffer, 0, &params, sizeof(params));

    // Compute pass: agent update
    wgpu::CommandEncoder encoder = device.CreateCommandEncoder();

    {
        wgpu::ComputePassEncoder pass = encoder.BeginComputePass();
        pass.SetPipeline(agentPipeline);
        pass.SetBindGroup(0, agentBindGroup[currentBuffer]);
        pass.DispatchWorkgroups((params.agentCount + 255) / 256);
        pass.End();
    }

    // Compute pass: diffusion
    {
        wgpu::ComputePassEncoder pass = encoder.BeginComputePass();
        pass.SetPipeline(trailPipeline);
        pass.SetBindGroup(0, agentBindGroup[currentBuffer]);
        pass.DispatchWorkgroups((params.width + 15) / 16, (params.height + 15) / 16);
        pass.End();
    }

    wgpu::CommandBuffer commands = encoder.Finish();
    queue.Submit(1, &commands);

    // Swap buffers
    currentBuffer = 1 - currentBuffer;
}

int main() {
    printf("Pixelocity WASM Renderer initialized\n");
    emscripten_set_main_loop(renderLoop, 0, true);
    return 0;
}
