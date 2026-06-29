// ═══════════════════════════════════════════════════════════════════
//  hyb-spectral-fbm-displace
//  Category: hybrid
//  Features: fbm-noise, domain-warp, spectral-displace, chromatic-smear,
//            alpha-passthrough, depth-passthrough
//  Chunks: fbm2 + domainWarp + wavelengthToRGB
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

// ── Chunk: wavelengthToRGB (from spec-prismatic-dispersion.wgsl) ──
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
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
    let fbmScale = mix(2.0, 24.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let warpAmt = mix(0.0, 0.35, clamp(u.zoom_params.y, 0.0, 1.0));
    let spectralSpread = mix(0.0, 0.08, clamp(u.zoom_params.z, 0.0, 1.0));
    let effectMix = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

    // Domain-warp displacement field
    let warpedUV = domainWarp(uv, time, fbmScale, warpAmt);
    let dispVec = warpedUV - uv;
    let spread = dispVec * spectralSpread;

    // Chromatic spectral smear: R and B channels sample along the warp gradient
    let rUV = clamp(uv + spread, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - spread, vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = src.g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var displaced = vec3<f32>(r, g, b);

    // Spectral tint driven by a second FBM layer
    let waveT = clamp(fbm2(uv * fbmScale * 0.5 + vec2<f32>(time * 0.08), 4), 0.0, 1.0);
    let lambda = mix(440.0, 680.0, waveT);
    let tint = wavelengthToRGB(lambda);
    displaced = mix(displaced, displaced * tint * 1.8, 0.35);

    let outRGB = mix(src.rgb, displaced, effectMix);

    textureStore(writeTexture, coord, vec4<f32>(clamp(outRGB, vec3<f32>(0.0), vec3<f32>(1.0)), src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
