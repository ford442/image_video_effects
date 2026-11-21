// ═══════════════════════════════════════════════════════════════════
//  Radiant Cyber-Plasma Astro-Griffin
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27, 2026-11-21
//  Ideas: primary-feather slots; beak shear glint; flap ghost; flap flexion wave + upstroke slot opening (primaries supinate); rachis + barb vane with plasma flow along the shaft; step-count AO (§12.2E)
//  A packing: ACES display RGBA
//  Rescued 2026-11-21: wing was an unbounded fract() lattice (infinite slab floor) -> bounded 5-feather fan; uv.y was
//    not flipped (upside-down); camera sat behind the griffin (beak glint unreachable) -> front-3/4 camera; pointer
//    offset the creature by mouse*2 (off-centre at rest) with a 1/(d+0.1) twist that wrecked it when centred;
//    tint / seam coordinates were world-space (swam when the pointer moved); ACES output was gamma-encoded a second time (washed out).
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Warp Intensity, y=Wing Span, z=Fractal Depth, w=Plasma Glow

// --- UTILITIES ---
const PI: f32 = 3.14159265359;
const MAX_DIST: f32 = 20.0;

// Rescue R3: front-three-quarter camera (the beak faces -z; HEAD's camera at +z saw only the rear).
// Orthonormal basis precomputed for yaw 0.62, pitch 0.30, distance 4.2, target (0, 0.1, 0).
const CAM_POS: vec3<f32>   = vec3<f32>(2.3314, 1.3412, -3.2656);
const CAM_FWD: vec3<f32>   = vec3<f32>(-0.55508, -0.29552, 0.77753);
const CAM_RIGHT: vec3<f32> = vec3<f32>(-0.81388, 0.0, -0.58104);
const CAM_UP: vec3<f32>    = vec3<f32>(-0.17171, 0.95534, 0.24052);
const CAM_DIST: f32 = 4.2;
const POINTER_REACH: f32 = 3.0; // world units the creature travels as the pointer crosses the canvas

// Rescue R1: finite fan of primaries (HEAD repeated the cell forever in x and z).
const WING_K_LO: f32 = -1.0;    // innermost feather (|x| 0.5..1.0, abutting the body)
const WING_K_HI: f32 = 3.0;     // outermost feather (|x| 2.5..3.0)

// Creature offset set once per invocation in main() (pointer follow, screen-space).
var<private> g_anomaly: vec3<f32>;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + vec3<f32>(33.33));
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn hash21(p: vec2<f32>) -> f32 {
    let q = fract(p * vec2<f32>(234.34, 435.345));
    let s = dot(q, q + 34.23);
    return fract(q.x * q.y + s);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Triangular tessellation edge distance (2D): 0 on grid lines.
// Used to carve glowing chrono-prism seams into the griffin's hide.
fn triGridEdge(p: vec2<f32>, scale: f32) -> f32 {
    let q = p * scale;
    let r = vec2<f32>(1.0, 1.7320508); // hex basis (1, sqrt3)
    let a = fract(q / r) * r - r * 0.5;
    let b = fract((q - r * 0.5) / r) * r - r * 0.5;
    let g = select(a, b, dot(b, b) < dot(a, a));
    // distance to the 3 mirror planes of the triangle cell
    let d1 = abs(g.y);
    let d2 = abs(dot(g, vec2<f32>(0.8660254, 0.5)));
    let d3 = abs(dot(g, vec2<f32>(-0.8660254, 0.5)));
    return min(d1, min(d2, d3)) / scale;
}

// --- SDF FUNCTIONS ---

// Wing feathers: a BOUNDED fan of primaries (returns distance + feather cell hash).
// Rescue R1: HEAD used fract() repetition in x AND z, so the "wing" was an infinite slab floor.
// `open` (0 closed .. 1 fully open, from the flap phase) drives Idea 1b: slots widen and each
// primary supinates about its own long axis on the upstroke.
fn wingFeathers(p: vec3<f32>, span: f32, open: f32) -> vec2<f32> {
    let k = clamp(floor(p.x * 2.0), WING_K_LO, WING_K_HI);   // limited repetition keeps the SDF exact
    let tipness = (k - WING_K_LO) / (WING_K_HI - WING_K_LO);
    // swept wing: outer primaries trail behind the root ones (finite-wing rescue, not an idea)
    var q = vec3<f32>(p.x - (k + 0.5) * 0.5, p.y, p.z - 0.8 * tipness);

    // ── Idea 1b: upstroke supination — tip feathers twist most (rigid rotation, distance stays exact)
    let ang = open * (0.12 + 0.28 * tipness);
    q = vec3<f32>(rot2D(ang) * q.xy, q.z);

    let width = 0.1 + span * 0.1;
    // primaries lengthen toward the tip (secondaries are shorter) — part of the finite-wing rescue (R1)
    let spanLen = (0.5 + span * 0.5) * mix(0.9, 1.5, tipness);

    // Primary-feather slots: each cell stops short of its neighbor so a dark gap remains.
    // 0.74 is the closed-wing value (HEAD); on the upstroke the slot opens to 0.56 (Idea 1b).
    let slotW = mix(0.74, 0.56, open);
    let slotL = 0.74;
    let d = abs(q) - vec3<f32>(width * slotW, 0.02, spanLen * slotL);
    let dist = length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
    return vec2<f32>(dist, hash21(vec2<f32>(k, 1.0)));
}

// Upstroke openness from the root flap phase: tips rise when cos(t) > 0.
fn upstrokeOpen(t: f32) -> f32 {
    return smoothstep(-0.35, 0.65, cos(t));
}

// Creature space: the pointer drags the whole creature (HEAD behaviour) and twists space around the
// anomaly. R4: pointer-follow is now centred at the default pointer; twist profile softened from
// 1/(d+0.1) (5 rad at the creature centre, which wrecked the body once centred) to a finite swirl.
fn anomalyWarp(p: vec3<f32>) -> vec3<f32> {
    var p_warp = p - g_anomaly;
    let warp_intensity = u.zoom_params.x;
    let dist_to_anomaly = length(p_warp);
    let twist_amount = warp_intensity * 0.6 / (dist_to_anomaly + 0.5);
    let tmp_x = p_warp.x * cos(twist_amount) - p_warp.z * sin(twist_amount);
    let tmp_z = p_warp.x * sin(twist_amount) + p_warp.z * cos(twist_amount);
    p_warp.x = tmp_x;
    p_warp.z = tmp_z;
    return p_warp;
}

// Wing-local frame shared by map() and the shading pass (feather-local coords at the hit).
// ── Idea 1a: flexion wave — the tip lags the root (phase delay grows with distance from the body axis).
fn wingFrame(pw: vec3<f32>, t: f32) -> vec3<f32> {
    var w = pw;
    let reachX = abs(w.x);
    let flap = sin(t - 0.45 * reachX) * 0.5;
    w.y -= reachX * flap;
    w.x = reachX - 1.0;
    return w;
}

// Griffin core body
fn griffinBody(p: vec3<f32>) -> f32 {
    let bodyScale = vec3<f32>(0.5, 0.4, 0.8);
    let bodyDist = length(p / bodyScale) - 1.0;
    return bodyDist * min(min(bodyScale.x, min(bodyScale.y, bodyScale.z)), 1.0);
}

// Eagle head + beak wedge crowning the body
fn griffinHead(p: vec3<f32>) -> f32 {
    var q = p - vec3<f32>(0.0, 0.45, -0.75);
    let skull = length(q / vec3<f32>(0.28, 0.26, 0.32)) - 1.0;
    // Beak: flattened wedge tapering forward
    var b = q - vec3<f32>(0.0, -0.05, -0.35);
    b.z = max(b.z, -b.z * 0.5);
    let beak = length(max(abs(b) - vec3<f32>(0.08 - b.z * 0.05, 0.06, 0.22), vec3<f32>(0.0))) - 0.02;
    return smin(skull * 0.26, beak, 0.08);
}

// Returns vec2(distance, materialId): 0=void, 1=wings, 2=body, 3=head
fn map(p: vec3<f32>) -> vec3<f32> {
    let p_warp = anomalyWarp(p);

    // Animated flight/flapping
    let t = u.config.x * 2.0;

    // Wings (flexion wave lives in wingFrame; slot opening follows the root flap phase)
    let wing_p = wingFrame(p_warp, t);
    let wing_span = u.zoom_params.y;
    let wing = wingFeathers(wing_p, wing_span, upstrokeOpen(t));

    // Body + head
    var body_p = p_warp;
    body_p.y += sin(t * 1.5) * 0.2;
    let body_dist = griffinBody(body_p);
    let head_dist = griffinHead(body_p);

    // Noise displacement for "shattered chrono-prism" look
    let fractal_depth = u.zoom_params.z;
    let displacement = sin(p_warp.x * 10.0) * sin(p_warp.y * 10.0) * sin(p_warp.z * 10.0) * 0.05 * fractal_depth;

    var d = smin(wing.x, body_dist, 0.2);
    var matId = select(2.0, 1.0, wing.x < body_dist);
    if (head_dist < d) {
        d = smin(d, head_dist, 0.1);
        matId = select(matId, 3.0, head_dist < d + 0.1);
    }
    d += displacement;

    // Facet id of the dominant feather cell rides in .z
    return vec3<f32>(d, matId, wing.y);
}

// ── Idea 3: step-count ambient occlusion (§12.2E) on the surface already marched.
// Five taps of the file's own map() along the normal; slots between primaries, the wing/body seam and the
// head/neck crease read as depth.
fn aoFive(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 1; i <= 5; i = i + 1) {
        let h = 0.01 + 0.12 * f32(i) / 5.0;
        occ += (h - map(p + n * h).x) * sca;
        sca *= 0.5;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var t = 0.0;
    var res = vec3<f32>(-1.0, 0.0, 0.0);
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d.x < 0.001) {
            res = vec3<f32>(t, d.y, d.z);
            break;
        }
        if (t > MAX_DIST) { break; }
        t += d.x;
    }
    return res;
}

// Background rift (volumetric accumulation)
fn getBackgroundRift(rd: vec3<f32>, time: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var p = rd * 5.0;
    for (var i = 1; i <= 4; i++) {
        let fi = f32(i);
        let tmp_x = p.x * cos(time * 0.1) - p.z * sin(time * 0.1);
        let tmp_z = p.x * sin(time * 0.1) + p.z * cos(time * 0.1);
        p.x = tmp_x;
        p.z = tmp_z;
        let noise_val = sin(p.x * fi + time) * cos(p.y * fi) * sin(p.z * fi);
        col += vec3<f32>(0.1, 0.2, 0.5) * max(0.0, noise_val) / fi;
    }
    let bass = plasmaBuffer[0].x;
    col *= (1.0 + bass * 0.5);
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel = vec2<i32>(id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    // R2: y up (HEAD used y-down pixel rows for a y-up scene -> upside-down griffin)
    let uv = vec2<f32>(f32(id.x) - 0.5 * res.x, 0.5 * res.y - f32(id.y)) / res.y;
    let time = u.config.x;

    // R3: front-three-quarter camera; R4: pointer follow in screen space (pointer 0.5,0.5 = centred)
    let mouse = u.zoom_config.yz;
    g_anomaly = POINTER_REACH * (CAM_RIGHT * ((mouse.x - 0.5) * res.x / res.y) + CAM_UP * (0.5 - mouse.y));
    let ro = CAM_POS;
    let rd = normalize(CAM_RIGHT * uv.x + CAM_UP * uv.y + CAM_FWD);

    // Audio (contract: plasmaBuffer[0].xyz only)
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let plasma_glow_multiplier = u.zoom_params.w;
    let fractal_depth = u.zoom_params.z;

    let hit = raymarch(ro, rd);
    let t = hit.x;

    var col = vec3<f32>(0.0);
    var depth = 0.0;
    var matTag = 0.0;

    if (t > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;
        let dot_nv = clamp(dot(n, v), 0.0, 1.0);
        let matId = hit.y;
        matTag = matId;

        // Creature-space + feather-local coordinates at the hit (R5: tints and seams used world p and
        // swam across the creature when the pointer moved).
        let pw = anomalyWarp(p);
        let wl = wingFrame(pw, time * 2.0);
        let fk = clamp(floor(wl.x * 2.0), WING_K_LO, WING_K_HI);
        let fx = wl.x - (fk + 0.5) * 0.5;      // across the vane, 0 on the rachis
        let fz = wl.z - 0.8 * (fk - WING_K_LO) / (WING_K_HI - WING_K_LO);   // along the feather (sweep removed), + toward the tip
        let fHalfW = (0.1 + u.zoom_params.y * 0.1) * 0.74;
        let vane = clamp(abs(fx) / max(fHalfW, 1e-3), 0.0, 1.0);
        let wingMask = select(0.0, 1.0, matId == 1.0);

        // ── Idea 3: step-count AO (§12.2E)
        let ao = aoFive(p, n);

        // Faceted chrono-prism normal: quantize toward facet centers
        let facetN = normalize(floor(n * 6.0) + 0.5);
        let facetHash = hash33(facetN * 3.7).x;

        // 3-point lighting rig
        let keyL = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let fillL = normalize(vec3<f32>(-0.8, 0.2, 0.5));
        let backL = normalize(vec3<f32>(0.0, -0.5, -1.0));
        let diffKey = clamp(dot(facetN, keyL), 0.0, 1.0);
        let diffFill = clamp(dot(n, fillL), 0.0, 1.0);
        let diffBack = clamp(dot(n, backL), 0.0, 1.0);

        // Material-ID driven palettes
        var baseCol = mix(vec3<f32>(0.1, 0.2, 0.8), vec3<f32>(0.5, 0.1, 0.8), pw.y + 0.5);
        baseCol = mix(baseCol, vec3<f32>(0.9, 0.75, 0.3), select(0.0, 1.0, matId == 3.0) * 0.7); // golden head
        baseCol *= 0.8 + facetHash * 0.4; // per-facet albedo variation

        // Plasma gold/magenta wingtips (per-feather cell tint)
        let wingGlow = smoothstep(0.5, 1.5, abs(pw.x)) * wingMask;
        let glowCol = mix(vec3<f32>(1.0, 0.8, 0.1), vec3<f32>(1.0, 0.2, 0.8), sin(time * 2.0 + hit.z * 6.28) * 0.5 + 0.5);
        baseCol = mix(baseCol, glowCol, wingGlow);

        // ── Idea 2: barb vane — chevron barbs rake back from the rachis; vane albedo breathes with them.
        let barbPhase = fz * 18.0 + abs(fx) * 10.0;
        let barb = 0.5 + 0.5 * cos(6.2831853 * barbPhase);
        baseCol *= mix(1.0, 0.72 + 0.4 * barb, wingMask);

        // Tri-tessellated chrono-prism inlay seams on the body/head
        let seamScale = 6.0 + fractal_depth * 14.0;
        let seamD = triGridEdge(pw.xy + pw.z * 0.35, seamScale);
        let seam = (1.0 - smoothstep(0.0, 0.06, seamD)) * select(0.0, 1.0, matId >= 2.0);
        let seamCol = mix(vec3<f32>(0.2, 0.9, 1.0), vec3<f32>(1.0, 0.4, 0.9), facetHash);

        // Lighting accumulation
        col += baseCol * diffKey * (0.5 + 0.5 * mids * plasma_glow_multiplier) * ao;
        col += baseCol.zyx * diffFill * 0.25 * ao;
        col += vec3<f32>(0.3, 0.6, 1.0) * diffBack * 0.2 * ao;
        col += seamCol * seam * plasma_glow_multiplier * (0.6 + treble * 0.6);

        // Blinn-Phong specular on prism facets
        let halfDir = normalize(keyL + v);
        let spec = pow(clamp(dot(facetN, halfDir), 0.0, 1.0), 40.0);
        col += vec3<f32>(0.9, 0.95, 1.0) * spec * (0.4 + facetHash * 0.6);

        // Fresnel plasma rim
        let rim = 1.0 - dot_nv;
        col += glowCol * pow(rim, 3.0) * plasma_glow_multiplier;

        // ── Idea 2: plasma flows along each rachis root -> tip (bass lifts the pulse); rides the existing
        // wingtip plasma tint and plasma_glow, no new colour.
        let rachis = exp(-fx * fx * 3500.0);
        let pulse = pow(max(sin(fz * 6.0 - time * 3.2 - hit.z * 6.2831853), 0.0), 6.0);
        col += glowCol * (rachis * (0.22 + 1.5 * pulse) + 0.35 * pulse * (1.0 - vane) * barb)
               * wingMask * plasma_glow_multiplier * (1.0 + plasmaBuffer[0].x * 0.8);

        // Beak shear glint: treble specular on the head, biased along the beak-forward normal.
        let beakForward = clamp(dot(n, vec3<f32>(0.0, -0.15, -1.0)), 0.0, 1.0);
        let beakGlint = spec * treble * beakForward * select(0.0, 1.0, matId == 3.0);
        col += vec3<f32>(1.0, 0.92, 0.62) * beakGlint;

        // Distance fog into the rift
        // (fog distance is measured from the creature, not the camera: HEAD's camera sat at 3, this one at CAM_DIST)
        let tFog = max(t - (CAM_DIST - 3.0), 0.0);
        col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.05 * tFog * tFog));

        depth = clamp(1.0 - t / MAX_DIST, 0.0, 1.0);
    } else {
        col = getBackgroundRift(rd, time);
    }

    // ACES filmic tonemap (R6: HEAD also applied pow(col, 1/2.2) AFTER ACES — the fit is already display-referred,
    // so that double-encoded and washed the creature to near-white; 426 of 429 ACES generative shaders omit it)
    col = acesToneMap(col * 1.2);

    // Flap ghost: previous display shifted along the flap axis, wings only.
    // y is up now, so the shift sign flips to keep HEAD's relation (ghost trails opposite to the wing motion)
    let flapShift = -i32(sin(time * 2.0) * 12.0);
    let maxPix = vec2<i32>(i32(res.x) - 1, i32(res.y) - 1);
    let ghost = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(0, flapShift), vec2<i32>(0), maxPix), 0).rgb;
    let wingHit = select(0.0, 1.0, t > 0.0 && matTag == 1.0);
    col = mix(col, ghost, wingHit * 0.16);

    // Semantic alpha: rift background stays translucent, the griffin is solid
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + select(0.1, 0.55, t > 0.0), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
}
