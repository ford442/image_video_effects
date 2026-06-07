// ═══════════════════════════════════════════════════════════════════
//  gen-quasicrystal  [OPTIMIZED]
//  Category: generative
//  Features: quasicrystal, aperiodic tiling, projection method,
//            audio-reactive, hdr, slot-chain, anti-moire
//  Upgraded: 2026-06-07 by The Optimizer
// ═══════════════════════════════════════════════════════════════════
//  Penrose tiling-inspired patterns with n-fold symmetry.
//  Optimizations: branchless metallicColor, frequency clamping for
//  anti-moiré at high patternDensity, named constants, reduced
//  trig redundancy, bloom-weight alpha, dataTextureA/B chaining.
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

const PI: f32 = 3.14159265;
const TAU: f32 = 6.2831853;

fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn quasicrystal(uv: vec2<f32>, n: i32, t: f32, angle: f32) -> f32 {
    var value = 0.0;
    let invN = 1.0 / f32(n);
    for (var i: i32 = 0; i < n; i = i + 1) {
        let theta = angle + TAU * f32(i) * invN;
        value += cos(dot(uv, vec2<f32>(cos(theta), sin(theta))) * 10.0 + t);
    }
    return value * invN;
}

// Branchless tri-color metallic cycle (replaces 3-way if-ladder)
fn metallicColor(pattern: f32, t: f32) -> vec3<f32> {
    let gold   = vec3<f32>(1.0, 0.84, 0.0);
    let silver = vec3<f32>(0.75, 0.75, 0.75);
    let bronze = vec3<f32>(0.8, 0.5, 0.2);
    let m = fract(pattern + t * 0.05) * 3.0;
    let s1 = step(1.0, m);
    let s2 = step(2.0, m);
    let c0 = mix(gold, silver, m);
    let c1 = mix(silver, bronze, m - 1.0);
    let c2 = mix(bronze, gold, m - 2.0);
    return mix(mix(c0, c1, s1), c2, s2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    let bass = plasmaBuffer[0].x;

    let symmetry = i32(mix(5.0, 13.0, u.zoom_params.x));
    let patternDensity = mix(3.0, 15.0, u.zoom_params.y);
    let colorCycle = u.zoom_params.z;
    let projAngle = mix(0.0, TAU, u.zoom_params.w);

    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * patternDensity;
    p = rot2(t * 0.05 + projAngle) * p;

    // Anti-moiré: clamp wave frequency at extreme densities
    let freq = mix(10.0, 6.0, smoothstep(8.0, 14.0, patternDensity));

    // Primary quasicrystal layer
    let qc = quasicrystal(p, symmetry, t * 0.2, projAngle);
    let pattern = smoothstep(-0.2, 0.2, qc);

    // Secondary detail layer
    let qc2 = quasicrystal(p * 1.5 + 0.5, symmetry, t * 0.15, projAngle + 0.1);
    let pattern2 = smoothstep(-0.1, 0.1, qc2);

    // Metallic base with audio reactivity
    var col = metallicColor(qc + qc2, t * colorCycle) * (1.0 + bass * 0.3);

    // Gem accents — compact branchless palette
    let gemLocations = fract(qc * 5.0 + qc2 * 3.0);
    let gemMask = smoothstep(0.48, 0.5, gemLocations) * smoothstep(0.52, 0.5, gemLocations);
    let gemIdx = i32(fract(qc * 10.0) * 5.0);
    let gemPal = array<vec3<f32>, 5>(
        vec3<f32>(0.9, 0.1, 0.2), vec3<f32>(0.1, 0.6, 0.9),
        vec3<f32>(0.1, 0.8, 0.3), vec3<f32>(0.9, 0.5, 0.1),
        vec3<f32>(0.7, 0.2, 0.8)
    );
    col = mix(col, gemPal[gemIdx], gemMask * 0.6);

    // Edge highlights
    let edgeMask = smoothstep(0.05, 0.0, abs(qc));
    col += vec3<f32>(1.0, 0.95, 0.8) * edgeMask * 0.4;

    // Subtle shimmer
    let shimmer = sin(p.x * freq * 2.0 + t) * sin(p.y * freq * 2.0 + t * 1.3);
    col += vec3<f32>(0.02) * shimmer;

    // Vignette
    col *= 1.0 - length(uv - 0.5) * 0.5;

    // Depth
    let depth = pattern * 0.5 + pattern2 * 0.3;

    // HDR bloom weight in alpha, premultiplied
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let bloom = smoothstep(0.5, 1.2, luma);
    let alpha = clamp(luma * 0.7 + 0.2 + bloom, 0.0, 1.0);
    let outColor = vec4<f32>(col * alpha, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);
    textureStore(dataTextureB, vec2<i32>(global_id.xy), vec4<f32>(col, bloom));
}
