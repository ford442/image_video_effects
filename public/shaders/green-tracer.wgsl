// ═══════════════════════════════════════════════════════════════════
//  Green Tracer World
//  Category: artistic
//  Features: audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: phosphor persist from exact C; edge-only trail
//  A packing: trail RGB (C is previous trail)
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

fn hash(p: vec2<f32>) -> f32 {
    var h = fract(vec3<f32>(p.xyx) * 0.1031);
    h += dot(h, h.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn edgeDetect(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    let dL = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
    let dR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
    let dD = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    return length(vec2<f32>(dR - dL, dD - dU));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(gid.x) >= resolution.x || f32(gid.y) >= resolution.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Canonical Uniforms: sliders on zoom_params, mouse/time on zoom_config.
    let trailLen  = u.zoom_params.x;
    let glowInt   = u.zoom_params.y;
    let greenTint = u.zoom_params.z;
    let noiseAmt  = u.zoom_params.w;
    let trailFade = mix(0.92, 0.995, trailLen);
    let motionThresh = mix(0.02, 0.12, 1.0 - trailLen);

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let prev = textureLoad(dataTextureC, coord, 0);

    let motion = length(src.rgb - prev.rgb);
    let edge = edgeDetect(uv, texel);
    // Idea 2 — edge-only trail (persist more on edges).
    let edgeGate = smoothstep(0.02, 0.18, edge);
    let isMoving = f32(motion > motionThresh);

    // Idea 1 — phosphor persist from exact C, fade from trailLen.
    var trail = prev.rgb * mix(trailFade, mix(trailFade, 0.999, edgeGate), 0.55);
    trail = mix(trail, mix(trail, src.rgb, 0.1 + trailLen * 0.15), isMoving);
    textureStore(dataTextureA, coord, vec4<f32>(trail, 1.0));

    let greenWorld = mix(src.rgb, vec3<f32>(0.1, 1.0, 0.2), greenTint);
    let glow = glowInt * smoothstep(0.0, 0.1, motion) * edge * (1.0 + bass * 0.25);
    let glowCol = vec3<f32>(0.0, 1.0, 0.3) * glow;
    let grain = (hash(uv * 1000.0 + time) - 0.5) * noiseAmt * (1.0 + treble * 0.3);

    var outCol = mix(greenWorld, trail, 0.35 + trailLen * 0.25) + glowCol + grain;
    outCol = aces(max(outCol, vec3<f32>(0.0)));
    let alpha = clamp(src.a * 0.3 + edgeGate * 0.4 + motion * 0.25 + mids * 0.05, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(outCol, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
