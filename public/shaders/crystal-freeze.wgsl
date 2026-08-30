// ═══════════════════════════════════════════════════════════════
//  Crystal Freeze - Physical Light Transmission with Alpha
//  Category: interactive-mouse
//  Features: mouse-driven, persistence, voronoi crystals
//  Simulates ice crystal formation with light transmission
// ═══════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 67 — fast motion / psychedelic / high energy)
//
//  Contract: canonical `@workgroup_size(16, 16, 1)` (house convention); the
//  freeze state is now read with exact `textureLoad` rather than through a
//  sampler; bounded click response and ACES added.
//
//  A carries the FREEZE STATE (r = freeze, g = growth front), read back as
//  dataTextureC; display goes to `writeTexture`.
//
//  FAST MOTION (two analytic techniques)
//
//    1. Dendrite growth fronts — freezing propagates as advancing fronts rather
//       than a uniform decay-toward-brush. Each front expands from its
//       nucleation site at a clamped analytic rate with a branching angular
//       modulation, so ice visibly races across the frame the way dendritic
//       crystallisation does.
//
//    2. Facet light-burst whip — crystal facets catch a specular sweep that
//       rotates continuously, and the refraction offset is stretched along that
//       sweep direction, so the gem flashes travel across the facets instead of
//       sitting static.
//
//  PSYCHEDELIC COLOUR — the flat blue-white ice tint is replaced by a per-cell
//  IQ cosine spectrum keyed to crystal thickness, cell identity and per-band FFT
//  energy, with the dispersion split fanned along the facet normal.
//
//  HIGH ENERGY — clicks detonate flash-freeze bursts that nucleate a new front
//  and blow a full-spectrum light burst through the facets.
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

// Ice IOR
const IOR_ICE: f32 = 1.31;
const IOR_GLASS: f32 = 1.5;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Fresnel-Schlick approximation
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn spectrum(tt: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(6.2831853 * (tt + vec3<f32>(0.0, 0.33, 0.67)));
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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // Audio: bass thickens freeze persistence, mids densifies crystals, treble cools the tint
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ═══════════════════════════════════════════════════════════════
    // Parameters:
    // x: decay / Freeze persistence
    // y: crystalScale (affects cell density)
    // z: refraction (IOR mix)
    // w: ice purity (affects transmission)
    // ═══════════════════════════════════════════════════════════════
    
    let decay = clamp(u.zoom_params.x + bass * 0.1, 0.0, 1.0);
    let crystalScale = (10.0 + u.zoom_params.y * 40.0) * (1.0 + mids * 0.4);
    let iorMix = u.zoom_params.z; // 0 = ice, 1 = glass
    let icePurity = (1.0 - u.zoom_params.w * 0.5) * (1.0 - treble * 0.2); // Purity decreases with param
    
    // Fixed brush radius
    let brushRadius = 0.08;

    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    let coord = vec2<i32>(global_id.xy);

    // Update Freeze State — exact load (dataTextureC is rgba32float).
    let oldState = textureLoad(dataTextureC, coord, 0);
    let oldFreeze = oldState.r;

    // Mouse interaction
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    var dist = length(distVec);
    let brush = smoothstep(brushRadius, brushRadius * 0.5, dist);

    // ── FAST MOTION 1: dendrite growth fronts ────────────────────────────────
    // Fronts advance from the pointer and from each click at a clamped analytic
    // rate, with a branching angular modulation — ice races rather than fading
    // uniformly toward the brush.
    let frontRate = clamp(0.18 + u.zoom_params.y * 0.35 + mids * 0.25, 0.0, 0.65);
    let branchAngle = atan2(distVec.y, distVec.x);
    let branching = 0.72 + 0.28 * cos(branchAngle * 6.0 + time * 1.4);
    let pointerFront = smoothstep(fract(time * frontRate) * branching + 0.06,
                                  fract(time * frontRate) * branching - 0.06,
                                  dist);

    // ── HIGH ENERGY: bounded click flash-freeze bursts ───────────────────────
    var clickFreeze = 0.0;
    var burstFlash = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age >= 2.4) { continue; }
        let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
        let branch = 0.72 + 0.28 * cos(atan2(uv.y - rp.y, uv.x - rp.x) * 7.0 + age * 4.0);
        // Nucleation front expands then holds.
        clickFreeze = max(clickFreeze, smoothstep(age * 0.5 * branch, age * 0.5 * branch - 0.08, rd));
        let rim = rd - age * 0.5;
        burstFlash += exp(-rim * rim * 200.0) * exp(-age * 1.4);
    }
    burstFlash = min(burstFlash, 1.5);

    // New freeze value: decayed history, pointer brush, growth front, clicks.
    let newFreeze = clamp(max(max(oldFreeze * decay, brush),
                              max(pointerFront * brush * 1.2, clickFreeze)), 0.0, 1.0);
    let growthVel = clamp(abs(newFreeze - oldFreeze) * 30.0, 0.0, 1.0);

    // A carries the FREEZE STATE, not display colour.
    textureStore(dataTextureA, coord, vec4<f32>(newFreeze, growthVel, burstFlash, 1.0));

    // Calculate IOR based on freeze state (frozen areas have higher IOR)
    let baseIOR = mix(IOR_ICE, IOR_GLASS, iorMix);
    let frozenIOR = mix(1.0, baseIOR, newFreeze); // Unfrozen = air (IOR 1.0)
    let F0 = pow((frozenIOR - 1.0) / (frozenIOR + 1.0), 2.0);

    // Crystal Effect Logic (Voronoi)
    var finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var transmissionAlpha = 1.0; // Full transmission where no crystal

    if (newFreeze > 0.01) {
        // Simple Voronoi
        let g = floor(uv * crystalScale);
        let f = fract(uv * crystalScale);

        var minLoading = 1.0;
        var center = vec2<f32>(0.0);
        var cellId = vec2<f32>(0.0);

        // 3x3 search
        for (var y: i32 = -1; y <= 1; y++) {
            for (var x: i32 = -1; x <= 1; x++) {
                let lattice = vec2<f32>(f32(x), f32(y));
                let offset = hash22(g + lattice);
                var dist = distance(lattice + offset, f);

                if (dist < minLoading) {
                    minLoading = dist;
                    center = lattice + offset;
                    cellId = g + lattice;
                }
            }
        }

        // Calculate vector from pixel to cell center
        let toCenter = (center - f) / crystalScale;

        // Per-cell purity variation
        let cellPurity = icePurity * (0.5 + 0.5 * hash21(cellId));
        
        // Refraction strength varies by frozen amount and purity
        let refraction = 0.1 * newFreeze * (0.5 + 0.5 / max(cellPurity, 0.1));
        let refractUV = uv + toCenter * refraction;

        // ── FAST MOTION 2: facet light-burst whip ────────────────────────────
        // A specular sweep rotates continuously; the dispersion split is
        // stretched ALONG that sweep, so flashes travel across the facets.
        let whipAngle = time * (1.6 + treble * 2.4) + hash21(cellId) * 6.2831853;
        let whipDir = vec2<f32>(cos(whipAngle), sin(whipAngle));
        let facetNormal = normalize(toCenter + vec2<f32>(1e-5));
        let whipAlign = pow(max(dot(facetNormal, whipDir), 0.0), 8.0);

        // Chromatic aberration fanned along the facet normal, widened by the whip.
        let dispersion = (frozenIOR - 1.0) * 0.02 * newFreeze;
        let split = facetNormal * (0.002 + dispersion * 0.9 + growthVel * 0.004)
                  * newFreeze * (1.0 + whipAlign);
        let r = textureSampleLevel(readTexture, u_sampler, refractUV + split, 0.0).r;
        let g_val = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, refractUV - split, 0.0).b;

        var crystalColor = vec3<f32>(r, g_val, b);

        // ── PSYCHEDELIC: per-cell dispersive ice spectrum ────────────────────
        let bandIdx = u32(clamp(fract(hash21(cellId) * 3.17) * 8.0, 0.0, 7.999));
        let band = plasmaBuffer[bandIdx + 1u].x;
        let iceHue = fract(newFreeze * 0.7 + hash21(cellId) * 0.55 + band * 0.6
                           + time * 0.05 + minLoading * 0.4);
        let iceTint = mix(vec3<f32>(1.0), pow(spectrum(iceHue), vec3<f32>(0.7)) * 1.6,
                          newFreeze * 0.85);
        crystalColor = crystalColor * iceTint;
        // Whip flash rides the facets full-spectrum.
        crystalColor += spectrum(fract(iceHue + 0.35)) * whipAlign * newFreeze
                      * (0.35 + treble * 1.1);

        // ═══════════════════════════════════════════════════════════════
        // Physical Transmission Calculation
        // ═══════════════════════════════════════════════════════════════
        
        // Angle to crystal surface (approximate from distance to center)
        let distToCenter = minLoading; // 0 at center, ~0.5 at edge
        let cosTheta = 1.0 - distToCenter; // Approximate: 1 = face-on, 0 = edge
        
        // Fresnel reflection at ice surface
        let fresnel = fresnelSchlick(cosTheta, F0);
        
        // Path length through crystal cell (longer at edges)
        let pathLength = mix(0.1, 0.5, distToCenter) * newFreeze;
        
        // Absorption based on path length and purity
        let absorptionCoeff = mix(0.5, 3.0, 1.0 - cellPurity);
        let absorption = exp(-absorptionCoeff * pathLength);
        
        // Transmission coefficient
        let transmission = absorption * (1.0 - fresnel) * cellPurity;
        
        // Facet brightness for gem look
        let facet = smoothstep(0.0, 1.0, 1.0 - minLoading);
        
        // Blend between original and crystal based on freeze
        // Alpha represents how much light passes through (transmission)
        let crystalAlpha = mix(1.0, transmission, newFreeze);
        
        // Add specular highlights on crystal surfaces
        let specular = fresnel * newFreeze * 0.3;
        crystalColor += vec3<f32>(specular);
        
        finalColor = mix(finalColor, vec4<f32>(crystalColor * (0.8 + facet * 0.4), 1.0), newFreeze);
        transmissionAlpha = crystalAlpha;
    }

    // Click bursts flash through the whole facet field.
    var outRGB = finalColor.rgb
               + spectrum(fract(newFreeze * 0.8 + time * 0.07)) * burstFlash
                 * (0.9 + bass * 1.0);
    outRGB = acesFilm(outRGB);

    let alpha = clamp(transmissionAlpha * 0.9 + newFreeze * 0.1 + burstFlash * 0.2, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(outRGB, alpha));

    // Depth: ice sits proud of the plate where it is thickest.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(clamp(depth - newFreeze * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
