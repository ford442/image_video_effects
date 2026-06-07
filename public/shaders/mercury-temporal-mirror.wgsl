// ═══════════════════════════════════════════════════════════════════
//  Mercury Temporal Mirror
//  Category: image
//  Features: liquid-mercury, temporal, ripple, reflection, audio-viscosity, mouse-impact, semantic-alpha
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — liquid mercury reflection with persistent ripple memory and visceral mouse impacts)
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
  zoom_params: vec4<f32>,  // x=Viscosity, y=Reflect, z=Impact, w=Metallic
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// Simple 2D wave equation step (temporal)
fn waveStep(prev: vec3<f32>, uv: vec2<f32>, dt: f32, viscosity: f32) -> vec3<f32> {
    let texel = 1.0 / u.config.zw;
    let l = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).xyz;
    let r = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( texel.x, 0.0), 0.0).xyz;
    let t = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).xyz;
    let b = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0,  texel.y), 0.0).xyz;

    let lap = (l + r + t + b) * 0.25 - prev;
    let damp = 1.0 - viscosity * 0.08;
    return (prev + lap * 0.92) * damp;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let viscosity = u.zoom_params.x * (0.6 + bass * 0.25);   // higher = slower, thicker mercury
    let reflectAmt = u.zoom_params.y;
    let impactAmt = u.zoom_params.z;
    let metallic = u.zoom_params.w;

    let mouse = u.zoom_config.yz;
    let isPress = u.zoom_config.w;

    // Read previous wave state (temporal memory)
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).xyz;

    // Input image
    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mouse impact ripples (visceral)
    var impact = 0.0;
    let md = length(uv - mouse);
    if (md < 0.28) {
        impact = (1.0 - smoothstep(0.0, 0.26, md)) * impactAmt * (0.5 + isPress * 1.5);
    }

    // Add new ripples from mouse + audio "rain"
    let rain = step(0.96, hash21(uv * 180.0 + floor(time * 11.0))) * treble * 0.6;
    let waveSource = impact + rain * 0.8;

    // Evolve wave field
    var wave = waveStep(prev, uv, 1.0, viscosity);
    wave.x = wave.x * 0.96 + waveSource * 1.4;

    // Distort UV with wave normals for reflection
    let waveNormal = vec2<f32>(wave.y - wave.z, wave.x * 0.6) * 0.035 * reflectAmt;
    let reflectUV = clamp(uv + waveNormal, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample reflected image (slightly blurred for liquid feel)
    let r1 = textureSampleLevel(readTexture, u_sampler, reflectUV, 0.0).rgb;
    let r2 = textureSampleLevel(readTexture, u_sampler, reflectUV + waveNormal * 0.6, 0.0).rgb;
    let reflected = (r1 + r2) * 0.5;

    // Mercury material response
    let luma = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let metalTint = mix(vec3<f32>(0.65, 0.68, 0.72), vec3<f32>(0.82, 0.85, 0.9), metallic);
    var col = mix(input.rgb * 0.15, reflected * metalTint, 0.35 + reflectAmt * 0.55);

    // Add specular highlights from wave
    let spec = pow(max(wave.x * 0.8 + 0.1, 0.0), 2.5) * (0.6 + bass * 0.5);
    col += vec3<f32>(0.95, 0.97, 1.0) * spec * reflectAmt * 0.85;

    // Audio thickens the mercury (viscosity visual)
    col = mix(col, col * 0.6 + vec3<f32>(0.1), viscosity * 0.12);

    // Semantic alpha — higher where wave energy or reflection is strong
    let waveEnergy = abs(wave.x) + length(wave.yz) * 0.5;
    let semantic_alpha = clamp(0.65 + waveEnergy * 1.6 + reflectAmt * 0.25, 0.5, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Write evolving wave state (ping-pong via renderer feeding A→C next frame)
    textureStore(dataTextureA, global_id.xy, vec4<f32>(wave.x, wave.y, wave.z, semantic_alpha * 0.8));

    // Depth from wave height for nice stacking
    let d = clamp(0.3 + waveEnergy * 0.4, 0.0, 0.95);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
