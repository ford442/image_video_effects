// ═══════════════════════════════════════════════════════════════════
//  Prismatic Ion Cascade
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-split,
//            temporal-cascade-persistence, audio-stream-modulation, depth-aware,
//            LOD-quality-scaling, hex-bokeh-glow, early-exit-culling, HDR-ready
//  Bloom Threshold: 1.25
//  Complexity: Medium
//  Upgraded: 2026-07-13
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

// ── Constants ─────────────────────────────────────────────────────
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const CASCADE_MAX_RADIUS: f32 = 1.35;
const CASCADE_CULL_MARGIN: f32 = 0.05;
const BLOOM_THRESHOLD: f32 = 1.25;
const GOLDEN_ANGLE: f32 = 2.39996322973;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash13(p: f32) -> vec3<f32> {
    let x = fract(sin(p * 127.11) * 43758.5453);
    let y = fract(sin(p * 269.13) * 43758.5453);
    let z = fract(sin(p * 419.19) * 43758.5453);
    return vec3<f32>(x, y, z);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, uu.x), mix(c, d, uu.x), uu.y);
}

// LOD-aware FBM: fewer octaves in low-alpha / distant regions.
fn fbm_lod(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var freq = p;
    for (var i = 0; i < octaves; i++) {
        v += amp * noise2(freq);
        freq = freq * 2.03;
        amp = amp * 0.5;
    }
    return v;
}

// Compute a single band mask from pre-rotated phase using one sin() call.
fn ion_band_mask(phase: f32, thickness: f32, edge: f32) -> f32 {
    let wave = sin(phase);
    let t = clamp(thickness * 25.0, 0.02, 0.98);
    return smoothstep(1.0 - t, 1.0 - t + edge, abs(wave));
}

// Sparse hex-bokeh / lens-dust glow approximation.
fn hex_bokeh_glow(uv: vec2<f32>, p: vec2<f32>, time: f32, treble: f32) -> vec3<f32> {
    let hexScale = 18.0;
    let hexUV = uv * hexScale;
    let idx = floor(hexUV);
    let rnd = hash13(idx.x * 73.1 + idx.y * 37.3 + floor(time * 2.0) * 0.0);
    let center = (idx + 0.5) / hexScale;
    let d = length((uv - center) * vec2<f32>(1.0, 1.732));
    let bokeh = smoothstep(0.035, 0.0, d) * step(0.92, rnd.x);
    let hue = fract(rnd.y + time * 0.05 + treble * 0.1);
    let chroma = vec3<f32>(
        0.5 + 0.5 * cos(TAU * (hue + 0.0)),
        0.5 + 0.5 * cos(TAU * (hue + 0.333)),
        0.5 + 0.5 * cos(TAU * (hue + 0.667))
    );
    return chroma * bokeh * (0.4 + treble * 0.8);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Uniform parameter remapping.
    let streamDensity = 4.0 + u.zoom_params.x * 16.0 + bass * 4.0;
    let cascadeSpeed = 0.3 + u.zoom_params.y * 2.0;
    let spectralSpread = 0.02 + u.zoom_params.z * 0.15;
    let ionThickness = 0.005 + u.zoom_params.w * 0.06;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let aspect = resolution.x / max(resolution.y, 1.0);
    let p = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y);

    let r = length(p);
    let theta = atan2(p.y, p.x);

    // Early-exit for pixels well outside the cascade influence radius.
    if (r > CASCADE_MAX_RADIUS + CASCADE_CULL_MARGIN) {
        let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeTexture, coord, baseSample);
        textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
        textureStore(dataTextureA, coord, baseSample);
        return;
    }

    // LOD quality: fewer FBM octaves for distant / low-alpha pixels.
    var octaves = 5;
    if (r > CASCADE_MAX_RADIUS * 0.65) {
        octaves = 3;
    } else if (r > CASCADE_MAX_RADIUS * 0.35 && u.zoom_params.w < 0.25) {
        octaves = 4;
    }

    // Curl-warped angular bands.
    let warpFreq = vec2<f32>(theta * 2.0, time * cascadeSpeed * (1.0 + mids * 0.4));
    let warp = fbm_lod(warpFreq, octaves);
    let bandPhase = theta * streamDensity + warp * 3.0 + time * cascadeSpeed * (1.0 + bass * 0.5);

    // Chromatic spectral split: compute three phase offsets, one sin() each.
    let split = spectralSpread * (1.0 + treble * 0.8);
    let phaseR = bandPhase + split * TAU;
    let phaseG = bandPhase;
    let phaseB = bandPhase - split * TAU;

    let edgeSoft = 0.005 + ionThickness * 0.02;
    let maskR = ion_band_mask(phaseR, ionThickness, edgeSoft);
    let maskG = ion_band_mask(phaseG, ionThickness, edgeSoft);
    let maskB = ion_band_mask(phaseB, ionThickness, edgeSoft);

    let radialPulse = 1.0 + bass * 0.6;
    let coreFall = exp(-r * (3.0 - radialPulse));
    let outerFall = exp(-r * 1.4);
    let falloff = coreFall + outerFall * 0.4;

    var ionR = maskR * falloff;
    var ionG = maskG * falloff;
    var ionB = maskB * falloff;

    // Sparse FBM shimmer and audio-reactive flicker.
    let shimmer = fbm_lod(p * 6.0 + vec2<f32>(time * 0.5, -time * 0.7), octaves) * 0.5 + 0.5;
    let flicker = mix(0.7, 1.3, shimmer) * (1.0 + treble * 0.4);

    var ionColor = vec3<f32>(ionR, ionG, ionB) * flicker;

    // Hex-bokeh glow overlay.
    let bokehGlow = hex_bokeh_glow(uv, p, time, treble);
    ionColor = ionColor + bokehGlow * (outerFall * 0.75 + coreFall * 0.25);

    // Temporal cascade persistence: ion trail burn-in.
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let trailBurn = mix(ionColor, prev * 0.92, 0.08 + bass * 0.03);
    ionColor = mix(ionColor, trailBurn, 0.5);

    // Base sample + depth-aware atmospheric haze.
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let haze = vec3<f32>(0.05, 0.08, 0.18) * outerFall * (1.0 + bass * 0.5);

    // Smart depth compositing: fade cascade behind scene depth planes.
    let depthFade = clamp(1.0 - (depth * 2.5 - r * 1.2), 0.0, 1.0);
    var composed = baseSample.rgb * 0.35 + ionColor * 2.2 * depthFade + haze;

    // Audio-reactive sparkle on band peaks.
    let sparkleSeed = hash21(floor(uv * resolution * 0.5) + floor(time * 8.0));
    let bandMaskAvg = (maskR + maskG + maskB) * 0.333;
    let sparkle = step(0.985, sparkleSeed) * bandMaskAvg * treble * 1.5;
    var finalRGB = composed + vec3<f32>(sparkle);

    // Depth-scaled ion intensity.
    let depthScale = 0.6 + depth * 0.4;
    finalRGB = finalRGB * depthScale;

    // Ion strength and alpha envelope.
    let ionStrength = (ionR + ionG + ionB) * 0.333;
    var alpha = clamp(baseSample.a * 0.25 + ionStrength * 0.6 + coreFall * 0.3 + bass * 0.1, 0.0, 1.0);

    // Distance falloff alpha fade near cull radius.
    alpha = alpha * smoothstep(CASCADE_MAX_RADIUS + CASCADE_CULL_MARGIN, CASCADE_MAX_RADIUS * 0.85, r);

    // HDR-ready: preserve super-threshold energy for bloom; clamp before tone map.
    finalRGB = clamp(finalRGB, vec3<f32>(0.0), vec3<f32>(8.0));

    let depthOut = clamp(1.0 - coreFall, 0.0, 1.0);

    finalRGB = acesToneMap(finalRGB * 1.1);

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
}
