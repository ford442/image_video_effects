// ═══════════════════════════════════════════════════════════════════
//  Liquid Metal — Phase A Upgrade
//  Category: liquid-effects
//  Features: mouse-driven, depth-aware, temporal, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: original liquid-metal.wgsl
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: viscosity        — how slowly the height field evolves
//  Param2: reflectivity     — F0 metallic base reflectance
//  Param3: chromatic_spread — RGB dispersion on reflections
//  Param4: flow_speed       — gravity-like flow toward depth attractor
//
//  dataTextureC.r = height field (persists across frames)

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 64)
//
//  A carries the HEIGHT FIELD (r = surface height), read back as dataTextureC
//  next frame; display goes to writeTexture. Overwriting A with colour would
//  destroy the fluid.
//
//  Contract gaps closed: the output was written without a tone map, and the
//  height field was fetched with `textureSampleLevel` rather than exact
//  `textureLoad`. The sampler in use is the non-filtering one so the reads were
//  valid, but nearest-sampling a float32 texture through the sampler path is
//  the house anti-pattern — exact loads make the intent explicit and let the
//  flow term do proper bilinear interpolation by hand.
//
//  TWO NEW STRUCTURES
//
//    1. Rosensweig (ferrofluid spike) instability — above a critical field
//       strength a magnetic fluid's flat surface becomes unstable and breaks
//       into a hexagonal lattice of standing peaks. The surface height now runs
//       that instability: wherever the local field exceeds the critical value
//       set by surface tension and gravity, a hexagonal mode grows and
//       saturates, which is the actual mechanism behind the spikes this shader
//       is imitating.
//
//    2. Anisotropic metal BRDF — liquid metal was shaded with an isotropic
//       Blinn-Phong lobe. Flowing metal has a directional micro-structure
//       aligned with the flow, so the highlight is now stretched perpendicular
//       to the flow direction using an anisotropic Ward-style lobe, with the
//       anisotropy driven per FFT band.
// ═══════════════════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=Viscosity, y=Reflectivity, z=ChromaticSpread, w=FlowSpeed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265;

// ─── Helpers ──────────────────────────────────────────────────────

fn hash1(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash1(i), hash1(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash1(i + vec2<f32>(0.0, 1.0)), hash1(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// FBM height field for liquid surface
fn fbmHeight(p: vec2<f32>, t: f32) -> f32 {
    var v = 0.0; var amp = 0.5; var pp = p;
    for (var i = 0; i < 4; i = i + 1) {
        v += amp * vnoise(pp + vec2<f32>(t * 0.07, t * 0.05));
        pp = pp * 2.1 + vec2<f32>(1.7, 9.2);
        amp *= 0.5;
    }
    return v;
}

// Schlick Fresnel reflectance
fn schlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Surface normal from height field gradient
fn heightNormal(uv: vec2<f32>, px: vec2<f32>, t: f32) -> vec3<f32> {
    let scale = 3.5;
    let hL = fbmHeight(uv * scale - vec2<f32>(px.x, 0.0), t);
    let hR = fbmHeight(uv * scale + vec2<f32>(px.x, 0.0), t);
    let hD = fbmHeight(uv * scale - vec2<f32>(0.0, px.y), t);
    let hU = fbmHeight(uv * scale + vec2<f32>(0.0, px.y), t);
    return normalize(vec3<f32>(hL - hR, hD - hU, 0.04));
}

// ─── Main ─────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv      = vec2<f32>(global_id.xy) / resolution;
    let time    = u.config.x;
    let px      = 1.0 / resolution;
    let aspect  = resolution.x / resolution.y;
    let mouse   = u.zoom_config.yz;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let viscosity      = u.zoom_params.x * 0.9 + 0.05;
    let reflectivity   = u.zoom_params.y;
    let chromaSpread   = u.zoom_params.z * 0.025;
    let flowSpeed      = u.zoom_params.w;

    // Depth (1=near foreground, 0=far background)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ── Temporal height field ─────────────────────────────────────
    // Read previous height from dataTextureC, evolve toward FBM target
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    let coordI = vec2<i32>(global_id.xy);
    let prevH = textureLoad(dataTextureC, coordI, 0).r;
    var targetH = fbmHeight(uv * 3.0, time);

    // Flow: height field drains toward high-depth (foreground) regions
    // Sample depth gradient to get flow direction
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(px.x, 0.0), 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, px.y), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, px.y), 0.0).r;
    let depthGrad = vec2<f32>(dR - dL, dU - dD);
    let flowUV = uv + depthGrad * flowSpeed * 0.02;
    let flowH = heightBilinear(clamp(flowUV, vec2<f32>(0.0), vec2<f32>(1.0))
                               * vec2<f32>(dimsI), dimsI);

    // Mouse pour: add height under cursor
    if (mouse.x >= 0.0) {
        let mDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
        if (mDist < 0.08) {
            let pour = (1.0 - smoothstep(0.0, 0.08, mDist)) * 0.6;
            targetH = max(targetH, pour);
        }
    }

    // Ripple impulses add height
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let r = u.ripples[ri];
        let elapsed = time - r.z;
        if (elapsed >= 0.0 && elapsed < 1.5) {
            let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
            let splash = exp(-rDist * 10.0) * exp(-elapsed * 3.0);
            targetH = max(targetH, splash * 0.8);
        }
    }

    // Audio pulses the surface
    targetH = targetH * (1.0 + bass * 0.3);

    // ── Structure 1: Rosensweig (ferrofluid spike) instability ──────────────
    // Above a critical field the flat surface is unstable and breaks into a
    // hexagonal lattice of standing peaks. Field strength here is the local
    // pointer proximity plus bass drive; the critical value comes from the
    // surface-tension/gravity balance the `viscosity` slider stands in for.
    let mDistField = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let fieldStrength = exp(-mDistField * 4.5) * (0.5 + bass * 1.6) + bass * 0.35;
    let critical = 0.30 + viscosity * 0.45;
    let supercritical = max(fieldStrength - critical, 0.0);
    if (supercritical > 0.0) {
        // Hexagonal mode: three plane waves at 60 degrees.
        let kSpike = 46.0 + treble * 26.0;
        let q = uv * vec2<f32>(aspect, 1.0) * kSpike;
        let h1 = cos(q.x);
        let h2 = cos(q.x * -0.5 + q.y * 0.8660254);
        let h3 = cos(q.x * -0.5 - q.y * 0.8660254);
        let hexMode = (h1 + h2 + h3) / 3.0;
        // Amplitude saturates as sqrt of the supercritical excess.
        let amp = sqrt(clamp(supercritical, 0.0, 1.0)) * 0.55;
        targetH = max(targetH, targetH + max(hexMode, 0.0) * amp);
    }

    // Viscosity: slow blend from prev to target (high viscosity = slow)
    let blendRate = (1.0 - viscosity) * 0.15 + 0.01;
    let newH = mix(mix(prevH, flowH, flowSpeed * 0.1), targetH, blendRate);

    // ── Surface normal from height gradient ───────────────────────
    let effTime = time * (1.0 - viscosity * 0.7);
    let normal = heightNormal(uv, px, effTime);

    // ── Fresnel reflectance ───────────────────────────────────────
    let viewDir = normalize(vec3<f32>((uv - 0.5) * vec2<f32>(aspect, 1.0), 1.0));
    let cosTheta = clamp(dot(viewDir, normal), 0.0, 1.0);
    let F0 = mix(0.04, 0.95, reflectivity);
    let F  = schlick(cosTheta, F0);

    // ── Chromatic dispersion on refraction ────────────────────────
    // Normal displaces UV differently per channel (RGB split by wavelength)
    let refractBase = vec2<f32>(normal.xy) * (newH * 0.06 + 0.01);
    let rUV = clamp(uv + refractBase * (1.0 - chromaSpread), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + refractBase,                        vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + refractBase * (1.0 + chromaSpread), vec2<f32>(0.0), vec2<f32>(1.0));

    let sampR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let sampG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let sampB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let refractedColor = vec3<f32>(sampR, sampG, sampB);

    // ── Metallic reflection colour ────────────────────────────────
    // Silver-grey tinted by iridescence from height and time
    let iridPhase = newH * 4.0 + time * 0.3;
    let irid = vec3<f32>(
        0.75 + 0.25 * sin(iridPhase),
        0.80 + 0.20 * sin(iridPhase + 2.09),
        0.85 + 0.15 * sin(iridPhase + 4.19)
    );
    let metalColor = mix(vec3<f32>(0.8, 0.85, 0.9), irid, reflectivity * 0.7);

    // ── Structure 2: anisotropic metal BRDF ─────────────────────────────────
    // Flowing metal has micro-structure aligned with the flow, so the highlight
    // stretches perpendicular to it. Ward-style anisotropic lobe with the
    // aspect ratio driven per FFT band.
    let halfV = normalize(viewDir + vec3<f32>(0.3, 0.5, 0.8));
    let bandIdx = u32(clamp(uv.x * 8.0, 0.0, 7.999));
    let bandE = plasmaBuffer[bandIdx + 1u].x;
    let flowDir3 = normalize(vec3<f32>(depthGrad * 40.0 + vec2<f32>(1e-4), 1.0));
    let tangentX = normalize(cross(normal, flowDir3) + vec3<f32>(1e-5, 0.0, 0.0));
    let tangentY = cross(normal, tangentX);
    let hDotN = max(dot(normal, halfV), 1e-4);
    let hx = dot(halfV, tangentX);
    let hy = dot(halfV, tangentY);
    // Roughness along vs across the flow.
    let alphaX = mix(0.42, 0.05, reflectivity);
    let alphaY = alphaX * (1.0 + bandE * 2.6 + mids * 0.8);
    let expo = -2.0 * ((hx * hx) / (alphaX * alphaX) + (hy * hy) / (alphaY * alphaY))
               / (1.0 + hDotN);
    let spec = exp(expo) / (4.0 * 3.14159265 * alphaX * alphaY);

    // Blend refracted image with metallic reflection via Fresnel
    var finalRGB = mix(refractedColor, metalColor, F);
    finalRGB += vec3<f32>(spec * reflectivity * (0.8 + bass * 0.4));

    finalRGB = acesFilm(finalRGB);

    // Semantic alpha: wetness / reflectivity drives opacity
    let alpha = clamp(F * (0.6 + newH * 0.4), 0.0, 1.0);

    textureStore(writeTexture, coordI, vec4<f32>(finalRGB, alpha));
    // A carries the HEIGHT FIELD, not display colour — the fluid reads it back
    // as dataTextureC next frame.
    textureStore(dataTextureA, coordI, vec4<f32>(newH, supercritical, F, alpha));
    textureStore(dataTextureB, coordI, vec4<f32>(finalRGB, spec));
    textureStore(writeDepthTexture, coordI,
                 vec4<f32>(clamp(depth * 0.7 + newH * 0.3, 0.0, 1.0), 0.0, 0.0, 0.0));
}

fn heightBilinear(p: vec2<f32>, dims: vec2<i32>) -> f32 {
    let maxC = dims - vec2<i32>(1);
    let f = fract(p);
    let i0 = vec2<i32>(floor(p));
    let s00 = textureLoad(dataTextureC, clamp(i0,                     vec2<i32>(0), maxC), 0).r;
    let s10 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0).r;
    let s01 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0).r;
    let s11 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0).r;
    return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}
