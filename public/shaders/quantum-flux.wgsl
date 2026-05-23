// ═══════════════════════════════════════════════════════════════════
//  Quantum Flux
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
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

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params with audio modulation
    let jitterAmount = u.zoom_params.x * (1.0 + treble * 0.6);
    let freq = u.zoom_params.y * (1.0 + mids * 0.4);
    let driftSpeed = u.zoom_params.z * (1.0 + mids * 0.5);
    let radiusParam = u.zoom_params.w * (1.0 + bass * 0.3);

    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    let influenceRadius = radiusParam * 0.8 + 0.1;
    let influence = smoothstep(influenceRadius, 0.0, dist);

    let seed = uv + vec2<f32>(time * 0.1, time * 0.1);
    let noiseX = (rand(seed) - 0.5) * 2.0;
    let noiseY = (rand(seed + vec2<f32>(1.0, 1.0)) - 0.5) * 2.0;
    let jitter = vec2<f32>(noiseX, noiseY) * jitterAmount * 0.05 * influence;
    let wave = sin(dist * (freq * 50.0) - time * 5.0) * 0.02 * influence;

    let split = jitterAmount * 0.02 * influence;
    let uvR = clamp(uv + jitter + vec2<f32>(wave + split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv - jitter + vec2<f32>(0.0, wave), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + jitter * 0.5 - vec2<f32>(split + wave, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
    let sG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
    let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // Hue drift (branchless via mix on influence)
    var hsv = rgb2hsv(color);
    hsv.x = fract(hsv.x + (time * driftSpeed * 0.5) + (dist * 2.0));
    hsv.y = min(1.0, hsv.y + influence * 0.2);
    let driftedColor = hsv2rgb(hsv);
    let driftMask = clamp(driftSpeed * 10.0, 0.0, 1.0) * smoothstep(0.0, 0.01, influence);
    color = mix(color, driftedColor, driftMask);

    // Interference scanlines
    let interference = sin(uv.y * resolution.y * 0.5 + time * 10.0) * 0.5 + 0.5;
    color = mix(color, color * (0.8 + 0.2 * interference), influence * 0.5);

    // Meaningful alpha: blend weight from influence + chromatic split + base alpha
    let splitMag = abs(sR.r - sB.b) + abs(sG.g - sR.r);
    let alpha = clamp(baseSample.a * 0.5 + influence * 0.3 + splitMag * 0.4 + treble * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
