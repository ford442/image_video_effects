// ═══════════════════════════════════════════════════════════════════
//  Ethereal Quantum-Medusa
//  Category: generative
//  Features: raymarched, audio-reactive, mouse-gravity-well, feedback-loops,
//            upgraded-rgba, chromatic-tentacles, temporal-bioluminescence,
//            audio-sway, depth-output, gravity-attractor, mouse-trail
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-11-19
//  Ideas: nematocyst stinger dots along tentacle rim from edge SDF; bell contraction wave from radial phase tied to bass;
//         peristaltic pulse travelling down the existing tentacle column (swells the radius, gates the stingers);
//         8-fold radial canals on the bell brightening with the contraction phase; click rings fixed-strength (ripple.w is always 0);
//         8 helical marginal tentacles from the bell rim (curl-twisted, peristaltic swell); mesoglea translucency from inner-field thickness
//  Rescued 2026-11-19: upside-down image; xy-tilted infinite column drew screen-wide streaks; 1/r² mouse well shredded the SDF at default (blank); bell framed tiny
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

const MAX_STEPS: i32 = 72;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;
// The whole medusa sits within ~4 units of the camera target; misses stop here instead of at 100.
const MARCH_FAR: f32 = 11.0;

fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── Mouse gravity well + attractor ───
// Rescue: HEAD's 1/r² push (with normalize at r→0) tore the distance field apart whenever the
// pointer sat on the medusa (it does by default), so only stray streaks rendered. Both forces are
// now a bounded Gaussian displacement, so the field stays marchable.
fn applyMouseGravity(p: vec3<f32>, mouse_pos: vec3<f32>, strength: f32) -> vec3<f32> {
    let dv = p - mouse_pos;
    return p + dv * strength * 0.22 * exp(-dot(dv, dv) * 0.8);
}

fn applyMouseAttractor(p: vec3<f32>, mouse_pos: vec3<f32>, attract: f32) -> vec3<f32> {
    let dv = p - mouse_pos;
    return p - dv * attract * 0.12 * exp(-dot(dv, dv) * 0.3);
}

// Idea 3rd-pass A: eight marginal tentacles hang from the bell rim (the 8-fold sector index HEAD
// computed but never used). Curl twists them into helices; the peristaltic swell rides them too.
fn marginalTentacles(p: vec3<f32>, time: f32, curl: f32, swell: f32) -> f32 {
    let tw = rot2D(time * 0.5 + p.y * curl * 0.35) * p.xz;
    let sector = TAU / 8.0;
    let a = atan2(tw.y, tw.x);
    let fa = (fract(a / sector + 0.5) - 0.5) * sector;
    let rr = length(tw);
    let q = vec2<f32>(rr * cos(fa) - 0.78, rr * sin(fa));
    let taper = clamp(1.0 + p.y * 0.22, 0.15, 1.0);
    let cyl = length(q) - 0.055 * taper * swell;
    return max(max(cyl, p.y + 0.05), -p.y - 3.6);
}

// Idea 2nd-pass A: the bell's contraction phase continued down the column, lagged by depth.
// Crests travel from the bell toward the tentacle tips as time grows.
fn columnPulse(y: f32, time: f32, bass: f32) -> f32 {
    return sin(-y * 5.0 - time * 2.2 - bass * 4.5);
}

fn map(p: vec3<f32>, time: f32, bass: f32, mids: f32) -> vec2<f32> {
    var p1 = p;

    // Mouse in 3D: screen-top (zoom_config.z=0) = +Y/up (now true: rd.y is flipped in main)
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 3.2, (0.5 - u.zoom_config.z) * 3.2, 0.0);

    // Gravity well repulsion + attractor dual force
    let heldGain = mix(0.25, 1.0, clamp(u.zoom_config.w, 0.0, 1.0));
    let repulse_strength = u.zoom_params.w * 3.0 * heldGain;
    let attract_strength = u.zoom_params.w * 1.5 * heldGain;
    p1 = applyMouseGravity(p1, mouse_pos, repulse_strength);
    p1 = applyMouseAttractor(p1, mouse_pos, attract_strength);

    // Audio-reactive tentacle sway with feedback memory
    let sway = sin(time * 0.5 + p1.y * 2.0) * 0.1 * (1.0 + mids * 0.5);
    let sway_bass = cos(time * 0.3 + p1.x * 1.5) * 0.05 * bass;
    p1.x += sway + sway_bass;
    p1.z += sway_bass * 0.5;

    var p_bell = p1;
    // Bell contraction wave from radial phase tied to bass
    let bellRadius = length(p_bell.xz);
    let contractPhase = bellRadius * 7.5 - time * 2.2 - bass * 4.5;
    let contractWave = sin(contractPhase) * 0.14 * (1.0 + bass * 0.45);
    p_bell.y += sin(time + bellRadius) * 0.2 * (1.0 + bass * 0.3) - contractWave;
    let bellScale = 1.0 + contractWave * 0.35;
    p_bell.x *= bellScale;
    p_bell.z *= bellScale;
    let bell = length(p_bell * vec3<f32>(1.0, 2.0, 1.0)) - 1.0;

    // Rescue: HEAD rotated the column in the xy plane, tipping an infinite cylinder sideways into
    // screen-wide streaks. Curl now twists the column about its own axis (a spiral oral arm),
    // capped below the bell.
    var p_tent = p1;
    let p_tent_xz = rot2D(time * 0.5 + p_tent.y * u.zoom_params.y) * p_tent.xz - vec2<f32>(0.14, 0.0);
    p_tent.x = p_tent_xz.x;
    p_tent.z = p_tent_xz.y;
    // Idea 2nd-pass A: peristaltic swell of the existing column below the bell
    let colEnv = smoothstep(0.3, -0.4, p1.y);
    let colSwell = 1.0 + (0.3 + bass * 0.12) * columnPulse(p1.y, time, bass) * colEnv;
    let tentacles = max(max(length(p_tent.xz) - 0.1 * (1.0 - p_tent.y * 0.1) * colSwell, p1.y - 0.1), -p1.y - 2.6);

    let marginal = marginalTentacles(p1, time, u.zoom_params.y, colSwell);
    let d = min(smin(bell, tentacles, 0.5), smin(bell, marginal, 0.12));
    return vec2<f32>(d, 1.0);
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, bass: f32, mids: f32) -> vec2<f32> {
    var dO = 0.0;
    var mat = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p, time, bass, mids);
        dO += dS.x * 0.6; // twisted / swollen fields are not 1-Lipschitz
        mat = dS.y;
        if(dO > MARCH_FAR || abs(dS.x) < SURF_DIST) { break; }
    }
    return vec2<f32>(dO, mat);
}

fn getNormal(p: vec3<f32>, time: f32, bass: f32, mids: f32) -> vec3<f32> {
    let d = map(p, time, bass, mids).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy, time, bass, mids).x,
        map(p - e.yxy, time, bass, mids).x,
        map(p - e.yyx, time, bass, mids).x
    );
    return normalize(n);
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
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }
    // Rescue: texel y grows downward, so HEAD hung the tentacles off the top of the bell.
    var uv = (vec2<f32>(id.xy) * 2.0 - res) / res.y;
    uv.y = -uv.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x * clamp(u.zoom_params.x, 0.1, 5.0);

    let ro = vec3<f32>(0.0, -0.9, -4.6); // rescue: HEAD framed the bell at ~20% of the height
    let rd = normalize(vec3<f32>(uv, 1.0));

    let rm = raymarch(ro, rd, time, bass, mids);
    let d = rm.x;

    var col = vec3<f32>(0.02, 0.01, 0.05);
    var hit = 0.0;
    var fresnel = 0.0;

    // Feedback loop: read previous frame glow accumulation
    let coord = vec2<i32>(id.xy);
    let prevFrame = textureLoad(dataTextureC, coord, 0);
    let prevGlow = prevFrame.a;

    if (d < MARCH_FAR) {
        hit = 1.0;
        let p = ro + rd * d;
        let n = getNormal(p, time, bass, mids);
        let viewDir = -rd;
        fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        let glow = clamp(bass * u.zoom_params.z * 1.5 + 0.2, 0.0, 1.0);

        // Chromatic tentacle separation: R core, B tips, G mid
        let distFromCore = length(p.xz);
        let coreFactor = exp(-distFromCore * 2.0);
        let tipFactor = smoothstep(0.5, 2.0, distFromCore);
        let rCol = mix(vec3<f32>(0.1, 0.5, 0.8), vec3<f32>(0.9, 0.3, 0.2), coreFactor);
        let bCol = mix(vec3<f32>(0.1, 0.5, 0.8), vec3<f32>(0.2, 0.3, 0.9), tipFactor);
        col = mix(rCol, bCol, 0.5) * (1.0 - fresnel);

        // Idea 3rd-pass B: mesoglea translucency — probe the field one step inside the surface;
        // thin jelly (bell margin, tentacles) lets the bioluminescence through, the thick crown stays dense.
        let inner = -map(p - n * 0.22, time, bass, mids).x;
        let thinness = 1.0 - smoothstep(0.0, 0.2, inner);
        col += vec3<f32>(0.35, 0.75, 1.0) * thinness * (0.25 + 0.35 * clamp(bass * u.zoom_params.z, 0.0, 1.5)) * (0.4 + 0.6 * fresnel);
        col += vec3<f32>(0.2, 0.9, 0.8) * glow * (1.0 - fresnel);

        // Mouse-proximity chromatic boost
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 3.2, (0.5 - u.zoom_config.z) * 3.2, 0.0);
        let mouse_dist = length(p - mouse_pos);
        let mouse_prox = exp(-mouse_dist * 2.0);
        col += vec3<f32>(0.5, 0.1, 0.3) * mouse_prox * bass * 2.0;

        // Temporal bioluminescence pulse memory with feedback
        let prevGlow2 = prevFrame.a;
        let pulseMemory = mix(glow, prevGlow2 * 0.92, 0.15 + bass * 0.05);
        col += vec3<f32>(0.3, 0.7, 0.6) * pulseMemory * fresnel;

        // Audio trail feedback: accumulate bass-driven color in feedback buffer
        let trailColor = vec3<f32>(0.6, 0.2, 0.8) * bass * mouse_prox;
        col += trailColor * 0.5;

        // Nematocyst stinger dots along tentacle rim from edge SDF
        let rimDist = length(p.xz);
        let tentRim = smoothstep(0.12, 0.32, rimDist) * smoothstep(2.2, 0.7, rimDist) * smoothstep(0.4, -0.1, p.y);
        let rimAngle = atan2(p.z, p.x);
        let stingerGrid = fract(rimAngle / TAU * 8.0 * 10.0 + p.y * 7.0 + time * 0.15);
        let stingers = tentRim * smoothstep(0.9, 0.94, stingerGrid) * smoothstep(0.98, 0.95, stingerGrid);
        // Idea 2nd-pass A: stingers flare as the peristaltic crest passes
        let pulseGate = 0.5 + 0.5 * columnPulse(p.y, time, bass);
        col += vec3<f32>(0.88, 0.95, 1.0) * stingers * (0.55 + treble * 0.25) * mix(0.4, 1.4, pulseGate);

        // Idea 2nd-pass B: 8-fold radial canals on the bell, brightening with the contraction phase
        let canalPhase = rimDist * 7.5 - time * 2.2 - bass * 4.5;
        let canalLine = smoothstep(0.86, 0.99, cos(rimAngle * 8.0));
        let canalMask = smoothstep(0.1, 0.3, rimDist) * smoothstep(1.2, 0.8, rimDist) * smoothstep(-0.05, 0.12, p.y);
        let canalBeat = 0.3 + 0.7 * (0.5 + 0.5 * sin(canalPhase));
        col += vec3<f32>(0.2, 0.85, 1.0) * canalLine * canalMask * canalBeat * 0.45;
    }

    // Feedback loop: blend with previous frame for motion trails
    col = mix(col, prevFrame.rgb * 0.95, 0.08 + bass * 0.03);

    let rippleCount = min(i32(u.config.y), 50);
    for (var i = 0; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age > 0.0 && age < 2.5) {
            let radius = age * 0.32;
            let ring = exp(-abs(distance(vec2<f32>(id.xy) / res, ripple.xy) - radius) * 100.0) * exp(-age * 1.8) * 0.7;
            col += vec3<f32>(0.25, 0.9, 1.0) * ring * (0.5 + treble);
        }
    }

    let lumaOut = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(hit * (0.5 + fresnel * 0.4) + lumaOut * 0.2 + 0.05, 0.0, 1.0);
    col = acesToneMap(col * 1.1);
    let packed = vec4<f32>(col, alpha);
    textureStore(writeTexture, coord, packed);

    let depth = select(1.0, clamp(d / MAX_DIST, 0.0, 1.0), d < MARCH_FAR);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, packed);
}
