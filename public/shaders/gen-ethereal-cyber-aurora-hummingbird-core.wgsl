// ═══════════════════════════════════════════════════════════════════
//  Ethereal Cyber-Aurora Hummingbird-Core
//  Category: generative
//  Features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba
//  Upgraded: 2026-10-18
//  Ideas: spring-eased hover target; bass nectar bloom; treble wingbeat
//         afterimage; gorget plate split by Aberration; forked tail ribbons;
//         figure-eight hover stroke (fore-aft sweep at half the flap rate,
//         wing pitch flips at each stroke reversal); lapping forked tongue
//         (licks out of the beak tip, reach swells with the nectar envelope)
//  A packing: HDR display RGB (ACES on output); alpha = hit coverage +
//             glow/shock energy. Texels (0,0) and (1,0) hold hover state:
//             (0,0) = eased.xy, vel.xy; (1,0) = nectar env, marker 7.25
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Flutter Speed, y=Aura Intensity, z=Pollen Density, w=Aberration

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// --- Helper Functions ---
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D Noise for volumetric pollen
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    let n = p.x + p.y * 57.0 + 113.0 * p.z;

    let res = mix(
        mix(
            mix(fract(sin(n + 0.0)*43758.5453), fract(sin(n + 1.0)*43758.5453), f2.x),
            mix(fract(sin(n + 57.0)*43758.5453), fract(sin(n + 58.0)*43758.5453), f2.x),
            f2.y
        ),
        mix(
            mix(fract(sin(n + 113.0)*43758.5453), fract(sin(n + 114.0)*43758.5453), f2.x),
            mix(fract(sin(n + 170.0)*43758.5453), fract(sin(n + 171.0)*43758.5453), f2.x),
            f2.y
        ),
        f2.z
    );
    return res;
}

// Simplex-like noise for auroral texture
fn simplex(p: vec3<f32>) -> f32 {
    return noise3(p * 2.0) * 0.5 + noise3(p * 4.0) * 0.25 + noise3(p * 8.0) * 0.125;
}

// SDF primitives
fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// Idea — lapping tongue: a forked tongue flicks out of the beak tip three
// times a second, tilted slightly up so it clears the head as seen from the
// chase camera; reach swells with the nectar envelope. p is the bird body frame.
fn sdTongue(p: vec3<f32>, t: f32, nectar: f32) -> f32 {
    let lick = sin(PI * fract(t * 3.0));
    let reach = lick * lick * (0.17 + nectar * 0.16);
    let beakTip = vec3<f32>(0.0, 0.2, 1.38 + nectar * 0.08);
    let tongueEnd = beakTip + vec3<f32>(0.0, 0.12 * reach, reach);
    let fork = 0.045 * lick;
    var tongue = sdCapsule(p, beakTip, tongueEnd, 0.012);
    tongue = min(tongue, sdCapsule(p, tongueEnd, tongueEnd + vec3<f32>(fork, 0.01, fork * 1.2), 0.009));
    tongue = min(tongue, sdCapsule(p, tongueEnd, tongueEnd + vec3<f32>(-fork, 0.01, fork * 1.2), 0.009));
    // Hidden inside the beak when retracted.
    return select(tongue, MAX_DIST, reach < 0.004);
}

// Tongue halo, analytic and unoccluded so it reads past the head silhouette:
// distance from the whole ray line to the (unwarped) tongue segment in world.
fn tongueHalo(ro: vec3<f32>, rd: vec3<f32>, t: f32, hover: vec4<f32>) -> f32 {
    let lick = sin(PI * fract(t * 3.0));
    let reach = lick * lick * (0.17 + hover.w * 0.16);
    if (reach < 0.004) { return 0.0; }
    let unbank = rot(-hover.z);
    let b0 = vec3<f32>(0.0, 0.2, 1.38 + hover.w * 0.08);
    let b1 = b0 + vec3<f32>(0.0, 0.12 * reach, reach);
    let x0 = unbank * b0.xy;
    let x1 = unbank * b1.xy;
    let a = vec3<f32>(x0.x + hover.x, x0.y + hover.y, b0.z);
    let seg = vec3<f32>(x1.x + hover.x, x1.y + hover.y, b1.z) - a;
    // Closest approach between the ray line and the segment.
    let w0 = ro - a;
    let bb = dot(rd, seg);
    let cc = dot(seg, seg);
    let dd = dot(rd, w0);
    let ee = dot(seg, w0);
    let den = max(cc - bb * bb, 1e-6);
    let sc = clamp((ee - bb * dd) / den, 0.0, 1.0);
    let along = max(dot(a + seg * sc - ro, rd), 0.5);
    let q = a + seg * sc - ro;
    // Angular distance (radians); one pixel is ~1/res.y.
    let ang = length(q - rd * dot(q, rd)) / along;
    return lick * (exp(-ang * ang * 2.0e5) + 0.3 * exp(-ang * ang * 1.5e4));
}

// --- Map Function ---
fn map(p_in: vec3<f32>, t: f32, audio: f32, flutter: f32, hover: vec4<f32>) -> vec2<f32> {
    // hover.xy = spring-eased bird offset, hover.z = bank roll, hover.w = nectar bloom
    var p = p_in - vec3<f32>(hover.x, hover.y, 0.0);
    let bank = rot(hover.z);
    let p_bank = bank * p.xy;
    p.x = p_bank.x;
    p.y = p_bank.y;
    let p_world = p_in;
    var d = MAX_DIST;
    var mat_id = 0.0;

    // Temporal high-frequency distortion for wings
    let wing_time = t * flutter * 10.0;

    // Core body (cyber-organic SDF)
    var p_body = p;
    // Low frequency warp
    p_body.y += sin(p_body.x * 2.0 + t) * 0.1;
    let body_base = sdEllipsoid(p_body, vec3<f32>(0.4, 0.2, 0.6));
    let head = sdEllipsoid(p_body - vec3<f32>(0.0, 0.2, 0.7), vec3<f32>(0.2, 0.15, 0.25));
    let beak = sdEllipsoid(p_body - vec3<f32>(0.0, 0.2, 1.1 + hover.w * 0.08), vec3<f32>(0.02 + hover.w * 0.01, 0.02 + hover.w * 0.01, 0.3));

    var body = smin(body_base, head, 0.2);
    body = smin(body, beak, 0.1);

    // Idea — gorget: a small throat plate in front of the head.
    let gorget = sdEllipsoid(p_body - vec3<f32>(0.0, 0.14, 0.9), vec3<f32>(0.09, 0.055, 0.02));

    // Idea — forked tail ribbons behind the body.
    let tailRibbon = min(
        sdEllipsoid(p_body - vec3<f32>(0.14, -0.02, -1.0), vec3<f32>(0.03, 0.015, 0.55)),
        sdEllipsoid(p_body - vec3<f32>(-0.14, -0.02, -1.0), vec3<f32>(0.03, 0.015, 0.55))
    );

    let tongue = sdTongue(p_body, t, hover.w);

    // Add auroral plasma texture displacement
    body -= simplex(p_body * 5.0 + vec3<f32>(t, 0.0, t)) * 0.05 * audio;

    // Wings
    var p_wing = p;
    p_wing.x = abs(p_wing.x) - 0.4; // mirror

    // Idea — figure-eight hover stroke: the stroke plane sweeps fore-aft at
    // half the flap rate, so each tip traces an 8 (vertical 2f, horizontal f).
    let sweep = rot(0.45 * sin(wing_time * 0.5));
    let p_wing_xz_sweep = sweep * p_wing.xz;
    p_wing.x = p_wing_xz_sweep.x;
    p_wing.z = p_wing_xz_sweep.y;

    // Flapping rotation
    let flap_angle = sin(wing_time) * 1.5;

    // Manual rotation matrices instead of mat3x3 components for rotZ
    let rot_flap = rot(flap_angle);
    let p_wing_xy_rot = rot_flap * p_wing.xy;
    p_wing.x = p_wing_xy_rot.x;
    p_wing.y = p_wing_xy_rot.y;

    // Wing pitch flips through the stroke reversal (supination on the back-sweep).
    let rot_pitch = rot(0.5 * cos(wing_time * 0.5));
    let p_wing_zy_rot = rot_pitch * p_wing.zy;
    p_wing.z = p_wing_zy_rot.x;
    p_wing.y = p_wing_zy_rot.y;

    // High frequency displacement for fractal light trails
    let wing_disp = sin(p_wing.x * 20.0 + wing_time) * sin(p_wing.z * 15.0 - wing_time) * 0.05;

    let wing = sdBox(p_wing - vec3<f32>(0.5, 0.0, 0.0), vec3<f32>(0.6, 0.01, 0.3)) + wing_disp;

    // Chrono-flower gravity well (Radial domain repetition)
    var p_flower = p_world;
    p_flower.y += 1.0;

    let petals = 8.0;
    let angle = atan2(p_flower.z, p_flower.x);
    let r = length(p_flower.xz);
    let local_angle = (angle * petals / PI) - t;

    let flower_disp = sin(r * 5.0 - t * 2.0) * 0.2 * audio;
    let flower = sdEllipsoid(vec3<f32>(r - 1.5, p_flower.y, local_angle), vec3<f32>(0.5 + hover.w * 0.25, 0.1 + hover.w * 0.05, 0.2)) + flower_disp;

    // Combine
    if (body < d) {
        d = body;
        mat_id = 1.0; // Body
    }
    if (wing < d) {
        d = wing;
        mat_id = 2.0; // Wings
    }
    if (flower < d) {
        d = flower;
        mat_id = 3.0; // Flower
    }
    if (gorget < d) {
        d = gorget;
        mat_id = 4.0; // Gorget
    }
    if (tailRibbon < d) {
        d = tailRibbon;
        mat_id = 5.0; // Tail ribbons
    }
    if (tongue < d) {
        d = tongue;
        mat_id = 6.0; // Tongue
    }

    return vec2<f32>(d, mat_id);
}

fn calcNormal(p: vec3<f32>, t: f32, audio: f32, flutter: f32, hover: vec4<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy, t, audio, flutter, hover).x +
                     e.yyx * map(p + e.yyx, t, audio, flutter, hover).x +
                     e.yxy * map(p + e.yxy, t, audio, flutter, hover).x +
                     e.xxx * map(p + e.xxx, t, audio, flutter, hover).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let t = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = 1.0 + bass * 1.1 + mids * 0.45 + treble * 0.25;

    let flutter = clamp(u.zoom_params.x, 0.1, 5.0);
    let aura_intensity = clamp(u.zoom_params.y, 0.0, 2.0);
    let pollen_density = clamp(u.zoom_params.z, 0.0, 3.0);
    let aberration = clamp(u.zoom_params.w, 0.0, 1.0);

    let uv01 = (vec2<f32>(id.xy) + 0.5) / res;
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = t - ripple.z;
        if (age >= 0.0 && age < 2.5) {
            let front = abs(length((uv01 - ripple.xy) * vec2<f32>(res.x / res.y, 1.0)) - age * (0.2 + flutter * 0.025));
            shock += (1.0 - smoothstep(0.0, 0.025, front)) * (1.0 - age / 2.5);
        }
    }
    shock = min(shock, 2.0);

    // Mouse Interaction
    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    if (length(mouse) < 0.01) {
        mouse = vec2<f32>(0.5, 0.5);
    }
    let m_uv = (mouse - 0.5) * PI * 2.0;

    // Spring-eased hover target + bass nectar envelope, persisted in A texels
    // (0,0)/(1,0) and read back from C. World +X is screen-left, +Y screen-up.
    let rawTarget = (mouse - 0.5) * vec2<f32>(-0.9, -0.6);
    var eased = rawTarget;
    var vel = vec2<f32>(0.0);
    var env = bass;
    let s0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let s1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    if (abs(s1.y - 7.25) < 0.01) {
        eased = clamp(s0.xy, vec2<f32>(-1.0), vec2<f32>(1.0));
        vel = clamp(s0.zw, vec2<f32>(-0.5), vec2<f32>(0.5));
        vel = (vel + (rawTarget - eased) * 0.12) * 0.78;
        eased += vel;
        env = max(bass, clamp(s1.x, 0.0, 2.0) * 0.94);
    }
    let isState0 = id.x == 0u && id.y == 0u;
    let isState1 = id.x == 1u && id.y == 0u;
    let nectar = clamp(env, 0.0, 1.5);
    let hover = vec4<f32>(eased, clamp(-vel.x * 6.0, -0.6, 0.6), nectar);

    // Camera setup
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    var ro = vec3<f32>(0.0, 1.0, -4.0 + held * 0.7);

    // Mouse rotation
    let rot_x = rot(m_uv.x);
    let ro_xz_rot = rot_x * ro.xz;
    ro.x = ro_xz_rot.x;
    ro.z = ro_xz_rot.y;

    let rot_y = rot(m_uv.y);
    let ro_yz_rot = rot_y * ro.yz;
    ro.y = ro_yz_rot.x;
    ro.z = ro_yz_rot.y;

    // uv.y grows downward; negate both axes so world +Y is screen-up (a 180°
    // turn — flipping only y would mirror left/right).
    var rd = normalize(vec3<f32>(-uv.x, -uv.y, 1.0));
    let rd_xz_rot = rot_x * rd.xz;
    rd.x = rd_xz_rot.x;
    rd.z = rd_xz_rot.y;
    let rd_yz_rot = rot_y * rd.yz;
    rd.y = rd_yz_rot.x;
    rd.z = rd_yz_rot.y;

    // Aberration Ray Offsets
    var rd_r = rd;
    var rd_b = rd;
    let ab_amount = aberration * 0.02 * audio;
    rd_r.x += ab_amount;
    rd_b.x -= ab_amount;

    // Render Function
    var final_color = vec3<f32>(0.0);
    var final_depth = 0.0;
    var coverage = 0.0;

    let rds = array<vec3<f32>, 3>(rd_r, rd, rd_b);
    let colors = array<vec3<f32>, 3>(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 1.0));

    for (var i = 0; i < 3; i++) {
        let cur_rd = rds[i];
        var dO = 0.0;
        var p = ro;
        var hit = false;
        var m = 0.0;

        var glow = 0.0;

        for (var i_step = 0; i_step < MAX_STEPS; i_step++) {
            let res_map = map(p, t, audio, flutter, hover);
            let d = res_map.x;
            m = res_map.y;

            // Volumetric accumulation (Auroral bloom)
            if (d < 0.5) {
               glow += 0.01 / (1.0 + d * d * 50.0);
            }

            if (d < SURF_DIST) {
                hit = true;
                break;
            }
            if (dO > MAX_DIST) {
                break;
            }

            p += cur_rd * d;
            dO += d;
        }

        final_depth = max(final_depth, dO);

        var col = vec3<f32>(0.0);

        if (hit) {
            coverage = max(coverage, 1.0);
            let n = calcNormal(p, t, audio, flutter, hover);
            let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let diff = max(dot(n, l), 0.0);
            let fresnel = pow(1.0 - max(dot(n, -cur_rd), 0.0), 3.0);

            if (m == 1.0) {
                // Body: Deep cyan/magenta with auroral emission
                col = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.0, 0.8), sin(p.y * 5.0 + t) * 0.5 + 0.5);
                col *= diff;
                col += vec3<f32>(0.0, 1.0, 1.0) * fresnel * aura_intensity;
            } else if (m == 2.0) {
                // Wings: Refractive / Plasma trails
                col = vec3<f32>(1.0, 0.9, 0.1) * fresnel * 2.0;
                col += vec3<f32>(0.5, 0.1, 1.0) * sin(p.z * 10.0 - t * flutter * 5.0) * aura_intensity;
            } else if (m == 3.0) {
                // Chrono-flower
                col = vec3<f32>(0.1, 0.0, 0.2) * diff;
                col += vec3<f32>(0.8, 0.0, 1.0) * fresnel;
                // Nectar bloom: warm glow rising from petal rims on bass
                col += vec3<f32>(1.0, 0.55, 0.9) * fresnel * nectar * aura_intensity * 1.5;
            } else if (m == 4.0) {
                // Gorget: view angle splits emerald and magenta. Aberration owns the split.
                let ndv = max(dot(n, -cur_rd), 0.0);
                let split = clamp(0.5 + aberration * (ndv * 2.0 - 1.0), 0.0, 1.0);
                col = mix(vec3<f32>(0.1, 0.9, 0.55), vec3<f32>(1.0, 0.12, 0.62), split);
                col *= diff + 0.35;
                col += vec3<f32>(1.0, 0.85, 0.95) * fresnel * (0.3 + aberration);
            } else if (m == 5.0) {
                col = vec3<f32>(0.15, 0.85, 1.0) * (0.4 + fresnel * 1.6) * aura_intensity;
                col += vec3<f32>(0.9, 0.3, 1.0) * fresnel * (0.3 + audio);
            } else if (m == 6.0) {
                // Tongue: wet nectar-pink, glowing with the nectar envelope.
                col = vec3<f32>(1.0, 0.42, 0.62) * (0.35 + diff * 0.65);
                col += vec3<f32>(1.0, 0.75, 0.9) * (fresnel + nectar * 0.8) * (0.5 + aura_intensity);
            }
        }

        // Background / Void Void
        col += vec3<f32>(0.0, 0.05, 0.1) * (1.0 - exp(-dO * 0.05));

        // Apply glow
        col += vec3<f32>(0.0, 0.5, 1.0) * glow * aura_intensity;
        col += vec3<f32>(1.0, 0.45, 0.75) * tongueHalo(ro, cur_rd, t, hover) * (0.6 + nectar + aura_intensity * 0.5);

        // Volumetric Pollen
        if (pollen_density > 0.0) {
            let p_pollen = ro + cur_rd * min(dO, MAX_DIST) * 0.5;
            let n_pollen = noise3(p_pollen * 5.0 + t * 0.5);
            let p_mask = smoothstep(0.7, 1.0, n_pollen);
            col += vec3<f32>(1.0, 1.0, 0.5) * p_mask * pollen_density * audio;
        }

        final_color += col * colors[i];
    }

    final_color += vec3<f32>(0.25, 0.8, 1.0) * shock * (0.45 + treble * 0.8);
    // Wing stripes swing negative; ACES maps negatives to bright, so clamp.
    final_color = max(final_color, vec3<f32>(0.0));
    var prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    if (isState0 || isState1) { prev = vec4<f32>(0.0); }
    // Wingbeat afterimage: treble + flutter lengthen persistence of trails
    let persist = clamp(0.9 + treble * 0.06 + flutter * 0.006, 0.85, 0.97);
    let hdr = mix(prev.rgb * persist, final_color, 0.3 + bass * 0.03);
    let mapped = acesToneMap(hdr * 1.15);
    let alpha = clamp(coverage * 0.68 + length(hdr) * 0.12 + shock * 0.22, 0.03, 1.0);
    textureStore(writeTexture, id.xy, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(1.0 - clamp(final_depth / MAX_DIST, 0.0, 1.0), 0.0, 0.0, 1.0));
    var outA = vec4<f32>(hdr, alpha);
    if (isState0) { outA = vec4<f32>(eased, vel); }
    if (isState1) { outA = vec4<f32>(env, 7.25, 0.0, 0.0); }
    textureStore(dataTextureA, vec2<i32>(id.xy), outA);
}
