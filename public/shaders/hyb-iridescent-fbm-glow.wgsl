// ═══════════════════════════════════════════════════════════════════
//  hyb-iridescent-fbm-glow
//  Category: hybrid
//  Features: fbm-noise, iridescence, image-glow, alpha-passthrough, depth-passthrough
//  Chunks: fbm2 + iridescence
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

// ── Chunk: iridescence (from gen-holographic-fracture.wgsl) ──
fn iridescence(theta: f32, shift: f32) -> vec3<f32> {
    let t = theta * 4.0 + shift;
    return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189));
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
    let fbmScale = mix(1.5, 18.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let octaves = i32(mix(2.0, 7.0, clamp(u.zoom_params.y, 0.0, 1.0)));
    let shiftSpeed = mix(0.0, 3.0, clamp(u.zoom_params.z, 0.0, 1.0));
    let glowMix = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

    // Animated FBM layer
    let q = vec2<f32>(
        fbm2(uv * fbmScale + vec2<f32>(time * 0.07, 0.0), octaves),
        fbm2(uv * fbmScale + vec2<f32>(5.2, 1.3 + time * 0.07), octaves)
    );
    let warped = uv * fbmScale + 4.0 * q + vec2<f32>(time * 0.05);
    let noise = fbm2(warped, octaves);

    // Iridescent glow layer
    let ird = iridescence(noise, time * shiftSpeed);
    let glowLayer = ird * noise * noise;

    // Blend glow over input, preserving luminance relationship
    let outRGB = mix(src.rgb, src.rgb + glowLayer, glowMix);

    textureStore(writeTexture, coord, vec4<f32>(outRGB, src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
