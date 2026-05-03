// ═══════════════════════════════════════════════════════════════════
//  Chrono Slit Scan
//  Category: image
//  Features: temporal-persistence, audio-reactive, fbm-warp, sdf-composition
//  Complexity: Medium
//  Chunks From: hash22 (fractal), smin (SDF)
//  Created: 2026-05-03
//  By: Algorithmist
// ═══════════════════════════════════════════════════════════════════

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash22 (fractal base) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var pp = p * vec2<f32>(0.1031, 0.1030);
    let a = dot(pp, vec2<f32>(127.1, 311.7));
    let b = dot(pp + 1.0, vec2<f32>(269.5, 183.3));
    let c = sin(vec2<f32>(a, b));
    return fract(c * 43758.5453 + pp);
}

// ═══ CHUNK: fbm2 (FBM domain warping) ═══
fn fbm2(p: vec2<f32>, t: f32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i: i32 = 0; i < 3; i = i + 1) {
        let h = hash22(pp + t * 0.1 * f32(i + 1));
        v += a * (h.x - 0.5);
        pp = pp * 2.3 + h.yx;
        a *= 0.5;
    }
    return v;
}

// ═══ CHUNK: smin (SDF smooth minimum) ═══
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let scanSpeed = u.zoom_params.x * 0.6 + 0.05;
    let baseWidth = u.zoom_params.y * 0.08 + 0.002;
    let warpAmt = u.zoom_params.z;
    let decayRate = u.zoom_params.w * 0.02;

    // Audio-reactive scan acceleration
    let audioPulse = plasmaBuffer[0].x * 0.3 + 1.0;

    // FBM domain-warped scan trajectory
    let warp = fbm2(vec2<f32>(uv.y * 3.0, time * 0.5), time) * warpAmt;
    let scanPos = fract(time * scanSpeed * audioPulse + warp);

    // Secondary fractal slit (golden-ratio offset)
    let warp2 = fbm2(vec2<f32>(uv.y * 5.0 + 1.7, time * 0.3), time * 0.7) * warpAmt * 0.5;
    let scanPos2 = fract(scanPos * 2.6180339887 + warp2);

    // SDF distances to both slits, composed with smooth minimum
    let d1 = abs(uv.x - scanPos);
    let d2 = abs(uv.x - scanPos2) * 1.5;
    let dist = smin(d1, d2, 0.15);

    // Fractal width modulation
    let widthMod = 1.0 + fbm2(vec2<f32>(time, uv.y * 2.0), time * 0.2) * 0.5;
    let slitW = baseWidth * widthMod;

    // Smooth SDF mask (branchless)
    let mask = 1.0 - smoothstep(slitW * 0.3, slitW, dist);

    // Sample frames
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Spatially-varying temporal decay via noise
    let decayNoise = fbm2(uv * 4.0 + time * 0.1, time * 0.05);
    let decay = mix(1.0, 0.94 + decayNoise * 0.04, decayRate);

    // Branchless blend: current in slit, decayed history outside
    let outColor = mix(history * vec4<f32>(decay, decay, decay, 1.0), current, mask);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
    textureStore(dataTextureA, global_id.xy, outColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
