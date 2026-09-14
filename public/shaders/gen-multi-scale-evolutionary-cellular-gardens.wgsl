// ═══════════════════════════════════════════════════════════════════
//  Multi-Scale Evolutionary Cellular Gardens
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: mycorrhizal hyphal transport (fungal species conducts substrate across the far neighbourhood); Red Queen frequency-dependent rule drift (locally dominant species' evolved thresholds shift against it)
//  A packing: ACES display RGBA in A — display is an exactly invertible
//    encoding of the sim: RGB = ACES(gain * vignette * speciesColor(s1,s2,s3,res)),
//    alpha = 1 - exp(-(0.9*pop + 0.45*res + 0.05)) (canopy+substrate optical
//    coverage). Next frame decodes (s1,s2,s3,res) from C via inverse ACES +
//    inverse pigment matrix, so no flourish that would corrupt state is drawn.
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Mutation Rate, .y = Species Competition, .z = Fertility, .w = Diversity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const ENC_GAIN: f32 = 1.1;

// ─── Hash utilities ───────────────────────────────────────────────
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    let p4 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p4.xx + p4.yz) * p4.zy);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ─── Smooth noise for organic patterns ────────────────────────────
fn smoothNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

// ─── Rule kernel: evolved growth behaviour ────────────────────────
// Returns growth impulse for a species given its neighbourhood average
// and the current "genetic" ruleset encoded in rulePhase
fn growthKernel(selfDensity: f32, neighborAvg: f32, rulePhase: f32,
                resourceLevel: f32, fertility: f32) -> f32 {
    // Evolving activation threshold (shifts with rulePhase)
    let activateThreshold = 0.15 + rulePhase * 0.3;
    let inhibitThreshold = 0.7 - rulePhase * 0.15;

    // Growth if neighbours in sweet-spot, decay if isolated or overcrowded
    let activation = smoothstep(activateThreshold - 0.05, activateThreshold + 0.05, neighborAvg);
    let inhibition = smoothstep(inhibitThreshold, inhibitThreshold + 0.15, neighborAvg);

    let growthImpulse = activation * (1.0 - inhibition) * resourceLevel * fertility;
    let decayRate = 0.02 + (1.0 - resourceLevel) * 0.03;

    return growthImpulse - selfDensity * decayRate;
}

// ─── Species coloring ─────────────────────────────────────────────
// Linear in (s1,s2,s3,res) for a fixed phase — this is what makes the
// display RGBA invertible back into sim state.
fn speciesColor(s1: f32, s2: f32, s3: f32, resourceLevel: f32,
                rulePhase: f32, t: f32) -> vec3<f32> {
    // Species 1: green-teal coral growth
    let c1 = vec3<f32>(0.1, 0.7, 0.5) * s1;
    // Species 2: magenta-violet fungal network
    let c2 = vec3<f32>(0.7, 0.2, 0.6) * s2;
    // Species 3: golden-amber crystalline lichen
    let c3 = vec3<f32>(0.8, 0.6, 0.1) * s3;
    // Resource substrate glow
    let rCol = vec3<f32>(0.15, 0.25, 0.15) * resourceLevel * 0.5;

    // Iridescent shift based on rule evolution
    let shift = sin(rulePhase * TAU + t * 0.3) * 0.15;
    let iridescence = vec3<f32>(shift, -shift * 0.5, shift * 0.7);

    return c1 + c2 + c3 + rCol + iridescence * (s1 + s2 + s3) * 0.3;
}

// Pigment matrix equivalent of speciesColor's species terms (columns = species)
fn pigmentMatrix(rulePhase: f32, t: f32) -> mat3x3<f32> {
    let shift = sin(rulePhase * TAU + t * 0.3) * 0.15;
    let irid = vec3<f32>(shift, -shift * 0.5, shift * 0.7) * 0.3;
    return mat3x3<f32>(
        vec3<f32>(0.1, 0.7, 0.5) + irid,
        vec3<f32>(0.7, 0.2, 0.6) + irid,
        vec3<f32>(0.8, 0.6, 0.1) + irid
    );
}

fn inverse3(m: mat3x3<f32>) -> mat3x3<f32> {
    let a = m[0]; let b = m[1]; let c = m[2];
    let r0 = cross(b, c);
    let r1 = cross(c, a);
    let r2 = cross(a, b);
    let det = dot(a, r0);
    let invDet = 1.0 / select(det, 1e-4, abs(det) < 1e-4);
    return transpose(mat3x3<f32>(r0, r1, r2)) * invDet;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Exact inverse of the ACES fit on [0, 0.999]
fn acesInverse(yIn: vec3<f32>) -> vec3<f32> {
    let y = clamp(yIn, vec3<f32>(0.0), vec3<f32>(0.999));
    let a = 2.43 * y - 2.51;
    let b = 0.59 * y - 0.03;
    let c = 0.14 * y;
    let disc = max(b * b - 4.0 * a * c, vec3<f32>(0.0));
    return max((-b - sqrt(disc)) / (2.0 * a), vec3<f32>(0.0));
}

fn gardenVignette(uv: vec2<f32>) -> f32 {
    let vig = 1.0 - smoothstep(0.35, 0.8, length(uv - 0.5) * 1.3);
    return mix(0.35, 1.0, vig); // floored so the encoding stays invertible
}

// Decode (s1, s2, s3, resource) from the previous frame's display RGBA
fn decodeState(coord: vec2<i32>, dims: vec2<i32>, res: vec2<f32>, pigInv: mat3x3<f32>) -> vec4<f32> {
    let cc = clamp(coord, vec2<i32>(0), dims - vec2<i32>(1));
    let texel = textureLoad(dataTextureC, cc, 0);
    let uvc = (vec2<f32>(cc) + 0.5) / res;
    let lin = acesInverse(texel.rgb) / (ENC_GAIN * gardenVignette(uvc));
    let rVec = vec3<f32>(0.15, 0.25, 0.15) * 0.5;
    let w = transpose(pigInv) * vec3<f32>(1.0);          // row sums of inverse
    let depthOpt = -log(max(1.0 - clamp(texel.a, 0.0, 0.999999), 1e-6));
    let denom = 0.45 - 0.9 * dot(w, rVec);
    let substrate = clamp((depthOpt - 0.05 - 0.9 * dot(w, lin)) / denom, 0.0, 1.2);
    let s = clamp(pigInv * (lin - rVec * substrate), vec3<f32>(0.0), vec3<f32>(1.5));
    return vec4<f32>(s, substrate);
}

// ─── Multi-scale neighbourhood sampling (exact texel loads) ───────
fn sampleNeighbourhood(coord: vec2<i32>, dims: vec2<i32>, res: vec2<f32>, scale: i32, pigInv: mat3x3<f32>) -> vec4<f32> {
    let n0 = decodeState(coord + vec2<i32>( scale, 0), dims, res, pigInv);
    let n1 = decodeState(coord - vec2<i32>( scale, 0), dims, res, pigInv);
    let n2 = decodeState(coord + vec2<i32>(0,  scale), dims, res, pigInv);
    let n3 = decodeState(coord - vec2<i32>(0,  scale), dims, res, pigInv);
    let n4 = decodeState(coord + vec2<i32>( scale,  scale), dims, res, pigInv);
    let n5 = decodeState(coord - vec2<i32>( scale,  scale), dims, res, pigInv);
    let n6 = decodeState(coord + vec2<i32>( scale, -scale), dims, res, pigInv);
    let n7 = decodeState(coord - vec2<i32>( scale, -scale), dims, res, pigInv);
    return (n0 + n1 + n2 + n3 + n4 + n5 + n6 + n7) * 0.125;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let aspect = res.x / res.y;

    let t = u.config.x;
    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // User parameters
    let mutationRate = u.zoom_params.x * 2.0 + 0.2;   // 0.2..2.2
    let competition  = u.zoom_params.y * 0.8 + 0.1;   // 0.1..0.9
    let fertility    = u.zoom_params.z * 1.5 + 0.3;   // 0.3..1.8
    let diversity    = u.zoom_params.w;                // 0..1

    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.15, 0.0, mouseDist) * mouseDown;

    // Audio-free colour phase: shared by encode (this frame) and decode (next frame)
    let colorPhase = fract(t * 0.01 * mutationRate);
    let pigInv = inverse3(pigmentMatrix(colorPhase, t));

    // Read previous state from temporal feedback (exact decode of A via C)
    let state = decodeState(coord, dims, res, pigInv);
    let s1 = state.r;       // Species 1 density
    let s2 = state.g;       // Species 2 density
    let s3 = state.b;       // Species 3 density
    let resourceLevel = state.a; // Local resourceLevel level

    // Evolving rule phase — slowly drifts with time and audio mutation pressure
    // This makes the CA rules themselves change over the life of the system
    let rulePhase = fract(t * 0.01 * mutationRate + bass * 0.15 + mids * 0.08);
    let rulePhase2 = fract(rulePhase + 0.33 + treble * 0.1);
    let rulePhase3 = fract(rulePhase + 0.67 + mids * 0.12);

    // Multi-scale neighbourhood averages (near + far = multi-scale competition)
    let nearNeighbours = sampleNeighbourhood(coord, dims, res, 1, pigInv);
    let farNeighbours  = sampleNeighbourhood(coord, dims, res, 3, pigInv);

    // Weighted neighbourhood for each species (multi-scale awareness)
    let nearWeight = 0.7;
    let farWeight = 0.3;
    let avgS1 = nearNeighbours.r * nearWeight + farNeighbours.r * farWeight;
    let avgS2 = nearNeighbours.g * nearWeight + farNeighbours.g * farWeight;
    let avgS3 = nearNeighbours.b * nearWeight + farNeighbours.b * farWeight;
    let avgRes = nearNeighbours.a * nearWeight + farNeighbours.a * farWeight;

    // ── Idea 2: Red Queen frequency-dependent selection ──
    // The locally dominant species' evolved thresholds drift against it
    // (parasites/grazers track the commonest genotype), curbing monocultures.
    let localPop = s1 + s2 + s3 + 1e-3;
    let redQueen = 0.25 * (0.5 + u.zoom_params.x) * (1.0 + treble * 0.4);
    let rq1 = min(rulePhase  + (s1 / localPop) * redQueen, 1.3);
    let rq2 = min(rulePhase2 + (s2 / localPop) * redQueen, 1.3);
    let rq3 = min(rulePhase3 + (s3 / localPop) * redQueen, 1.3);

    // Apply evolving growth kernels per species
    let grow1 = growthKernel(s1, avgS1, rq1, resourceLevel, fertility);
    let grow2 = growthKernel(s2, avgS2, rq2, resourceLevel, fertility * 0.9);
    let grow3 = growthKernel(s3, avgS3, rq3, resourceLevel, fertility * 0.85) * diversity;

    // Inter-species competition
    let comp12 = s1 * s2 * competition;
    let comp13 = s1 * s3 * competition * 0.8;
    let comp23 = s2 * s3 * competition * 0.9;

    // Audio-driven genetic pressure modifies growth rates — acts only on
    // populations already present (no spontaneous fill of bare substrate)
    let audioPressure1 = bass * 0.03 * smoothstep(0.02, 0.25, avgS1);
    let audioPressure2 = mids * 0.025 * smoothstep(0.02, 0.25, avgS2);
    let audioPressure3 = treble * 0.02 * smoothstep(0.02, 0.25, avgS3) * diversity;

    // Update species densities
    var newS1 = s1 + grow1 - comp12 - comp13 + audioPressure1;
    var newS2 = s2 + grow2 - comp12 - comp23 + audioPressure2;
    var newS3 = s3 + grow3 - comp13 - comp23 + audioPressure3;

    // Resource dynamics: slowly regenerates, consumed by all species
    let totalConsumption = (newS1 + newS2 + newS3) * 0.012;
    let regeneration = 0.015 * fertility + avgRes * 0.01;
    var newRes = resourceLevel + regeneration - totalConsumption;

    // ── Idea 1: mycorrhizal hyphal transport ──
    // The fungal species forms a conductive network: where hyphae are dense,
    // substrate flows from the far (3-texel) neighbourhood toward local deficit.
    let hyphalConductance = smoothstep(0.05, 0.6, avgS2) * (0.2 + mids * 0.1);
    newRes += hyphalConductance * (farNeighbours.a - resourceLevel);
    // Mutualism: coral fed by the network grows slightly where hyphae connect
    newS1 += hyphalConductance * max(farNeighbours.a - resourceLevel, 0.0) * s1 * 0.5;

    // Mouse interaction: seeds invasive burst or creates protected zone
    if (mouseInfluence > 0.01) {
        // Seed a burst of the currently dominant species in that region
        if (newS1 >= newS2 && newS1 >= newS3) {
            newS1 += mouseInfluence * 0.4;
        } else if (newS2 >= newS3) {
            newS2 += mouseInfluence * 0.4;
        } else {
            newS3 += mouseInfluence * 0.4;
        }
        newRes += mouseInfluence * 0.3; // Inject resources
    }

    // Click ripples: founder-spore rings seed the locally rarest species
    let rippleCount = min(u32(u.config.y), 50u);
    var founder = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = t - rp.z;
        if (age > 0.0 && age < 1.5) {
            let d = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            let ringD = d - age * 0.22;
            founder += exp(-ringD * ringD / 0.0004) * (1.0 - age / 1.5);
        }
    }
    if (founder > 0.01) {
        if (newS3 <= newS1 && newS3 <= newS2) {
            newS3 += founder * 0.25;
        } else if (newS2 <= newS1) {
            newS2 += founder * 0.25;
        } else {
            newS1 += founder * 0.25;
        }
        newRes += founder * 0.15;
    }

    // Random seeding for new growth when population is low
    let totalPopPre = newS1 + newS2 + newS3;
    if (totalPopPre < 0.05) {
        let seed = hash13(vec3<f32>(uv * 100.0, floor(t * 2.0)));
        if (seed > 0.97) {
            let which = hash12(uv * 57.3 + t);
            if (which < 0.33) { newS1 += 0.3; }
            else if (which < 0.66) { newS2 += 0.3; }
            else { newS3 += 0.3; }
            newRes += 0.2;
        }
    }

    // Clamp all values
    newS1 = clamp(newS1, 0.0, 1.5);
    newS2 = clamp(newS2, 0.0, 1.5);
    newS3 = clamp(newS3, 0.0, 1.5);
    newRes = clamp(newRes, 0.0, 1.2);
    let totalPop = newS1 + newS2 + newS3;

    // ─── Visualization = invertible state encoding ────────────────
    // Colour is purely the pigment mix (+ substrate glow + iridescence,
    // all linear), vignetted, then ACES. Bass never touches the encoding
    // gain (it would break decode); audio acts through the sim instead.
    let color = speciesColor(newS1, newS2, newS3, newRes, colorPhase, t);
    let display = acesToneMap(color * ENC_GAIN * gardenVignette(uv));

    // Semantic alpha: Beer-Lambert canopy + substrate coverage
    let alpha = 1.0 - exp(-(0.9 * totalPop + 0.45 * newRes + 0.05));

    let finalColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(totalPop * 0.4, 0.0, 0.0, 0.0));
}
