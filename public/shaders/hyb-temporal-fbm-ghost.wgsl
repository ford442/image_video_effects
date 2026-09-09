// ═══════════════════════════════════════════════════════════════════
//  Temporal FBM Ghost
//  Category: hybrid
//  Features: audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: per-channel lag from exact C; source-tied ghost
//  A packing: ACES display RGBA
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
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

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

fn domainWarp(uv: vec2<f32>, time: f32, scale: f32, amount: f32) -> vec2<f32> {
    let q = vec2<f32>(
        fbm2(uv * scale + vec2<f32>(0.0, time * 0.1), 4),
        fbm2(uv * scale + vec2<f32>(5.2, 1.3 + time * 0.1), 4)
    );
    let r = vec2<f32>(
        fbm2(uv * scale + 4.0 * q + vec2<f32>(1.7 - time * 0.15, 9.2), 4),
        fbm2(uv * scale + 4.0 * q + vec2<f32>(8.3 - time * 0.15, 2.8), 4)
    );
    return uv + amount * r;
}

fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius)) * intensity;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    let dimsI = vec2<i32>(dims);
    if (any(coord >= dimsI)) { return; }

    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let prev = textureLoad(dataTextureC, coord, 0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let time = u.config.x;
    let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
    let temporalShift = mix(0.0, 0.06, zp.x) * (1.0 + bass * 0.2);
    let fbmScale = mix(2.0, 20.0, zp.y);
    let warpAmt = mix(0.0, 0.25, zp.z);
    let effectMix = mix(0.0, 1.0, zp.w);

    let angleR = time * 0.30;
    let angleG = time * 0.55 + 2.094;
    let angleB = time * 0.80 + 4.189;
    let dirR = vec2<f32>(cos(angleR), sin(angleR));
    let dirG = vec2<f32>(cos(angleG), sin(angleG));
    let dirB = vec2<f32>(cos(angleB), sin(angleB));

    let warped = domainWarp(uv, time, fbmScale, warpAmt);
    let disp = warped - uv;

    let uvR = clamp(uv + disp + dirR * temporalShift, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + disp * 0.7 + dirG * temporalShift * 0.8, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + disp * 0.4 + dirB * temporalShift * 0.6, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    var ghostRGB = vec3<f32>(r, g, b);

    // Idea 1 — per-channel lag from exact C (R lags more than B).
    ghostRGB.r = mix(ghostRGB.r, prev.r, 0.22 + zp.x * 0.25);
    ghostRGB.g = mix(ghostRGB.g, prev.g, 0.14 + zp.x * 0.18);
    ghostRGB.b = mix(ghostRGB.b, prev.b, 0.08 + zp.x * 0.12);

    let luma = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    // Idea 2 — source-tied ghost (halo follows plate luma, not a new palette).
    let halo = glow(1.0 - luma, 0.45, 0.4) * src.rgb * (1.0 + mids * 0.25);
    let layerRGB = clamp(ghostRGB + halo * 0.25, vec3<f32>(0.0), vec3<f32>(1.0));
    let outRGB = aces(mix(src.rgb, layerRGB, effectMix));
    let alpha = clamp(src.a * 0.4 + luma * 0.35 + effectMix * 0.2 + treble * 0.05, 0.0, 1.0);
    let outColor = vec4<f32>(outRGB, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
