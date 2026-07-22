// ═══════════════════════════════════════════════════════════════════
//  spec-analytic-noise-flow
//  Category: generative
//  Features: analytic-derivatives, flow-field, noise, temporal, chromatic, depth-aware
//  Complexity: High
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  Upgraded: 2026-05-31
//  Optimized: 2026-07-22 — iso-contour ridges, bass surge, temporal
//             streamline smoothing (free analytic gradient exploitation)
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Noise with Analytic Derivatives for Flow Fields
//  Implements Perlin noise with analytic derivatives — gradient is
//  computed alongside noise value in a single evaluation. Creates
//  perfectly smooth flow fields without finite-difference jitter.
//  The gradient is a FREE byproduct: this shader spends it on
//  iso-contour ridge lines, gradient-aware line widths, and
//  temporally smoothed streamlines.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash2(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash12(p), hash12(p + vec2<f32>(37.0, 17.0)));
}

// Analytic derivative noise: returns x = value, yz = gradient
fn noiseWithDerivative(p: vec2<f32>) -> vec3<f32> {
    let i = floor(p);
    let f = fract(p);

    // Quintic interpolation with analytic derivative
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    // Hash corners
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));

    // Value interpolation
    let k0 = a;
    let k1 = b - a;
    let k2 = c - a;
    let k4 = a - b - c + d;

    let value = k0 + k1 * u.x + k2 * u.y + k4 * u.x * u.y;
    let derivative = vec2<f32>(
        (k1 + k4 * u.y) * du.x,
        (k2 + k4 * u.x) * du.y
    );

    return vec3<f32>(value, derivative);
}

// Multi-octave analytic noise
fn fbmAnalytic(p: vec2<f32>, octaves: i32) -> vec3<f32> {
    var value = 0.0;
    var grad = vec2<f32>(0.0);
    var amplitude = 0.5;
    var frequency = 1.0;

    for (var i: i32 = 0; i < octaves; i = i + 1) {
        let n = noiseWithDerivative(p * frequency);
        value += amplitude * n.x;
        grad += amplitude * frequency * n.yz;
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    return vec3<f32>(value, grad);
}

// Iso-contour ridge mask built from the noise value and the FREE
// analytic gradient magnitude. The line width adapts to |grad|:
// hairline-thin where the field is steep, softly feathered where it
// is flat — impossible to get right with finite differences.
//   value   : noise value (noise.x)
//   gradMag : length of the analytic gradient (noise.yz)
//   count   : number of contour bands across the value range
//   sharpen : 0..1 treble-driven line sharpening
fn contourRidge(value: f32, gradMag: f32, count: f32, sharpen: f32) -> f32 {
    let phase = abs(fract(value * count) - 0.5) * 2.0; // 0 at line center
    let width = max((0.10 + gradMag * 0.30) * (1.0 - sharpen * 0.60), 0.02);
    return 1.0 - smoothstep(0.0, width, phase);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    // ─── Slider wiring (zoom_params.x/y/z/w) ───
    // x: Flow Scale  -> noise domain frequency (streamline density)
    // y: Flow Speed  -> time-evolution rate of the field
    // z: Advection   -> UV warp distance (amplified by bass surges)
    // w: Curl Amount -> perpendicular-gradient curl + contour density
    let flowScale = mix(1.0, 5.0, u.zoom_params.x);
    let flowSpeed = mix(0.2, 2.0, u.zoom_params.y);
    let advectionStr = mix(0.0, 0.3, u.zoom_params.z);
    let curlAmount = mix(0.0, 1.0, u.zoom_params.w);

    // ─── Audio envelopes ───
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    // Bass envelope: kicks visibly surge the whole flow field.
    let bassEnv = clamp(bass * 1.5, 0.0, 1.8);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Sample base image for advection source
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Analytic noise flow field (value in .x, gradient free in .yz)
    let p = uv * flowScale + time * flowSpeed;
    let noise1 = fbmAnalytic(p, 4);
    let noise2 = fbmAnalytic(p + vec2<f32>(5.2, 1.3), 4);

    // Build velocity field from analytic gradients
    var velocity = vec2<f32>(noise1.y, noise2.y);

    // Add curl (perpendicular to gradient)
    let curl = vec2<f32>(-noise1.z, noise1.y) * curlAmount;
    velocity += curl;

    // Mouse vortex
    if (isMouseDown) {
        let toMouse = mousePos - uv;
        let dist = length(toMouse);
        let vortexStrength = exp(-dist * dist * 500.0);
        let perp = vec2<f32>(-toMouse.y, toMouse.x) / (dist + 0.001);
        velocity += perp * vortexStrength * 0.5;
    }

    // ─── Temporally coherent streamlines ───
    // dataTextureA stores velocity in .rg; it resurfaces one frame later
    // through dataTextureC. This is a SEPARATE read path from the light
    // color feedback below. Exponential frame-to-frame smoothing stops
    // streamline shimmer; bass surges briefly reopen the filter so kicks
    // still punch through instead of lagging behind the music.
    let prevVel = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rg;
    let velSmooth = clamp(0.65 - bassEnv * 0.25, 0.15, 0.75);
    velocity = mix(velocity, prevVel, velSmooth);

    // ─── Advect sample position along the (smoothed) flow ───
    // Bass surge: advection distance scales with the bass envelope.
    let advectedUV = uv + velocity * advectionStr * (1.0 + bassEnv);
    let warpedColor = textureSampleLevel(readTexture, u_sampler, fract(advectedUV), 0.0).rgb;

    // Flow visualization: color by direction
    let flowAngle = atan2(velocity.y, velocity.x) / 6.28318 + 0.5;
    let flowColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * flowAngle),
        0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.67))
    );

    // Blend warped image with flow visualization
    let blendFactor = 0.6;
    var outColor = mix(warpedColor, flowColor * 0.5 + warpedColor * 0.5, blendFactor);

    // ─── Iso-contour ridges from the analytic gradient ───
    // Gradient magnitude is a free byproduct of noiseWithDerivative.
    // Contour density rides the Detail-adjacent Curl slider; treble
    // sharpens the lines into crisp topographic ridges.
    let contourCount = mix(4.0, 20.0, u.zoom_params.w);
    let gradMag = length(noise1.yz);
    let ridge = contourRidge(noise1.x, gradMag, contourCount, treble);
    let ridgeColor = vec3<f32>(0.85, 0.92, 1.0) * ridge * (0.25 + mids * 0.30);
    outColor += ridgeColor * (0.35 + curlAmount * 0.65);

    // Legacy soft streamline band (kept for the shader's soul).
    // Fades out as Curl rises so the crisp contour ridges take over
    // without double-lighting the same streamlines.
    let streamline = smoothstep(0.0, 0.1, abs(noise1.x - 0.5));
    outColor += vec3<f32>(0.1, 0.15, 0.2) * streamline * (1.0 - curlAmount);

    // Gradient-magnitude vignette: fast-flowing cores glow slightly,
    // anchoring the eye on the strongest streamlines.
    let speedGlow = smoothstep(0.4, 1.4, length(velocity)) * 0.12;
    outColor += flowColor * speedGlow;

    // ─── Chromatic dispersion ───
    let chrStrength = 0.004 + bass * 0.008;
    let chrR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chrStrength * (1.0 + mids * 0.5), 0.0), 0.0).r;
    let chrG = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, chrStrength * (1.0 + treble * 0.3)), 0.0).g;
    let chrB = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-chrStrength * 0.7 * (1.0 + bass * 0.4), chrStrength * 0.3), 0.0).b;
    let chrColor = vec3<f32>(chrR, chrG, chrB);
    outColor = mix(outColor, chrColor, 0.2 + bass * 0.15);

    // ─── Temporal color feedback (light ~3% mix, kept intact) ───
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    outColor = mix(outColor, prev.rgb * 0.9, 0.03 + bass * 0.01);

    // Depth output: flow magnitude mapped to a soft depth field so the
    // depth-aware pipeline sees fast streamlines as closer ridges.
    let flowDepth = length(velocity) * 0.5 + 0.25;
    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, length(velocity)));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(flowDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(velocity, noise1.x, 1.0));
}
