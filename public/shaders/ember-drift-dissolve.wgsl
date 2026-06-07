// ═══════════════════════════════════════════════════════════════════
//  Ember Drift Dissolve
//  Category: image
//  Features: ember, dissolve, advection, heat, audio-sparks, semantic-alpha, temporal
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — bright regions lift as glowing embers carried by rising heat, beautiful disintegration on video)
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
  zoom_params: vec4<f32>,  // x=Rise, y=Spark, z=Heat, w=Decay
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
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

    let riseSpeed = u.zoom_params.x * (0.7 + bass * 0.4);
    let sparkDensity = u.zoom_params.y * (0.6 + treble * 1.1);
    let heat = u.zoom_params.z;
    let decay = u.zoom_params.w * 0.9 + 0.1;

    // Previous ember state (age, intensity, lateral drift)
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Only bright areas produce embers
    let emberMask = smoothstep(0.35, 0.82, luma);

    // Rising heat advection field (with some curl)
    let heatField = vec2<f32>(
        sin(uv.y * 6.0 + time * 0.6) * 0.018,
        -riseSpeed * (0.018 + heat * 0.012 + prev.g * 0.008)
    );

    // Sample previous location (advection)
    let prevUV = clamp(uv - heatField * 1.6, vec2<f32>(0.0), vec2<f32>(1.0));
    let carried = textureSampleLevel(dataTextureC, u_sampler, prevUV, 0.0);

    // New ember birth from bright pixels + audio sparks
    let birth = emberMask * (0.4 + sparkDensity * 0.7) * step(0.82, hash21(uv * 140.0 + floor(time * 7.0)));
    let spark = step(0.91, hash21(uv * 290.0 + time * 19.0)) * treble * 0.9 * emberMask;

    var age = carried.r * decay + birth * 0.9 + spark * 0.6;
    age = clamp(age, 0.0, 1.0);

    // Lateral turbulence increases with age and treble
    let turb = (hash21(uv * 17.0 + time * 2.3) - 0.5) * 0.008 * (age * 0.7 + treble * 0.4);
    let lateral = carried.g * 0.92 + turb;

    let intensity = age * (0.7 + mids * 0.3) * smoothstep(1.0, 0.2, age);

    // Ember color (warm core → cooler ash)
    let emberCol = mix(vec3<f32>(1.0, 0.45, 0.08), vec3<f32>(0.2, 0.05, 0.01), smoothstep(0.3, 1.0, age));
    let glow = pow(intensity, 1.6) * (0.9 + bass * 0.4);

    // Composite: original darkens as embers lift, bright embers added on top
    var col = input.rgb * (1.0 - intensity * 0.65);
    col += emberCol * glow * 1.6;

    // Heat haze on rising areas
    let haze = intensity * 0.12 * (1.0 - depth);
    col = mix(col, col + vec3<f32>(0.15, 0.08, 0.02), haze);

    // Semantic alpha — embers are ethereal and glow
    let semantic_alpha = clamp(0.55 + glow * 0.65 + intensity * 0.3, 0.4, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Write new ember state for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(age, lateral, intensity, glow));

    // Depth from ember height in scene
    let d = clamp(0.2 + intensity * 0.55, 0.0, 0.96);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
