// ═══════════════════════════════════════════════════════════════════
//  Crystal Facets
//  Category: distortion
//  Features: mouse-driven, refraction, fresnel, dispersion, internal-reflection, audio-caustics, depth-prisms, volumetric-gems
//  Complexity: Medium
//  Updated: 2026-05-31
//  By: Grok (visual flourish — richer internal light, caustics, and prismatic depth)
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 64)
//
//  Brought up to the pool standard: `dataTextureA` was never written and
//  `dataTextureC` never read (both bound but dead), there was no click
//  response, and the output was written untone-mapped.
//
//  TWO NEW STRUCTURES
//
//    1. Facet-normal Fresnel with total internal reflection — the crystal used
//       a single scalar `fresnel` term against a fixed view. Each facet now
//       carries its own normal, the incidence angle is measured against THAT
//       normal, and rays past the critical angle (asin(1/n) for the current
//       IOR) are totally internally reflected instead of transmitted. TIR is
//       what gives real gemstones their bright flashing facets; a plain Fresnel
//       ramp can only darken toward the edges.
//
//    2. Crystal-axis birefringence — a uniaxial crystal splits light into
//       ordinary and extraordinary rays whose indices differ by the
//       birefringence. The two rays are sampled separately along a per-facet
//       optic axis and recombined, producing the characteristic doubled edges,
//       with the retardation banded across the eight FFT bins.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Refractive indices for different crystal types
const IOR_QUARTZ: f32 = 1.54;
const IOR_DIAMOND: f32 = 2.42;
const IOR_GLASS: f32 = 1.5;
const IOR_ICE: f32 = 1.31;

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

// Fresnel reflectance for unpolarized light
fn fresnelReflectance(cosTheta: f32, ior: f32) -> f32 {
    let g = sqrt(ior * ior - 1.0 + cosTheta * cosTheta);
    let gmc = g - cosTheta;
    let gpc = g + cosTheta;
    let a = (gmc * gpc) / ((gpc) * (gpc));
    let b = (cosTheta * gpc - 1.0) / (cosTheta * gmc + 1.0);
    return 0.5 * a * (1.0 + b * b);
}

// Fresnel-Schlick approximation (cheaper)
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate path length through crystal based on angle and thickness
fn pathLengthThroughCrystal(cosTheta: f32, thickness: f32) -> f32 {
    // Path length increases as viewing angle becomes more grazing
    return thickness / max(abs(cosTheta), 0.01);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    // ═══════════════════════════════════════════════════════════════
    // Parameters via zoom_params:
    // x: Facet Count (3 to 16)
    // y: Refraction Strength + IOR mix
    // z: Rotation Speed / Fracture density
    // w: Crystal Thickness / Transmission
    // ═══════════════════════════════════════════════════════════════
    
    let facetCount = floor(mix(3.0, 16.0, u.zoom_params.x));
    let iorMix = u.zoom_params.y; // 0 = glass, 1 = diamond
    let fractureDensity = u.zoom_params.z; // 0 = pure crystal, 1 = heavily fractured
    let crystalThickness = mix(0.1, 2.0, u.zoom_params.w);
    
    // Calculate IOR based on mix parameter
    let ior = mix(IOR_GLASS, IOR_DIAMOND, iorMix);
    let refraction = mix(0.02, 0.15, iorMix);
    let rotation = u.config.x * 0.1;
    let zoom = 1.0;

    // Coordinate relative to mouse/center
    var center = mouse;
    var dir = (uv - center);
    dir.x *= aspect;

    let dist = length(dir);
    var angle = atan2(dir.y, dir.x);
    angle += rotation;

    // Quantize angle to create facets
    let sector = floor(angle / (6.28318 / facetCount));
    let sectorAngle = sector * (6.28318 / facetCount);

    // Each facet has a random tilt/offset
    let facetID = sector;
    let randomTilt = (hash11(facetID) - 0.5) * 2.0;
    let facetFracture = hash11(facetID + 100.0); // Per-facet fracture amount

    // Offset vector for this facet
    let offsetDir = vec2<f32>(cos(sectorAngle), sin(sectorAngle));

    // Chromatic aberration with dispersion based on IOR
    let dispersion = (ior - 1.0) * 0.1; // Higher IOR = more dispersion
    let rOffset = offsetDir * refraction * (1.0 + randomTilt * 0.5);
    let gOffset = offsetDir * refraction * 0.5;
    let bOffset = offsetDir * refraction * (0.0 - randomTilt * 0.5);

    // Zoom effect per facet
    let distDistorted = pow(dist, zoom);

    // Reconstruct coordinate
    let baseUV = center + vec2<f32>(cos(angle - rotation), sin(angle - rotation)) * distDistorted / vec2<f32>(aspect, 1.0);

    // Sample background
    let r = textureSampleLevel(readTexture, u_sampler, baseUV - rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, baseUV - gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, baseUV - bOffset, 0.0).b;
    var color = vec3<f32>(r, g, b);

    // ═══════════════════════════════════════════════════════════════
    // Physical Light Transmission & Alpha Calculation
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate angle to facet normal (simplified as angle from facet center)
    let angleToNormal = abs(fract(angle / (6.28318 / facetCount)) - 0.5) * 2.0; // 0 = center, 1 = edge
    let cosTheta = cos(angleToNormal * 1.57); // Approximate angle
    
    // Fresnel at surface
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
    let fresnel = fresnelSchlick(cosTheta, F0);
    
    // Path length through crystal (varies by viewing angle)
    let pathLength = pathLengthThroughCrystal(cosTheta, crystalThickness);
    
    // Purity factor (inverse of fracture density)
    let purity = 1.0 - (fractureDensity * facetFracture);
    
    // Absorption coefficient based on purity
    let absorptionCoeff = mix(0.5, 5.0, fractureDensity);
    let absorption = exp(-absorptionCoeff * pathLength / max(purity, 0.1));
    
    // Distance to facet edge for edge effects
    let angleLocal = fract(angle / (6.28318 / facetCount));
    let edgeDist = min(angleLocal, 1.0 - angleLocal);
    let edgeFactor = smoothstep(0.02, 0.0, edgeDist);
    
    // Transmission coefficient (alpha)
    // Face-on: mostly transmitted (high alpha)
    // Edge-on: mostly reflected (low alpha)
    // More fractures = more scattering = lower alpha
    let transmission = absorption * (1.0 - fresnel) * purity;
    
    // Add specular highlight on edges
    let specular = edgeFactor * fresnel * 0.8;
    color += vec3<f32>(specular);
    
    // Internal reflections and scattering tint
    let internalScatter = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.95, 1.0), fractureDensity);
    color = color * internalScatter;

    // === Visual Flourish: Audio-reactive caustics and facet sparkle ===
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Bass pulses internal light transport (like light moving through the crystal)
    let time = u.config.x;
    let causticPulse = 1.0 + bass * 0.6 + sin(time * 6.0 + facetID) * treble * 0.3;
    
    // Mids add subtle color temperature shift inside the facets
    let internalTint = vec3<f32>(1.0 + mids * 0.15, 1.0 - mids * 0.08, 1.0 - mids * 0.12);
    
    // Treble adds high-frequency facet sparkle / micro-reflections
    let sparkle = pow(hash11(facetID + time * 12.0), 8.0) * treble * 0.8;
    
    color = color * internalTint * causticPulse;
    color += vec3<f32>(0.8, 0.9, 1.0) * sparkle * edgeFactor;

    let coord = vec2<i32>(global_id.xy);

    // ── Structure 1: facet-normal Fresnel with total internal reflection ────
    // Each facet gets its own normal; rays past the critical angle reflect
    // internally instead of transmitting, which is what makes real gem facets
    // flash rather than merely darken toward their edges.
    let facetNormal = normalize(vec3<f32>(
        cos(facetID * 2.399) * 0.55,
        sin(facetID * 1.732) * 0.55,
        1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cosI = clamp(dot(viewDir, facetNormal), 0.02, 1.0);
    let sinI = sqrt(max(0.0, 1.0 - cosI * cosI));
    let iorNow = mix(1.33, 2.42, clamp(u.zoom_params.y, 0.0, 1.0));
    let criticalSin = 1.0 / iorNow;
    // Past the critical angle the facet is a mirror.
    let tir = smoothstep(criticalSin * 0.92, criticalSin, sinI);
    color = mix(color, color * vec3<f32>(1.25, 1.28, 1.35) + vec3<f32>(0.10, 0.12, 0.16),
                tir * (0.5 + edgeFactor * 0.5));

    // ── Structure 2: crystal-axis birefringence ────────────────────────────
    // Uniaxial split into ordinary and extraordinary rays along a per-facet
    // optic axis; retardation is banded across the spectrum.
    let bandIdx = u32(clamp(fract(facetID * 0.1379) * 8.0, 0.0, 7.999));
    let band = plasmaBuffer[bandIdx + 1u].x;
    let deltaN = 0.008 + fractureDensity * 0.02 + band * 0.02;
    let axisAngle = facetID * 1.107 + time * 0.05;
    let optAxis = vec2<f32>(cos(axisAngle), sin(axisAngle)) / vec2<f32>(aspect, 1.0);
    let split = optAxis * deltaN * (0.6 + pathLength * 1.4);
    let ordinary = textureSampleLevel(readTexture, u_sampler,
                                      clamp(uv + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let extraordinary = textureSampleLevel(readTexture, u_sampler,
                                      clamp(uv - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    // Retardation between the two rays gives the interference tint.
    let retardation = deltaN * pathLength * 260.0;
    let biTint = 0.5 + 0.5 * cos(vec3<f32>(retardation, retardation * 1.18, retardation * 1.37));
    color = mix(color, (ordinary + extraordinary) * 0.5 * biTint, clamp(deltaN * 22.0, 0.0, 0.6));

    // ── Bounded click fracture fronts ──────────────────────────────────────
    var fractureFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.3) {
            let r = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            let front = r - age * 0.5;
            fractureFront += exp(-front * front * 180.0) * exp(-age * 1.5);
        }
    }
    fractureFront = min(fractureFront, 1.5);
    color += vec3<f32>(0.85, 0.93, 1.0) * fractureFront * (0.4 + bass * 0.7);

    // Temporal glint memory (exact load — dataTextureC is rgba32float).
    let prev = textureLoad(dataTextureC, coord, 0);
    color = max(color, prev.rgb * (0.74 + purity * 0.12));

    color = acesFilm(color);

    // Advanced Alpha: Physical Transmittance
    let alpha = clamp(
        calculateAdvancedAlpha(color, transmission, pathLength, fresnel, purity, edgeFactor)
        + tir * 0.12 + fractureFront * 0.18,
        0.0, 1.0);
    let outColor = vec4<f32>(color, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(facetNormal * 0.5 + 0.5, tir));

    // Depth: facets sit proud of the plate where the crystal is thickest.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(clamp(depth - pathLength * 0.04, 0.0, 1.0), 0.0, 0.0, 0.0));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// ═══ ADVANCED ALPHA FUNCTION ═══
fn calculateAdvancedAlpha(color: vec3<f32>, transmission: f32, pathLength: f32, fresnel: f32, purity: f32, falloff: f32) -> f32 {
    // Tunable parameters from zoom_params
    let facetCount = u.zoom_params.x;       // Facet Count
    let iorMix = u.zoom_params.y;           // Refractive Index
    let fractureDensity = u.zoom_params.z;  // Fracture Density
    let crystalThickness = mix(0.1, 2.0, u.zoom_params.w); // Crystal Thickness
    
    // Beer's Law absorption
    let absorptionCoeff = vec3<f32>(0.18, 0.12, 0.25) * (1.0 + fractureDensity * 3.0);
    let opticalDepth = pathLength * crystalThickness;
    let absorption = exp(-absorptionCoeff * opticalDepth);
    
    // Volumetric alpha from optical thickness
    let density = falloff * (1.0 + iorMix) * (1.0 + fractureDensity);
    let volumetricAlpha = 1.0 - exp(-density * opticalDepth * 1.5);
    
    // Transmittance alpha: path-through crystal
    let transmittanceAlpha = transmission * dot(absorption, vec3<f32>(0.333)) * purity;
    
    // Fresnel edge boost
    let fresnelBoost = fresnel * falloff * 0.4;
    
    // Combine physical transmittance with volumetric density
    let alpha = mix(transmittanceAlpha, volumetricAlpha, 0.45) + fresnelBoost;
    
    return clamp(alpha, 0.0, 1.0);
}
