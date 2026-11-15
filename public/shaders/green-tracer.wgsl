// ═══════════════════════════════════════════════════════════════════
//  Green Tracer World
//  Category: artistic
//  Features: audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09, 2026-11-15
//  Ideas: phosphor persist from exact C; edge-only trail; phosphor strike color; phosphor bloom
//  A packing: trail RGB in A.rgb (not tonemapped). A.a is coverage. ACES on writeTexture
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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
    // Edge-only trail (persist more on edges).
    let edgeGate = smoothstep(0.02, 0.18, edge);
    let isMoving = f32(motion > motionThresh);

    // Phosphor persist from exact C, fade from trailLen.
    var trail = prev.rgb * mix(trailFade, mix(trailFade, 0.999, edgeGate), 0.55);
    trail = mix(trail, mix(trail, src.rgb, 0.1 + trailLen * 0.15), isMoving);

    let greenWorld = mix(src.rgb, vec3<f32>(0.1, 1.0, 0.2), greenTint);
    let glow = glowInt * smoothstep(0.0, 0.1, motion) * edge * (1.0 + bass * 0.25);
    let glowCol = vec3<f32>(0.0, 1.0, 0.3) * glow;
    let grain = (hash(uv * 1000.0 + time) - 0.5) * noiseAmt * (1.0 + treble * 0.3);

    // ── Idea 1: phosphor strike color ───────────────────────────────
    // P43 strikes yellow-green on a fresh edge and rests as deep green.
    // The stored trail stays the image persist; only the display is tinted.
    let freshness = smoothstep(motionThresh, motionThresh + 0.12, motion) * edgeGate;
    let trailGain = mix(vec3<f32>(0.42, 0.92, 0.58), vec3<f32>(1.2, 1.05, 0.38), freshness);

    // ── Idea 2: phosphor bloom ──────────────────────────────────────
    // Four loads of the previous trail. Bright neighbors halo in green.
    // Amount is Glow Intensity. This is not film halation.
    let dimsI = vec2<i32>(i32(resolution.x), i32(resolution.y));
    let lim = dimsI - vec2<i32>(1);
    let lumaW = vec3<f32>(0.15, 0.75, 0.10);
    let n0 = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-2, 0), vec2<i32>(0), lim), 0).rgb;
    let n1 = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 2, 0), vec2<i32>(0), lim), 0).rgb;
    let n2 = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 0,-2), vec2<i32>(0), lim), 0).rgb;
    let n3 = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 0, 2), vec2<i32>(0), lim), 0).rgb;
    let halo = max(dot(n0, lumaW) - 0.55, 0.0) + max(dot(n1, lumaW) - 0.55, 0.0)
             + max(dot(n2, lumaW) - 0.55, 0.0) + max(dot(n3, lumaW) - 0.55, 0.0);
    let bloom = halo * 0.25 * glowInt;

    var outCol = mix(greenWorld, trail * trailGain, 0.35 + trailLen * 0.25) + glowCol + vec3<f32>(grain);
    outCol += vec3<f32>(0.22, 1.0, 0.32) * bloom;
    outCol = aces(max(outCol, vec3<f32>(0.0)));
    let alpha = clamp(src.a * 0.3 + edgeGate * 0.4 + motion * 0.25 + mids * 0.05 + bloom * 0.2, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(trail, alpha));
    textureStore(writeTexture, coord, vec4<f32>(outCol, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
