// ═══════════════════════════════════════════════════════════════════
//  hyb-temporal-fbm-ghost
//  Category: hybrid
//  Features: temporal-offset, fbm-displacement, domain-warp, ghost-glow,
//            palette-color, alpha-passthrough, depth-passthrough
//  Chunks: fbm2 + domainWarp + glow + palette
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

// ── Chunk: hash12 (from gen_grid.wgsl) ──
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Chunk: valueNoise (from gen_grid.wgsl) ──
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ── Chunk: fbm2 (from gen_grid.wgsl) ──
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ── Chunk: domainWarp (from gen_grid.wgsl) ──
fn domainWarp(uv: vec2<f32>, time: f32, scale: f32, amount: f32) -> vec2<f32> {
    let q = vec2<f32>(
        fbm2(uv * scale + vec2<f32>(0.0, time * 0.1), 4),
        fbm2(uv * scale + vec2<f32>(5.2, 1.3 + time * 0.1), 4)
    );
    let r = vec2<f32>(
        fbm2(uv * scale + 4.0 * q + vec2<f32>(1.7 - time * 0.15, 9.2), 4),
        fbm2(uv * scale + 4.0 * q + vec2<f32>(8.3 - time * 0.15, 2.8), 4)
    );
    let warped = uv + amount * r;
    return warped;
}

// ── Chunk: glow (from anamorphic-flare.wgsl) ──
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius)) * intensity;
}

// ── Chunk: palette (from gen-xeno-botanical-synth-flora.wgsl) ──
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    let dimsI = vec2<i32>(dims);

    if (any(coord >= dimsI)) {
        return;
    }

    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Normalize zoom_params
    let time = u.config.x;
    let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
    let temporalShift = mix(0.0, 0.06, zp.x);
    let fbmScale = mix(2.0, 20.0, zp.y);
    let warpAmt = mix(0.0, 0.25, zp.z);
    let effectMix = mix(0.0, 1.0, zp.w);

    // Per-channel temporal offset direction (RGB drift apart over time)
    let angleR = time * 0.30;
    let angleG = time * 0.55 + 2.094;
    let angleB = time * 0.80 + 4.189;
    let dirR = vec2<f32>(cos(angleR), sin(angleR));
    let dirG = vec2<f32>(cos(angleG), sin(angleG));
    let dirB = vec2<f32>(cos(angleB), sin(angleB));

    // FBM-driven displacement field warps the sampling coordinates
    let warped = domainWarp(uv, time, fbmScale, warpAmt);
    let disp = warped - uv;

    // Sample R/G/B from slightly offset, time-evolved coordinates
    let uvR = clamp(uv + disp + dirR * temporalShift, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + disp * 0.7 + dirG * temporalShift * 0.8, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + disp * 0.4 + dirB * temporalShift * 0.6, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    let ghostRGB = vec3<f32>(r, g, b);

    // Organic color tint from a cosine palette keyed by FBM phase
    let palettePhase = fbm2(uv * fbmScale * 0.4 + vec2<f32>(time * 0.12), 4);
    let tint = palette(
        palettePhase,
        vec3<f32>(0.5, 0.5, 0.5),
        vec3<f32>(0.5, 0.5, 0.5),
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    let tintedGhost = mix(ghostRGB, ghostRGB * tint * 2.0, 0.3);

    // Soft ghosting halo around bright regions
    let luma = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let halo = glow(1.0 - luma, 0.45, 0.4) * tint;
    let layerRGB = clamp(tintedGhost + halo * 0.25, vec3<f32>(0.0), vec3<f32>(1.0));

    let outRGB = mix(src.rgb, layerRGB, effectMix);

    textureStore(writeTexture, coord, vec4<f32>(clamp(outRGB, vec3<f32>(0.0), vec3<f32>(1.0)), src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
