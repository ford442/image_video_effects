// ═══════════════════════════════════════════════════════════════════
//  Neural Nexus
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: neural-nexus
//  Upgraded: 2026-05-30
// ═══════════════════════════════════════════════════════════════════
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let density = clamp(u.zoom_params.x, 0.5, 4.0);
    let signalSpeed = clamp(u.zoom_params.y, 0.0, 4.0);
    let decayRate = clamp(u.zoom_params.z, 0.05, 2.5);
    let branches = clamp(u.zoom_params.w, 1.0, 8.0);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    var activity = 0.0;
    var sparks = 0.0;
    let nodeCount = 5u + u32(density * 2.0);

    for (var i: u32 = 0u; i < nodeCount; i = i + 1u) {
        let seed = f32(i) * 17.23;
        let neuronPos = vec2<f32>(
            hash(vec2<f32>(seed, 0.13)),
            hash(vec2<f32>(seed, 9.71))
        );
        let toNeuron = uv - neuronPos;
        let dist = max(length(toNeuron), 0.001);
        let connectionDist = distance(neuronPos, mousePos);
        let signalPhase = time * (3.0 + bass * 6.0) - connectionDist * (2.5 + signalSpeed * 2.0) * 6.0;
        let pulse = sin(signalPhase) * exp(-connectionDist * (1.5 + decayRate));
        let angle = atan2(toNeuron.y, toNeuron.x);
        let dendrite = 0.5 + 0.5 * cos(angle * branches + time * (1.2 + treble * 3.0) + seed);
        let aura = pulse * dendrite / (dist * (2.5 + density) + 0.35);
        activity += aura;
        sparks += exp(-dist * (20.0 + treble * 15.0)) * (0.3 + 0.7 * abs(pulse));
    }

    let mouseDist = distance(uv, mousePos);
    let mousePulse = sin(mouseDist * (16.0 + treble * 12.0) - time * (7.0 + bass * 4.0)) *
        exp(-mouseDist * (3.0 + density)) * (0.3 + bass * 0.7);

    let totalActivity = activity + mousePulse;
    let sampleUV = clamp(
        uv + vec2<f32>(totalActivity * 0.025, activity * 0.015 + mousePulse * 0.01),
        vec2<f32>(0.001, 0.001),
        vec2<f32>(0.999, 0.999)
    );
    let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let electricBlue = vec3<f32>(0.05, 0.45 + treble * 0.15, 1.0) * max(totalActivity, 0.0);
    let synapsePurple = vec3<f32>(0.9, 0.15, 1.0) * max(-totalActivity, 0.0) * 0.65;
    let warmSparks = vec3<f32>(1.0, 0.7 + mids * 0.2, 0.25) * sparks * (0.12 + bass * 0.08);
    let finalColor = baseColor.rgb + electricBlue + synapsePurple + warmSparks;
    let alpha = clamp(baseColor.a * 0.38 + abs(totalActivity) * 0.28 + sparks * 0.2 + bass * 0.05, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + abs(totalActivity) * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(totalActivity, sparks, mousePulse, alpha));
}
