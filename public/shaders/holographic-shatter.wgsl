// ═══════════════════════════════════════════════════════════════════
//  Holographic Shatter
//  Category: image
//  Features: advanced-alpha, holographic, shatter, glass, mouse-driven, audio-reactive,
//            temporal-shard-persistence, audio-impact, chromatic-edge-refraction
//  Complexity: High
//  Upgraded: 2026-05-31
//  Batch-19: guarded plasma palette read (live FFT bins), wired the dead
//            Depth Weight slider, near-focused impact falloff (was inverted),
//            click shatter detonations via live ripples
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Slider mapping (saved-preset contract: zoom_params x/y/z/w) ──
    //   x: Shatter Amount     -> shard flight distance (bass-boosted)
    //   y: Hologram Intensity -> foil / edge interference strength
    //   z: Depth Weight       -> depth- vs luma-tiered alpha blend
    //   w: Shard Count        -> fracture grid density (10..60 cells)
    let shatterAmount = clamp(u.zoom_params.x * (1.0 + bass * 0.4), 0.0, 1.0);
    let holographicIntensity = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let shardCount = u.zoom_params.w * 50.0 + 10.0;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dM = distance(uv, mouse);

    // FIXED: impact falloff was inverted (grew with distance, so mouse-down
    // flung far shards while the cursor zone sat still). Now near-focused,
    // with a small global baseline so idle / far-field drift survives.
    let mouseGain = 0.4 + mouseDown * 0.6;
    let nearImpact = mouseGain * smoothstep(0.6, 0.0, dM);
    let impact = max(nearImpact, 0.25 * mouseGain);

    // Fracture grid + per-shard identity
    let gridUV = uv * shardCount;
    let shardId = floor(gridUV);
    let shardUv = fract(gridUV);

    let shardRand = rand(shardId);
    let shardCenter = (shardId + 0.5) / shardCount;
    let flightDir = normalize(shardCenter - mouse + vec2<f32>(1e-4));

    // Click shatter detonations: each live ripple acts as a decaying impact
    // center (same flight math, ripple position as origin, weight
    // exp(-age * 2.5) over a ~1.5s life) so individual clicks crack the
    // glass even with the mouse button up.
    let rippleCount = min(u32(u.config.y), 50u);
    var clickImpact: f32 = 0.0;
    var clickDir = vec2<f32>(0.0, 0.0);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 1.5) {
            let rDist = distance(shardCenter, ripple.xy);
            let rDir = normalize(shardCenter - ripple.xy + vec2<f32>(1e-4));
            let w = exp(-age * 2.5) * smoothstep(0.5, 0.0, rDist);
            clickImpact = clickImpact + w;
            clickDir = clickDir + rDir * w;
        }
    }
    clickImpact = min(clickImpact, 1.0);

    // Audio-driven impact force: mouse shockwave + click detonations
    let shardForce = shatterAmount * (0.4 + shardRand * 0.6) * (1.0 + treble * 0.3);
    let offset = flightDir * shardForce * impact + clickDir * shardForce * 0.8;

    let warpedUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let edgeDist = min(min(shardUv.x, 1.0 - shardUv.x), min(shardUv.y, 1.0 - shardUv.y));
    let edgeGlow = smoothstep(0.1, 0.0, edgeDist);

    // Chromatic edge refraction per shard (holographic sin math unchanged).
    // FIXED: palette index wrapped into the live FFT bin range 1..8 -
    // previously palIdx % 256u read far past the real bin count (OOB
    // storage reads return zeros -> dead black palette).
    let phase = time + shardRand * TAU + depth * PI;
    let holographic = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));
    let palIdx = u32(clamp((shardRand + time * 0.05) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[(palIdx % 8u) + 1u].rgb;
    let foil = mix(holographic, holographic * (0.6 + palette * 0.7), 0.4);

    // Per-channel refraction along the flight direction: shard edges split
    // light like a prism; strength is mids-driven so edges shimmer with audio.
    let chromaMix = clamp(edgeGlow * (0.5 + mids * 0.5) + clickImpact * 0.3, 0.0, 1.0);
    let refr = flightDir * (edgeGlow * 0.012 + impact * shatterAmount * 0.01);
    let refrR = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + refr, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let refrB = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV - refr, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    // Temporal shard persistence: previous frame offsets blend for settling glass
    let prevShards = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let settled = mix(sample.rgb, prevShards * 0.92, 0.06 + bass * 0.02);

    var finalColor = mix(settled, foil, edgeGlow * holographicIntensity);
    finalColor = vec3<f32>(
        mix(finalColor.r, refrR, chromaMix * 0.6),
        finalColor.g,
        mix(finalColor.b, refrB, chromaMix * 0.6)
    );

    let effectIntensity = edgeGlow * holographicIntensity + shatterAmount * 0.5 + clickImpact * 0.3;

    // FIXED: Depth Weight slider was dead - depthLayeredAlpha() was never
    // called. zoom_params.z now blends source alpha against the
    // depth/luma-tiered alpha, scaled by how strongly the effect applies.
    let finalAlpha = mix(baseColor.a, depthLayeredAlpha(finalColor, uv, depthWeight), clamp(effectIntensity, 0.0, 1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    // dataTextureA stays DISPLAY color (raw - the C feedback expects color, not masks)
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    // Depth passthrough (normalized: alpha lane 0.0 instead of the odd 1)
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
