// ═══════════════════════════════════════════════════════════════════
//  Neon Pulse Edge
//  Category: lighting-effects
//  Features: audio-reactive, depth-aware, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-11
//  Ideas: Sobel-tangent tube glow; exact-C edge afterglow
//  A packing: raw edgeMag, depth, gx, gy (not ACES)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: edge_threshold   — Sobel magnitude cutoff (lower = more edges)
//  Param2: glow_radius      — width of atmospheric halo bloom
//  Param3: pulse_speed      — colour cycling / pulse frequency
//  Param4: color_cycle_rate — how fast edge hue rotates with direction

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

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadEdge(coord: vec2<i32>, max_coord: vec2<i32>) -> f32 {
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), max_coord), 0).r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let max_coord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = 1.0 / resolution;

    let threshold = u.zoom_params.x * 0.5 + 0.02;
    let glowRadius = u.zoom_params.y * 6.0 + 1.0;
    let pulseSpeed = u.zoom_params.z * 6.0 + 0.5;
    let cycleRate = u.zoom_params.w;

    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);
    let audioBoost = 1.0 + bass * 0.6 + treble * 0.2;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-px.x, -px.y), 0.0).rgb;
    let tc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -px.y), 0.0).rgb;
    let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, -px.y), 0.0).rgb;
    let ml = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-px.x, 0.0), 0.0).rgb;
    let mr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb;
    let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-px.x, px.y), 0.0).rgb;
    let bc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb;
    let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, px.y), 0.0).rgb;

    let lum = vec3<f32>(0.299, 0.587, 0.114);
    let gxMag = -dot(tl, lum) - 2.0 * dot(ml, lum) - dot(bl, lum)
        + dot(tr, lum) + 2.0 * dot(mr, lum) + dot(br, lum);
    let gyMag = -dot(tl, lum) - 2.0 * dot(tc, lum) - dot(tr, lum)
        + dot(bl, lum) + 2.0 * dot(bc, lum) + dot(br, lum);

    let edgeMag = sqrt(gxMag * gxMag + gyMag * gyMag);
    let edgeAngle = atan2(gyMag, gxMag);
    let gLen = max(length(vec2<f32>(gxMag, gyMag)), 0.001);
    let tangent = vec2<f32>(-gyMag, gxMag) / gLen;
    let normal = vec2<f32>(gxMag, gyMag) / gLen;

    textureStore(dataTextureA, coord, vec4<f32>(edgeMag, depth, gxMag, gyMag));

    let hue = fract(edgeAngle / 6.28318 + time * pulseSpeed * 0.02 + cycleRate * 0.3 + bass * 0.15);
    let sat = 0.8 + treble * 0.15;
    let neonColor = hsv2rgb(vec3<f32>(hue, sat, 1.0));

    // Idea 1: tube samples along Sobel tangent (and a thin normal for glass thickness)
    var tube = 0.0;
    var halo = 0.0;
    let tapCount = 6;
    for (var i = 0; i < tapCount; i++) {
        let s = (f32(i) / f32(tapCount - 1) - 0.5) * 2.0;
        let along = vec2<i32>(round(tangent * s * glowRadius));
        let thick = vec2<i32>(round(normal * s * 1.5));
        tube += loadEdge(coord + along, max_coord);
        halo += loadEdge(coord + along + thick, max_coord);
    }
    tube = tube / f32(tapCount);
    halo = halo / f32(tapCount);
    // Idea 2: local exact-C afterglow
    let afterglow = loadEdge(coord, max_coord);

    let depthFactor = 1.0 + depth * 1.2;
    let mouse = u.zoom_config.yz;
    var mouseFactor = 1.0;
    if (mouse.x >= 0.0) {
        let mDist = length((uv - mouse) * vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0));
        mouseFactor = 1.0 + (1.0 - smoothstep(0.0, 0.25, mDist)) * 1.5;
    }

    var emission = vec3<f32>(0.0);
    let isEdge = step(threshold, edgeMag);
    if (isEdge > 0.5) {
        let pulse = 0.7 + 0.3 * sin(time * pulseSpeed * (1.0 + bass));
        emission += neonColor * edgeMag * pulse * depthFactor * mouseFactor * audioBoost * 1.8;
    }

    let haloColor = hsv2rgb(vec3<f32>(fract(hue + 0.05), sat * 0.7, 1.0));
    emission += neonColor * tube * depthFactor * audioBoost * 0.55;
    emission += haloColor * halo * depthFactor * audioBoost * 0.22;
    emission += haloColor * afterglow * 0.18 * audioBoost;

    let edgeDim = 1.0 - isEdge * 0.4;
    let finalColor = aces(src.rgb * edgeDim + emission);
    let glowStrength = clamp(length(emission) * 0.5, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, mix(src.a, 1.0, glowStrength)));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
