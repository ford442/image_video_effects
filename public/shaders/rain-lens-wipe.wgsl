// Rain-lens distortion with falling streak packets and click-launched wipe fronts.

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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

fn rainDistortion(uv: vec2<f32>, time: f32, scale: f32) -> vec2<f32> {
    // Cell identity is spatially stable; only the closed-form fall phase moves.
    let fallingUV = uv + vec2<f32>(sin(time * 0.41) * 0.025, time * 0.42);
    let cellUV = fallingUV * scale;
    let cell = floor(cellUV);
    let local = fract(cellUV);
    var nearest = 1.0;
    var offset = vec2<f32>(0.0);
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let seed = hash22(cell + neighbor);
            let center = vec2<f32>(0.2 + seed.x * 0.6, 0.18 + seed.y * 0.64);
            let delta = neighbor + center - local;
            let dropDistance = length(delta * vec2<f32>(1.0, 1.7));
            if (dropDistance < nearest) {
                nearest = dropDistance;
                offset = delta;
            }
        }
    }
    let drop = smoothstep(0.45, 0.30, nearest);
    return offset * drop;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let rainStrength = u.zoom_params.x;
    let decaySpeed = 0.003 + u.zoom_params.y * 0.05;
    let wipeRadius = 0.05 + u.zoom_params.z * 0.30;
    let rainScale = 5.0 + u.zoom_params.w * 20.0;
    let aspect = resolution.x / resolution.y;

    // Advect the clean-state mask downward with the falling water.
    let stateUV = clamp(uv - vec2<f32>(sin(time * 0.7) * 0.0015, 0.004 + rainStrength * 0.006), vec2<f32>(0.0), vec2<f32>(1.0));
    let previousState = historyLoadUV(stateUV).r;
    var newState = max(0.0, previousState - decaySpeed);
    let mouseDistance = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0));
    let mouseWipe = smoothstep(wipeRadius, wipeRadius * 0.45, mouseDistance) * (0.30 + u.zoom_config.w * 0.70);
    newState = max(newState, mouseWipe);

    var clickWipe = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.8) {
            let ring = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.22 + audio.x * 0.08));
            clickWipe += (1.0 - smoothstep(0.0, 0.03, ring)) * (1.0 - age / 2.8);
        }
    }
    newState = clamp(max(newState, clickWipe), 0.0, 1.0);

    let distortion = rainDistortion(uv, time * (1.0 + rainStrength * 1.8), rainScale);
    let streakPhase = fract(uv.y * (5.0 + u.zoom_params.w * 11.0) - time * (1.4 + rainStrength * 3.5) + floor(uv.x * rainScale) * 0.173);
    let streakPacket = exp(-pow((streakPhase - 0.5) / 0.09, 2.0));
    let streakOffset = vec2<f32>(sin(uv.x * rainScale * 2.1 + time) * 0.002, -0.012 * streakPacket) * rainStrength;
    let finalDistortion = (distortion * rainStrength * 0.10 + streakOffset) * (1.0 - newState);
    let sampleUV = clamp(uv + finalDistortion, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let wetness = clamp(length(finalDistortion) * 18.0 + streakPacket * 0.18, 0.0, 1.0) * (1.0 - newState);
    let finalColor = vec4<f32>(clamp(color.rgb + vec3<f32>(0.08, 0.11, 0.14) * wetness * (1.0 + audio.z), vec3<f32>(0.0), vec3<f32>(1.0)), clamp(color.a, 0.0, 1.0));

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, vec4<f32>(newState, 0.0, 0.0, 1.0));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
