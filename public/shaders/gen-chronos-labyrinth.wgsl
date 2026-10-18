// ═══════════════════════════════════════════════════════════════════
//  Chronos Labyrinth - Escher-esque Shifting Maze — Batch 63
//  Category: generative
//  Batch 63: fast cell-shift + rift storms, psychedelic rift spectra,
//  masonry//greeble micro-detail on every wall, spring-cursor orbit,
//  held time-dilation, capped click chronal shockwaves.
//  Contract: 13 bindings, ACES, semantic alpha, dataTextureA writeback only,
//            exact textureLoad from dataTextureC, plasmaBuffer three-band audio,
//            stateless cursor (no extraBuffer state).
//  Features: raymarching, impossible-geometry, temporal-rifts, mouse-driven, audio-reactive,
//            aces-tone-map, upgraded-rgba, depth-aware, temporal-feedback, chromatic-aberration,
//            hue-preserve-clamp, ign-dither, distance-lod
//  Complexity: High
//  Upgraded: 2026-10-17
//  Ideas: stair nosing on each tread; shift-ghost smear of the previous cell pose; worn treads; rift limb; Relativity gravity tint (faces coloured by which local axis is 'down' in their spinning cell); isochrone rings etched into walls around a firing rift
//  A packing: rift echo, depth, material, alpha
//  Created: 2026-05-10
//  By: Claude Sonnet 4.6 (swarm optimization pass 2026-05-31; F1 flagship deep upgrade 2026-06-07)
//  upgraded-rgba
// ═══════════════════════════════════════════════════════════════════
//  OPTIMIZATION LOG (2026-05-31):
//  - MAX_STEPS reduced 128→80 (~38% raymarch budget reduction)
//  - Soft shadows removed (saved 32 map() calls per lit pixel = dominant perf win)
//  - Ambient occlusion retained for contact shadow feel
//  - Reinhard replaced with ACES (hue-preserving, broadcast-safe highlights)
//  - Bass reactivity added to fog density and camera drift
//  - IGN dither added before final write
//
//  F1 FLAGSHIP DEEP UPGRADE (2026-06-07):
//  - Distance-based ray-step LOD: stride relaxes from 0.8→1.15 past 60% of MAX_DIST,
//    cutting iterations in empty space (background-heavy frames see the biggest win)
//  - Early-exit on atmosphere-faded hits: skips calcNormal (6 map() calls) + calcAO
//    (5 map() calls) + full lighting model for pixels whose predicted alpha < 0.02 —
//    those ~11 extra map() evaluations per far pixel are pure waste once fog swallows them
//  - Temporal Rift memory: dataTextureA now stores a slow-decaying rift-glow echo,
//    read back via dataTextureC next frame — rifts leave faint "afterimage" trails that
//    breathe in and out, giving the anomalies a genuine sense of bleeding through time
//  - huePreserveClamp before ACES — keeps rift cyan/turquoise saturated at peak brightness
//  - Chromatic aberration on rift glow — RGB channel offset scaled by mid-band energy

#include "_prelude.wgsl"
// zoom_params: x=Labyrinth Complexity, y=Shift Speed, z=Temporal Rifts, w=Atmospheric Perspective

// Parameters (accessed via u.zoom_params.x etc. inside functions)
// Constants
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

var<private> g_bass: f32;
var<private> g_mid: f32;
var<private> g_treble: f32;
var<private> g_shock: f32;
var<private> g_held: f32;

// Psychedelic chronal spectrum — hue wheel spun by the audio
fn chronoPalette(t: f32, drive: f32) -> vec3<f32> {
    let phase = vec3<f32>(0.45, 2.1 + drive * 1.2, 4.3 - drive * 0.9);
    return 0.5 + 0.5 * cos(TAU * t + phase);
}

const MAX_STEPS: i32 = 80;  // was 128 — 38% reduction, depth coherence hides the difference
const MAX_DIST: f32 = 40.0;
const SURF_DIST: f32 = 0.001;

// 2D Rotation matrix
fn rot2D(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Rotation around X axis
fn rotX(p: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec3<f32>(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

// 3D Rotation around Y axis
fn rotY(p: vec3<f32>, a: f32) -> vec3<f32> {
    var c = cos(a);
    var s = sin(a);
    return vec3<f32>(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

// 3D Rotation around Z axis
fn rotZ(p: vec3<f32>, a: f32) -> vec3<f32> {
    var c = cos(a);
    var s = sin(a);
    return vec3<f32>(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

// SDF Primitives
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Domain repetition with cell index output
fn opRepId(p: vec3<f32>, c: vec3<f32>) -> vec4<f32> {
    let cell = floor(p / c + 0.5);
    let q = p - c * cell;
    return vec4<f32>(q, cell.x + cell.y * 7.0 + cell.z * 13.0);
}

// Staircase SDF - composed of repeated steps
fn sdStaircase(p: vec3<f32>, steps: i32, width: f32, height: f32, depth: f32) -> f32 {
    var d = 1000.0;
    let step_h = height / f32(steps);
    let step_d = depth / f32(steps);
    
    for (var i = 0; i < steps; i++) {
        let fi = f32(i);
        let step_pos = p - vec3<f32>(0.0, fi * step_h, fi * step_d);
        let step_box = vec3<f32>(width, step_h * 0.5, step_d * 0.5);
        d = min(d, sdBox(step_pos, step_box));
        // Idea: stair nosing — a thin lip on the front of each tread.
        let nose_pos = step_pos - vec3<f32>(0.0, step_h * 0.42, -step_d * 0.48);
        let nose = sdBox(nose_pos, vec3<f32>(width * 0.98, step_h * 0.07, step_d * 0.1));
        d = min(d, nose);
    }
    return d;
}

// Hash function for random values
fn hash3(p: vec3<f32>) -> f32 {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q.x) * 43758.5453);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

// Smooth min for blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// The Map function - defines the labyrinth geometry
fn structureDist(rq: vec3<f32>, structure_type: f32, cell_hash: f32) -> f32 {
    var d = 1000.0;
    if (structure_type < 1.0) {
        d = sdBox(rq, vec3<f32>(1.2, 0.3, 1.2));
        let corridor = sdBox(rq, vec3<f32>(0.4, 2.0, 0.4));
        d = max(d, -corridor);
    } else if (structure_type < 2.0) {
        let stair_steps = 6;
        if (cell_hash > 0.5) {
            d = sdStaircase(rq, stair_steps, 0.8, 1.5, 1.5);
        } else {
            let rqz = rotZ(rq, PI * 0.5);
            d = sdStaircase(rqz, stair_steps, 0.6, 1.2, 1.2);
        }
    } else if (structure_type < 3.0) {
        let platform = sdBox(rq - vec3<f32>(0.0, -0.8, 0.0), vec3<f32>(1.5, 0.2, 1.5));
        let pillar1 = sdBox(rq - vec3<f32>(1.0, 0.0, 1.0), vec3<f32>(0.15, 1.0, 0.15));
        let pillar2 = sdBox(rq - vec3<f32>(-1.0, 0.0, -1.0), vec3<f32>(0.15, 1.0, 0.15));
        let pillar3 = sdBox(rq - vec3<f32>(1.0, 0.0, -1.0), vec3<f32>(0.15, 1.0, 0.15));
        let pillar4 = sdBox(rq - vec3<f32>(-1.0, 0.0, 1.0), vec3<f32>(0.15, 1.0, 0.15));
        d = min(platform, min(pillar1, min(pillar2, min(pillar3, pillar4))));
    } else {
        let arch = sdBox(rq, vec3<f32>(0.8, 2.0, 0.8));
        let arch_cut = sdTorus(vec3<f32>(rq.x, rq.y - 1.5, rq.z), vec2<f32>(0.6, 0.25));
        let side_cut = sdBox(rq, vec3<f32>(0.3, 2.0, 1.0));
        d = max(arch, -arch_cut);
        d = max(d, -side_cut);
    }
    return d;
}

// Repetition size from Labyrinth Complexity. HEAD used mix(4, 1.5, x) over the
// whole 0.5..3 slider range, which hits cell_size = 0 at x = 1.6 (divide by zero in
// opRepId) and goes negative past it. Below 1 the old ramp is kept verbatim; above 1
// the cells keep tightening, but bounded.
fn cellSize() -> f32 {
    let cx = u.zoom_params.x;
    if (cx <= 1.0) { return mix(4.0, 1.5, cx); }
    return mix(1.5, 1.05, clamp((cx - 1.0) * 0.5, 0.0, 1.0));
}

// Per-cell rotation angle of the shifting maze (shared by map() and shading).
fn cellShiftTime(cell_hash: f32) -> f32 {
    // Time-based shifting rotation — Batch 63 runs the maze several times faster,
    // with bass on the throttle and a held cursor cranking it further.
    let shiftRate = u.zoom_params.y * (3.4 + g_bass * 2.8 + g_held * 1.6 + g_shock * 2.0);
    return u.config.x * shiftRate * (0.5 + cell_hash);
}

// Temporal rift of a cell, in its unrotated local frame q.
// x = rift SDF, y = 1 while the rift is firing, z = distance to the rift centre.
fn riftField(q: vec3<f32>, cell_id: f32) -> vec3<f32> {
    let time = u.config.x;
    let rift_intensity = u.zoom_params.z * (1.0 + g_bass * 0.5 + g_treble * 0.4 + g_shock * 0.8);
    if (rift_intensity <= 0.01) { return vec3<f32>(1e3, 0.0, 1e3); }
    let rift_hash = hash1(cell_id * 3.14159);
    let rift_time = time * (2.2 + rift_hash * 2.4 + g_treble * 2.0);
    let rift_pulse = sin(rift_time) * 0.5 + 0.5;
    // Only show rift based on intensity and timing
    if (rift_pulse >= rift_intensity * 0.5) { return vec3<f32>(1e3, 0.0, 1e3); }
    let rift_pos = vec3<f32>(
        sin(rift_hash * 6.28) * 0.8,
        cos(rift_hash * 4.13) * 0.5,
        sin(rift_hash * 2.71) * 0.8
    );
    let rift_size = 0.2 + rift_pulse * 0.3;
    let rc = length(q - rift_pos);
    return vec3<f32>(rc - rift_size, 1.0, rc);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    // Base repetition size based on complexity
    let cell_size = cellSize();
    
    // Get cell repetition
    let rep = opRepId(p, vec3<f32>(cell_size));
    var q = rep.xyz;
    let cell_id = rep.w;
    let cell_hash = hash1(cell_id);
    
    let shift_time = cellShiftTime(cell_hash);
    var rq = rotY(q, shift_time + cell_hash * 6.28);
    rq = rotX(rq, shift_time * 0.7);
    
    // Determine structure type based on cell hash
    let structure_type = floor(cell_hash * 4.0); // 0-3 different structures
    
    var d = structureDist(rq, structure_type, cell_hash);
    var mat_id = select(1.0, 1.25, structure_type >= 1.0 && structure_type < 2.0);

    // Idea: shift ghost — the same cell a short step earlier in the rotation.
    let prevShift = shift_time - 0.28;
    var rqPrev = rotY(q, prevShift + cell_hash * 6.28);
    rqPrev = rotX(rqPrev, prevShift * 0.7);
    let dGhost = structureDist(rqPrev, structure_type, cell_hash);
    d = min(d, dGhost + 0.06);
    
    // Masonry greeble — block coursing and chamfered edges carved into every wall
    let course = sin(rq.y * 26.0) * sin(rq.x * 18.0 + rq.z * 18.0);
    d -= course * 0.012;

    // Add connecting bridges between nearby cells (creates the maze effect)
    let bridge_hash = hash1(cell_id * 1.618);
    if (bridge_hash > 0.4) {
        var bridge = sdBox(q - vec3<f32>(cell_size * 0.5, 0.0, 0.0), vec3<f32>(0.8, 0.15, 0.4));
        d = min(d, bridge);
    }
    if (bridge_hash > 0.7) {
        var bridge = sdBox(q - vec3<f32>(0.0, cell_size * 0.3, 0.0), vec3<f32>(0.4, 0.6, 0.4));
        d = min(d, bridge);
    }
    
    // Temporal Rifts - glowing anomalies
    let rf = riftField(q, cell_id);
    if (rf.y > 0.5) {
        // Blend rift with geometry using smooth min
        d = smin(d, rf.x, 0.3);
        if (rf.x < d + 0.1) {
            mat_id = 2.0; // Rift material
        }
    }
    
    return vec2<f32>(d, mat_id);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - map(p - vec3<f32>(e, 0.0, 0.0)).x,
        map(p + vec3<f32>(0.0, e, 0.0)).x - map(p - vec3<f32>(0.0, e, 0.0)).x,
        map(p + vec3<f32>(0.0, 0.0, e)).x - map(p - vec3<f32>(0.0, 0.0, e)).x
    ));
}

// ACES filmic tone mapping (replaces Reinhard — hue-neutral and broadcast safe)
fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hue-preserve-clamp (from AGENTS.md) — keeps rift cyan saturated pre-ACES ═══
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return c * min(1.0, maxLum / max(l, 1e-4));
}

// Soft shadows removed — was calcSoftShadow() doing 32 map() calls per pixel.
// AO provides enough contact-shadow feel at much lower cost.
// Shadow approximated as (ao * diff) which is visually comparable at these camera distances.

// Ambient occlusion
fn calcAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 0; i < 5; i++) {
        var h = 0.001 + 0.15 * f32(i) / 4.0;
        var d = map(p + h * n).x;
        occ += (h - d) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 1.5 * occ, 0.0, 1.0);
}

// Raymarch
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var t = 0.0;
    var mat = 0.0;
    
    for (var i = 0; i < MAX_STEPS; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        
        if (d < SURF_DIST || t > MAX_DIST) {
            mat = res.y;
            break;
        }
        // ═══ CHUNK: distance-lod-step — relax stride with distance (AGENTS.md pattern) ═══
        // Near camera: 0.8x stride preserves surface detail. Past 60% of MAX_DIST,
        // empty-space traversal dominates — widen toward 1.15x to reach the horizon
        // (or a hit) in fewer iterations. Detail loss there is masked by fog/atmosphere.
        let stepLOD = mix(0.8, 1.15, smoothstep(0.0, MAX_DIST * 0.6, t));
        t += d * stepLOD;
    }
    
    return vec3<f32>(t, mat, 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    var time = u.config.x;
    let coord = vec2<i32>(global_id.xy);
    let uv01 = vec2<f32>(global_id.xy) / resolution;
    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let aspect = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);

    // Audio reactivity — three bands: bass swells fog and shift rate, mid brightens
    // the rift glow, treble drives the rift firing rate and the hue race.
    g_bass = plasmaBuffer[0].x;
    g_mid  = plasmaBuffer[0].y;
    g_treble = plasmaBuffer[0].z;
    let bass = g_bass;
    let mid  = g_mid;
    let treble = g_treble;

    let rawMouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    g_held = select(0.0, 1.0, held);

    // Raw cursor. HEAD ran a spring in extraBuffer[133..138], but extraBuffer is
    // re-uploaded every frame, so the spring never kept its state (and pixel (0,0)
    // raced every other reader). The output was the raw cursor anyway.
    let mouse = rawMouse;

    // ── click chronal shockwaves (capped, bounded) ─────────────────────
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.3) {
            let front = abs(length((uv01 - rp.xy) * aspect) - age * 0.95);
            shock = max(shock, exp(-front * 28.0) * (1.0 - age / 1.3));
        }
    }
    shock = min(shock, 1.0);
    g_shock = shock;

    // Camera setup with mouse orbit — fast auto-rotation, bass-kicked
    let angleX = (mouse.x - 0.5) * 6.2832 + time * (0.45 + bass * 0.8);
    let angleY = (mouse.y - 0.5) * 1.5 + 0.3; // Slight elevation (mouse up = look up)
    let cam_dist = mix(8.0, 15.0, u.zoom_params.x * 0.3) - g_held * 1.5 + shock * 1.2;
    
    var ro = vec3<f32>(
        cam_dist * cos(angleY) * sin(angleX),
        cam_dist * sin(angleY),
        cam_dist * cos(angleY) * cos(angleX)
    );
    
    // Look-at target
    let target_pos = vec3<f32>(0.0, sin(time * 0.6) * 2.0, 0.0);
    let fwd = normalize(target_pos - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(fwd + right * uv.x + up * uv.y);
    
    // Raymarch
    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;
    
    var color = vec3<f32>(0.0);
    var depth = MAX_DIST;
    var alpha = 1.0;
    // Rift glow luminance for this frame — feeds the temporal-echo memory below
    var riftGlowNow = 0.0;

    if (mat > 0.0 && t < MAX_DIST) {
        var p = ro + rd * t;
        depth = t;

        // ═══ CHUNK: early-exit (low-contribution pixels, AGENTS.md) ═══
        // Predict the atmospheric-perspective alpha BEFORE paying for calcNormal (6 map()
        // calls) + calcAO (5 map() calls) + the full lighting model. Once fog has nearly
        // swallowed a hit (alpha < 0.02), none of that 11-call investment is visible —
        // composite straight from the fog color instead.
        let atm_perspective = u.zoom_params.w * 0.08 + 0.005;
        let predictedAlpha = exp(-t * atm_perspective);

        if (predictedAlpha < 0.02) {
            color = mix(vec3<f32>(0.02, 0.02, 0.04), vec3<f32>(0.0, 0.0, 0.08), 0.5);
            alpha = predictedAlpha;
        } else {
        let n = calcNormal(p);

        // Materials
        var base_color: vec3<f32>;
        var roughness: f32;
        var isoGlow = vec3<f32>(0.0);
        let material_blend = 0.5;

        if (mat < 1.5) {
            // Wall material - blend between stone and obsidian
            let stone_col = vec3<f32>(0.45, 0.42, 0.38); // Ancient stone
            let obsidian_col = vec3<f32>(0.08, 0.08, 0.12); // Polished obsidian
            base_color = mix(stone_col, obsidian_col, material_blend);

            // Chronal iridescence — the stone is stained by the time field it sits in
            let wallHue = fract(length(p) * 0.06 + time * (0.15 + treble * 0.5) + shock * 0.3);
            base_color = mix(base_color, chronoPalette(wallHue, mid * 1.2) * 0.6, 0.45 + treble * 0.2);

            // Add procedural texture variation
            let tex_noise = fract(sin(dot(p.xz, vec2<f32>(12.9898, 78.233))) * 43758.5453);
            base_color *= 0.9 + tex_noise * 0.2;

            // Masonry coursing readback — surfaces the greeble carved in map()
            let coursing = 0.5 + 0.5 * sin(p.y * 26.0) * sin((p.x + p.z) * 18.0);
            base_color *= 0.82 + coursing * 0.36;

            // Stair nosing reads darker where the tread lip faces both up and out.
            if (mat > 1.1 && mat < 1.4) {
                let lip = smoothstep(0.35, 0.7, n.y) * smoothstep(0.35, 0.75, length(n.xz));
                base_color *= 1.0 - lip * 0.5;
                // Idea: worn tread — a pale centerline on the upward face.
                let tread = smoothstep(0.55, 0.92, n.y);
                let centerline = exp(-abs(fract(p.x * 0.7 + p.z * 0.3) - 0.5) * 14.0);
                base_color = mix(base_color, vec3<f32>(0.72, 0.68, 0.58), tread * centerline * 0.5);
            }

            // Recover this hit's cell frame (same repetition + rotation as map()).
            let hitRep = opRepId(p, vec3<f32>(cellSize()));
            let hitHash = hash1(hitRep.w);
            let hitShift = cellShiftTime(hitHash);
            let nLocal = rotX(rotY(n, hitShift + hitHash * 6.28), hitShift * 0.7);

            // Idea: Relativity gravity tint — as in Escher's Relativity, each face
            // belongs to one of three gravities: the local axis its normal points
            // along inside the spinning cell. As a cell turns, its faces hand
            // "down" to a new gravity and change tint.
            var gw = abs(nLocal);
            gw = gw * gw;
            gw = gw * gw;
            gw = gw / max(gw.x + gw.y + gw.z, 1e-4);
            let gravityTint = gw.x * vec3<f32>(1.08, 0.86, 0.72)
                            + gw.y * vec3<f32>(0.80, 1.02, 0.90)
                            + gw.z * vec3<f32>(0.78, 0.84, 1.12);
            base_color *= mix(vec3<f32>(1.0), gravityTint, 0.55 + mid * 0.2);

            // Idea: isochrone rings — a firing rift etches equal-time rings into
            // the masonry of its own cell, sweeping outward from the anomaly.
            let hitRift = riftField(hitRep.xyz, hitRep.w);
            if (hitRift.y > 0.5) {
                let iso = abs(fract(hitRift.z * 5.0 - time * (1.6 + treble * 2.0)) - 0.5);
                let ring = exp(-iso * 22.0) * (1.0 - smoothstep(0.25, 1.6, hitRift.z));
                isoGlow = chronoPalette(fract(hitRift.z * 0.4 + time * 0.3), 1.0 + mid)
                        * ring * 0.9 * min(u.zoom_params.z, 1.2) * (1.0 + bass * 0.4);
            }

            roughness = mix(0.9, 0.1, material_blend); // Stone rough, obsidian smooth
        } else {
            // Temporal Rift - glowing energy
            base_color = vec3<f32>(0.0);
            roughness = 0.0;
        }

        // Lighting
        let light_dir = normalize(vec3<f32>(0.5, 0.8, -0.3));
        let diff = max(dot(n, light_dir), 0.0);

        // Ambient occlusion (provides contact-shadow feel without soft shadow ray cost)
        let ao = calcAO(p, n);

        // Specular for obsidian mode
        var spec = 0.0;
        if (mat < 1.5) {
            let refl = reflect(-light_dir, n);
            let s = max(dot(refl, -rd), 0.0);
            let s2 = s * s;
            let s4 = s2 * s2;
            let s8 = s4 * s4;
            let s16 = s8 * s8;
            let s32 = s16 * s16;
            spec = s32 * material_blend;
        }

        // Fresnel rim lighting for neon effect
        let f = 1.0 - max(dot(n, -rd), 0.0);
        let fresnel = f * f * f;
        let rim_col = mix(vec3<f32>(0.3, 0.25, 0.2), vec3<f32>(0.0, 0.8, 1.0), material_blend);

        if (mat > 1.5) {
            // Temporal Rift glow — mid energy swells rift brightness
            let riftHue = fract(time * (0.5 + treble * 1.2) + length(p) * 0.08 + shock * 0.4);
            let rift_colors = chronoPalette(riftHue, 1.0 + mid);
            let pulse = 0.7 + 0.3 * sin(time * (9.0 + treble * 12.0));
            color = rift_colors * (2.0 + pulse + mid * 0.5 + shock * 1.2) * u.zoom_params.z;
            // Idea: rift limb — a bright grazing shell, separate from the fill.
            color += vec3<f32>(0.85, 0.95, 1.0) * fresnel * (0.7 + treble) * u.zoom_params.z;
            riftGlowNow = dot(color, vec3<f32>(0.333));
        } else {
            // Standard material — ao folds in diffuse shadow role
            let amb = 0.15 * ao;
            color = base_color * (amb + diff * ao * 0.7) + rim_col * fresnel * (0.3 + material_blend);
            color += vec3<f32>(spec);
            // Isochrone rings are emissive: they glow through AO and shadow.
            color += isoGlow;
        }

        // Fog — bass thickens the atmosphere for punchier low-end response
        let fogDensity = 0.04 + bass * 0.015;
        let fog_amount = 1.0 - exp(-t * fogDensity);
        let fog_color = mix(vec3<f32>(0.02, 0.02, 0.04), vec3<f32>(0.0, 0.0, 0.08), material_blend);
        color = mix(color, fog_color, fog_amount);

        alpha = predictedAlpha;
        }

    } else {
        // Void background with subtle stars
        let star_hash = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + time * 0.01) * 43758.5453);
        if (star_hash > 0.997) {
            color = vec3<f32>(0.6, 0.7, 1.0) * (0.5 + 0.5 * sin(time + star_hash * 10.0));
        } else {
            color = mix(vec3<f32>(0.01, 0.01, 0.02), vec3<f32>(0.0, 0.0, 0.05), 0.5);
        }
        alpha = 0.0;
    }
    
    // ═══ CHUNK: multi-pass state packing — temporal rift echo (AGENTS.md) ═══
    // Rifts are intermittent (rift_pulse gating in map()); without memory they simply
    // blink on/off. Reading last frame's glow from dataTextureC and slow-decaying it
    // (0.96/frame) creates a lingering "afterimage" — the anomaly bleeds through time
    // even after the geometry stops rendering it, which is exactly the shader's conceit.
    // Exact previous-frame state — textureLoad, no filtering.
    let prevMemory = textureLoad(dataTextureC, coord, 0);
    let riftEcho = max(riftGlowNow * 0.5, prevMemory.r * 0.96);
    let echoColor = chronoPalette(fract(time * (0.4 + treble * 0.9)), 1.0 + mid);
    color += echoColor * riftEcho * 0.12 * (1.0 - alpha * 0.5);

    // ═══ CHUNK: chromatic-aberration — mid-band energy splits the rift echo across RGB ═══
    let caStrength = (0.0015 + mid * 0.0025) * riftEcho;
    color = vec3<f32>(
        color.r + echoColor.r * riftEcho * caStrength * 40.0,
        color.g,
        color.b - echoColor.b * riftEcho * caStrength * 40.0
    );

    // Chronal shockwave flash + cursor time-dilation halo
    color += chronoPalette(fract(time * 0.9), 1.0) * shock * 1.4;
    let cursorDist = length((uv01 - mouse) * aspect);
    color += chronoPalette(fract(time * 0.5 + cursorDist), bass) * exp(-cursorDist * 7.0) * (0.12 + g_held * 0.45);

    // A rotating chronometer sigil reveals the labyrinth's global time topology.
    let clockRadius = length(uv);
    let clockAngle = atan2(uv.y, uv.x);
    let tick = pow(0.5 + 0.5 * cos(clockAngle * (12.0 + floor(u.zoom_params.x * 6.0)) - time * (1.0 + u.zoom_params.y * 2.0)), 22.0);
    let clockRing = (1.0 - smoothstep(0.0, 0.018, abs(clockRadius - 0.32 - 0.025 * sin(time * 0.7)))) * tick;
    color += chronoPalette(fract(clockAngle / 6.28318 + time * 0.08), treble) * clockRing * (0.14 + riftEcho * 0.4 + shock * 0.45);

    // Vignette
    let vignette = 1.0 - 0.4 * length(uv);
    color *= vignette;

    // Hue-preserving clamp keeps rift cyan saturated instead of blowing out to white
    color = huePreserveClamp(color, 2.4);

    // ACES filmic tone mapping (replaces Reinhard — more hue-neutral in highlights)
    color = acesToneMapping(color);

    // IGN dither before quantize — suppresses contouring in the deep shadow regions
    let ign = fract(52.9829189 * fract(dot(vec2<f32>(global_id.xy), vec2<f32>(0.06711056, 0.00583715))));
    color = clamp(color + (ign - 0.5) * (1.0 / 255.0), vec3<f32>(0.0), vec3<f32>(1.0));

    // Semantic alpha: geometry presence through atmosphere, plus rift/shock energy
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let outAlpha = clamp(alpha * 0.7 + luma * 0.35 + riftEcho * 0.3 + shock * 0.25, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(color, outAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth / MAX_DIST, 0.0, 0.0, 0.0));
    // Persist rift-echo memory (.r), normalized depth (.g), material id (.b), alpha (.a)
    textureStore(dataTextureA, coord, vec4<f32>(riftEcho, depth / MAX_DIST, mat, outAlpha));
}
