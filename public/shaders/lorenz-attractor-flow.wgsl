// ═══════════════════════════════════════════════════════════════════
//  Lorenz Attractor Flow
//  Category: generative
//  Features: generative, mouse-driven, temporal, chromatic, depth-aware
//  Complexity: High
//  Chunks From: none (original)
//  Created: 2026-05-09
//  Upgraded: 2026-05-31
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Integration Speed, y=Color Shift, z=Glow Intensity, w=Mouse Influence
  ripples: array<vec4<f32>, 50>,
};

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let t = u.config.x * 0.05;
    let mouse = u.zoom_config.yz;
    let click = u.config.y;

    let dt = 0.002 + u.zoom_params.x * 0.012;
    let colorShift = u.zoom_params.y;
    let glowIntensity = u.zoom_params.z;
    let mouseInfluence = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Map UV to phase space (scaled Lorenz coordinates)
    var p = vec3<f32>(
        (uv.x - 0.5) * 50.0 + sin(t * 0.3) * 2.0,
        (uv.y - 0.5) * 50.0 + cos(t * 0.4) * 2.0,
        20.0 + sin(t * 0.2) * 5.0
    );

    // Mouse interaction: perturb starting position
    p.x += (mouse.x - 0.5) * 20.0 * mouseInfluence;
    p.y += (mouse.y - 0.5) * 20.0 * mouseInfluence;

    // Lorenz parameters (classic chaotic values)
    let sigma: f32 = 10.0;
    let rho: f32 = 28.0;
    let beta: f32 = 8.0 / 3.0;

    var pathLength: f32 = 0.0;
    var prevP = p;

    // Integrate Lorenz ODE (Euler method, 80 steps for smooth flow)
    for (var i: i32 = 0; i < 80; i = i + 1) {
        let dx = sigma * (p.y - p.x);
        let dy = p.x * (rho - p.z) - p.y;
        let dz = p.x * p.y - beta * p.z;

        p.x += dx * dt;
        p.y += dy * dt;
        p.z += dz * dt;

        pathLength += length(p - prevP);
        prevP = p;
    }

    // Color based on final position and trajectory
    let hue = fract(p.z * 0.015 + t * 0.1 + pathLength * 0.002 + colorShift);
    let sat = 0.85 + sin(p.x * 0.08 + t) * 0.15;
    let val = 0.55 + 0.45 * (sin(p.y * 0.06 + t * 1.5) * 0.5 + 0.5);

    var rgb = hsv2rgb(vec3<f32>(hue, sat, val));

    // Chromatic dispersion: offset lobe glow per channel by audio
    let lobeDistR = min(
        length(vec2<f32>(p.x + 8.0 + bass * 1.5, p.y + mids * 0.5) * 0.08),
        length(vec2<f32>(p.x - 8.0 + bass * 1.5, p.y + mids * 0.5) * 0.08)
    );
    let lobeDistG = min(
        length(vec2<f32>(p.x + 8.0 - treble * 1.0, p.y + bass * 1.0) * 0.08),
        length(vec2<f32>(p.x - 8.0 - treble * 1.0, p.y + bass * 1.0) * 0.08)
    );
    let lobeDistB = min(
        length(vec2<f32>(p.x + 8.0 + mids * 0.8, p.y - treble * 1.2) * 0.08),
        length(vec2<f32>(p.x - 8.0 + mids * 0.8, p.y - treble * 1.2) * 0.08)
    );
    let glowR = exp(-lobeDistR * 1.8) * 0.35 * glowIntensity;
    let glowG = exp(-lobeDistG * 1.8) * 0.35 * glowIntensity;
    let glowB = exp(-lobeDistB * 1.8) * 0.35 * glowIntensity;
    rgb = vec3<f32>(rgb.r * (0.85 + glowR), rgb.g * (0.85 + glowG), rgb.b * (0.85 + glowB));

    // Mouse click ripple boost
    if (click > 0.5) {
        let rippleDist = length(uv - mouse);
        let ripple = exp(-rippleDist * 8.0) * sin(t * 20.0) * 0.4;
        rgb += vec3<f32>(0.3, 0.6, 1.0) * ripple;
    }

    // Gentle vignette for depth
    let vignette = 1.0 - length(uv - 0.5) * 0.6;
    rgb *= vignette;

    // Temporal feedback
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    rgb = mix(rgb, prev.rgb * 0.9, 0.03 + bass * 0.01);

    // Luminance-key alpha: brighter regions more opaque
    let luma = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.75, 1.0, smoothstep(0.2, 0.6, luma));

    textureStore(writeTexture, gid.xy, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(0.5, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(rgb, alpha));
}
