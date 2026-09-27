// ═══════════════════════════════════════════════════════════════════
//  Chromatic Singularity-Loom
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: tidal spaghettification (thread radius necks thin and striations stretch with the local 1/r^2 pull); mirror-parity warp/weft families (fold-reflection determinant splits the threads into two complementary chromatic families); orbital infall trail (exact C history advected around and into the projected singularity)
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read exactly, rotated/infalling around the singularity
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
    ripples: array<vec4<f32>, 50>
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.005;
const CAM_Z: f32 = -3.0;
const PI: f32 = 3.14159265;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Singularity mass: slider x (0 -> HEAD's 2.0 substitution), bass pulse (HEAD).
fn singularityMass(params: vec4<f32>, bass: f32) -> f32 {
    var mass = params.x;
    if (mass == 0.0) { mass = 2.0; }
    return mass * (1.0 + bass * 0.5);
}

// Returns (distance, material, tidal pull, folded axial coordinate).
// material: 1 = warp family, 2 = weft family, 3 = singularity sphere.
fn map(p: vec3<f32>, time: f32, audio_intensity: f32, params: vec4<f32>, center: vec3<f32>, bass: f32) -> vec4<f32> {
    var pos = p;

    let toC = pos - center;
    let dist_sq = dot(toC, toC);

    let mass = singularityMass(params, bass);

    // Gravity warp 1/r^2 — FIX: direction measured from the singularity (HEAD used the origin),
    // pull clamped so a centred mouse / r -> 0 cannot NaN or explode.
    let pull = min(mass / max(dist_sq, 1e-4), 2.5);
    pos += toC * inverseSqrt(max(dist_sq, 1e-8)) * pull;

    // Idea 1: tidal spaghettification — the thread cylinder necks thin where the pull is strong
    // (0.05 * 1.4 = 0.07 far away, ~0.026 grazing the singularity).
    let threadR = 0.05 * 1.4 / (1.0 + 4.0 * pull);

    // FIX: continuous fold count 2..6 from slider y (HEAD i32(y) gave 0 folds on 0<y<1),
    // blended between floor/ceil fold depths so the weave morphs instead of popping.
    let foldsF = 2.0 + clamp(params.y, 0.0, 1.0) * 4.0;
    let nLo = i32(floor(foldsF));
    let foldFrac = foldsF - floor(foldsF);
    // Weave speed: phase from time only (HEAD multiplied time by audio chaos -> phase jumps).
    let weaveRate = 0.2 * clamp(params.y, 0.0, 1.0);

    var dLo = 0.0;
    var axLo = 0.0;
    var parLo = 0.0;
    var flips = 0.0;
    for (var i = 0; i <= nLo; i++) {
        if (i == nLo) {
            dLo = length(pos.xz) - threadR;
            axLo = pos.y;
            parLo = flips;
        }
        // Idea 2: count the mirror reflections abs() applies — their parity is the determinant
        // sign of the fold map, so neighbouring copies across any fold plane alternate family.
        flips += select(0.0, 1.0, pos.x < 0.0) + select(0.0, 1.0, pos.y < 0.0) + select(0.0, 1.0, pos.z < 0.0);
        pos = abs(pos) - vec3<f32>(0.5 + audio_intensity * 0.2);
        // Audio-reactive thread chaos: additive angle jitter, never a time multiplier.
        let r = rot(time * weaveRate + f32(i) + audio_intensity * 0.3 * sin(f32(i)));
        let x_new = r[0][0]*pos.x + r[0][1]*pos.y;
        let y_new = r[1][0]*pos.x + r[1][1]*pos.y;
        pos.x = x_new;
        pos.y = y_new;
    }
    let dHi = length(pos.xz) - threadR;

    let d1 = mix(dLo, dHi, foldFrac);
    let useHi = foldFrac > 0.5;
    let parity = (select(parLo, flips, useHi)) % 2.0;
    let axial = select(axLo, pos.y, useHi);
    let d2 = length(p - center) - 1.0;

    if (d2 < d1) {
        return vec4<f32>(d2, 3.0, pull, 0.0);
    }
    return vec4<f32>(d1, 1.0 + parity, pull, axial);
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
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }

    // FIX: y flipped so screen top = +y (HEAD rendered upside-down relative to the mouse).
    let uv = vec2<f32>(f32(coords.x) + 0.5 - 0.5 * res.x, 0.5 * res.y - f32(coords.y) - 0.5) / res.y;
    let time = u.config.x;
    // FIX: audio from plasmaBuffer[0] (HEAD read config.y = rippleCount as audio).
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio_intensity = mids;

    var mousePos = u.zoom_config.yz;
    if (mousePos.x == 0.0 && mousePos.y == 0.0) {
        mousePos = vec2<f32>(0.5);
    }

    let params = u.zoom_params;

    var ro = vec3<f32>(0.0, 0.0, CAM_Z);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // FIX: singularity sits under the pointer on the z = 0 plane (HEAD scaled mouse by 10 -> off-screen).
    let aspect = res.x / res.y;
    let mouseUV = vec2<f32>((mousePos.x - 0.5) * aspect, 0.5 - mousePos.y);
    let center = vec3<f32>(mouseUV * -CAM_Z, 0.0);
    let mass = singularityMass(params, bass);

    var dO = 0.0;
    var hit = false;
    var m = vec4<f32>(MAX_DIST, 0.0, 0.0, 0.0);
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        m = map(p, time, audio_intensity, params, center, bass);
        if (m.x < SURF_DIST) {
            hit = true;
            break;
        }
        // FIX: the 1/r^2 warp is not 1-Lipschitz; relax the step by its gradient bound.
        let rc = length(p - center);
        let lip = 1.0 + 2.0 * mass / max(rc * rc * rc, 1.0);
        dO += m.x / lip * 0.8;
        if (dO > MAX_DIST) {
            break;
        }
    }
    if (!hit && dO < MAX_DIST && m.x < 0.03) { hit = true; }

    var col = vec3<f32>(0.0);
    var dist_center = MAX_DIST;
    if (hit) {
        let hit_p = ro + rd * dO;
        dist_center = length(hit_p - center);
        let isThread = m.y < 2.5;
        let parity = select(0.0, m.y - 1.0, isThread);

        var chromatic_shift = params.w;
        if (chromatic_shift == 0.0) { chromatic_shift = 0.5; }

        // Chromatic gravitational lensing: R/B bend differently
        // Idea 2: the weft family (odd mirror parity) runs half a cycle out of phase -> complementary hue.
        let familyPhase = parity * PI;
        let phaseR = hit_p.z * chromatic_shift * (1.0 + bass * 0.1) + time + familyPhase;
        let phaseB = hit_p.z * chromatic_shift * (1.0 - treble * 0.1) + time + familyPhase;
        let c_shiftR = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(phaseR, phaseR + 2.09, phaseR + 4.18));
        let c_shiftB = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(phaseB, phaseB + 2.09, phaseB + 4.18));
        let c_shift = mix(c_shiftR, c_shiftB, 0.5);

        var accretion_glow = params.z;
        if (accretion_glow == 0.0) { accretion_glow = 1.0; }
        let bloom = accretion_glow * exp(-dist_center * 2.0) * (1.0 + audio_intensity * 2.0);

        // FIX: HEAD's plasmaBuffer[dist*10 + time*10] lookup read zero/out-of-range slots (black frame).
        // Glow tint is a warm accretion white nudged by the live audio triple.
        let glowTint = vec3<f32>(1.0, 0.8, 0.6) + plasmaBuffer[0].xyz * 0.4;

        var body = vec3<f32>(1.0);
        if (isThread) {
            // Idea 1: tidal spaghettification — striations along each thread stretch apart and the
            // thread heats (brightens) as the local pull grows toward the singularity.
            let strain = m.z;
            let stria = 0.5 + 0.5 * sin(m.w * 14.0 / (1.0 + 6.0 * strain) - time * 0.7);
            body = vec3<f32>((0.65 + 0.35 * stria) * (1.0 + 1.5 * strain));
            // Idea 2: warp family slightly brighter than weft so the two read as layered threads.
            body *= mix(1.0, 0.8, parity);
        }

        col = c_shift * body * (1.0 / (1.0 + dO * dO * 0.1)) + glowTint * bloom;
    }

    // Idea 3: orbital infall trail — exact C history read at a pixel rotated backwards around the
    // projected singularity and pushed outward, so last frame's light orbits and falls in.
    // Angular step is faster near the singularity. (Replaces HEAD's ~2.4% sampled memory on hits only.)
    let rel = uv - mouseUV;
    let rr = length(rel);
    let orbit = 0.035 / (rr + 0.15);
    let srcUV = mouseUV + (rot(orbit) * rel) * 1.012;
    let srcPix = vec2<i32>(i32(floor(srcUV.x * res.y + 0.5 * res.x)), i32(floor(0.5 * res.y - srcUV.y * res.y)));
    let srcC = clamp(srcPix, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    let prev = max(textureLoad(dataTextureC, srcC, 0).rgb, vec3<f32>(0.0));
    let decay = 0.8 + 0.12 * exp(-rr * 2.0) + bass * 0.02;
    let hdr = max(col, prev * min(decay, 0.95));

    let alpha = clamp(length(hdr) * 0.8 + bass * 0.05, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(id.xy), applyGenerativePrimaryControls(vec4<f32>(hdr, alpha)));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(hdr, alpha));
    // FIX: depth near = 1, miss = 0 (HEAD wrote dO/MAX_DIST, inverted and ~0 everywhere).
    let depthOut = select(0.0, 1.0 / (1.0 + 0.25 * dO), hit);
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
