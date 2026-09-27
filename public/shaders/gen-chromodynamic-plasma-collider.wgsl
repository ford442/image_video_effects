// ═══════════════════════════════════════════════════════════════════
//  Chromodynamic Plasma-Collider
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive,
//            upgraded-rgba, aces-tone-map, temporal-feedback
//  Complexity: High
//  Chunks From: gen-protocell-division.wgsl (upgraded-rgba stack)
//  Upgraded: 2026-09-27
//  Ideas: bunch-crossing bursts at the ring planes; magnetic beam steering + betatron wobble; momentum dispersion in the bends
//  A packing: HDR linear radiance RGB (pre-ACES) + semantic alpha; C read back as HDR history
//  By: Claude Code Batch 3B
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
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Ring Density, y=Collision Rate, z=Anomaly Pull, w=Tunnel Warp
    ripples: array<vec4<f32>, 50>,
};

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise for FBM
fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    return fract(dot(q, q + 33.33));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn map(p_in: vec3<f32>, time: f32, audio: f32, ring_density: f32, warp: f32) -> f32 {
    var p = p_in;
    // Tunnel Warp (4D relativistic speed distortion)
    p.x += sin(p.z * 0.1 * warp + time) * 2.0 * warp;
    p.y += cos(p.z * 0.15 * warp - time * 0.5) * 1.5 * warp;

    // Magnetic containment tunnel
    let tunnel_radius = 3.0 + audio * 0.12;
    let base_tunnel = length(p.xy) - tunnel_radius;

    // Domain repetition for obsidian magnetic rings
    let ring_spacing = 30.0 / max(ring_density, 1.0);
    let p_z_mod = (fract(p.z / ring_spacing + 0.5) - 0.5) * ring_spacing;
    // FIX: HEAD was max(base_tunnel, |z|-0.2) = a SOLID DISC every ring_spacing, so every ray
    // hit a disc at t~0.8. Hollow washer rings + an obsidian sleeve wall make the tunnel visible.
    let rings = max(abs(base_tunnel) - 0.25, abs(p_z_mod) - 0.2);
    let sleeve = (tunnel_radius + 1.2) - length(p.xy);

    // High-frequency SDF streams (particle streaks)
    var d = min(rings, sleeve);
    return d;
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, ring_density: f32, warp: f32) -> vec3<f32> {
    let e = vec2<f32>(0.002, -0.002);
    let n = e.xyy * map(p + e.xyy, time, audio, ring_density, warp)
          + e.yyx * map(p + e.yyx, time, audio, ring_density, warp)
          + e.yxy * map(p + e.yxy, time, audio, ring_density, warp)
          + e.xxx * map(p + e.xxx, time, audio, ring_density, warp);
    let l = length(n);
    return select(vec3<f32>(0.0, 0.0, -1.0), n / l, l > 1e-6);
}

// Same displacement map() applies: world -> tunnel (warped) coordinates are p.xy + tunnelOffset(p.z).
fn tunnelOffset(z: f32, time: f32, warp: f32) -> vec2<f32> {
    return vec2<f32>(sin(z * 0.1 * warp + time) * 2.0 * warp, cos(z * 0.15 * warp - time * 0.5) * 1.5 * warp);
}

// d(tunnelOffset)/dz: how hard the containment field is bending the orbit here.
fn tunnelSlope(z: f32, time: f32, warp: f32) -> vec2<f32> {
    return vec2<f32>(cos(z * 0.1 * warp + time) * 0.2 * warp * warp,
                     -sin(z * 0.15 * warp - time * 0.5) * 0.225 * warp * warp);
}

fn clampLen(v: vec2<f32>, m: f32) -> vec2<f32> {
    let l = length(v);
    return select(v, v * (m / l), l > m);
}

// Idea 2: Magnetic beam steering + betatron wobble. Beam axis in tunnel coordinates: bends
// quadratically with distance ahead toward the anomaly (saturating at the containment band) and
// oscillates about the design orbit with a betatron tune of 0.17 per ring cell.
fn beamAxis(z: f32, dz: f32, steer: vec2<f32>, ring_spacing: f32, time: f32) -> vec2<f32> {
    let dzc = max(dz, 0.0);
    let bend = clampLen(steer * 0.02 * dzc * dzc, 2.0);
    let tune = 6.2832 * 0.17 / ring_spacing;
    let betatron = 0.3 * vec2<f32>(sin(z * tune + time * 1.3), cos(z * tune * 1.13 - time * 1.1));
    return bend + betatron;
}

// Idea 3: Momentum dispersion in the bends. Lower-momentum (red) and higher-momentum (blue)
// components are deflected by +/- this offset along the local bend (warp slope + steering slope).
fn dispersionOffset(z: f32, dz: f32, steer: vec2<f32>, time: f32, warp: f32) -> vec2<f32> {
    let steerSlope = select(steer * 0.04 * max(dz, 0.0), vec2<f32>(0.0), length(steer * 0.02 * dz * dz) > 2.0);
    return clampLen((tunnelSlope(z, time, warp) + steerSlope) * 3.0, 0.6);
}

// Idea 1: Bunch-crossing clock for one ring plane. HEAD's bunch phase s = z*rate*0.1 - 5t; every
// time the train passes ring k a luminosity lottery decides whether a collision fires.
// Returns (fired 0/1, age in seconds since the bunch crossed the ring).
fn crossingEvent(ringId: f32, z: f32, collision_rate: f32, time: f32) -> vec2<f32> {
    let cyc = time * 5.0 - z * collision_rate * 0.1;
    let n = floor(cyc);
    let prob = clamp(0.12 + collision_rate * 0.035, 0.12, 0.85);
    let fired = select(0.0, 1.0, hash(vec3<f32>(ringId, n, 17.0)) < prob);
    return vec2<f32>(fired, fract(cyc) / 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;
    let time = u.config.x;
    let audio = plasmaBuffer[0].x;

    let ring_density = u.zoom_params.x;
    let collision_rate = u.zoom_params.y;
    let anomaly_pull = u.zoom_params.z;
    let tunnel_warp = u.zoom_params.w;

    // Camera setup for high-speed journey
    let speed = 10.0 + audio * 5.0;
    var ro = vec3<f32>(0.0, 0.0, time * speed);

    // Apply tunnel warp to camera
    ro.x -= sin(ro.z * 0.1 * tunnel_warp + time) * 2.0 * tunnel_warp;
    ro.y -= cos(ro.z * 0.15 * tunnel_warp - time * 0.5) * 1.5 * tunnel_warp;

    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse interaction (Magnetic Anomaly)
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouse = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouse) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouse += mouseVelocity * springDt;
    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = time;
    }
    let mouseNdc = (mouse - vec2<f32>(0.5)) * vec2<f32>(res.x / res.y, 1.0);
    let anomalyTarget = normalize(vec3<f32>(mouseNdc * 0.75, 1.0));
    rd = normalize(mix(rd, anomalyTarget, clamp(anomaly_pull * 0.08, 0.0, 0.4)));
    // Idea 2: the anomaly also steers the beam itself (not just the camera).
    let steer = mouseNdc * anomaly_pull;
    let ring_spacing = 30.0 / max(ring_density, 1.0);

    var t = 0.0;
    var d = 0.0;
    var hit = false;
    var p = ro;

    // Raymarching loop
    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        d = map(p, time, audio, ring_density, tunnel_warp);
        if (abs(d) < 0.001) { hit = true; break; }
        t += max(abs(d) * 0.7, 0.002);
        if (t > 100.0) { break; }
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let depth = t / 100.0;
        // Obsidian ring color
        let tunnelXY = p.xy + tunnelOffset(p.z, time, tunnel_warp);
        let isRing = length(tunnelXY) < 3.6 + audio * 0.12;
        let base_col = vec3<f32>(0.05, 0.05, 0.08) * select(0.6, 1.0, isRing);
        col = base_col * (1.0 - depth);

        // Specular highlight approximation
        // FIX: HEAD normal was normalize(p.x, p.y, 0) in unwarped space, so reflect(rd,n).z == rd.z > 0
        // and spec against (0,0,-1) was always 0. Real SDF normal; the (steered) beam is the light.
        let n = calcNormal(p, time, audio, ring_density, tunnel_warp);
        let toBeam = beamAxis(p.z, p.z - ro.z, steer, ring_spacing, time) - tunnelXY;
        let L = normalize(vec3<f32>(toBeam, -0.3));
        let beamFall = 1.0 / (1.0 + dot(toBeam, toBeam) * 0.15);
        let spec = pow(max(dot(reflect(rd, n), L), 0.0), 32.0);
        col += vec3<f32>(0.8, 0.9, 1.0) * spec * (1.0 - depth) * beamFall;
        col += vec3<f32>(0.25, 0.35, 0.9) * max(dot(n, L), 0.0) * 0.12 * beamFall * (1.0 - depth);

        // Idea 1: the ring whose bunch crossing just fired glows magenta along its rim.
        if (isRing) {
            let ringId = floor(p.z / ring_spacing + 0.5);
            let ev = crossingEvent(ringId, ringId * ring_spacing, collision_rate, time);
            col += vec3<f32>(1.0, 0.2, 0.8) * ev.x * exp(-ev.y * 10.0) * 0.5 * (1.0 - depth);
        }
    }
    let t_limit = select(100.0, t, hit);

    // Plasma & Particle Collisions Pass (Volumetric accumulation)
    var plasma = vec3<f32>(0.0);
    var t_vol = 0.0;
    for (var i = 0; i < 30; i++) {
        // FIX: stop at the opaque ring/sleeve hit (HEAD accumulated plasma behind it).
        if (t_vol > t_limit) { break; }
        let vp = ro + rd * t_vol;
        // Particle streams intersecting
        let particle_phase = fract(vp.z * collision_rate * 0.1 - time * 5.0);
        // FIX: measure from the warped tunnel axis (HEAD used unwarped world xy, so the beam
        // drifted off the rings by up to 1-4 units).
        let tunnelXY = vp.xy + tunnelOffset(vp.z, time, tunnel_warp);
        let beamRel = tunnelXY - beamAxis(vp.z, vp.z - ro.z, steer, ring_spacing, time);
        let dist_to_center = length(beamRel);

        if (particle_phase < 0.1) {
             let burst = (0.1 - particle_phase) * 10.0;
             // Idea 3: per-channel beam lookups offset along the bend (collapses to HEAD's
             // single dist_to_center < 1 gate when the orbit is straight).
             let disp = dispersionOffset(vp.z, vp.z - ro.z, steer, time, tunnel_warp);
             let gate = vec3<f32>(select(0.0, 1.0, length(beamRel - disp) < 1.0),
                                  select(0.0, 1.0, dist_to_center < 1.0),
                                  select(0.0, 1.0, length(beamRel + disp) < 1.0));
             let chromatic = vec3<f32>(1.0, 0.2, 0.8) * burst * gate; // Magenta/Cyan dispersion
             plasma += chromatic * (1.0 + audio * 2.0) * 0.05;
        }

        // Glowing containment fields
        let dist_to_wall_axis = length(tunnelXY);
        if (dist_to_wall_axis > 2.5 && dist_to_wall_axis < 3.0) {
             plasma += vec3<f32>(0.1, 0.3, 0.8) * (1.0 + audio) * 0.02;
        }

        t_vol += 3.3; // Step size
    }

    // Ring-plane pass: evaluated analytically where the ray pierces each containment ring's plane,
    // so the beam cross-section and the crossing bursts are alias-free (no 3.3-unit stepping).
    let k0 = floor(ro.z / ring_spacing) + 1.0;
    for (var j = 0; j < 24; j++) {
        let ringId = k0 + f32(j);
        let zk = ringId * ring_spacing;
        let tk = (zk - ro.z) / max(rd.z, 1e-3);
        if (tk > t_limit) { break; }
        let q = ro + rd * tk;
        let dz = zk - ro.z;
        let rel = q.xy + tunnelOffset(zk, time, tunnel_warp) - beamAxis(zk, dz, steer, ring_spacing, time);
        // Idea 3: dispersed R/G/B radii of the beam at this ring.
        let disp = dispersionOffset(zk, dz, steer, time, tunnel_warp);
        let r3 = vec3<f32>(length(rel - disp), length(rel), length(rel + disp));
        let atten = exp(-tk * 0.035) * smoothstep(0.5, 3.0, tk);

        // Idea 2/3: beam cross-section threading the ring aperture (traces the steered, wobbling orbit).
        plasma += exp(-r3 * r3 * 10.0) * vec3<f32>(0.55, 0.45, 1.0) * 0.08 * atten;

        // Idea 1: bunch-crossing burst — core flash + debris shell expanding out to the ring.
        let ev = crossingEvent(ringId, zk, collision_rate, time);
        if (ev.x > 0.5) {
            let shellR = 0.25 + ev.y * 14.0;
            let burst3 = exp(-r3 * r3 * 3.0) * exp(-ev.y * 22.0) * 0.9
                       + exp(-abs(r3 - vec3<f32>(shellR)) * 7.0) * exp(-ev.y * 9.0) * 0.4;
            plasma += vec3<f32>(1.0, 0.2, 0.8) * burst3 * atten * (1.0 + audio * 2.0) * 0.5;
        }
    }

    col += plasma;

    let uv01 = (vec2<f32>(global_id.xy) + vec2<f32>(0.5)) / res;
    var collisionFlash = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.5) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(res.x / res.y, 1.0);
            let radius = length(delta);
            let shell = exp(-abs(radius - age * 0.3) * 78.0) * exp(-age * 2.0);
            collisionFlash = max(collisionFlash, shell);
        }
    }
    col += vec3<f32>(1.2, 0.25, 0.9) * collisionFlash * (0.75 + plasmaBuffer[0].z * 0.35);

    // ═══ CHUNK: temporal-feedback (dataTextureC → dataTextureA) ═══
    let coord = vec2<i32>(global_id.xy);
    let prev = textureLoad(dataTextureC, coord, 0);
    // C holds HDR radiance (A is written pre-ACES below), so this blend is HDR-consistent.
    // FIX: HEAD stored ACES colour in A, blended it here as HDR and tone-mapped it a second time.
    col = mix(col, prev.rgb * 0.92, clamp(0.04 + audio * 0.01, 0.0, 0.07));
    let hdr = max(col, vec3<f32>(0.0));

    // (HEAD's constant "chromatic-aberration" red lift is replaced by Idea 3's beam dispersion.)
    col = acesToneMap(hdr * 1.2);

    let _luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let _alpha = clamp(_luma * 0.75 + collisionFlash * 0.3, 0.0, 0.96);
    textureStore(writeTexture, global_id.xy, vec4<f32>(col, _alpha));
    let _depth = select(0.0, clamp(1.0 - t / 100.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdr, _alpha));
}
