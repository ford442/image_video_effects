// Ion stream with helical packet conveyors, magnetic wakes, and click fronts.

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let q = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), q.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), q.x), q.y);
}

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let speed = mix(1.0, 8.0, u.zoom_params.x);
    let curlStrength = u.zoom_params.y;
    let streamDensity = max(u.zoom_params.z, 0.02);
    let colorIntensity = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;

    let phaseNoise = valueNoise(uv * 5.0 + vec2<f32>(time * 0.16, -time * 0.11));
    let flow = vec2<f32>(cos(phaseNoise * 6.283 + time), sin(phaseNoise * 6.283 - time * 0.7)) * curlStrength;
    let advectedUV = clamp(uv + flow * 0.018 * (1.0 + audio.x * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseDelta = vec2<f32>((uv.x - u.zoom_config.y) * aspect, uv.y - u.zoom_config.z);
    let safeDist = max(length(mouseDelta), 0.001);
    let bendDir = vec2<f32>(-mouseDelta.y, mouseDelta.x) / safeDist;
    let magnetic = exp(-safeDist * 5.0) * (0.004 + curlStrength * 0.018) * (1.0 + u.zoom_config.w);
    let bentUV = clamp(advectedUV + bendDir * magnetic, vec2<f32>(0.0), vec2<f32>(1.0));
    let source = textureSampleLevel(readTexture, u_sampler, bentUV, 0.0);

    let lanes = max(2.0, floor(4.0 + streamDensity * 42.0));
    let lane = floor(uv.x * lanes);
    let laneCenter = (lane + 0.5) / lanes;
    let helix = sin(lane * 2.17 + uv.y * 18.0 - time * speed) * (0.018 + curlStrength * 0.05);
    let coreDist = abs(uv.x - laneCenter - helix);
    let core = exp(-coreDist * (90.0 + streamDensity * 140.0));
    let packetPhase = fract(uv.y * (3.0 + streamDensity * 9.0) - time * speed * 0.42 + lane * 0.173);
    let packet = exp(-pow((packetPhase - 0.5) / 0.10, 2.0));
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.6) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.24 + audio.x * 0.09));
            clickFront += (1.0 - smoothstep(0.0, 0.024, ring)) * (1.0 - age / 2.6);
        }
    }

    let wakeUV = clamp(uv - vec2<f32>(flow.x * 0.010, 0.006 + speed * 0.0015), vec2<f32>(0.0), vec2<f32>(1.0));
    let wake = historyLoadUV(wakeUV);
    let ionGlow = (core * (0.25 + packet * 1.6) + clickFront * 0.9) * colorIntensity * (1.0 + audio.y);
    let ionColor = mix(vec3<f32>(0.12, 0.45, 1.0), vec3<f32>(0.75, 0.2, 1.0), packet + audio.z * 0.4) * ionGlow;
    let finalRGB = clamp(mix(source.rgb, wake.rgb, 0.18 + curlStrength * 0.24) + ionColor, vec3<f32>(0.0), vec3<f32>(1.0));
    let alpha = clamp(max(source.a, wake.a * 0.88) + ionGlow * 0.45, 0.0, 1.0);
    let output = vec4<f32>(finalRGB, alpha);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
