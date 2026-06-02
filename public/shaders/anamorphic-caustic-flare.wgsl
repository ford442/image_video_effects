// ═══════════════════════════════════════════════════════════════════
//  Anamorphic Caustic Flare
//  Category: visual-effects
//  Features: anamorphic, caustic, lens-flare, refraction, audio-stretch, mouse-tilt, cinematic, semantic-alpha
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — premium anamorphic lens with living water caustics refracting the source)
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
  zoom_params: vec4<f32>,  // x=Flare, y=Caustic, z=Refraction, w=Stretch
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash21 (from _hash_library.wgsl) ═══
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn caustic(p: vec2<f32>, t: f32, freq: f32) -> f32 {
    let q = p * freq + vec2<f32>(t * 0.6, t * -0.4);
    let c1 = sin(q.x * 1.7 + sin(q.y * 2.3)) * 0.5 + 0.5;
    let c2 = sin(q.y * 2.1 + sin(q.x * 1.4 + t * 0.8)) * 0.5 + 0.5;
    return pow(c1 * c2, 1.6);
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

    // Sliders
    let flareStrength = u.zoom_params.x * (0.7 + bass * 0.9);
    let causticStrength = u.zoom_params.y * (0.8 + treble * 0.6);
    let refraction = u.zoom_params.z * 0.035;
    let stretch = u.zoom_params.w * (1.0 + bass * 0.8);

    let mouse = u.zoom_config.yz;
    let mouseTilt = (mouse.x - 0.5) * 0.6;

    // Sample input (will be refracted by caustics)
    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Anamorphic horizontal flare (classic blue + orange)
    let centerDist = abs(uv.y - 0.5) * 1.8;
    let anamorph = smoothstep(0.08, 0.0, centerDist) * flareStrength;
    let flareCol = mix(vec3<f32>(0.2, 0.55, 1.0), vec3<f32>(1.0, 0.6, 0.15), uv.x * 0.6 + 0.2);
    var flare = flareCol * pow(anamorph, 1.3) * (1.0 + bass * 0.5);

    // Add horizontal light streaks (anamorphic signature)
    let streak = smoothstep(0.012, 0.0, abs(uv.y - 0.5)) * (0.6 + bass * 0.4);
    flare += vec3<f32>(0.85, 0.9, 1.0) * streak * flareStrength * 0.7;

    // Living water caustics that refract the image
    let c = caustic(uv + mouseTilt * 0.1, time * 0.7 + mids * 0.3, 9.0 + stretch * 4.0);
    let causticMask = pow(c, 2.2) * causticStrength;

    // Refraction offset (stronger where caustic is bright)
    let refractUV = uv + vec2<f32>(causticMask * refraction * (mouse.x - 0.5), causticMask * refraction * 0.6);
    let refracted = textureSampleLevel(readTexture, u_sampler, clamp(refractUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Blend refracted image with caustic highlights
    let causticLight = vec3<f32>(0.6, 0.85, 1.0) * causticMask * 1.8;
    var col = mix(input.rgb, refracted.rgb, 0.35 + causticMask * 0.5);
    col += causticLight * (0.4 + mids * 0.3);

    // Subtle filmic chromatic aberration on strong flares
    if (flareStrength > 0.4) {
        let caOff = flareStrength * 0.0018;
        let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(caOff, 0.0), 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(caOff * 0.7, 0.0), 0.0).b;
        col.r = mix(col.r, r, 0.25);
        col.b = mix(col.b, b, 0.25);
    }

    // Final mix with anamorphic flare
    col = col * (1.0 - flareStrength * 0.25) + flare * 0.85;

    // Gentle contrast curve
    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.88));

    // Semantic alpha — strong on bright caustic and flare regions (great for layering)
    let energy = causticMask * 0.65 + anamorph * 0.9 + streak * 0.4;
    let semantic_alpha = clamp(0.68 + energy * 0.42, 0.5, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Depth carries caustic energy for downstream effects
    let d = clamp(0.25 + causticMask * 0.55 + anamorph * 0.3, 0.0, 0.97);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    // Store caustic field for possible multi-pass use
    textureStore(dataTextureA, global_id.xy, vec4<f32>(c, causticMask, flareStrength, semantic_alpha));
}
