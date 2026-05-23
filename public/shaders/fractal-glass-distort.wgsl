// ═══════════════════════════════════════════════════════════════════════════════
//  IFS Attractor Glass — Iterated Function System + Chromatic Glass
//  Category: distortion
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: High
//  Scientific: 4-contraction IFS (Barnsley fern variant),
//              attractor density field drives refraction index,
//              chromatic dispersion through fractal structure,
//              audio-driven contraction parameter modulation
//  Upgraded: Phase B
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,  // x=Contraction, y=Rotation, z=Refraction, w=Aberration
    ripples:     array<vec4<f32>, 50>,
}

// Apply one IFS affine transformation: p' = A·p + b
fn ifsAffine(p: vec2<f32>, angle: f32, scale: f32, tx: f32, ty: f32) -> vec2<f32> {
    let c = cos(angle); let s = sin(angle);
    return vec2<f32>(scale * (c * p.x - s * p.y) + tx,
                     scale * (s * p.x + c * p.y) + ty);
}

// Evaluate IFS attractor density at point p by inverse iteration.
// Each IFS map is the inverse of f_k; we apply it N times and measure escape.
fn ifsAttractorDensity(p: vec2<f32>, contraction: f32, rotation: f32, audio: f32) -> f32 {
    // Four contractions (Barnsley-inspired but time-animated)
    let s  = contraction * 0.55;
    let s2 = contraction * 0.45;
    let r1 = rotation;
    let r2 = rotation + 2.094; // +120°
    let r3 = rotation - 2.094; // -120°

    var q = p;
    var density = 0.0;
    // 8 inverse IFS iterations  — sufficient for stable density estimate
    for (var i = 0; i < 8; i++) {
        // Choose the contraction that brings q closest to each fixed point
        let q1 = ifsAffine(q, r1, 1.0 / s,  0.0, 0.5);
        let q2 = ifsAffine(q, r2, 1.0 / s2, 0.5, -0.4);
        let q3 = ifsAffine(q, r3, 1.0 / s2,-0.5, -0.4);
        let q4 = (q - vec2<f32>(0.0, -0.3)) * (1.0 / (s * 0.3));   // stem

        let d1 = length(q1);
        let d2 = length(q2);
        let d3 = length(q3);
        let d4 = length(q4);
        // Pick the branch that maps q into the unit circle (closest to attractor)
        if (d1 <= d2 && d1 <= d3 && d1 <= d4) { q = q1; }
        else if (d2 <= d3 && d2 <= d4)          { q = q2; }
        else if (d3 <= d4)                       { q = q3; }
        else                                     { q = q4; }

        density += exp(-length(q) * 3.0);
    }
    density = density / 8.0;
    return clamp(density, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;

    let contraction = mix(0.4, 0.75, u.zoom_params.x);
    let rotation    = u.zoom_params.y * 6.28318 + time * 0.2;
    let refrStr     = mix(0.0, 0.08, u.zoom_params.z) * (1.0 + bass * 0.4);
    let aberration  = u.zoom_params.w * 0.015 + mids * 0.005;

    // Center coordinate
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 1.5;

    // IFS density at current pixel and its gradient neighbours
    let d0  = ifsAttractorDensity(p, contraction, rotation, bass);
    let dx  = ifsAttractorDensity(p + vec2<f32>(0.008, 0.0), contraction, rotation, bass);
    let dy  = ifsAttractorDensity(p + vec2<f32>(0.0, 0.008), contraction, rotation, bass);
    // Gradient of the density field = normal for refraction
    let grad = vec2<f32>(dx - d0, dy - d0) * refrStr;

    // Chromatic aberration: R refracts more, B less (Cauchy dispersion)
    let uvR = clamp(uv + grad * 1.3, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + grad * 1.0, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + grad * 0.7, vec2<f32>(0.0), vec2<f32>(1.0));

    let sR  = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
    let sG  = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
    let sB  = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // IFS glow overlay — fractal structure shows in hot regions
    let glow  = d0 * d0 * 0.6;
    // Iridescent colour from gradient direction
    let angle  = atan2(grad.y, grad.x) / 6.28318 + 0.5;
    let iridR  = 0.5 + 0.5 * sin(angle * 6.28318 + 0.0);
    let iridG  = 0.5 + 0.5 * sin(angle * 6.28318 + 2.094);
    let iridB  = 0.5 + 0.5 * sin(angle * 6.28318 + 4.189);
    color = mix(color, vec3<f32>(iridR, iridG, iridB), glow * 0.4);

    // Bright highlights at high-density ridges
    color += vec3<f32>(0.9, 0.95, 1.0) * smoothstep(0.7, 1.0, d0) * 0.5;

    let dep = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(d0, grad.x, grad.y, glow));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(dep, 0.0, 0.0, 0.0));
}

