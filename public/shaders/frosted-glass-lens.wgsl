// ═══════════════════════════════════════════════════════════════════
//  Frosted Glass Lens
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-23 (Batch 64)
//
//  Brought up to the pool standard: no ACES (the output was written raw), no
//  click response, and `dataTextureC` was never read.
//
//  Also fixed: the frost grain came from `hash12(uv * 100.0 + time * 0.1)` — a
//  per-pixel hash reseeded every frame, which is uncorrelated frame to frame
//  and therefore strobes as static rather than reading as frost. The grain is
//  now a spatially-coherent value-noise field that drifts slowly, so the frost
//  looks deposited on the glass instead of boiling.
//
//  TWO NEW STRUCTURES
//
//    1. Beckmann microfacet scattering lobe — frosted glass scatters through a
//       distribution of microfacet slopes, not a single offset. The scatter is
//       now a five-tap lobe whose sample offsets are drawn from a Beckmann
//       slope distribution with roughness driven by the frost parameter, so
//       edges blur with the correct heavy-tailed falloff and the lens rim
//       softens the way ground glass actually does.
//
//    2. Depth-dependent frost thickness — frost accumulates where the surface
//       is coldest. Scene depth now modulates the Beer-Lambert thickness (far
//       geometry frosts over, near geometry stays clear), with the deposition
//       rate banded across the eight FFT bins.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=FrostAmount, y=LensRadius, z=EdgeSoftness, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Spatially coherent value noise for the frost grain.
fn frostNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Beckmann slope distribution sample offset for microfacet scattering.
// tan^2(theta) = -m^2 * ln(xi), with m the RMS slope (roughness).
fn beckmannOffset(xi: f32, phi: f32, m: f32) -> vec2<f32> {
    let tanTheta = m * sqrt(-log(max(xi, 1e-4)));
    return vec2<f32>(cos(phi), sin(phi)) * tanTheta;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv    = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params — bass pulses frost amount, mids drive aberration
    let frost_amt_base = u.zoom_params.x;
    let frost_dyn      = frost_amt_base * (1.0 + bass * 0.3);
    let lens_radius    = u.zoom_params.y * 0.4 + 0.05;
    let edge_softness  = u.zoom_params.z * 0.2 + 0.01;
    let aberration     = u.zoom_params.w * 0.02 * (1.0 + mids * 0.5);
    let glassDensity   = frost_dyn * 1.5 + 0.5;

    // Mouse
    let mouse  = u.zoom_config.yz;
    let aspect = resolution.x / max(resolution.y, 0.001);

    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist     = length(dist_vec);

    // Lens mask: 0 inside lens (clear), 1 outside (frost)
    let lens_mask = smoothstep(lens_radius, lens_radius + edge_softness, dist);

    // ── Structure 2: depth-dependent frost thickness ────────────────────────
    // Frost deposits on the cold (far) surfaces first.
    let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let bandIdx = u32(clamp(uv.y * 8.0, 0.0, 7.999));
    let band = plasmaBuffer[bandIdx + 1u].x;
    let coldness = mix(0.55, 1.45, sceneDepth) * (1.0 + band * 0.5);
    let frost_cold = frost_dyn * coldness;

    // Spatially coherent frost grain that drifts slowly. The previous
    // `hash12(uv * 100 + time * 0.1)` reseeded every pixel every frame, so it
    // strobed as static rather than sitting on the glass.
    let grainP = uv * 60.0 + vec2<f32>(u.config.x * 0.05, u.config.x * 0.037);
    let noise_val    = frostNoise(grainP);
    let frost_offset = (noise_val - 0.5) * 0.05 * frost_cold * lens_mask;

    // ── Bounded click frost-clear fronts ────────────────────────────────────
    // A click wipes a patch clear, which then re-frosts as the front decays.
    var clearFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = u.config.x - rp.z;
        if (age >= 0.0 && age < 2.6) {
            let r = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            clearFront += smoothstep(age * 0.32, 0.0, r) * exp(-age * 1.1);
        }
    }
    clearFront = min(clearFront, 1.0);

    // Fresnel via rough normal
    let roughNormal = normalize(vec3<f32>(frost_offset * 20.0, 0.0, 1.0 - frost_dyn * 0.5));
    let viewDir     = vec3<f32>(0.0, 0.0, 1.0);
    let cos_theta   = max(dot(viewDir, roughNormal), 0.0);
    let R0          = 0.04;
    let fresnel     = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);

    // Beer-Lambert thickness and absorption
    let thickness   = 0.03 + frost_cold * 0.1 * (1.0 + noise_val);
    let glassColor  = vec3<f32>(0.92, 0.95, 0.98);
    let absorption  = exp(-(1.0 - glassColor) * thickness * glassDensity);

    let baseTransmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;
    let transmission     = mix(baseTransmission, baseTransmission * 0.7, frost_dyn * lens_mask);

    // ── Structure 1: Beckmann microfacet scattering lobe ────────────────────
    // Five taps drawn from a Beckmann slope distribution, so the blur has the
    // heavy-tailed falloff of ground glass rather than a single offset.
    let roughM = clamp(0.012 + frost_cold * 0.055, 0.001, 0.12) * lens_mask;
    var lobe = vec3<f32>(0.0);
    var lobeW = 0.0;
    for (var s = 0u; s < 5u; s = s + 1u) {
        let fs = f32(s);
        let xi = fract(noise_val + fs * 0.2137);
        let phi = 6.2831853 * fract(noise_val * 3.17 + fs * 0.382);
        let off = beckmannOffset(xi, phi, roughM);
        // Beckmann weight falls off with slope; the centre tap dominates.
        let w = exp(-dot(off, off) / max(roughM * roughM, 1e-6) * 0.5);
        lobe += textureSampleLevel(readTexture, u_sampler,
                    clamp(uv + vec2<f32>(frost_offset) + off, vec2<f32>(0.0), vec2<f32>(1.0)),
                    0.0).rgb * w;
        lobeW += w;
    }
    let tex_a_rgb   = lobe / max(lobeW, 1e-4);
    let frostTint_a = mix(vec3<f32>(1.0), glassColor, 0.7);
    let rgb_a       = mix(tex_a_rgb, frostTint_a, 0.2 * frost_cold * lens_mask);

    // Branch B: inside lens — clear with slight tint
    let tex_b = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let rgb_b = tex_b.rgb * glassColor;

    // Mix by lens_mask (0=inside=branch B, 1=outside=branch A)
    let blended_rgb = mix(rgb_b, rgb_a, lens_mask);
    // alpha also blended: inside uses baseTransmission, outside uses transmission
    let blended_alpha = mix(baseTransmission, transmission, lens_mask);

    // Edge chromatic aberration mask
    let ab_mask = smoothstep(lens_radius, lens_radius + edge_softness * 0.5, dist) *
                  (1.0 - smoothstep(lens_radius + edge_softness * 0.5, lens_radius + edge_softness, dist));

    // Final sampling with chromatic aberration (overrides blended_rgb for final color)
    let uv_r = uv + vec2<f32>(frost_offset) + vec2<f32>(aberration * ab_mask, 0.0);
    let uv_g = uv + vec2<f32>(frost_offset);
    let uv_b = uv + vec2<f32>(frost_offset) - vec2<f32>(aberration * ab_mask, 0.0);

    let col_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let col_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let col_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    // Apply frost tint to aberrated color
    let frostTint  = vec3<f32>(0.9, 0.95, 1.0);
    let ab_rgb_raw = vec3<f32>(col_r, col_g, col_b);
    let ab_rgb     = mix(ab_rgb_raw, ab_rgb_raw * frostTint, 0.3 * frost_dyn * lens_mask);

    // Where we have aberration (ab_mask > 0), use aberrated color; elsewhere use blended
    var final_rgb = mix(blended_rgb, ab_rgb, ab_mask);
    // Click fronts wipe back toward the clear plate.
    let clearSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    final_rgb = mix(final_rgb, clearSample, clearFront * 0.85);
    final_rgb += vec3<f32>(0.55, 0.75, 1.0) * clearFront * (0.12 + treble * 0.3);

    // Temporal frost memory (exact load — dataTextureC is rgba32float).
    let prev = textureLoad(dataTextureC, coord, 0);
    final_rgb = mix(final_rgb, max(final_rgb, prev.rgb * 0.86), 0.28);

    final_rgb = acesFilm(final_rgb);

    // Beer-Lambert transmission as alpha; clear fronts open the glass up.
    let final_alpha = clamp(mix(blended_alpha, 1.0, clearFront * 0.5), 0.0, 1.0);
    let finalColor = vec4<f32>(final_rgb, final_alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);

    // Depth: frost sits on the surface, so geometry is preserved.
    textureStore(writeDepthTexture, coord, vec4<f32>(sceneDepth, 0.0, 0.0, 0.0));
}
