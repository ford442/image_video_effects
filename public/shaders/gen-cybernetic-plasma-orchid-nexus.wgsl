// ═══════════════════════════════════════════════════════════════════
//  Cybernetic Plasma-Orchid Nexus
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: zygomorphic labellum with nectar-well glow; column with bass-pulsed pollinia
//  A packing: ACES display RGBA (rgb = tone-mapped colour, a = surface/glow coverage); C is not read
// ═══════════════════════════════════════════════════════════════════
//  A raymarched plasma core (sphere smin spinning torus) inside a polar
//  ring of fBm-displaced petals, with volumetric plasma glow.
//  Floor fixes (2026-09-28): petal box half-extents were applied to
//  (radial, tangential) the wrong way round, so every petal was a 0.3-deep
//  sliver buried inside the r=0.4 core — petals now run radially out to
//  r=2.5 with a tapered blade; pixel y flipped so the scene is y-up (the
//  mouse y was already flipped); pointer mapped onto the z=0 plane with
//  aspect (view half-height there is 5, was x3 without aspect); audio from
//  plasmaBuffer[0] (was extraBuffer[0]); petal distance divided by the bend
//  Lipschitz bound; tetrahedral normals; ACES replaces Reinhard+gamma;
//  depth + A written; semantic alpha. Bloom Spread is now a visible radial
//  R/B split (per-channel glow softness + palette phase) instead of a ≤4 %
//  red/blue gain.
//  Audio: bass -> core swell / spin kick / pollinia pulse; mids -> nectar well.
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
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Petal Complexity, .y = Plasma Intensity, .z = Distortion Strength, .w = Bloom Spread
  ripples: array<vec4<f32>, 50>,
};

// Per-frame scene constants (hoisted out of map()).
struct Scene {
  frame: mat3x3<f32>,  // flower spin (world -> flower space via p * frame)
  mouse3: vec3<f32>,   // pointer on the z=0 plane, world units
  lab: vec3<f32>,      // .xy = world-down in flower space (labellum axis), .z = its angle
  time: f32,
  petals: f32,
  distortion: f32,
  bass: f32,
};

const TAU: f32 = 6.28318;
const PETAL_LEN: f32 = 2.5;
const LIP_START: f32 = 0.3;
const LIP_LEN: f32 = 1.7;
const THROAT_R: f32 = 0.62;

// 3D Rotation matrices
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(
        1.0, 0.0, 0.0,
        0.0, c, -s,
        0.0, s, c
    );
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(
        c, 0.0, s,
        0.0, 1.0, 0.0,
        -s, 0.0, c
    );
}

fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(
        c, -s, 0.0,
        s, c, 0.0,
        0.0, 0.0, 1.0
    );
}

// Custom SDFs and Noise functions
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdBoxQ(q: vec3<f32>) -> f32 {
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn hash3(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
}

// Basic 3D noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(
            mix(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), hash3(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), hash3(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y
        ),
        mix(
            mix(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), hash3(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), hash3(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y
        ), u.z
    );
}

// fBm
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var q = p;
    for (var i = 0; i < 4; i = i + 1) {
        f += w * noise(q);
        q *= 2.0;
        w *= 0.5;
    }
    return f;
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// World -> flower space: magnetic gravity well toward the pointer, then spin.
fn flowerSpace(p: vec3<f32>, sc: Scene) -> vec3<f32> {
    let to_m = sc.mouse3 - p;
    let dist_to_mouse = length(to_m);
    let gravity_pull = sc.distortion / (dist_to_mouse * dist_to_mouse + 0.1);
    let p_mod = p + to_m / max(dist_to_mouse, 1e-4) * min(gravity_pull, 1.0);
    return p_mod * sc.frame;
}

// Labellum-local coords: x = along world-down (out of the throat), y = across the lip.
fn lipCoords(p_mod: vec3<f32>, sc: Scene) -> vec2<f32> {
    let dn = sc.lab.xy;
    return vec2<f32>(dot(p_mod.xy, dn), dot(p_mod.xy, vec2<f32>(-dn.y, dn.x)));
}

// Scene SDF. Returns (distance, material, nectar-throat distance, pollinia distance).
// Materials: 1 core, 2 petal, 3 labellum, 4 column, 5 pollinia.
fn map(p: vec3<f32>, sc: Scene) -> vec4<f32> {
    let time = sc.time;
    let p_mod = flowerSpace(p, sc);

    // Core (Plasma)
    let core_scale = 1.0 + sc.bass * 0.2;
    let sphere = sdSphere(p_mod, 0.4 * core_scale);
    let torus = sdTorus(p_mod * rotX(time), vec2<f32>(0.5 * core_scale, 0.1));
    let core_dist = smin(sphere, torus, 0.2);

    // Petals — polar repetition
    var petal_p = p_mod;
    let angle = atan2(petal_p.y, petal_p.x);
    let radius = length(petal_p.xy);

    let num_petals = floor(sc.petals) * 2.0;
    let segment = TAU / num_petals;
    let a_mod = (fract(angle / segment + 0.5) - 0.5) * segment;

    petal_p.x = radius * cos(a_mod);   // radial
    petal_p.y = radius * sin(a_mod);   // tangential

    // Idea 1 (labellum): the sector facing world-down yields to the lip.
    // Continuous weight, so as the ring spins the lip hands off smoothly
    // between neighbouring petals (the lip itself never leaves the bottom).
    var dc = (angle - a_mod) - sc.lab.z;
    dc = abs(dc - TAU * round(dc / TAU));
    let lab_w = 1.0 - smoothstep(max(0.3 * segment, 0.2), max(0.85 * segment, 0.55), dc);
    let petal_len = mix(PETAL_LEN, 0.3, lab_w);

    // Bend petals outwards
    let bend_ph = time + radius * 2.0;
    let bend = radius * radius * 0.2 * sin(bend_ph);
    petal_p.z -= bend;
    let bend_grad = abs(0.4 * radius * sin(bend_ph) + 0.4 * radius * radius * cos(bend_ph));

    // Petal shape: HEAD's pulsing width, tapered along the blade and kept
    // inside its polar cell so neighbours never merge into a disc.
    let petal_width = 0.2 + 0.1 * sin(radius * 5.0 - time);
    let s = clamp(petal_p.x / petal_len, 0.0, 1.0);
    let taper = 0.35 + 2.6 * s * (1.0 - s);
    let cell_half = radius * sin(min(0.5 * segment, 1.5707));
    let half_w = min(petal_width * 2.0 * taper, 0.8 * cell_half) * (1.0 - lab_w);

    // Displace with fBm
    let disp = fbm(p_mod * 3.0 + time * 0.5) * 0.1;

    // FIX: (radial, tangential) half-extents = (length, width); HEAD had them swapped.
    let q = abs(petal_p) - vec3<f32>(petal_len, half_w, 0.02 + disp);
    let d_box = sdBoxQ(q);

    // Mask by radius to make them petal shaped; divide by the bend Lipschitz bound.
    let petal_dist = max(d_box, radius - petal_len) / sqrt(1.0 + bend_grad * bend_grad);

    // ── Idea 1: zygomorphic labellum ─────────────────────────────────
    // One lip outside the polar repeat, always along world-down: short,
    // wide lobe, cupped across (edges curl toward the camera), tip curling
    // forward, frilled rim. fBm skin shared with the petals.
    let lc = lipCoords(p_mod, sc);
    let ls = clamp((lc.x - LIP_START) / LIP_LEN, 0.0, 1.0);
    let lip_half_w = mix(0.16, 0.78, smoothstep(0.0, 0.75, ls)) * (1.0 - 0.45 * smoothstep(0.8, 1.0, ls));
    let cup = 0.9;
    let frill = 0.05 * sin(lc.y * 14.0 + time * 1.5) * ls;
    let lz = p_mod.z + cup * lc.y * lc.y + 0.35 * ls * ls + frill;
    let ql = vec3<f32>(
        abs(lc.x - (LIP_START + 0.5 * LIP_LEN)) - 0.5 * LIP_LEN,
        abs(lc.y) - lip_half_w,
        abs(lz) - (0.03 + disp * 0.5)
    );
    let lip_grad = vec2<f32>(2.0 * cup * abs(lc.y) + 0.7 * ls, 0.7 * ls / LIP_LEN + 0.7);
    let lip_dist = sdBoxQ(ql) / sqrt(1.0 + dot(lip_grad, lip_grad));
    // Nectar well: a point in the throat where the lip meets the core.
    let throat = vec3<f32>(sc.lab.xy * THROAT_R, -0.12);
    let throat_d = length(p_mod - throat);

    // ── Idea 2: column with pollinia ─────────────────────────────────
    // A short column rises from the core toward the viewer and leans over
    // the lip's throat; two pollinia beads sit at its tip, swelling on bass.
    let col_tip = vec3<f32>(sc.lab.xy * 0.2, -0.82);
    let column = sdCapsule(p_mod, vec3<f32>(0.0, 0.0, -0.2), col_tip, 0.08);
    let perp = vec3<f32>(-sc.lab.y, sc.lab.x, 0.0);
    let bead_r = 0.07 * (1.0 + 0.35 * clamp(sc.bass, 0.0, 2.0));
    let bead_c = col_tip + vec3<f32>(sc.lab.xy * 0.03, -0.05);
    let pollen_d = min(
        length(p_mod - (bead_c + perp * 0.085)),
        length(p_mod - (bead_c - perp * 0.085))
    ) - bead_r;

    // Material resolve (min with ids)
    var res = vec2<f32>(core_dist, 1.0);
    if (petal_dist < res.x) { res = vec2<f32>(petal_dist, 2.0); }
    if (lip_dist < res.x) { res = vec2<f32>(lip_dist, 3.0); }
    if (column < res.x) { res = vec2<f32>(column, 4.0); }
    if (pollen_d < res.x) { res = vec2<f32>(pollen_d, 5.0); }
    return vec4<f32>(res, throat_d, pollen_d);
}

// Tetrahedral normal (4 taps; offsets the extra lip/column SDF cost).
fn calcNormal(p: vec3<f32>, sc: Scene) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.001;
    return normalize(
        e.xyy * map(p + e.xyy, sc).x +
        e.yyx * map(p + e.yyx, sc).x +
        e.yxy * map(p + e.yxy, sc).x +
        e.xxx * map(p + e.xxx, sc).x
    );
}

// Palette generation (HEAD)
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

// Bloom Spread R/B split: red reads the palette ahead, blue behind.
fn paletteCA(t: f32, k: f32) -> vec3<f32> {
    return vec3<f32>(palette(t + k).r, palette(t).g, palette(t - k).b);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);

    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) {
        return;
    }

    let resolution = vec2<f32>(dimensions);
    let aspect = resolution.x / resolution.y;
    var uv = (vec2<f32>(coords) + 0.5) / resolution;
    uv = uv * 2.0 - 1.0;
    uv.y = -uv.y;          // FIX: scene is y-up (screen y=0 is the top)
    uv.x *= aspect;

    // Parameters
    let time = u.config.x;
    let petal_complexity = clamp(u.zoom_params.x, 1.0, 8.0);
    let plasma_intensity = clamp(u.zoom_params.y, 0.1, 3.0);
    let distortion = clamp(u.zoom_params.z, 0.0, 2.0);
    let bloom_spread = clamp(u.zoom_params.w, 0.1, 2.0);

    // Audio reactivity (bass / mids)
    let audio = plasmaBuffer[0].xyz;
    let bass = audio.x * 2.0;
    let mids = audio.y;

    // Pointer onto the z=0 plane: camera at z=-5 with focal 1 sees 5*uv there.
    let mouse_ndc = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, -1.0);
    let mouse3 = vec3<f32>(mouse_ndc * 5.0, 0.0);

    // Animate overall structure (HEAD spin); world-down in flower space is the lip axis.
    let frame = rotY(time * 0.2 + bass * 0.1) * rotZ(time * 0.1);
    let down_f = vec3<f32>(0.0, -1.0, 0.0) * frame;
    let dn = normalize(down_f.xy + vec2<f32>(1e-5, 0.0));
    let sc = Scene(frame, mouse3, vec3<f32>(dn, atan2(dn.y, dn.x)), time, petal_complexity, distortion, bass);

    // Bloom Spread: radial split strength (grows toward the frame edge).
    let ca = smoothstep(0.0, 1.5, length(uv)) * bloom_spread * 0.6;
    let glow_soft = 0.1 * vec3<f32>(1.0 + ca, 1.0, max(1.0 - 0.6 * ca, 0.25));

    // Raymarching setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var p = ro;

    var glow = vec3<f32>(0.0);   // per-channel softness = radial R/B split
    var nectar = 0.0;
    var pollen = 0.0;
    var hit = false;

    for (var i = 0; i < 100; i = i + 1) {
        p = ro + rd * t;
        let res = map(p, sc);
        d = res.x;
        m = res.y;

        // Volumetric glow accumulation (HEAD weights)
        let w = select(0.01, 0.05, m < 1.5);
        glow += w * plasma_intensity / (glow_soft + abs(d));
        // Nectar well in the labellum throat; pollinia halo.
        nectar += 0.004 / (0.02 + res.z * res.z);
        pollen += 0.002 / (0.004 + res.w * res.w);

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d * 0.7; // step size multiplier to avoid artifacts with domain warping
    }

    let pk = ca * 0.1; // palette phase split for surfaces
    let nectar_col = paletteCA(time * 0.5 + 0.35, pk) * vec3<f32>(1.6, 0.6, 1.9);
    let pollen_col = mix(vec3<f32>(1.0, 0.72, 0.22), paletteCA(time * 0.3, pk), 0.3);
    let pollen_pulse = 0.35 + 1.4 * clamp(bass, 0.0, 2.0);

    // Color mapping and shading
    var col = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(p, sc);
        let ndv = max(dot(n, -rd), 0.0);
        let fresnel = pow(1.0 - ndv, 3.0);
        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let amb = 0.2;

        if (m < 1.5) { // Core
            // Sub-surface scattering approximation
            let sss = smoothstep(0.0, 1.0, 0.5 + 0.5 * ndv);
            let core_color = paletteCA(p.z * 0.5 + time, pk) * vec3<f32>(1.5, 0.5, 2.0); // Cyan/Magenta bias
            col = core_color * sss * plasma_intensity;
        } else if (m < 2.5) { // Petal
            // Procedural iridescence via Fresnel
            let view_angle_color = paletteCA(fresnel + time * 0.2, pk); // shifts purple to gold
            col = view_angle_color * (diff + amb) + fresnel * vec3<f32>(1.0, 0.8, 0.2);
            col *= 0.5; // Petals are slightly darker than the core
        } else if (m < 3.5) { // Labellum: petal iridescence + nectar glow flowing out of the throat
            let lc = lipCoords(flowerSpace(p, sc), sc);
            let throat_fall = exp(-max(lc.x - LIP_START, 0.0) * 2.2);
            let vein = 0.5 + 0.5 * sin(lc.y * 22.0 + lc.x * 3.0);
            let lip_color = paletteCA(fresnel * 0.6 + time * 0.2 + 0.5, pk);
            col = lip_color * (diff + amb) * 0.55 + fresnel * vec3<f32>(1.0, 0.8, 0.2) * 0.5;
            col += nectar_col * throat_fall * (0.35 + 0.25 * vein) * plasma_intensity * (0.6 + mids);
        } else if (m < 4.5) { // Column: waxy, lit from within by the core
            let sss = smoothstep(0.0, 1.0, 0.5 + 0.5 * ndv);
            col = vec3<f32>(0.62, 0.8, 0.7) * (diff + amb) * 0.6 + paletteCA(time + 0.2, pk) * sss * 0.25;
        } else { // Pollinia: emissive beads
            col = pollen_col * (0.6 + 0.4 * ndv) * pollen_pulse * plasma_intensity;
        }
    }

    // Add glow (HEAD colour); nectar + pollinia halos
    let glow_col = paletteCA(time * 0.5, pk) * vec3<f32>(0.8, 0.2, 1.0);
    col += glow_col * glow * 0.1;
    col += nectar_col * nectar * 0.08 * plasma_intensity * (0.6 + mids);
    col += pollen_col * pollen * 0.04 * pollen_pulse;

    // Tone mapping (ACES on display RGB)
    col = acesToneMap(col * 1.5);

    // Semantic alpha: geometry is opaque, halo alpha follows glow brightness.
    let halo = clamp(max(col.r, max(col.g, col.b)) * 1.2, 0.05, 1.0);
    let alpha = select(halo, 1.0, hit);
    let final_color = vec4<f32>(col, alpha);

    let depth = select(0.0, clamp(1.0 - t / 12.0, 0.0, 1.0), hit);

    textureStore(writeTexture, coords, final_color);
    textureStore(dataTextureA, coords, final_color);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
