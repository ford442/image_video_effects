// ═══════════════════════════════════════════════════════════════════
//  Film Cross-Process
//  Category: artistic
//  Features: audio-reactive, upgraded-rgba
//  Complexity: Low
//  Description: Simulates E6 slide film developed in C41 negative chemistry.
//    Each channel is passed through a different S-curve (lifted shadows,
//    crushed mids, or blown highlights depending on channel), the colour
//    gamut is skewed (greens shift cyan, reds shift orange-yellow), grain
//    is added, and the result is pushed toward the iconic high-contrast
//    vivid-yet-desaturated cross-processed look. Bass boosts contrast;
//    mids shift the colour skew; treble increases grain texture.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=contrast, y=color_skew, z=grain, w=vignette

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=contrast, y=skew, z=grain, w=vignette
  ripples: array<vec4<f32>, 50>,
};

// S-curve via smooth cubic — maps [0,1] to [0,1] with user pivot
fn scurve(t: f32, pivot: f32, slope: f32) -> f32 {
    let p = clamp(pivot, 0.05, 0.95);
    let s = 1.0 + slope * 3.0;
    // Split at pivot: low half is lifted, high half is compressed
    let low  = t / p;
    let high = (t - p) / (1.0 - p);
    let bl   = low * low * (3.0 - 2.0 * low);          // smoothstep low
    let bh   = high * high * (3.0 - 2.0 * high);       // smoothstep high
    let rLow  = mix(t, bl * p, 0.6);
    let rHigh = mix(t, p + bh * (1.0 - p), 0.6);
    return select(rLow, rHigh, t >= p);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / res;
    let time  = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let src  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var r    = src.r;
    var g    = src.g;
    var b    = src.b;

    // Contrast strength driven by param + bass
    let contrast = 0.3 + u.zoom_params.x * 0.7 + bass * 0.2;

    // Per-channel S-curves (cross-process signature):
    //   Red  — lifted shadows, blown highlights (pivot low)
    //   Green — compressed, shifted toward cyan
    //   Blue  — heavy lift in shadows, muted highlights
    r = scurve(r, 0.30, contrast * 0.9);
    g = scurve(g, 0.55, contrast * 0.6);
    b = scurve(b, 0.45, contrast * 1.1);

    // Colour skew: mids shift green→cyan, red→yellow-orange
    let skew = u.zoom_params.y * 0.35 + mids * 0.12;
    r = clamp(r + skew * 0.15 - skew * g * 0.3, 0.0, 1.0);
    g = clamp(g - skew * 0.1 + skew * b * 0.2, 0.0, 1.0);
    b = clamp(b + skew * 0.2 - skew * r * 0.1, 0.0, 1.0);

    // Desaturate shadows (cross-process mutes dark areas)
    let luma = 0.299 * r + 0.587 * g + 0.114 * b;
    let shadowMix = clamp(1.0 - luma * 3.0, 0.0, 1.0) * 0.4;
    r = mix(r, luma, shadowMix);
    g = mix(g, luma, shadowMix);
    b = mix(b, luma, shadowMix);

    // Film grain (denser with treble)
    let grainAmt  = u.zoom_params.z * 0.08 + treble * 0.04;
    let grainSeed = uv * 3791.3 + vec2<f32>(fract(time * 0.1), fract(time * 0.17 + 0.3));
    let grain     = (hash21(grainSeed) - 0.5) * grainAmt;
    r = clamp(r + grain, 0.0, 1.0);
    g = clamp(g + grain * 0.8, 0.0, 1.0);
    b = clamp(b + grain * 1.1, 0.0, 1.0);

    // Vignette
    let vigStrength = u.zoom_params.w * 1.2;
    let vigDist     = length((uv - 0.5) * vec2<f32>(1.0, res.y / res.x));
    let vig         = 1.0 - smoothstep(0.4, 0.9, vigDist) * vigStrength;
    let finalRGB    = clamp(vec3<f32>(r, g, b) * vig, vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha: preserve source, boost at high-contrast cross-processed regions
    let crossLuma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
    let alpha     = clamp(src.a * 0.7 + crossLuma * 0.4 + bass * 0.08, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
