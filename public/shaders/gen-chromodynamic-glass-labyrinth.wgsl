// ═══════════════════════════════════════════════════════════════════
//  Chromodynamic Glass Labyrinth
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-11-08
//  Ideas: real interior march with per-channel Beer-Lambert replacing the fake dot(r_rd,1) colour; checkerboard-parity counter-rotating cells with per-cell ior and hollow radius; audio bands as wavelength (bass widens red eta, treble blue eta, mids nudge ior); Cauchy dispersion (§12.2F); Fresnel-Schlick from per-cell ior + exit-face transmittance (§12.2F); one-bounce reflection march into the neighbouring glass cell
//  Rescue 2026-11-08: camera-in-glass (on-axis ride crossed cell corners at every integer second) -> start ray marched out through the glass, Beer-Lambert tinted
//  A packing: ACES display RGBA (alpha = glass transmission coverage)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: .x = Structural Density, .y = Refraction Index, .z = Dispersion, .w = Chromatic Phase

const PI: f32 = 3.14159265359;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smax(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

// Mouse structural warp (shared by map() and the per-cell lookup so ids agree).
fn warp_p(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    if (u.zoom_config.w > 0.5) {
        let mouse_offset = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
        let rot_xy = rot2D(mouse_offset.x * 2.0);
        let p_xy = p.xy * rot_xy;
        p = vec3<f32>(p_xy, p.z);
        // y axis warp expansion
        p *= (1.0 + mouse_offset.y * 0.5);
    }
    return p;
}

fn cell_hash(id: vec3<f32>) -> f32 {
    return fract(sin(dot(id, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

// Idea 2: lattice cell id of a world point (same fold as map()).
fn cell_id_at(p_in: vec3<f32>) -> vec3<f32> {
    let cell_size = 4.0 / u.zoom_params.x;
    return floor(warp_p(p_in) / cell_size + 0.5);
}

fn map(p_in: vec3<f32>) -> f32 {
    // Mouse Interaction for structural warping
    var p = warp_p(p_in);

    // Spatial folding
    let s_density = u.zoom_params.x;
    let cell_size = 4.0 / s_density;
    let g = p / cell_size + 0.5;
    let id = floor(g);
    p = (fract(g) - 0.5) * cell_size;

    // Idea 2: checkerboard parity -> neighbouring cells spin in opposite directions;
    // hash(id) varies speed and the radius of the hollow.
    let h = cell_hash(id);
    let parity = select(-1.0, 1.0, fract((id.x + id.y + id.z) * 0.5) < 0.25);
    let spin = parity * (0.85 + 0.3 * h);

    let p_xz = p.xz * rot2D(u.config.x * 0.2 * spin);
    p = vec3<f32>(p_xz.x, p.y, p_xz.y);
    let p_yz = p.yz * rot2D(u.config.x * 0.15 * spin);
    p = vec3<f32>(p.x, p_yz.x, p_yz.y);

    let d_box = length(max(abs(p) - vec3<f32>(cell_size * 0.3), vec3<f32>(0.0))) - cell_size * 0.05;
    let d_sphere = length(p) - cell_size * (0.35 + 0.08 * (h - 0.5));

    // rounded intersection / subtraction
    let d = smax(d_box, -d_sphere, cell_size * 0.1);

    return d;
}

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p);
    let n = vec3<f32>(
        map(p + e.xyy) - d,
        map(p + e.yxy) - d,
        map(p + e.yyx) - d
    );
    return normalize(n);
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557) + u.zoom_params.w; // Chromatic Phase
    return a + b * cos(6.28318 * (c * t + d));
}

// ── Idea 5: Fresnel-Schlick base reflectance from the (per-cell) ior ──
fn schlickF0(eta: f32) -> f32 {
    let r = (eta - 1.0) / (eta + 1.0);
    return r * r;
}

// ── Idea 6: one-bounce reflection march ──────────────────────────
// `refl` used to feed only a white spec dot. March it ≤14 steps through the
// same lattice; a hit returns the neighbouring cell's own glass tint (its
// palette colour at that spot, attenuated with distance), a miss the sky.
fn reflectLattice(p: vec3<f32>, refl: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    let o = p + n * 0.01;
    var t = 0.04;
    var hit = false;
    for (var i = 0; i < 14; i++) {
        let d = map(o + refl * t);
        if (d < 0.003) { hit = true; break; }
        t += d;
        if (t > 6.0) { break; }
    }
    let q = o + refl * t;
    let neighbour = palette(length(q) * 0.1 + u.config.x * 0.5) * 0.6 * exp(-t * 0.25);
    let sky = palette(refl.y + u.config.x * 0.1) * 0.1;
    return select(sky, neighbour, hit);
}

// Idea 1: march INSIDE the glass for one wavelength. Returns (exit-direction
// phase for the palette lookup, interior path length). Inside, -map() is the
// distance to the nearest wall; rays that hit total internal reflection leave
// along the mirror direction.
// Returns (exit-direction phase, interior path length, exit-face transmittance).
fn interior(p: vec3<f32>, rd: vec3<f32>, n: vec3<f32>, eta: f32) -> vec3<f32> {
    var r = refract(rd, n, 1.0 / eta);
    if (dot(r, r) < 0.5) { r = reflect(rd, n); }
    var t = 0.03;
    for (var i = 0; i < 12; i++) {
        let di = -map(p + r * t);
        if (di < 0.002) { break; }
        t += max(di, 0.01);
    }
    let q = p + r * t;
    let n_out = get_normal(q);
    var e = refract(r, -n_out, eta);
    let tir = dot(e, e) < 0.5;
    if (tir) { e = reflect(r, -n_out); }
    // ── Idea 5b: exit-face transmittance — glass->air Schlick (angle in glass,
    // same F0 as the entry face); total internal reflection passes only a
    // fraction of the light on.
    let cosIn = clamp(dot(r, n_out), 0.0, 1.0);
    let f0 = schlickF0(eta);
    let fExit = f0 + (1.0 - f0) * pow(1.0 - cosIn, 5.0);
    return vec3<f32>(dot(e, vec3<f32>(1.0)), t, select(1.0 - fExit, 0.4, tir));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = u.config.zw;
    if (f32(id.x) >= dims.x || f32(id.y) >= dims.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * dims) / dims.y;

    // Audio reactivity
    let audio_val = plasmaBuffer[0].x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 2.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Interaction for perspective
    if (u.zoom_config.w > 0.5) {
        let mouse_offset = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
        let rd_xz = rd.xz * rot2D(-mouse_offset.x * PI);
        rd = vec3<f32>(rd_xz.x, rd.y, rd_xz.y);
        let rd_yz = rd.yz * rot2D(-mouse_offset.y * PI * 0.5);
        rd = vec3<f32>(rd.x, rd_yz.x, rd_yz.y);
    }

    // Rescue: camera-in-glass. The on-axis ride crosses a cell boundary at every
    // integer second (ro.z odd) where rotating cube corners (reach r=1.21) hold
    // the camera point (r=1): map(ro)<0 and every ray hit at t~0 -> one flat
    // colour. March out through the glass first and tint by the path (same
    // Beer-Lambert form as the interior march).
    // The ride also passes within ~0.2 of a corner at every boundary (a smooth
    // wall-in-face frame): a soft near plane opens only when the camera is that
    // close, so the lattice beyond is visible instead.
    let camClear = map(ro);
    var t = 0.8 * (1.0 - smoothstep(0.05, 0.5, camClear));
    var camPath = 0.0;
    for (var k = 0; k < 20; k++) {
        let dIn = map(ro + rd * t);
        if (dIn > 0.01) { break; }
        let stepIn = max(-dIn, 0.02);
        t += stepIn;
        camPath += stepIn;
    }
    let camSigma = (vec3<f32>(1.0) - palette(length(ro) * 0.1 + u.config.x * 0.5)) * 0.9 + vec3<f32>(0.08);
    let camTrans = exp(-camSigma * camPath);
    var d = 0.0;
    var hit = false;
    var steps_taken: i32 = 0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001) {
            hit = true;
            steps_taken = i;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d * 0.8;
    }

    var color = vec3<f32>(0.0);
    var depth = 1.0;
    var transmission = 0.0;

    if (hit) {
        let p = ro + rd * t;
        let n = get_normal(p);
        let v = -rd;

        // Idea 2: per-cell ior from hash(id)
        let cell_h = cell_hash(cell_id_at(p - n * 0.01));
        // Idea 3: bands as wavelength - mids nudge ior, bass widens the red
        // eta spread, treble widens the blue spread.
        let ior = u.zoom_params.y * (1.0 + 0.10 * (cell_h - 0.5)) + mids * 0.12;
        let dispersion = u.zoom_params.z;
        // ── Idea 4: Cauchy dispersion (§12.2F). n(λ) = A + B/λ² at 650/550/450 nm:
        // (1/λ² − 1/λg²) = −0.94 (R), +1.63 (B); /1.286 keeps the mean spread equal
        // to the old symmetric ±dispersion, so the slider keeps its role but blue
        // now separates 1.7x further than red, like real glass.
        let eta_r = max(ior - dispersion * 0.73 * (1.0 + bass * 1.5), 1.01);
        let eta_g = max(ior, 1.01);
        let eta_b = max(ior + dispersion * 1.27 * (1.0 + treble * 1.5), 1.01);

        // ── Idea 5: Fresnel-Schlick (§12.2F), F0 = ((n-1)/(n+1))^2 from this cell's ior —
        // denser glass is a stronger mirror; replaces the F0=0 (1-cos)^3 stand-in.
        let f0 = schlickF0(max(ior, 1.0));
        let fresnel = f0 + (1.0 - f0) * pow(clamp(1.0 - max(dot(n, v), 0.0), 0.0, 1.0), 5.0);

        let refl = reflect(rd, n);

        let mat_color = palette(length(p) * 0.1 + u.config.x * 0.5);

        // Caustic highlight approx
        let spec = pow(max(dot(refl, normalize(vec3<f32>(1.0, 1.0, -1.0))), 0.0), 32.0);

        // Audio bump
        let audio_bump = audio_val * 0.5 * max(0.0, dot(n, vec3<f32>(0.0, 1.0, 0.0)));

        // Idea 1: real interior march per wavelength + Beer-Lambert absorption
        // (dyed by the palette tint) instead of palette(dot(refracted,1)).
        let ir = interior(p, rd, n, eta_r);
        let ig = interior(p, rd, n, eta_g);
        let ib = interior(p, rd, n, eta_b);
        let sigma = (vec3<f32>(1.0) - mat_color) * 0.9 + vec3<f32>(0.08);
        let trans = vec3<f32>(exp(-sigma.x * ir.y) * ir.z, exp(-sigma.y * ig.y) * ig.z, exp(-sigma.z * ib.y) * ib.z);
        let refr_color = vec3<f32>(palette(ir.x).r, palette(ig.x).g, palette(ib.x).b) * trans;

        let reflCol = reflectLattice(p, refl, n);
        color = mix(refr_color * mat_color, reflCol + vec3<f32>(1.0) * spec + audio_bump, fresnel);
        transmission = clamp((trans.x + trans.y + trans.z) / 3.0, 0.0, 1.0) * (1.0 - fresnel);

        // AO
        let ao = 1.0 - f32(steps_taken) / 100.0;
        color *= ao;

        depth = clamp(t / 20.0, 0.0, 1.0);
    } else {
        color = palette(rd.y + u.config.x * 0.1) * 0.1;
    }

    // ACES on display RGB; alpha = coverage (opaque at grazing/dense glass,
    // clearer where light transmits, faint for open sky).
    let alpha = select(0.3, clamp(1.0 - 0.45 * transmission, 0.55, 1.0), hit);
    let final_color = vec4<f32>(acesToneMap(max(color * camTrans, vec3<f32>(0.0))), alpha);

    textureStore(writeTexture, id.xy, final_color);
    textureStore(dataTextureA, id.xy, final_color);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
