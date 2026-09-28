// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Cyber-Aether Void-Seahorse
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: sagittal fin-ray membrane with a travelling undulation wave; fold-tree chromatophore cascade through the fractal tail beads
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read back as HDR history
// ═══════════════════════════════════════════════════════════════════
//  History: 2026-08-05 Algorithmist b35 (capsule-chain spine anatomy,
//  tail orbit trap, domain-warped FBM bioluminescence + void nebula,
//  tetrahedral normals, 3-point lighting + Fresnel, ripple pulses).
//  2026-09-27 fixes: ACES on display only; mouse X is a real yaw orbit
//  (was an image roll); fin/tail smooth unions blend unconditionally (the
//  gated smin jumped by k/4 -> seams); tail trap excludes the final bead
//  fold (was <= 0.1 everywhere -> uniform wash); the "near-miss halo" is
//  now real (min SDF along missed rays); miss depth = 0; screen-top = +y
//  so the seahorse stands head-up.
// ═══════════════════════════════════════════════════════════════════
// --- COPY PASTE THIS HEADER ---
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ----------------------------------------------------------------
// SDF Primitives & Operations
// ----------------------------------------------------------------
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdSphere(p: vec3<f32>, c: vec3<f32>, r: f32) -> f32 {
    return length(p - c) - r;
}

// ----------------------------------------------------------------
// Noise & Volumetrics (value-noise FBM + domain warping)
// ----------------------------------------------------------------
fn hash33(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn vnoise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let c000 = hash33(i).x;
    let c100 = hash33(i + vec3<f32>(1.0, 0.0, 0.0)).x;
    let c010 = hash33(i + vec3<f32>(0.0, 1.0, 0.0)).x;
    let c110 = hash33(i + vec3<f32>(1.0, 1.0, 0.0)).x;
    let c001 = hash33(i + vec3<f32>(0.0, 0.0, 1.0)).x;
    let c101 = hash33(i + vec3<f32>(1.0, 0.0, 1.0)).x;
    let c011 = hash33(i + vec3<f32>(0.0, 1.0, 1.0)).x;
    let c111 = hash33(i + vec3<f32>(1.0, 1.0, 1.0)).x;
    return mix(mix(mix(c000, c100, w.x), mix(c010, c110, w.x), w.y),
               mix(mix(c001, c101, w.x), mix(c011, c111, w.x), w.y), w.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var x = p;
    for (var i = 0; i < 4; i++) {
        f += amp * (vnoise(x) - 0.5);
        amp *= 0.5;
        x = x * 2.03 + vec3<f32>(11.3, 7.1, 5.7);
    }
    return f;
}

// Domain-warped FBM: q = fbm(p), r = fbm(p + q); temporal coherence via
// time as the third noise axis (smooth frame-to-frame drift).
fn fbmWarped(p: vec3<f32>) -> f32 {
    let q = vec3<f32>(fbm(p), fbm(p + vec3<f32>(5.2, 1.3, 2.8)), fbm(p + vec3<f32>(1.7, 9.2, 4.1)));
    return fbm(p + 1.7 * q);
}

// Bioluminescent palette (IQ cosine), phase shifted by slider p1
fn bioPalette(t: f32, shift: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(TAU * (t + shift) + vec3<f32>(0.0, 1.2, 2.4) + vec3<f32>(0.2, 0.6, 1.0));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 1 (field): dorsal fin-ray frame in spine-curved space.
// Rays are parallel spines running out from the back (one every 1/15 in y);
// returns x = ray ridge (1 on a ray, 0 on webbing), y = free-edge factor
// (0 at the back, 1 at the fin rim), z = distance to the nearest ray (0..0.5).
fn finRayField(p: vec3<f32>) -> vec3<f32> {
    let s = abs(fract(p.y * 15.0 + 0.5) - 0.5);
    let ridge = 1.0 - smoothstep(0.0, 0.2, s);
    let free = clamp((-0.65 - p.x) / 0.45, 0.0, 1.0);
    return vec3<f32>(ridge, free, s);
}

// ----------------------------------------------------------------
// Mapping & Raymarching
// map returns: x = signed distance, y = material id
//              (1 body/head, 2 fractal tail, 3 dorsal fin)
//              z = tail orbit-trap minimum over the pre-bead folds
//              w = fold address of the tail bead (0..1, first fold = MSB)
// ----------------------------------------------------------------
fn map(p_in: vec3<f32>, t: f32, audio: vec3<f32>) -> vec4<f32> {
    var p = p_in;

    // Space curving for the seahorse spine (existing soul, kept verbatim)
    p.x += sin(p.y * 2.0 + t) * 0.2;

    // Bass-driven breathing of the whole body
    let breathe = 1.0 + audio.x * 0.07;

    // --- Body: bent ellipsoid + belly, smooth-unioned ---
    let qb = p / (vec3<f32>(0.60, 1.05, 0.48) * breathe);
    let dBody = (length(qb) - 1.0) * 0.48;
    let dBelly = sdSphere(p, vec3<f32>(-0.12, -0.38, 0.0), 0.60 * breathe);
    var d = smin(dBody, dBelly, 0.35);

    // --- Head + tapered snout capsule chain + coronet ---
    let dHead = sdSphere(p, vec3<f32>(0.30, 0.86, 0.0), 0.40 * breathe);
    d = smin(d, dHead, 0.30);
    // Snout: two shrinking spheres blended into a tapered tube
    let dSnoutA = sdSphere(p, vec3<f32>(0.62, 0.78, 0.0), 0.20);
    let dSnoutB = sdSphere(p, vec3<f32>(0.92, 0.66, 0.0), 0.115);
    d = smin(d, smin(dSnoutA, dSnoutB, 0.16), 0.18);
    // Coronet ridge on the skull
    let dCoronet = sdSphere(p, vec3<f32>(0.20, 1.24, 0.0), 0.14);
    d = smin(d, dCoronet, 0.12);
    let dMain = d;

    // --- Idea 1: sagittal fin-ray membrane on the lower back ---
    // HEAD's fin sat edge-on in the x = -0.56 plane (a 0.03-wide sliver down
    // the back). The seahorse's real propulsor is a membrane in the sagittal
    // (z = 0) plane standing off the back, stiffened by parallel fin rays.
    // The existing finWave (mids drift its frequency) now bends the membrane
    // out of plane, pinned at the back and free at the rim, so the wave
    // visibly runs ray-to-ray along the fin.
    let finWave = sin(p.y * (6.0 + audio.y * 3.0) + t * 2.2) * 0.06;
    let fr = finRayField(p);
    let finZ = finWave * fr.y;
    let finPlane = (abs(p.z - finZ) - (0.006 + 0.006 * fr.x)) * 0.7;
    // Outline: rounded fan off the back; the webbing sags between ray tips.
    let rEdge = 1.0 - 0.06 * smoothstep(0.1, 0.5, fr.z) * fr.y;
    let finClip = (length(vec2<f32>((p.x + 0.78) / 0.48, (p.y + 0.28) / 0.50)) - rEdge) * 0.32;
    let dFin = max(finPlane, finClip);
    d = smin(d, dFin, 0.08);

    // --- Fractal curled tail with orbit trap (existing fold, kept) ---
    var pTail = p + vec3<f32>(0.08, 1.60, 0.0);
    var trap = length(pTail);
    var foldId = 0.0;
    var place = 512.0;
    for (var i = 0; i < 4; i++) {
        pTail = vec3<f32>(pTail.xy * rotate(0.5 + audio.x * 0.15), pTail.z);
        // Idea 2: record which mirror octant this fold sent the point to.
        let code = select(0.0, 4.0, pTail.x < 0.0) + select(0.0, 2.0, pTail.y < 0.0) + select(0.0, 1.0, pTail.z < 0.0);
        foldId += code * place;
        place *= 0.125;
        pTail = abs(pTail) - vec3<f32>(0.2);
        // Trap over the pre-bead folds only (the last fold IS the bead, so
        // including it pinned trap <= 0.1 on every tail pixel).
        if (i < 3) { trap = min(trap, length(pTail)); }
    }
    let dTail = length(pTail) - 0.10;
    let dPre = d;
    d = smin(d, dTail, 0.5);

    var mat = select(1.0, 3.0, dFin < dMain);
    mat = select(mat, 2.0, dTail < dPre);

    return vec4<f32>(d, mat, trap, foldId / 4096.0);
}

fn mapDist(p: vec3<f32>, t: f32, audio: vec3<f32>) -> f32 {
    return map(p, t, audio).x;
}

// Tetrahedral SDF gradient → true surface normals
fn calcNormal(p: vec3<f32>, t: f32, audio: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.0025, -0.0025);
    return normalize(
        e.xyy * mapDist(p + e.xyy, t, audio) +
        e.yyx * mapDist(p + e.yyx, t, audio) +
        e.yxy * mapDist(p + e.yxy, t, audio) +
        e.xxx * mapDist(p + e.xxx, t, audio));
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    let coord = vec2<i32>(global_id.xy);
    // Resolution bounds guard — mandatory
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    // --- Uniform truth: sliders (updatedParams index order) ---
    let bioShift = u.zoom_params.x;            // p1: Bioluminescent Shift (-1..1)
    let audioGain = u.zoom_params.y;           // p2: Audio Reactivity (0..3)
    let voidIntensity = clamp(u.zoom_params.z, 0.0, 1.0); // p3: Void Intensity
    let evoSpeed = u.zoom_params.w;            // p4: Evolution Speed (0.1..5)

    let t = time * evoSpeed;
    let audio = vec3<f32>(plasmaBuffer[0].x, plasmaBuffer[0].y, plasmaBuffer[0].z) * audioGain;

    // --- Camera: bounded mouse orbit ---
    // uv.y = 0 is screen-top, so screen-top maps to +y (head up).
    var ro = vec3<f32>(0.0, 0.0, 4.6);
    var rd = normalize(vec3<f32>((uv.x - 0.5) * 2.0 * (res.x / res.y), (0.5 - uv.y) * 2.0, -1.5));
    let mx = (u.zoom_config.y - 0.5) * 1.2;
    let my = (u.zoom_config.z - 0.5) * 0.9;
    // Pitch (yz), then yaw (xz) about the seahorse — mouse X used to roll
    // the image (it rotated rd.xy and ro.xy with ro.xy = 0).
    let ryz = rd.yz * rotate(my);
    rd = vec3<f32>(rd.x, ryz.x, ryz.y);
    let oyz = ro.yz * rotate(my);
    ro = vec3<f32>(ro.x, oyz.x, oyz.y);
    let rxz = rd.xz * rotate(mx);
    rd = vec3<f32>(rxz.x, rd.y, rxz.y);
    let oxz = ro.xz * rotate(mx);
    ro = vec3<f32>(oxz.x, ro.y, oxz.y);

    // --- Raymarch ---
    var dist = 0.0;
    var mat = 0.0;
    var trap = 10.0;
    var foldId = 0.0;
    var minMiss = 10.0; // closest approach of the ray to the creature
    var hit = false;
    let maxDist = 16.0;
    for (var i = 0; i < 64; i++) {
        let p = ro + rd * dist;
        let m = map(p, t, audio);
        if (m.x < 0.002) {
            mat = m.y;
            trap = m.z;
            foldId = m.w;
            hit = true;
            break;
        }
        minMiss = min(minMiss, m.x);
        dist += m.x * 0.9;
        if (dist > maxDist) { break; }
    }

    // --- Shading ---
    let phase = bioShift * 0.5 + t * 0.03;
    var col = vec3<f32>(0.0);
    var relief = 0.0; // generated depth accumulator

    if (hit) {
        let p = ro + rd * dist;
        let n = calcNormal(p, t, audio);
        let cosV = clamp(dot(-rd, n), 0.0, 1.0);
        let fres = pow(clamp(1.0 - cosV, 0.0, 1.0), 3.5);

        // Domain-warped bioluminescent surface bands (macro + micro scales)
        let warpMacro = fbmWarped(p * 2.2 + vec3<f32>(0.0, t * 0.10, t * 0.05));
        let warpMicro = fbm(p * 9.0 + vec3<f32>(t * 0.2));
        let bands = 0.5 + 0.5 * sin(p.y * 9.0 + warpMacro * 9.0 + warpMicro * 2.5 + phase * TAU);
        let emis = smoothstep(0.55, 0.95, bands);

        // 3-point lighting: abyssal key, aether fill, cyber rim
        let keyDir = normalize(vec3<f32>(0.6, 0.7, 0.5));
        let fillDir = normalize(vec3<f32>(-0.7, -0.3, 0.4));
        // Spine-curved position (same warp as map) for the fin-ray frame.
        let pc = vec3<f32>(p.x + sin(p.y * 2.0 + t) * 0.2, p.y, p.z);
        let isFin = select(0.0, 1.0, mat > 2.5);
        let isTail = select(0.0, 1.0, mat > 1.5 && mat < 2.5);
        let dif = max(dot(n, keyDir), 0.0);
        let fill = max(dot(n, fillDir), 0.0) * 0.4;
        let spec = pow(max(dot(reflect(rd, n), keyDir), 0.0), 42.0) * (1.0 + audio.z * 2.0);

        // Material palettes
        let bodyAlbedo = vec3<f32>(0.05, 0.35, 0.55);
        let tailAlbedo = vec3<f32>(0.30, 0.12, 0.50);
        let finAlbedo = vec3<f32>(0.10, 0.55, 0.65);
        var albedo = bodyAlbedo;
        albedo = mix(albedo, tailAlbedo, step(1.5, mat));
        albedo = mix(albedo, finAlbedo, step(2.5, mat));

        col = albedo * (vec3<f32>(0.6, 0.9, 1.1) * dif + vec3<f32>(0.4, 0.2, 0.8) * fill + vec3<f32>(0.04));

        // Idea 1: fin-ray membrane shading. The webbing between rays is a
        // translucent sheet lit two-sided by the aether fill (it glows through
        // whichever way the undulation tilts it); the bony rays stay opaque and
        // carry bioluminescent pulses out from the back to the rim, phase-locked
        // to the same undulation wave that bends the membrane.
        if (isFin > 0.5) {
            let fr = finRayField(pc);
            let web = 1.0 - fr.x;
            let transl = 0.30 + 0.90 * abs(dot(n, fillDir));
            col = mix(col, col * 0.55, fr.x * 0.6);
            col += finAlbedo * vec3<f32>(0.7, 0.9, 1.2) * transl * web * (0.45 + 0.35 * fr.y);
            let rayPulse = 0.5 + 0.5 * sin(fr.y * 14.0 - t * 3.0 + pc.y * (6.0 + audio.y * 3.0));
            col += bioPalette(pc.y * 0.4 + 0.3, phase) * fr.x * rayPulse * rayPulse * (0.9 + audio.y * 0.6);
        }

        // Bioluminescent emission, palette phased by p1, pumped by mids
        let emisCol = bioPalette(warpMacro * 0.8 + p.y * 0.15, phase);
        col += emisCol * emis * (0.55 + audio.y * 0.8);

        // Tail orbit-trap filaments: cyan glow where beads crowd a fold centre
        let trapGlow = exp(-clamp(trap, 0.0, 4.0) * 6.0);
        col += vec3<f32>(0.2, 1.0, 0.8) * trapGlow * isTail * (0.7 + audio.x);

        // Idea 2: fold-tree chromatophore cascade. Every tail bead has a fold
        // address (which mirror octant each of the 4 folds sent it to, first
        // fold = most significant digit). A flash walks through the addresses
        // in order, so light hops mirror-sibling to mirror-sibling: one half of
        // the tail, then its halves, then theirs — the fractal's own tree.
        let cascadePh = fract(t * 0.25 - foldId);
        let flash = pow(max(1.0 - cascadePh, 0.0), 10.0);
        col += bioPalette(foldId * 0.7 + 0.15, phase) * flash * isTail * (1.4 + audio.x * 0.8);

        // Fresnel rim + treble glints = the "cyber" sheen
        col += vec3<f32>(0.5, 0.3, 1.0) * fres * (0.6 + audio.z * 0.6);
        col += vec3<f32>(1.0, 0.9, 1.0) * spec * 0.6;

        relief = clamp(1.0 - dist / maxDist, 0.0, 1.0);
    } else {
        // --- Void nebula background: domain-warped quantum reef ---
        let nebP = rd * 2.6 + vec3<f32>(0.0, 0.0, t * 0.04);
        let nebMacro = fbmWarped(nebP);
        let nebMicro = fbm(rd * 11.0 + vec3<f32>(t * 0.06));
        let neb = clamp(nebMacro * 0.5 + 0.5, 0.0, 1.0) * (0.6 + nebMicro);
        let nebCol = bioPalette(neb * 0.6 + 0.35, phase * 0.5);
        // Void Intensity: higher = deeper, darker void with tighter contrast
        let voidGain = mix(0.55, 0.16, voidIntensity);
        col = nebCol * neb * voidGain;
        // Near-miss halo around the creature silhouette (fix: HEAD only
        // commented it; now driven by the ray's closest approach).
        col += vec3<f32>(0.25, 0.55, 1.0) * exp(-max(minMiss, 0.0) * 14.0) * 0.35;
        relief = 0.0; // miss = far
    }

    // --- Click ripples: bounded, finite, spatially local pulses ---
    let rippleCount = min(u32(u.config.y), 50u);
    let aspect = vec2<f32>(res.x / res.y, 1.0);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age > 2.5) { continue; }
        let dUv = length((uv - rp.xy) * aspect);
        let ring = exp(-abs(dUv - age * 0.45) * 22.0) * exp(-age * 2.2);
        col += bioPalette(age * 0.3, phase) * ring * 0.8;
    }
    // Mouse-hold local aether glow (bounded spring-like falloff)
    if (u.zoom_config.w > 0.5) {
        let dM = length((uv - u.zoom_config.yz) * aspect);
        col += vec3<f32>(0.2, 0.8, 1.0) * exp(-dM * 6.0) * 0.35 * (1.0 + audio.x);
    }

    // --- Temporal coherence: blend with HDR history (A→C copy, pre-ACES) ---
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, max(prev.rgb, vec3<f32>(0.0)), 0.12);

    let display = acesFilm(col);
    let hitMask = select(0.0, 1.0, hit);
    let alpha = clamp(0.30 + hitMask * 0.45 + length(display) * 0.25, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(relief, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
