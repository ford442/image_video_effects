// ═══════════════════════════════════════════════════════════════════
//  Chronodynamic Aether-Weaver Automata
//  Category: generative
//  Features: temporal, chromatic, depth-aware, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: gear-tooth automaton ring (each tooth is a Rule 90 cell, one generation per tooth pitch, the meshing teeth trade bits so sun and planet compute together); capstan wrap (aether threads swirl onto the rotating gear rims along the gear SDF and show wound turns riding the rim)
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read back exactly as HDR colour for echo trails and chromatic smear
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseHeld
    zoom_params: vec4<f32>,  // x=Thread Count, y=Loom Rotation Speed, z=Aether Bloom, w=Temporal Decay
    ripples: array<vec4<f32>, 50>,
};
// Math and Hash Functions
fn hash12(p: vec2<f32>) -> f32 {
    let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q.x) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - vec2<f32>(2.0) * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn rot2d(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdGear(p: vec2<f32>, radius: f32, teeth: f32, toothDepth: f32) -> f32 {
    let r = length(p);
    let a = atan2(p.y, p.x);
    let f = radius + toothDepth * cos(a * teeth);
    return r - f;
}

const TAU: f32 = 6.28318530718;
// Planet gear arm: its centre sits at (1.2, 0.5) in the arm frame (HEAD placement, verbatim).
const PLANET_BETA: f32 = 0.39479112;   // atan2(0.5, 1.2): arm-frame direction of the planet centre
const PLANET_PHI0: f32 = -3.73587137;  // self-spin phase so a planet gap faces a sun tooth at the mesh
const CA_EPOCH: i32 = 24;              // generations between fresh seeds punched in at the mesh

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn imod(a: i32, n: i32) -> i32 {
    return ((a % n) + n) % n;
}

// Idea 1: one Rule 90 step on a cyclic ring of n teeth (bit k = tooth k lit).
fn rule90(s: u32, n: u32) -> u32 {
    let m = (1u << n) - 1u;
    let l = ((s << 1u) | (s >> (n - 1u))) & m;
    let r = ((s >> 1u) | (s << (n - 1u))) & m;
    return l ^ r;
}

// Idea 1: the two tooth rings at generation g (x = sun, 12 teeth; y = planet, 8 teeth).
// A generation is one tooth pitch of rotation. Each epoch starts from one lit sun tooth at the mesh;
// every generation both rings take a Rule 90 step and the meshing teeth trade a bit: the sun's contact
// tooth is XORed into the planet's contact tooth, the planet tooth that just left the mesh into the sun's.
// Stateless: at most CA_EPOCH-1 uniform bit steps per invocation.
fn toothAutomaton(g: i32) -> vec2<u32> {
    let g0 = g - imod(g, CA_EPOCH);
    var s1 = 1u << u32(imod(g0, 12));
    var s2 = 0u;
    let steps = g - g0;
    for (var n: i32 = 0; n < CA_EPOCH; n++) {
        if (n >= steps) { break; }
        let h = g0 + n;
        let j1 = u32(imod(h, 12));
        let j2 = u32(imod(-h, 8));
        let b1 = (s1 >> j1) & 1u;
        let b2 = (s2 >> ((j2 + 1u) % 8u)) & 1u;
        s1 = rule90(s1, 12u);
        s2 = rule90(s2, 8u);
        s2 = s2 ^ (b1 << j2);
        s1 = s1 ^ (b2 << j1);
    }
    return vec2<u32>(s1, s2);
}

// Idea 1: tooth index nearest a gear-local angle, and a crown mask that is 1 at the tooth tip.
fn toothIndex(a: f32, teeth: f32) -> u32 {
    return u32(imod(i32(floor(a * teeth / TAU + 0.5)), i32(teeth)));
}

fn toothCrown(a: f32, teeth: f32) -> f32 {
    return pow(max(cos(a * teeth), 0.0), 4.0);
}

// Idea 2: capstan wrap. Rotate the thread lookup about a gear centre by an angle that peaks on the
// gear's own SDF contour (band = exp(-|d|/w)), so threads crossing the rim are dragged around it.
fn capstanWrap(p: vec2<f32>, centre: vec2<f32>, band: f32, turn: f32) -> vec2<f32> {
    return centre + (p - centre) * rot2d(turn * band);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) {
        return;
    }

    let uv = vec2<f32>(coords) / res;
    let aspect = res.x / res.y;
    var p = (uv - vec2<f32>(0.5)) * 2.0;
    p.x *= aspect;

    let time = u.config.x;

    // Audio analysis: plasmaBuffer[0] = (bass, mids, treble). HEAD read u.config.y (ripple count) as audio.
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = bass;

    // Mouse Interaction
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    var mouse_p = (mouse - vec2<f32>(0.5)) * 2.0;
    mouse_p.x *= aspect;

    // Temporal Decay parameter
    let temporal_decay = u.zoom_params.w;

    // Chrono-Distortion Ripples from Mouse
    var distorted_p = p;
    let dist_to_mouse = length(p - mouse_p);

    // Held pointer pulls space in (HEAD tested mouse.x > 0 && mouse.y > 0, which is always true).
    if (u.zoom_config.w > 0.5) {
        let pull = exp(-dist_to_mouse * 5.0) * 0.5 * sin(time * 5.0);
        distorted_p = mix(distorted_p, mouse_p, pull);
    } else {
        let bend = exp(-dist_to_mouse * 2.0) * 0.1;
        distorted_p += normalize(p - mouse_p + vec2<f32>(0.001)) * bend;
    }

    // Loom Architecture (Gears): Background massive slow-rotating gears.
    // time * speed (HEAD) is kept: moving the slider re-phases the stateless clock (documented).
    let rotation_speed = u.zoom_params.y;
    let a1 = time * rotation_speed * 0.1;
    let a2 = -time * rotation_speed * 0.15 + 1.0;
    // Idea 1 mesh: the planet rides the HEAD arm (same orbit) and now also rolls on the sun without slip
    // (12:8 teeth), phased so its gaps take the sun's teeth; one tooth pitch = one automaton generation.
    let spin2 = 1.5 * (a2 - a1) + PLANET_PHI0;
    let gear_uv = distorted_p * rot2d(a1);
    let d1 = sdGear(gear_uv, 0.8, 12.0, 0.1);
    let planet_uv = (distorted_p * rot2d(a2) - vec2<f32>(1.2, 0.5)) * rot2d(spin2);
    let d2 = sdGear(planet_uv, 0.5, 8.0, 0.08);
    let planet_centre = vec2<f32>(1.2, 0.5) * rot2d(-a2);

    // Idea 1: gear-tooth automaton ring. u1 counts sun teeth that have passed the mesh.
    let u1 = (PLANET_BETA - a2 + a1) * 12.0 / TAU;
    let gen = i32(floor(u1 + 0.5));
    let gen_age = fract(u1 + 0.5);
    let ring = toothAutomaton(gen);
    let ring_prev = toothAutomaton(gen - 1);
    let born = ring & ~ring_prev;
    let ang1 = atan2(gear_uv.y, gear_uv.x);
    let ang2 = atan2(planet_uv.y, planet_uv.x);
    let k1 = toothIndex(ang1, 12.0);
    let k2 = toothIndex(ang2, 8.0);
    let live1 = f32((ring.x >> k1) & 1u);
    let live2 = f32((ring.y >> k2) & 1u);
    let new1 = f32((born.x >> k1) & 1u);
    let new2 = f32((born.y >> k2) & 1u);
    let crown1 = toothCrown(ang1, 12.0);
    let crown2 = toothCrown(ang2, 8.0);
    // Live teeth stand proud of the rim, so the automaton state is readable as gear geometry.
    let d1e = d1 - live1 * crown1 * 0.05;
    let d2e = d2 - live2 * crown2 * 0.04;
    let gear_d = min(d1e, d2e);

    // Metallic gear shading
    var bg_color = vec3<f32>(0.0);
    if (gear_d < 0.0) {
        bg_color = vec3<f32>(0.05, 0.05, 0.1) * (1.0 + 0.5 * sin(gear_d * 50.0));
    }
    // Glow on gear edges
    let gear_glow = exp(-abs(gear_d) * 10.0) * vec3<f32>(0.2, 0.4, 0.8) * 0.5;

    // Idea 1: live teeth burn amber; a tooth born this generation flashes, then settles.
    let flash = 1.0 - smoothstep(0.0, 0.35, gen_age);
    let lamp1 = live1 * crown1 * exp(-abs(d1e) * 18.0) * (0.55 + 1.6 * new1 * flash);
    let lamp2 = live2 * crown2 * exp(-abs(d2e) * 18.0) * (0.55 + 1.6 * new2 * flash);
    var tooth_emit = vec3<f32>(1.0, 0.58, 0.2) * (lamp1 + lamp2) * (1.0 + treble * 0.5);
    // Idea 1: the bit handed across the mesh at the last tooth pitch glints at the pitch point.
    let handed = f32((ring_prev.x >> u32(imod(gen - 1, 12))) & 1u);
    let pitch_pt = planet_centre * (0.8 / 1.3);
    tooth_emit += vec3<f32>(1.0, 0.85, 0.6) * handed * flash * exp(-length(distorted_p - pitch_pt) * 28.0) * 1.2;

    // Idea 2: capstan wrap. Threads are looked up in a space swirled about each hub by the gear's own
    // SDF band, turning with the gear's spin sense (sun clockwise, planet counter-clockwise).
    let wrap_turn = 0.9 * (0.4 + rotation_speed);
    let band1 = exp(-abs(d1e) / 0.12);
    let band2 = exp(-abs(d2e) / 0.10);
    var q = capstanWrap(distorted_p, vec2<f32>(0.0), band1, wrap_turn);
    q = capstanWrap(q, planet_centre, band2, -wrap_turn * 1.5);
    // Wound turns ride the rim with the gear angle; wrapped thread is under tension and brighter.
    let rib1 = 0.5 + 0.5 * cos(ang1 * 36.0);
    let rib2 = 0.5 + 0.5 * cos(ang2 * 24.0);
    let cap_band = max(band1, band2);
    let rib = select(rib2, rib1, band1 >= band2);
    let capstan_gain = mix(1.0, 0.4 + 1.8 * rib, cap_band);

    // Aether Threads: Mathatically braided strings that react to audio.
    // Thread Count maps 0..1 -> 2..12 threads (default 7); the last thread fades in fractionally.
    // (HEAD i32(zoom_params.x) was 0 threads for every x < 1.)
    let thread_count = 2.0 + clamp(u.zoom_params.x, 0.0, 1.0) * 10.0;
    let aether_bloom = u.zoom_params.z;
    var thread_glow = vec3<f32>(0.0);
    var thread_cov = 0.0;

    for (var i: i32 = 0; i < 12; i++) {
        let fi = f32(i);
        let fade = clamp(thread_count - fi, 0.0, 1.0);
        if (fade <= 0.0) { break; }

        let freq = 1.0 + fi * 0.02;
        let phase = time * (0.1 + fi * 0.01) + hash12(vec2<f32>(fi, 1.0)) * 6.28;

        // Audio reactivity modifies thread positions
        let audio_mod = audio * 0.2 * sin(time * 5.0 + fi * 0.1);

        let spline_y = sin(q.x * freq + phase) * 0.5 + noise(q * 2.0 + vec2<f32>(time * 0.2, fi * 0.1)) * 0.3 + audio_mod;
        let dist_to_spline = abs(q.y - spline_y);

        // Per-thread aether colour between cold aether blue and loom brass (HEAD indexed plasmaBuffer[1..255],
        // which is zero / out of range, so threads were black).
        let thread_color = mix(vec3<f32>(0.25, 0.65, 1.0), vec3<f32>(1.0, 0.62, 0.28), hash12(vec2<f32>(fi, 7.0)));

        // Bioluminescent nodes where threads bend: a quiet base glint, audio brightens them.
        let node_glow = max(0.0, sin(q.x * 20.0 + time * 5.0) * sin(spline_y * 20.0 - time * 3.0)) * (0.4 + audio);

        let thickness = 0.005 + audio * 0.01;
        let core = exp(-dist_to_spline / thickness);
        let halo = exp(-dist_to_spline / (thickness * 8.0));
        let intensity = (core * (0.35 + node_glow) * (0.3 + aether_bloom) + halo * 0.12 * aether_bloom) * capstan_gain;

        thread_glow += thread_color * intensity * fade;
        thread_cov = max(thread_cov, core * fade);
    }

    // Temporal Echo Trails (Feedback loop for time dilation trails)
    var back_uv = uv - vec2<f32>(0.5);
    back_uv *= 0.99; // Slight zoom in
    back_uv = back_uv * rot2d(0.01 * sin(time)); // Slight rotation
    back_uv += vec2<f32>(0.5);

    // Previous frame = exact dataTextureC (HEAD sampled readTexture, the user's photo, as "previous frame").
    let max_coord = vec2<i32>(res) - vec2<i32>(1);
    var prev_color = vec3<f32>(0.0);
    if (back_uv.x >= 0.0 && back_uv.x <= 1.0 && back_uv.y >= 0.0 && back_uv.y <= 1.0) {
        let back_coord = clamp(vec2<i32>(back_uv * res), vec2<i32>(0), max_coord);
        prev_color = max(textureLoad(dataTextureC, back_coord, 0).xyz, vec3<f32>(0.0));
    }

    // Combine everything (HDR, linear)
    var final_color = bg_color + gear_glow + tooth_emit + thread_glow;

    // Mix with temporal decay
    final_color = mix(final_color, max(final_color, prev_color * 0.95), temporal_decay);

    // ─── Chromatic dispersion (per-channel offset reads of the C history, not the input photo) ───
    let chrStrength = 0.004 + bass * 0.008;
    let offR = vec2<f32>(chrStrength * (1.0 + mids * 0.5), 0.0);
    let offG = vec2<f32>(0.0, chrStrength * (1.0 + treble * 0.3));
    let offB = vec2<f32>(-chrStrength * 0.7 * (1.0 + bass * 0.4), chrStrength * 0.3);
    let chrR = textureLoad(dataTextureC, clamp(vec2<i32>((uv + offR) * res), vec2<i32>(0), max_coord), 0).r;
    let chrG = textureLoad(dataTextureC, clamp(vec2<i32>((uv + offG) * res), vec2<i32>(0), max_coord), 0).g;
    let chrB = textureLoad(dataTextureC, clamp(vec2<i32>((uv + offB) * res), vec2<i32>(0), max_coord), 0).b;
    let chrColor = max(vec3<f32>(chrR, chrG, chrB), vec3<f32>(0.0));
    final_color = mix(final_color, chrColor, 0.2 + bass * 0.15);

    // Semantic alpha: gear / thread coverage plus emitted light.
    let cov1 = 1.0 - smoothstep(-0.01, 0.01, d1e);
    let cov2 = 1.0 - smoothstep(-0.01, 0.01, d2e);
    let luma = dot(final_color, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(max(max(cov1, cov2), thread_cov) * 0.85 + luma, 0.0, 1.0);

    // Depth: gears near (sun 0.9, planet 0.8), threads mid, void 0.
    let depthVal = max(max(cov1 * 0.9, cov2 * 0.8), thread_cov * 0.5);

    // A keeps HDR (pre-ACES) so the C echo / smear above re-blend in the same space; ACES on display only.
    textureStore(dataTextureA, coords, vec4<f32>(max(final_color, vec3<f32>(0.0)), alpha));
    textureStore(writeTexture, coords, vec4<f32>(acesToneMap(max(final_color * 1.2, vec3<f32>(0.0))), alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
