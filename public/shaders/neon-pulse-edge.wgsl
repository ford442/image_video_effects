// ═══════════════════════════════════════════════════════════════════
//  Neon Pulse Edge — Phase A Upgrade
//  Category: lighting-effects
//  Features: audio-reactive, depth-aware, mouse-driven
//  Complexity: Medium
//  Chunks From: original neon-pulse-edge.wgsl
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=EdgeThreshold, y=GlowRadius, z=PulseSpeed, w=ColorCycleRate
  ripples: array<vec4<f32>, 50>,
};

// ─── Colour helpers ────────────────────────────────────────────────

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// Approximate signed distance to nearest bright edge by sampling a blurred edge ring
fn softEdgeDist(uv: vec2<f32>, px: vec2<f32>, r: f32) -> f32 {
    var acc = 0.0;
    let steps = 8;
    for (var i = 0; i < steps; i++) {
        let angle = f32(i) / f32(steps) * 6.28318;
        let offset = vec2<f32>(cos(angle), sin(angle)) * r;
        acc += textureSampleLevel(dataTextureC, non_filtering_sampler,
                                  clamp(uv + offset * px, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    }
    return acc / f32(steps);
}

// ─── Main ─────────────────────────────────────────────────────────

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv   = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px   = 1.0 / resolution;

    // Params
    let threshold     = u.zoom_params.x * 0.5 + 0.02;
    let glowRadius    = u.zoom_params.y * 6.0 + 1.0;
    let pulseSpeed    = u.zoom_params.z * 6.0 + 0.5;
    let cycleRate     = u.zoom_params.w;

    // Audio from canonical plasmaBuffer
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass   = select(0.0, plasmaBuffer[0].x, hasAudio);
    let mids   = select(0.0, plasmaBuffer[0].y, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);
    let audioBoost = 1.0 + bass * 0.6 + treble * 0.2;

    // Depth: near = 1.0
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ── Full 3×3 Sobel edge detection ────────────────────────────
    let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-px.x, -px.y), 0.0).rgb;
    let tc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,  -px.y), 0.0).rgb;
    let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( px.x, -px.y), 0.0).rgb;
    let ml = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-px.x,  0.0), 0.0).rgb;
    let mr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( px.x,  0.0), 0.0).rgb;
    let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-px.x,  px.y), 0.0).rgb;
    let bc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,   px.y), 0.0).rgb;
    let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( px.x,  px.y), 0.0).rgb;

    // Sobel kernels (luma)
    let lum = vec3<f32>(0.299, 0.587, 0.114);
    let gxMag = -dot(tl,lum) - 2.0*dot(ml,lum) - dot(bl,lum)
               + dot(tr,lum) + 2.0*dot(mr,lum) + dot(br,lum);
    let gyMag = -dot(tl,lum) - 2.0*dot(tc,lum) - dot(tr,lum)
               + dot(bl,lum) + 2.0*dot(bc,lum) + dot(br,lum);

    let edgeMag = sqrt(gxMag*gxMag + gyMag*gyMag);

    // Edge direction angle → drives colour cycling
    let edgeAngle = atan2(gyMag, gxMag);  // -π to π

    // Store edge magnitude in dataTextureA for glow sampling next frame
    textureStore(dataTextureA, vec2<i32>(global_id.xy),
                 vec4<f32>(edgeMag, depth, 0.0, 1.0));

    // ── Hue from edge direction + time + audio ────────────────────
    let hue = fract(edgeAngle / 6.28318 + time * pulseSpeed * 0.02
                  + cycleRate * 0.3 + bass * 0.15);
    let sat = 0.8 + treble * 0.15;
    let val = 1.0;
    let neonColor = hsv2rgb(vec3<f32>(hue, sat, val));

    // ── Multi-layer bloom ─────────────────────────────────────────
    // Tight core glow (1px ring)
    let coreGlow  = softEdgeDist(uv, px, 1.5);
    // Wide atmospheric halo (glowRadius px ring)
    let haloGlow  = softEdgeDist(uv, px, glowRadius);
    // Very wide diffuse (3× glowRadius)
    let diffuseGlow = softEdgeDist(uv, px, glowRadius * 2.8);

    // Depth amplifies glow for near edges
    let depthFactor = 1.0 + depth * 1.2;

    // Mouse proximity boosts glow
    let mouse = u.zoom_config.yz;
    var mouseFactor = 1.0;
    if (mouse.x >= 0.0) {
        let mDist = length((uv - mouse) * vec2<f32>(resolution.x / resolution.y, 1.0));
        mouseFactor = 1.0 + (1.0 - smoothstep(0.0, 0.25, mDist)) * 1.5;
    }

    // Core edge emission
    var emission = vec3<f32>(0.0);
    let isEdge = step(threshold, edgeMag);
    if (isEdge > 0.5) {
        // Pulsing core: tight, bright, saturated
        let pulse = 0.7 + 0.3 * sin(time * pulseSpeed * (1.0 + bass));
        emission += neonColor * edgeMag * pulse * depthFactor * mouseFactor * audioBoost * 1.8;
    }

    // Halo: uses stored previous-frame edge map for softer accumulation
    let haloColor = hsv2rgb(vec3<f32>(fract(hue + 0.05), sat * 0.7, 1.0));
    emission += haloColor  * coreGlow   * depthFactor * audioBoost * 0.6;
    emission += neonColor  * haloGlow   * depthFactor * audioBoost * 0.25;
    emission += haloColor  * diffuseGlow * 0.08 * audioBoost;

    // Base image dims behind glow
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let edgeDim   = 1.0 - isEdge * 0.4;
    let finalColor = baseColor * edgeDim + emission;

    // RGBA alpha: glow emission drives additive blending compatibility
    let glowStrength = clamp(length(emission) * 0.5, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy),
                 vec4<f32>(finalColor, glowStrength));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy),
                 vec4<f32>(depth, 0.0, 0.0, 1.0));
}
