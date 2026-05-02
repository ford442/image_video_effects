// ═══════════════════════════════════════════════════════════════════
//  Procedural Texture Analyzer v2 - RGBA, depth-aware, audio-reactive
//  Category: image
//  Features: upgraded-rgba, depth-aware, audio-reactive, temporal
//  Upgraded: 2026-05-02 (Tier-1 integration pass)
//  Creative additions: golden-ratio vignette, voronoi glitch on treble
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

fn hash12(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let q = p3 + dot(p3, p3.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let q = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(q) * 43758.5453);
}

// Cheap voronoi distance for the glitch effect (1-cell, 3x3 search)
fn voronoiDist(uv: vec2<f32>, scale: f32) -> f32 {
    let p = uv * scale;
    let i = floor(p);
    let f = fract(p);
    var minDist = 8.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i + neighbor);
            let diff = neighbor + point - f;
            let d = dot(diff, diff);
            minDist = min(minDist, d);
        }
    }
    return sqrt(minDist);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn safeSampleRGBA(uv: vec2<f32>) -> vec4<f32> {
    let cuv = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    return textureSampleLevel(readTexture, u_sampler, cuv, 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;

    // Audio reactivity from plasmaBuffer (NOT u.config.yzw)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Domain-specific parameters
    let edgeStrength = u.zoom_params.x;       // Edge Enhance
    let unsharpAmount = u.zoom_params.y;      // Unsharp Mask
    let temporalBlend = u.zoom_params.z;      // Temporal Smooth
    let audioReactivity = u.zoom_params.w;    // Audio Reactivity

    // Texel size for neighborhood sampling
    let texel = 1.0 / max(resolution, vec2<f32>(1.0));

    // Center sample
    let centerSample = safeSampleRGBA(uv);
    let center = centerSample.rgb;
    let inputAlpha = centerSample.a;

    // 3x3 neighborhood
    let n  = safeSampleRGBA(uv + vec2<f32>(0.0, -texel.y)).rgb;
    let s  = safeSampleRGBA(uv + vec2<f32>(0.0,  texel.y)).rgb;
    let e_ = safeSampleRGBA(uv + vec2<f32>( texel.x, 0.0)).rgb;
    let w  = safeSampleRGBA(uv + vec2<f32>(-texel.x, 0.0)).rgb;
    let nw = safeSampleRGBA(uv + vec2<f32>(-texel.x, -texel.y)).rgb;
    let ne = safeSampleRGBA(uv + vec2<f32>( texel.x, -texel.y)).rgb;
    let sw = safeSampleRGBA(uv + vec2<f32>(-texel.x,  texel.y)).rgb;
    let se = safeSampleRGBA(uv + vec2<f32>( texel.x,  texel.y)).rgb;

    // Laplacian edge detection (sum of neighbors - 8*center)
    let laplacian = (n + s + e_ + w + nw + ne + sw + se) - 8.0 * center;
    let edgeBoost = edgeStrength * 1.5;
    var color = center + laplacian * edgeBoost;

    // Unsharp mask: blur via box average, then add high-pass
    let blur = (n + s + e_ + w + nw + ne + sw + se + center) / 9.0;
    let highPass = center - blur;
    color = color + highPass * (unsharpAmount * 1.2);

    // Temporal filtering with previous frame from dataTextureC
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let blendT = clamp(temporalBlend * 0.85, 0.0, 0.85);
    color = mix(color, prev, blendT);

    // ─── Creative addition: golden-ratio vignette with iridescent rim ───
    let phi = 1.61803398875;
    let centered = uv - 0.5;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let elliptic = vec2<f32>(centered.x * aspect, centered.y);
    let r = length(elliptic) * phi;
    // Bass-driven breathing pulse
    let pulse = 1.0 + bass * 0.45 * audioReactivity;
    let vignette = smoothstep(1.05 * pulse, 0.35, r);
    // Iridescent rim shifts hue with luma + time
    let luma = dot(center, vec3<f32>(0.299, 0.587, 0.114));
    let rimBand = smoothstep(0.78, 1.0, r) * (1.0 - smoothstep(1.0, 1.18, r));
    let hueT = luma * 6.2831853 + time * 0.3 + mids * 1.2;
    let rimColor = 0.5 + 0.5 * vec3<f32>(
        cos(hueT),
        cos(hueT + 2.094),
        cos(hueT + 4.188)
    );
    color = color * vignette + rimColor * rimBand * (0.25 + bass * 0.35 * audioReactivity);

    // ─── Audio sparkle on bright regions (treble) ───
    let brightMask = smoothstep(0.55, 0.95, luma);
    let sparkleSeed = hash12(uv * resolution + vec2<f32>(time * 60.0, 0.0));
    let sparkle = step(1.0 - treble * 0.18 * audioReactivity, sparkleSeed) * brightMask;
    color = color + vec3<f32>(sparkle);

    // ─── Creative addition: voronoi glitch on treble spikes ───
    let glitchAmt = smoothstep(0.65, 0.95, treble) * audioReactivity;
    if (glitchAmt > 0.001) {
        let vd = voronoiDist(uv + vec2<f32>(time * 0.05), 12.0 + bass * 8.0);
        // Snap color to its voronoi cell average direction
        let glitchColor = mix(color, vec3<f32>(1.0 - vd) * (color + 0.15), 0.6);
        color = mix(color, glitchColor, glitchAmt * 0.5);
    }

    // Tone mapping
    color = acesToneMapping(color);

    // Calculated alpha (never hardcoded)
    let outLuma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let presence = smoothstep(0.02, 0.6, outLuma);
    let opacity = 0.9 + bass * 0.1 * audioReactivity;
    let generatedAlpha = presence * opacity;
    let finalAlpha = max(inputAlpha, generatedAlpha);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Persist current frame to dataTextureA for downstream/future passes
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
