// ═══════════════════════════════════════════════════════════════════
//  Crystal Refraction
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-04, 2026-11-09
//  Ideas: brilliant-cut flat table window inside the facet ring; per-facet spectral fire flashes (bass sparkle); energy-conserving fire with facet spill (§12.2F energy-conserving bloom: a flashing facet gives up its transmitted light and its glow bleeds into the neighbouring wedges); frosted girdle (granular rim band that outlines the stone, treble sparkle); click strike ignites facets in sequence (replaces the screen-wide rainbow rings). Rescued: full-screen clock-ring overlay cut; stone is round on wide frames (aspect-corrected); facet seed no longer jumps across the atan2 seam.
//  A packing: ACES display RGBA (HEAD never wrote A)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"


const IOR_QUARTZ: f32 = 1.54;
const IOR_DIAMOND: f32 = 2.42;

// Fresnel-Schlick
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Fully saturated spectral colour for a hue in [0, 1).
fn spectralHue(h: f32) -> vec3<f32> {
    return clamp(abs(fract(vec3<f32>(h) + vec3<f32>(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
// Smooth value noise in [0, 1] (no per-block mosaic at high resolution).
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}
// Per-facet random seed (facet index wrapped so the wedge across the atan2 seam keeps one seed).
fn facetSeedOf(idx: f32, n: f32) -> f32 {
    let w = idx - n * floor(idx / n);
    return fract(sin(w * 91.7 + 3.1) * 43758.5453);
}
// One facet's fire flash at its own phase (HEAD's sweep, factored so neighbours can spill).
fn fireFlash(stepped: f32, seed: f32, time: f32) -> f32 {
    let c = max(cos(stepped * 2.0 - time * 0.9 + seed * 6.28318), 0.0);
    let c2 = c * c;
    let c4 = c2 * c2;
    let c8 = c4 * c4;
    return c8 * c8 * c8;   // c^24 by squaring (no exp/log)
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;

    // ═══════════════════════════════════════════════════════════════
    // Parameters:
    // x: facetScale (number of facets)
    // y: dispersion (IOR-based chromatic aberration)
    // z: strength (refraction strength)
    // w: crystalThickness (affects transmission)
    // ═══════════════════════════════════════════════════════════════
    
    let facetScale = u.zoom_params.x;
    let dispersion = u.zoom_params.y;
    let strength = u.zoom_params.z;
    let crystalThickness = mix(0.1, 1.5, u.zoom_params.w);
    let ior = mix(IOR_QUARTZ, IOR_DIAMOND, u.zoom_params.y);
    
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

    // Mouse Interaction
    var mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Distance / angle to the cursor in ISOTROPIC space (HEAD used raw uv: on wide frames the stone
    // was a stretched ellipse with squashed wedges).
    let aspect = resolution.x / max(resolution.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);
    let toCenter = (uv - mousePos) * aspectVec;
    let dist = length(toCenter);

    // Lens Radius
    let lensRadius = 0.4;
    let falloff = smoothstep(lensRadius, 0.0, dist);

    // Facet Logic - Create angular stepping for facets
    let angle = atan2(toCenter.y, toCenter.x);
    let numFacets = floor(10.0 * facetScale + 3.0);
    let sector = 6.28318 / numFacets;
    let facetIdx = floor(angle / sector + 0.5);
    let steppedAngle = facetIdx * sector;

    // Calculate displacement vector
    let displacementDir = vec2<f32>(cos(steppedAngle), sin(steppedAngle));

    // ── Idea 1: brilliant-cut table. The centre of a cut stone is a flat octagonal
    // window: it shows the scene almost undistorted (slightly magnified),
    // ringed by the angled facets.
    let tableR = lensRadius * 0.22;
    let oct = max(max(abs(toCenter.x), abs(toCenter.y)), (abs(toCenter.x) + abs(toCenter.y)) * 0.70710678);
    let inTable = 1.0 - smoothstep(tableR, tableR + 0.004, oct);
    let tableEdge = (1.0 - smoothstep(0.0, 0.003, abs(oct - tableR))) * falloff;

    // Refraction strength falls off with distance from center (isotropic units -> uv)
    let displaceAmount = mix(displacementDir * dist * strength * falloff, toCenter * 0.08 * strength, inTable) / aspectVec;

    // Chromatic Aberration (Dispersion) based on IOR
    // Higher IOR = more dispersion
    let dispersionAmt = (ior - 1.0) * dispersion * 2.0;
    let rOffset = displaceAmount * (1.0 + dispersionAmt);
    let gOffset = displaceAmount;
    let bOffset = displaceAmount * (1.0 - dispersionAmt);

    let r = textureSampleLevel(readTexture, u_sampler, uv - rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv - gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - bOffset, 0.0).b;

    // ═══════════════════════════════════════════════════════════════
    // Physical Transmission & Alpha
    // ═══════════════════════════════════════════════════════════════
    
    // Angle from lens center affects Fresnel
    let cosTheta = 1.0 - dist / lensRadius; // 1 at center, 0 at edge
    let fresnel = fresnelSchlick(max(cosTheta, 0.0), F0);
    
    // Path length through crystal (longer at edges)
    let pathLength = crystalThickness * (1.0 + dist / lensRadius);
    
    // Absorption (minimal for clear crystal)
    let absorption = exp(-0.2 * pathLength);
    
    // Transmission coefficient
    let transmission = absorption * (1.0 - fresnel) * falloff;
    
    // Add specular highlight on facet edges
    let angleDiff = abs(angle - steppedAngle);
    let edgeHighlight = (1.0 - smoothstep(0.0, 0.1, angleDiff)) * falloff * fresnel * 0.5;

    var color = vec3<f32>(r, g, b);
    color += vec3<f32>(edgeHighlight) * (1.0 - inTable) + vec3<f32>(tableEdge * fresnel * 0.6 + tableEdge * 0.15);

    // ── Idea 2: fire. Each facet is a tiny prism that throws one spectral colour
    // when its normal sweeps past the light; facets flash at their own phase,
    // and bass makes the stone sparkle harder.
    // ── Idea 3: energy-conserving fire with facet spill (§12.2F energy-conserving bloom): a flashing facet is MIRRORING light it is not
    // transmitting, so the flash is taken out of the facet's own image, and its glow spills into the
    // two neighbouring wedges near their shared edge (scintillation bloom) instead of an additive wedge.
    let outsideTable = (1.0 - inTable) * falloff;
    if (outsideTable > 0.0) {
        let facetSeed = facetSeedOf(facetIdx, numFacets);
        let flash = fireFlash(steppedAngle, facetSeed, time) * outsideTable;
        let across = clamp((angle - steppedAngle) / (0.5 * sector), -1.0, 1.0);   // -1 left edge .. +1 right edge
        let hueShift = time * 0.05 + mids * 0.12 + dispersion * 0.3;
        let fireColor = spectralHue(fract(facetSeed + hueShift));
        let fireGain = (0.25 + dispersion * 0.9) * (1.0 + bass * 1.5);
        // Only the neighbour on the side this pixel is near can spill into it.
        var spill = 0.0;
        var spillCol = vec3<f32>(0.0);
        if (abs(across) > 0.3) {
            let side = select(-1.0, 1.0, across > 0.0);
            let seedN = facetSeedOf(facetIdx + side, numFacets);
            spill = 0.30 * fireFlash(steppedAngle + side * sector, seedN, time) * outsideTable * smoothstep(0.3, 1.0, abs(across));
            spillCol = spectralHue(fract(seedN + hueShift));
        }
        color = color * (1.0 - 0.55 * min(flash + spill, 1.0));
        color += (fireColor * flash + spillCol * spill) * fireGain;

        // ── Idea 5: click strike. A click is a light strike on the stone: every facet ignites after its own
        // random delay and burns down in its own fire colour (the stone scintillates in sequence).
        // Replaces HEAD's screen-wide rainbow rings. Strike weight falls with the click's distance to the stone.
        var strike = 0.0;
        let rippleCount = min(u32(u.config.y), 50u);
        for (var i = 0u; i < rippleCount; i = i + 1u) {
            let event = u.ripples[i];
            let age = time - event.z;
            let tt = age - facetSeed * 0.45;
            let near = smoothstep(lensRadius * 1.5, 0.0, length((event.xy - mousePos) * aspectVec));
            strike += select(0.0, exp(-tt * 4.0) * exp(-age * 0.6) * near, age > 0.0 && age < 2.5 && tt >= 0.0);
        }
        let strikeAmt = min(strike, 1.5) * outsideTable;
        color = color * (1.0 - 0.5 * min(strikeAmt, 1.0));
        color += mix(fireColor, vec3<f32>(1.0), 0.45) * strikeAmt * (0.9 + dispersion * 0.8);
    }

    // ── Idea 4: frosted girdle. A cut stone is outlined by its girdle: a thin rough band where the
    // crown meets the pavilion, grainy rather than faceted. Where HEAD's refraction simply faded to
    // nothing at the stone edge this band frosts the image (lifted, desaturated veil) and sparkles.
    let gr = dist / lensRadius;
    let girdle = smoothstep(0.86, 0.93, gr) * (1.0 - smoothstep(0.985, 1.0, gr));
    if (girdle > 0.0) {
        let grain = vnoise(toCenter * 140.0 + vec2<f32>(7.3, 2.9));
        let veil = girdle * (0.55 + 0.45 * grain);
        let g2 = grain * grain;
        color = mix(color, color * 0.65 + vec3<f32>(0.30, 0.32, 0.35) * (0.6 + 0.4 * grain), veil * 0.8);
        color += vec3<f32>(0.9, 0.95, 1.0) * (g2 * g2 * grain) * girdle * (0.25 + treble * 1.2);
    }

    // Advanced Alpha: Physical Transmittance (the frosted girdle is semi-opaque)
    let alpha = max(calculateAdvancedAlpha(color, transmission, falloff, pathLength, fresnel), girdle * 0.6);

    let finalRGB = aces(max(color, vec3<f32>(0.0)) * 0.8);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));

    // Update Depth (Pass-through)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

// ═══ ADVANCED ALPHA FUNCTION ═══
fn calculateAdvancedAlpha(color: vec3<f32>, transmission: f32, falloff: f32, pathLength: f32, fresnel: f32) -> f32 {
    // Tunable parameters from zoom_params
    let thickness = mix(0.1, 1.5, u.zoom_params.w); // Crystal Thickness
    let dispersion = u.zoom_params.y;                // IOR / Dispersion
    let strength = u.zoom_params.z;                  // Refraction Strength
    
    // Beer's Law absorption
    let absorptionCoeff = vec3<f32>(0.15, 0.08, 0.22) * (1.0 + dispersion);
    let absorption = exp(-absorptionCoeff * pathLength * thickness);
    
    // Volumetric alpha from optical thickness
    let density = falloff * (1.0 + strength);
    let opticalDepth = density * pathLength * thickness;
    let volumetricAlpha = 1.0 - exp(-opticalDepth * 2.0);
    
    // Combine Fresnel reflection with transmittance
    let transmittanceAlpha = transmission * (1.0 - fresnel) * dot(absorption, vec3<f32>(0.333));
    
    // Final alpha blends physical transmittance with volumetric density
    let alpha = mix(transmittanceAlpha, volumetricAlpha, 0.4);
    
    return clamp(alpha, 0.0, 1.0);
}
