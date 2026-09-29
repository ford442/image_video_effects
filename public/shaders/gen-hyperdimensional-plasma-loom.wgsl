// ═══════════════════════════════════════════════════════════════════
//  Hyperdimensional Plasma Loom
//  Category: generative
//  Features: audio-reactive, mouse-driven, temporal-feedback, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: moving hyperplane slice (strands are 4D hypertube cross-sections); counter-propagating current packets
//  A packing: rgb = pre-tonemap HDR radiance (trail-blended), a = coverage; C read back as HDR colour history
// ═══════════════════════════════════════════════════════════════════
//  Twisted xy-repeated cells of counter-rotating helical tubes with
//  Fresnel iridescence and volumetric plasma glow.
//  - Hyperplane slice: each strand is the cut of a 4D hypertube of
//    radius R by a moving w-plane, radius = sqrt(R^2 - w^2). w is a
//    per-cell hash41 offset plus a diagonal travelling phase, so strands
//    swell, pinch and vanish in a wave across the lattice.
//  - Current packets: emissive packets run +z on helix 1 and -z on
//    helix 2; where they overlap they flash, hardest when the helices
//    touch. Mids lengthen packets, treble brightens them.
//  Mouse: hold to pull the weave toward the cursor (no pull on hover).
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
  zoom_params: vec4<f32>,  // .x = Weave Density, .y = Thread Thickness, .z = Plasma Intensity, .w = Time Speed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Trail weight of the previous frame's HDR radiance (exact C texel).
// Steady state converges to the current frame: col = mix(cur, prev, w).
const TRAIL_W: f32 = 0.4;
// March starts past this near distance so the lens never samples a tube at t=0.
const NEAR_T: f32 = 0.12;

// Basic 3D rotation functions
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}
fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 4D hash (per-cell hyperplane offset / packet phase)
fn hash41(p: vec4<f32>) -> f32 {
    var p4 = fract(p * vec4<f32>(0.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.x + p4.y) * p4.z + p4.w);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let res = exp(-k * a) + exp(-k * b);
    return -log(res) / k;
}

// Mouse pull (held only) + global rotation. Returns the rotated world point.
fn warpRotate(p_in: vec3<f32>, tt: f32, m_world: vec3<f32>, pull_str: f32) -> vec3<f32> {
    var p = p_in;
    let to_mouse = m_world - p;
    let dist_to_mouse = length(to_mouse);
    let pull = pull_str / (1.0 + dist_to_mouse * dist_to_mouse);
    p = p + to_mouse * pull * 0.5;
    p = rotY(tt * 0.3) * p;
    p = rotZ(tt * 0.2) * p;
    return p;
}

// Lattice twist about the z axis.
fn twist(p: vec3<f32>, tt: f32) -> vec3<f32> {
    var q = p;
    let tw = rot2D(q.z * 0.5 + tt);
    let qxy = tw * q.xy;
    q.x = qxy.x;
    q.y = qxy.y;
    return q;
}

// IDEA 1 — moving hyperplane slice.
// Cross-section radius of a 4D hypertube of radius R cut at hyperplane w:
// sqrt(R^2 - w^2). Past |w| > R the strand is gone; the value goes negative
// (clamped) so the field stays a conservative bound instead of a zero-radius line.
fn sliceRadius(R: f32, w: f32) -> f32 {
    let k = R * R - w * w;
    return clamp(sign(k) * sqrt(abs(k)), -0.5 * R, R);
}

// IDEA 2 — one current packet profile along a helix; ph in [0,1).
fn packet(ph: f32, sharp: f32) -> f32 {
    let x = (ph - 0.5) * sharp;
    return exp(-x * x);
}

// Map returning (distance, material_id, nearest-strand packet emission, packet-crossing flash)
fn map(p_in: vec3<f32>, time: f32, m_world: vec3<f32>, pull_str: f32, cam_off: vec2<f32>,
       bass: f32, mid: f32) -> vec4<f32> {
    let t = time * u.zoom_params.w * 0.5;
    let p = warpRotate(p_in, t, m_world, pull_str);

    // Domain repetition for weaving (bass breathes density, anchored on the camera corner)
    let density = u.zoom_params.x * (1.0 + bass * 0.3);
    let spacing = 2.0 / density;

    let q = twist(p, t);

    // Cells are laid out so the camera's own lattice point is a cell CORNER
    // (the widest gap between strands), which keeps the lens out of the tubes.
    let local = q.xy - cam_off;
    let cell = floor(local / spacing);
    var r = q;
    r.x = (fract(local.x / spacing) - 0.5) * spacing;
    r.y = (fract(local.y / spacing) - 0.5) * spacing;

    // Strands (helices): thread_thickness is the hypertube radius scale
    let thickness = u.zoom_params.y * (1.0 + bass * 1.5);
    let R1 = thickness * 1.35;
    let R2 = thickness * 0.8 * 1.35;
    let h1 = hash41(vec4<f32>(cell, 1.0, 17.0));
    let h2 = hash41(vec4<f32>(cell, 2.0, 17.0));

    // IDEA 1: w-plane position = per-cell hash offset + diagonal travelling phase
    // (across cells) + a slower drift along the strand, so swell/pinch fronts
    // sweep the lattice diagonally and run along each thread.
    let wave = dot(cell, vec2<f32>(0.83, 0.61)) * 1.1 + r.z * 0.35 - t * 1.6;
    let w1 = R1 * 1.1 * sin(wave + h1 * PI);
    let w2 = R2 * 1.1 * sin(wave * 0.9 + 1.7 + h2 * PI);
    let rad1 = sliceRadius(R1, w1);
    let rad2 = sliceRadius(R2, w2);

    // Strand 1
    var s1_p = r;
    let r1 = rot2D(s1_p.z * 2.0 + t * 2.0);
    let s1_xy = r1 * s1_p.xy;
    s1_p.x = s1_xy.x; s1_p.y = s1_xy.y;
    s1_p.x += spacing * 0.2;
    let d1 = length(s1_p.xy) - rad1;

    // Strand 2
    var s2_p = r;
    let r2 = rot2D(s2_p.z * 2.0 - t * 2.5 + PI);
    let s2_xy = r2 * s2_p.xy;
    s2_p.x = s2_xy.x; s2_p.y = s2_xy.y;
    s2_p.x += spacing * 0.2;
    let d2 = length(s2_p.xy) - rad2;

    // (HEAD's strand-3 "cross weave" was smin'd at d3+0.5 and never reachable; removed.)
    var d = smin(d1, d2, 8.0);

    // Add noise bump
    let n = sin(p.x * 4.0 + t) * sin(p.y * 4.0 + t) * sin(p.z * 4.0 + t);
    d += n * 0.05;

    var mat = 0.0;
    if (d1 < d2) { mat = 1.0; }

    // IDEA 2: counter-propagating current packets. Helix 1 carries packets toward
    // +z, helix 2 toward -z (lattice axis). Mids lengthen packets. Packets only
    // exist where the hyperplane slice leaves the strand present.
    let sharp = mix(11.0, 5.5, clamp(mid, 0.0, 1.0));
    let pf = 0.55;
    let pv = 0.9;
    let pk1 = packet(fract(r.z * pf - t * pv + h1), sharp) * smoothstep(0.0, 0.35 * R1, rad1);
    let pk2 = packet(fract(r.z * pf + t * pv + h2), sharp) * smoothstep(0.0, 0.35 * R2, rad2);
    // Crossing flash: both packets at the same z in the same cell; strongest when
    // the two helices' angular gap (4.5t - PI, z-independent) closes.
    let cg = 0.5 + 0.5 * cos(4.5 * t - PI);
    let flash = pk1 * pk2 * (0.3 + 0.7 * cg * cg * cg);
    let pk_near = select(pk2, pk1, d1 < d2);

    return vec4<f32>(d, mat, pk_near, flash);
}

fn calcNormal(p: vec3<f32>, time: f32, m_world: vec3<f32>, pull_str: f32, cam_off: vec2<f32>,
              bass: f32, mid: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, m_world, pull_str, cam_off, bass, mid).x;
    let nx = map(p + e.xyy, time, m_world, pull_str, cam_off, bass, mid).x - d;
    let ny = map(p + e.yxy, time, m_world, pull_str, cam_off, bass, mid).x - d;
    let nz = map(p + e.yyx, time, m_world, pull_str, cam_off, bass, mid).x - d;
    return normalize(vec3<f32>(nx, ny, nz) + vec3<f32>(0.0, 0.0, 1e-7));
}

// Iridescent palette
fn iridescence(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
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
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= dims.x || coords.y >= dims.y) {
        return;
    }

    let aspect = f32(dims.x) / f32(dims.y);
    var uv = vec2<f32>(coords) / vec2<f32>(dims);
    uv = uv * 2.0 - 1.0;
    uv.y = -uv.y;
    uv.x *= aspect;

    let time = u.config.x;
    let mouse_pos = u.zoom_config.yz;

    // Audio reactivity (bass / mids / treble)
    let audio = plasmaBuffer[0];
    let bass = audio.x;
    let mid = audio.y;
    let treble = audio.z;

    // Mouse: cursor projected onto the z=0 plane (focal 2, camera at z=5 -> x2.5).
    // The gravity-well pull only acts while the button is held.
    let m_world = vec3<f32>((mouse_pos.x * 2.0 - 1.0) * aspect, -(mouse_pos.y * 2.0 - 1.0), 0.0) * 2.5;
    let pull_str = select(0.0, 1.5, u.zoom_config.w > 0.5);

    // Camera
    let ro = vec3<f32>(0.0, 0.0, 5.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 2.0 * cw);

    // Camera's own lattice xy: the cell grid is anchored so this is a cell corner.
    let tt = time * u.zoom_params.w * 0.5;
    let cam_off = twist(warpRotate(ro, tt, m_world, pull_str), tt).xy;

    // Raymarching
    var t_dist = NEAR_T;
    let max_d = 20.0;
    var col = vec3<f32>(0.0);
    var d = vec4<f32>(0.0);
    var p = ro;
    var hit = false;

    // Glow accumulation (plasma haze + packet beads)
    var glow = 0.0;
    var glow_pk = 0.0;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t_dist;
        d = map(p, time, m_world, pull_str, cam_off, bass, mid);

        // Accumulate glow based on proximity to threads
        glow += 0.01 / (0.01 + abs(d.x));
        glow_pk += (d.z + d.w * 2.5) * 0.004 / (0.004 + abs(d.x));

        // Only a converged step is a hit; step exhaustion is a miss.
        if (d.x < 0.001 * (1.0 + t_dist * 0.5)) { hit = true; break; }
        if (t_dist > max_d) { break; }
        t_dist += d.x * 0.7; // step slightly smaller for safety with domain warping
    }

    let intensity = u.zoom_params.z;
    // Packet colour: palette phase opposite the plasma haze, pushed toward white-hot.
    let pk_col = mix(iridescence(time * 0.5 + mid * 2.0 + 0.5), vec3<f32>(1.0), 0.35);
    let pk_gain = intensity * (0.6 + treble * 1.2);

    if (hit) {
        let n = calcNormal(p, time, m_world, pull_str, cam_off, bass, mid);
        let view_dir = normalize(ro - p);

        // Lighting
        let light_dir = normalize(vec3<f32>(sin(time), 1.0, cos(time)));
        let diff = max(dot(n, light_dir), 0.0);

        // Fresnel / Thin-film iridescence
        let fresnel = pow(max(1.0 - max(dot(n, view_dir), 0.0), 0.0), 3.0);

        // Material color base
        let irid_color = iridescence(p.z * 0.1 + fresnel + time * 0.2 + d.y * 0.3);

        // Ambient + Diffuse
        let ambient = vec3<f32>(0.05, 0.0, 0.1);
        col = ambient + irid_color * diff;

        // Specular
        let h = normalize(light_dir + view_dir);
        let spec = pow(max(dot(n, h), 0.0), 32.0);
        col += vec3<f32>(1.0) * spec * fresnel;

        // IDEA 2 at the surface: packet bead on its own helix + crossing flash
        col += pk_col * d.z * 1.6 * pk_gain;
        col += vec3<f32>(1.0, 0.95, 0.88) * d.w * 5.0 * pk_gain;

        // Distance fog
        col = mix(col, vec3<f32>(0.0, 0.0, 0.02), smoothstep(10.0, max_d, t_dist));
    }

    // Add volumetric plasma glow
    let plasma_color = iridescence(time * 0.5 + mid * 2.0);
    col += plasma_color * glow * 0.02 * intensity;
    col += pk_col * glow_pk * 0.03 * pk_gain;

    // Temporal trail: exact previous-frame HDR radiance from C (our own A).
    let prev_raw = textureLoad(dataTextureC, coords, 0).rgb;
    let prev_ok = all(prev_raw == prev_raw);
    let prev_col = clamp(select(vec3<f32>(0.0), prev_raw, prev_ok), vec3<f32>(0.0), vec3<f32>(32.0));
    col = mix(max(col, vec3<f32>(0.0)), prev_col, TRAIL_W);

    // Semantic alpha: tube coverage, else glow density
    let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = select(clamp(lum * 1.5, 0.0, 1.0), 1.0, hit);

    // A = HDR radiance history for the next frame's trail
    textureStore(dataTextureA, coords, vec4<f32>(col, alpha));

    // Depth: 1 at the lens, falling to 0 at max distance; misses are far (0)
    let depth = select(0.0, clamp(1.0 - t_dist / max_d, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Display: ACES, then HEAD's 2.2 gamma encode
    let disp = pow(acesToneMap(col), vec3<f32>(1.0 / 2.2));
    textureStore(writeTexture, coords, vec4<f32>(disp, alpha));
}
