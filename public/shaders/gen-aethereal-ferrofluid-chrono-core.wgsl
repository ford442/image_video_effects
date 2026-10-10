// ═══════════════════════════════════════════════════════════════════
//  Aethereal Ferrofluid Chrono-Core
//  Category: generative
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: Rosensweig needle sharpening (spike profile pow-sharpened by magnetic strength × bass); chrono clock ring (12 equatorial tick spikes, the active tick extends and glows amber); seam-routed bioluminescence (cyan glow follows the Voronoi edge distance v.y − v.x)
//  A packing: ACES display RGBA, a = coverage (hit) / seam halo (background); C unread
// ═══════════════════════════════════════════════════════════════════
//  A raymarched ferrofluid sphere whose surface is pushed out into
//  Voronoi spikes. Viscosity paces the flow, Spike Density sets the cell
//  frequency, Magnetic Strength sharpens the spikes into needles (and the
//  held-pointer dipole), Bioluminescence lights the cell seams.
#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const FAR: f32 = 20.0;
const CAM_DIST: f32 = 6.0;
const MAX_STEPS: i32 = 128;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn hash31(p: vec3<f32>) -> f32 {
    return hash33(p).x;
}

// Smooth trilinear value noise in [-1, 1]. HEAD used fract(sin(dot)) white
// noise here, which made every normal grainy.
fn valueNoise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let n000 = hash31(i);
    let n100 = hash31(i + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = hash31(i + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = hash31(i + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = hash31(i + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = hash31(i + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = hash31(i + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = hash31(i + vec3<f32>(1.0, 1.0, 1.0));
    let x00 = mix(n000, n100, w.x);
    let x10 = mix(n010, n110, w.x);
    let x01 = mix(n001, n101, w.x);
    let x11 = mix(n011, n111, w.x);
    return mix(mix(x00, x10, w.y), mix(x01, x11, w.y), w.z) * 2.0 - 1.0;
}

// 3D Voronoi for spike placement: (F1, F2, cell id)
fn voronoi(x: vec3<f32>) -> vec3<f32> {
    let p = floor(x);
    let f = fract(x);

    var res = vec3<f32>(8.0);

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let h = hash33(p + b);
                let r = b - f + h;
                let d = dot(r, r);

                if (d < res.x) {
                    res.y = res.x;
                    res.x = d;
                    res.z = h.x;
                } else if (d < res.y) {
                    res.y = d;
                }
            }
        }
    }
    return vec3<f32>(sqrt(res.x), sqrt(res.y), res.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hue2rgb(hue: f32) -> vec3<f32> {
    let R = abs(hue * 6.0 - 3.0) - 1.0;
    let G = 2.0 - abs(hue * 6.0 - 2.0);
    let B = 2.0 - abs(hue * 6.0 - 4.0);
    return saturate(vec3<f32>(R, G, B));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

struct Audio {
    bass: f32,
    mids: f32,
    treble: f32,
};

struct MapHit {
    d: f32,
    spike: f32,     // 1 at a spike tip, 0 far from the cell centre
    seam: f32,      // Voronoi edge distance F2 - F1 (0 on a seam)
    tick: f32,      // clock-ring membership (1 on a tick spike)
    litTick: f32,   // 1 on the currently lit tick
};

// Idea 2: chrono clock ring — which of the 12 ticks is lit, and how hard.
fn clockState(time: f32) -> vec2<f32> {
    let rate = 0.6 + u.zoom_params.x * 0.8;
    let phase = time * rate;
    let idx = floor(phase) - floor(phase / 12.0) * 12.0;
    let strike = exp(-fract(phase) * 3.0);
    return vec2<f32>(idx, strike);
}

fn map(p: vec3<f32>, time: f32, au: Audio) -> MapHit {
    var d = length(p) - 1.5; // Base sphere

    // Viscosity (zoom_params.x) controls temporal speed and noise amplitude
    let viscosity = u.zoom_params.x;
    // Spike Density (zoom_params.y) controls voronoi frequency
    let density = u.zoom_params.y * 5.0 + 1.0;
    let magnetic_strength = u.zoom_params.z;

    // Audio affects temporal flow
    let t = time * viscosity * (1.0 + au.bass * 0.5);

    // Apply Voronoi for spikes
    let v = voronoi(p * density + vec3<f32>(0.0, t * 0.2, 0.0));

    // Smooth out the voronoi cells to make spikes
    let spike_shape = clamp(1.0 - v.x, 0.0, 1.0);

    // Idea 1: Rosensweig needles — the field sharpens the rounded cell domes
    // into needles. Exponent and height grow with magnetic strength × (1 + bass).
    let field = magnetic_strength * (0.6 + au.bass * 1.4);
    let needle = pow(spike_shape, 1.0 + field * 3.0) * (1.0 + field * 0.7);

    // Smooth value-noise flow
    let flow = valueNoise3(p * 2.0 + vec3<f32>(sin(t), cos(t), t * 0.5));

    let spike_displacement = (needle * 0.5 + flow * 0.2) * (1.0 - viscosity * 0.5);

    d = d - spike_displacement;

    // Idea 2: chrono clock ring — 12 tapered tick spikes on the equator.
    // Fold the azimuth into the nearest tick sector and measure a tapered
    // round cone along the sector axis.
    let clk = clockState(time);
    let az = atan2(p.z, p.x);
    let sector = floor(az / TAU * 12.0 + 0.5);
    let sectorAngle = sector * TAU / 12.0;
    let qxz = rot2D(sectorAngle) * p.xz; // rotate tick axis onto +x
    let q = vec3<f32>(qxz.x, p.y, qxz.y);
    let sectorIdx = sector - floor(sector / 12.0) * 12.0;
    let isActive = 1.0 - step(0.5, abs(sectorIdx - clk.x));
    let tickLen = 0.35 + isActive * clk.y * (0.4 + au.bass * 0.3);
    let r0 = 1.3;
    let h = clamp((q.x - r0) / (tickLen + 0.2), 0.0, 1.0);
    let tickD = length(q - vec3<f32>(r0 + h * (tickLen + 0.2), 0.0, 0.0)) - mix(0.11, 0.015, h);
    let dRing = smin(d, tickD, 0.12);
    let tickMask = 1.0 - smoothstep(0.0, 0.12, tickD - d);

    // Mouse Interaction: Magnetic Dipole (held pointer)
    var d_final = dRing;
    if (u.zoom_config.w > 0.5) {
        let mouse_uv = u.zoom_config.yz; // 0 to 1, y=0 top
        let mouse_world = vec3<f32>((mouse_uv.x - 0.5) * 10.0, (0.5 - mouse_uv.y) * 10.0, 0.0);
        let dist_to_mouse = length(p - mouse_world);
        let pull = exp(-dist_to_mouse * 0.5) * magnetic_strength * 2.0;
        d_final = smin(d_final, dist_to_mouse - pull, 0.8);
    }

    var hit: MapHit;
    hit.d = d_final;
    hit.spike = spike_shape;
    hit.seam = v.y - v.x; // Idea 3: carried out for the seam glow
    hit.tick = tickMask;
    hit.litTick = tickMask * isActive * clk.y;
    return hit;
}

fn get_normal(p: vec3<f32>, time: f32, au: Audio) -> vec3<f32> {
    let e = vec2<f32>(0.0015, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, au).d - map(p - e.xyy, time, au).d,
        map(p + e.yxy, time, au).d - map(p - e.yxy, time, au).d,
        map(p + e.yyx, time, au).d - map(p - e.yyx, time, au).d
    );
    return normalize(n + vec3<f32>(1e-6));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y)) + 0.5;
    var uv = (fragCoord - 0.5 * resolution) / resolution.y;
    uv.y = -uv.y; // storage rows run top-down

    let time = u.config.x;

    var au: Audio;
    au.bass = plasmaBuffer[0].x;
    au.mids = plasmaBuffer[0].y;
    au.treble = plasmaBuffer[0].z;

    // Camera — pulled back from HEAD's 4.0 so the spiked silhouette and the
    // equatorial clock ring read against the void instead of filling the frame
    var ro = vec3<f32>(0.0, 0.0, CAM_DIST);
    let target_pt = vec3<f32>(0.0, 0.0, 0.0);

    // Mouse orbit (held pointer)
    if (u.zoom_config.w > 0.5) {
        let mouse_orbit_x = (u.zoom_config.y - 0.5) * PI * 2.0;
        // keep off the poles: cross(ww, up) is zero at ±PI/2
        let mouse_orbit_y = clamp((u.zoom_config.z - 0.5) * PI, -1.4, 1.4);
        let rotX = rot2D(mouse_orbit_y);
        let rotY = rot2D(-mouse_orbit_x);

        var temp_ro = vec3<f32>(0.0, 0.0, CAM_DIST);
        let yz = temp_ro.yz * rotX;
        temp_ro = vec3<f32>(temp_ro.x, yz.x, yz.y);
        let xz = temp_ro.xz * rotY;
        temp_ro = vec3<f32>(xz.x, temp_ro.y, xz.y);
        ro = temp_ro;
    }

    let ww = normalize(target_pt - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching (needles break the unit Lipschitz bound, so under-step)
    var t = 0.0;
    var p = ro;
    var hitInfo: MapHit;
    var steps: i32 = MAX_STEPS;
    var hit = false;
    var minSeamGlow = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * t;
        hitInfo = map(p, time, au);
        let d = hitInfo.d;
        // Idea 3 (halo): near-miss rays pick up the seam glow they graze
        minSeamGlow = max(minSeamGlow, exp(-max(d, 0.0) * 6.0) * exp(-hitInfo.seam * 10.0));

        if (abs(d) < 0.001 * (1.0 + t)) {
            steps = i;
            hit = true;
            break;
        }
        if (t > FAR) {
            steps = i;
            break;
        }
        t += d * 0.55;
    }

    let bioluminescence_intensity = u.zoom_params.w;
    var col = vec3<f32>(0.05, 0.05, 0.08); // Background
    var depth = 0.0; // far
    var alpha = 0.0;

    if (hit) {
        let n = get_normal(p, time, au);

        // Lighting
        let l = normalize(vec3<f32>(1.0, 1.0, 2.0));
        let v = -rd;
        let h = normalize(l + v);

        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(n, h), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

        // Iridescent coloring based on fresnel and normal
        let iridescence_hue = fract(dot(n, vec3<f32>(0.5)) * 0.5 + time * 0.1);
        let iridescence = hue2rgb(iridescence_hue) * fresnel;

        // Fake Ambient Occlusion based on steps
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);

        // Base metallic color
        let mat_col = vec3<f32>(0.1, 0.12, 0.15) * diff + spec * vec3<f32>(1.0) + iridescence * 2.0;

        // Idea 3: seam-routed bioluminescence. The cyan glow lives on the
        // Voronoi seams (F2 − F1 → 0) between spikes, pooled in the valleys,
        // with bands that run outward from each seam, paced by mids.
        let valley = saturate(1.0 - hitInfo.spike * 2.0);
        let seamLine = exp(-hitInfo.seam * 14.0);
        let seamPulse = 0.6 + 0.4 * sin(hitInfo.seam * 30.0 - time * (2.0 + au.mids * 4.0));
        let bio_color = vec3<f32>(0.0, 0.8, 1.0) * (seamLine * seamPulse + valley * 0.35);
        let bio = bio_color * bioluminescence_intensity * (1.0 + au.bass * 2.0) * ao;

        // Idea 2: clock ring — brushed bezel ticks, the active tick strikes amber
        let tickMetal = vec3<f32>(0.55, 0.5, 0.42) * (diff * 0.6 + spec) * hitInfo.tick;
        let tickGlow = vec3<f32>(1.0, 0.55, 0.15) * hitInfo.litTick * (2.0 + au.treble * 3.0);

        col = mat_col * ao + bio + tickMetal * ao + tickGlow;

        // Depth: near = 1
        depth = clamp(1.0 - (t - 0.1) / (FAR - 0.1), 0.0, 1.0);
        alpha = clamp(1.0 - 0.25 * fresnel, 0.0, 1.0);
    } else {
        // Background: faint seam halo around the silhouette
        let halo = vec3<f32>(0.0, 0.5, 0.7) * minSeamGlow * bioluminescence_intensity * 0.25;
        col = col + halo;
        alpha = clamp(minSeamGlow * bioluminescence_intensity * 0.3, 0.0, 0.6);
    }

    let display = acesToneMap(max(col, vec3<f32>(0.0)));

    let store_coord = vec2<i32>(global_id.xy);
    textureStore(writeTexture, store_coord, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, store_coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, store_coord, vec4<f32>(display, alpha));
}
