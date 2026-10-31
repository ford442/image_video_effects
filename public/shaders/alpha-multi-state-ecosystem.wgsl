// ═══════════════════════════════════════════════════════════════════
//  Alpha Multi-State Ecosystem
//  Category: simulation
//  Features: multi-species-ecosystem, seasonal-cycles, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12, 2026-10-31
//  Ideas: ecotone ridge where s1≈s2; toxin stain from stored A; isotropic 9-point Laplacian diffusion; nutrient recycling from the dead
//  A packing: raw (s1, s2, resource, toxin); A(0,0).r = sentinel -0.6875
// ═══════════════════════════════════════════════════════════════════
//  RGBA Channels:
//    R = Species 1 density (prey-like)
//    G = Species 2 density (competitor)
//    B = Resource level (shared nutrients)
//    A = Toxin concentration
//  Why f32: Continuous densities require sub-1% precision for stable
//  competitive dynamics, birth thresholds, and extinction cascades.
//  Updated: 2026-05-31 — Grok (real ecosystem with audio seasons + keystone dynamics)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

// A.r of the corner texel: marks C as this shader's own state (f16-exact, never a density).
const STATE_SENTINEL: f32 = -0.6875;
var<private> stateOwned: bool = false;

// Exact history load. Foreign history (previous shader's A) reads as an empty field.
fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    if (!stateOwned) { return vec4<f32>(0.0, 0.0, 0.5, 0.0); }
    let q = clamp(p, vec2<i32>(0), dims - vec2<i32>(1));
    var v = textureLoad(dataTextureC, q, 0);
    if (q.x == 0 && q.y == 0) { v.r = 0.0; }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dims = vec2<i32>(res);
    let time = u.config.x;

    stateOwned = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).r == STATE_SENTINEL;

    // === AUDIO SEASONS (plasmaBuffer as climate) ===
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Bass = harsh/dry season: higher death, slower growth, toxin lingers
    // Mids = bloom/abundant season: strong resource regen, lower competition
    // Treble = volatile/spore season: erratic diffusion + random birth pulses
    let seasonHarsh = bass * 0.7;
    let seasonBloom = mids * 0.6;
    let seasonVolatile = treble * 0.8;

    // Read previous state
    let prevState = stateAt(coord, dims);
    var s1 = prevState.r;
    var s2 = prevState.g;
    var resourceVal = prevState.b;
    var toxin = prevState.a;

    // Seed on first frame, or whenever history is not ours (shader switched in later)
    if (time < 0.1 || !stateOwned) {
        s1 = 0.0;
        s2 = 0.0;
        resourceVal = 0.5;
        toxin = 0.0;
        // Seed species 1 clusters
        let n1 = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        if (n1 > 0.92) { s1 = 0.8; }
        // Seed species 2 clusters
        let n2 = fract(sin(dot(uv + vec2<f32>(5.0), vec2<f32>(93.0, 17.0))) * 271.0);
        if (n2 > 0.95) { s2 = 0.7; }
    }

    // Clamp
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resourceVal = clamp(resourceVal, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // === DIFFUSION ===
    let left = stateAt(coord + vec2<i32>(-1, 0), dims);
    let right = stateAt(coord + vec2<i32>(1, 0), dims);
    let down = stateAt(coord + vec2<i32>(0, -1), dims);
    let up = stateAt(coord + vec2<i32>(0, 1), dims);

    // Idea 3 — isotropic 9-point Laplacian (same scale as the 5-point stencil): round colony edges, no diamond bias
    let downLeft = stateAt(coord + vec2<i32>(-1, -1), dims);
    let downRight = stateAt(coord + vec2<i32>(1, -1), dims);
    let upLeft = stateAt(coord + vec2<i32>(-1, 1), dims);
    let upRight = stateAt(coord + vec2<i32>(1, 1), dims);
    let lap9 = (4.0 * (left + right + down + up) + (downLeft + downRight + upLeft + upRight)
        - 20.0 * vec4<f32>(s1, s2, resourceVal, toxin)) / 6.0;
    let lapS1 = lap9.x;
    let lapS2 = lap9.y;
    let lapResource = lap9.z;
    let lapToxin = lap9.w;

    // === SEASONAL ECOSYSTEM PARAMETERS ===
    let growthRate1 = mix(0.018, 0.075, u.zoom_params.x) * (1.0 + seasonBloom * 0.4);
    let growthRate2 = mix(0.014, 0.055, u.zoom_params.y) * (1.0 + seasonBloom * 0.35);

    // Harsh seasons increase death rate and toxin persistence
    let deathRate = 0.002 + seasonHarsh * 0.012;
    let toxinDecay = mix(0.96, 0.88, seasonHarsh);

    // Bloom seasons boost resource regeneration dramatically
    let resourceRegen = 0.0008 + seasonBloom * 0.0045;

    // Volatile seasons add chaotic diffusion variance
    let volatileFactor = 1.0 + seasonVolatile * 0.6;
    let dt = 0.48;

    // === EVOLVING ECOSYSTEM DYNAMICS (birth, competition, extinction) ===
    // Species consume resources to grow — but only above a small birth threshold
    let birthThreshold = 0.025;
    let food1 = select(0.0, s1 * resourceVal * growthRate1, s1 > birthThreshold);
    let food2 = select(0.0, s2 * resourceVal * growthRate2, s2 > birthThreshold);

    // Competition becomes more lethal when one species is dominant (extinction pressure)
    let dominance = abs(s1 - s2) * 0.15;
    let competition = s1 * s2 * (0.09 + dominance * 0.6);

    // Species produce toxin (more in harsh seasons)
    let toxinProduction1 = s1 * (0.004 + seasonHarsh * 0.003);
    let toxinProduction2 = s2 * (0.003 + seasonHarsh * 0.0025);

    // Toxin damage is amplified in harsh seasons
    let diffusionRate = mix(0.018, 0.12, u.zoom_params.z) * volatileFactor;
    let toxinStrength = mix(0.25, 2.0, u.zoom_params.w);
    let toxinDamage = toxin * (0.018 + seasonHarsh * 0.025) * toxinStrength;

    // Resource dynamics with seasonal bloom boost
    resourceVal += resourceRegen - food1 - food2;
    resourceVal += lapResource * diffusionRate * (0.8 + seasonBloom);

    // Species update with seasonal death pressure
    s1 += food1 - competition - toxinDamage + lapS1 * diffusionRate;
    s2 += food2 - competition - toxinDamage + lapS2 * diffusionRate * 0.86;

    // Toxin dynamics — lingers longer in harsh seasons
    toxin += (toxinProduction1 + toxinProduction2) * toxinStrength - toxin * (0.009 + seasonHarsh * 0.01);
    toxin += lapToxin * 0.07;
    toxin *= toxinDecay;

    // Idea 4 — nutrient recycling: what dies (season death + competitive kill) rots back into the resource field
    resourceVal += ((s1 + s2) * deathRate + 2.0 * competition) * 0.5;

    // Seasonal death wave (higher in harsh seasons)
    let seasonalDeath = 1.0 - deathRate;
    s1 *= seasonalDeath;
    s2 *= seasonalDeath;

    // Clamp
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resourceVal = clamp(resourceVal, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // === MOUSE AS KEYSTONE SPECIES (high-signal upgrade) ===
    // Mouse can now trigger extinction events or protective blooms depending on season
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.11, 0.0, mouseDist) * mouseDown;

    // In harsh seasons, mouse press creates localized extinction zones (dramatic recovery theater)
    // In bloom seasons, mouse creates protected fertile zones
    let keystoneExtinction = mouseInfluence * (0.6 + seasonHarsh * 1.2);
    let keystoneBloom = mouseInfluence * (0.4 + seasonBloom * 0.9);

    resourceVal += keystoneBloom * 0.7 - keystoneExtinction * 0.4;
    toxin -= mouseInfluence * (0.4 + seasonHarsh * 0.3);
    toxin = max(toxin, 0.0);

    // Harsh season + mouse = stronger extinction pressure on both species
    // Idea 4 (cont.) — the extinction zone also leaves detritus behind (only what actually existed)
    resourceVal += (min(s1, keystoneExtinction * 0.9) + min(s2, keystoneExtinction * 0.85)) * 0.5;
    s1 -= keystoneExtinction * 0.9;
    s2 -= keystoneExtinction * 0.85;

    // Bloom season + mouse = localized population surge
    s1 += keystoneBloom * 0.5;
    s2 += keystoneBloom * 0.45;

    // === SEASONAL RIPPLE SPORES ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.4) {
            let strength = exp(-abs(rDist - age * 0.14) * 52.0 - age * 1.15);
            let sign = select(1.0, 0.0, f32(i) % 2.0 < 1.0);
            // Volatile seasons make ripples much more effective at seeding new life
            let sporeBoost = 1.0 + seasonVolatile * 1.4;
            s1 += strength * sign * 0.6 * sporeBoost;
            s2 += strength * (1.0 - sign) * 0.55 * sporeBoost;
        }
    }
    s1 = clamp(s1, 0.0, 2.5);
    s2 = clamp(s2, 0.0, 2.5);

    // === STORE STATE ===
    let isCorner = gid.x == 0u && gid.y == 0u;
    textureStore(dataTextureA, coord, vec4<f32>(select(s1, STATE_SENTINEL, isCorner), s2, resourceVal, toxin));

    // === LIVING ECOSYSTEM VISUALIZATION + SEASONAL COLOR ===
    // Species 1 = teal/cyan, Species 2 = magenta, with seasonal hue shifts
    let seasonHueShift = seasonHarsh * 0.15 - seasonBloom * 0.1;
    let colorS1 = vec3<f32>(0.0, 0.75 + seasonHueShift, 0.95) * min(s1, 1.2);
    let colorS2 = vec3<f32>(0.95, 0.18 + seasonVolatile * 0.1, 0.55) * min(s2, 1.2);

    // Resources glow brighter in bloom seasons
    let resourceGlow = min(resourceVal, 1.0) * (0.25 + seasonBloom * 0.35);
    let colorResource = vec3<f32>(0.25, 0.65, 0.25) * resourceGlow;

    // Toxin looks more menacing in harsh seasons
    let toxinVis = min(toxin, 1.0) * (0.45 + seasonHarsh * 0.4);
    let colorToxin = vec3<f32>(0.35, 0.0, 0.38) * toxinVis;

    var displayColor = colorS1 + colorS2 + colorResource + colorToxin;

    // Stronger edge highlighting at species boundaries (competition fronts)
    let s1Grad = length(vec2<f32>(left.r - right.r, down.r - up.r));
    let s2Grad = length(vec2<f32>(left.g - right.g, down.g - up.g));
    let edgeHighlight = (s1Grad + s2Grad) * (2.2 + seasonVolatile * 1.5);
    displayColor += vec3<f32>(1.0, 0.92, 0.55) * edgeHighlight * 0.35;

    // Idea 1 — ecotone ridge where both species coexist (contact front, not just gradient glow)
    let overlap = min(s1, s2);
    let balance = 1.0 - abs(s1 - s2) / max(s1 + s2, 0.08);
    let ecotone = overlap * balance * smoothstep(0.08, 0.28, overlap);
    displayColor += vec3<f32>(0.95, 0.88, 0.35) * ecotone * 0.55;

    // Idea 2 — toxin stain from A (mottled contamination, not a faint purple add)
    let stainCell = fract(sin(dot(floor(uv * 48.0), vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let stain = min(toxin, 1.4) * (0.45 + stainCell * 0.55) * (0.5 + seasonHarsh * 0.5);
    displayColor = mix(displayColor, vec3<f32>(0.22, 0.02, 0.28), clamp(stain, 0.0, 0.65));

    // Depth stratification: deeper areas appear slightly cooler/darker
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthTint = mix(vec3<f32>(0.92, 0.95, 1.05), vec3<f32>(1.0), depth);
    displayColor *= depthTint;

    // Alpha = total living biomass + instability (excellent for layering)
    let totalBiomass = s1 + s2;
    let instability = abs(lapS1) + abs(lapS2) + abs(lapResource);
    displayColor += vec3<f32>(bass, mids, treble) * instability * 0.1;
    let bioAlpha = clamp(totalBiomass * 0.55 + instability * 1.8, 0.25, 1.0);
    let finalAlpha = mix(bioAlpha * 0.8, bioAlpha, depth);

    let a = clamp(finalAlpha, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(aces(displayColor), a));

    // Depth output modulated by biomass (deeper biomass = slightly different depth feel)
    let outDepth = mix(depth, depth * 0.9 + totalBiomass * 0.06, 0.4);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(outDepth, 0.0, 1.0), 0.0, 0.0, 0.0));
}
