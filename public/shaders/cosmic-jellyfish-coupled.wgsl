// ═══════════════════════════════════════════════════════════════════
//  cosmic-jellyfish-coupled
//  Category: advanced-hybrid
//  Features: raymarching, fluid-coupling, mouse-driven, bioluminescent, upgraded-rgba
//  Complexity: Very High
//  Chunks From: cosmic-jellyfish.wgsl, mouse-fluid-coupling.wgsl
//  Created: 2026-04-18
//  By: Agent CB-16 — Generative & Cosmic Enhancer
//  Upgraded: 2026-10-31
//  Ideas: damped travelling contraction wave down the tentacles (§12.2D);
//         translucent gel — Henyey-Greenstein back-light + Beer-Lambert thickness (§12.2F);
//         stir-lit plankton motes from the fluid field
//  A packing: raw fluid state (vel.xy, vel.x-vel.y, dens); texel (0,0) = (mouse.xy, sentinel, 1)
// ═══════════════════════════════════════════════════════════════════
//  A majestic cosmic jellyfish whose tentacles and bell are distorted
//  by a real-time fluid velocity field. Mouse movement stirs the fluid
//  which advects the raymarched SDF, creating organic viscous motion.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Exact bilinear read of the rgba32float fluid history (no filtering sampler).
fn bilinC(uv: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
    let p = uv * res - vec2<f32>(0.5);
    let i = vec2<i32>(floor(p));
    let f = fract(p);
    let m = vec2<i32>(res) - vec2<i32>(1);
    let a = textureLoad(dataTextureC, clamp(i, vec2<i32>(0), m), 0);
    let b = textureLoad(dataTextureC, clamp(i + vec2<i32>(1, 0), vec2<i32>(0), m), 0);
    let c = textureLoad(dataTextureC, clamp(i + vec2<i32>(0, 1), vec2<i32>(0), m), 0);
    let d = textureLoad(dataTextureC, clamp(i + vec2<i32>(1, 1), vec2<i32>(0), m), 0);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ACES (Narkowicz fit) for the display path; callers clamp >= 0 first.
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn stars(dir: vec3<f32>) -> f32 {
    var p = dir * 100.0;
    let cell = floor(p);
    let local = fract(p);
    let n = cell.x + cell.y * 57.0 + cell.z * 113.0;
    let h = hash(n);
    if (h > 0.95) {
        let star_pos = vec3<f32>(hash(n + 1.0), hash(n + 2.0), hash(n + 3.0));
        let d = length(local - star_pos);
        return smoothstep(0.1, 0.0, d);
    }
    return 0.0;
}

fn map(p: vec3<f32>, time: f32, fluidVel: vec2<f32>) -> f32 {
    let pulse_speed = u.zoom_params.x * 2.0;
    let pulse = sin(time * pulse_speed) * 0.1;
    let tentacle_amp = u.zoom_params.y;

    // Fluid distortion on position
    let fluidDistort = vec3<f32>(fluidVel.x, fluidVel.y, 0.0) * 0.5;
    var p_bell = p - fluidDistort;
    p_bell.y -= 0.5;

    let d_bell = length(p_bell / vec3<f32>(1.0 + pulse, 0.8 - pulse, 1.0 + pulse)) * 0.8 - 0.5;
    let d_hollow = length(p_bell + vec3<f32>(0.0, 0.5, 0.0)) - 0.4;
    let bell_final = max(d_bell, -d_hollow);

    // ── Idea 1: damped travelling contraction wave (§12.2D). The bell's squeeze
    // runs down the tentacles as exp(-k s)·sin(ωt − κ s), s = arc distance from
    // the bell; amplitude keeps the tentacle_amp role.
    let sArc = clamp((0.5 - p.y) * 0.5, 0.0, 1.0);
    let squeeze = exp(-1.4 * sArc) * sin(time * pulse_speed - 4.0 * sArc) * 0.1 * (0.5 + tentacle_amp);

    var d_tentacles = 100.0;
    let num_tentacles = 8.0;
    for (var i = 0.0; i < num_tentacles; i = i + 1.0) {
        var angle = (i / num_tentacles) * 6.28318;
        let radius = 0.3;
        let tentacle_pos = vec3<f32>(cos(angle) * radius, 0.0, sin(angle) * radius);
        var p_t = p - tentacle_pos;

        // Fluid affects tentacle waving
        p_t.x += sin(p_t.y * 3.0 + time * 2.0 + i) * 0.1 * tentacle_amp + fluidVel.x * 0.3;
        p_t.z += cos(p_t.y * 3.0 + time * 2.0 + i) * 0.1 * tentacle_amp + fluidVel.y * 0.3;
        p_t.x += tentacle_pos.x * (squeeze / radius);
        p_t.z += tentacle_pos.z * (squeeze / radius);

        // HEAD fix: the old code overwrote p_t.y with its clamped value and took
        // length(p_t), so the "capsule" measured distance to a point: tentacles were
        // half-infinite stalks below y=-1 and nothing above. Now a true capsule from
        // the bell (y=0.5) down to the tip (y=-1.5), thick at the bell and thin at
        // the tip (yc: 0 = tip .. h = bell).
        p_t.y += 1.5;
        let h = 2.0;
        let yc = clamp(p_t.y, 0.0, h);
        p_t.y = p_t.y - yc;
        let d_t = length(p_t) - 0.05 * (0.25 + 0.75 * yc / h);
        d_tentacles = min(d_tentacles, d_t);
    }

    return smin(bell_final, d_tentacles, 0.2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    // HEAD fix: y-up (gid.y runs down the screen; the jelly was upside-down).
    let uv = vec2<f32>(f32(gid.x) - res.x * 0.5, res.y * 0.5 - f32(gid.y)) / res.y;
    let time = u.config.x;
    let aspect = res.x / res.y;

    // ═══ Fluid Simulation (simplified from mouse-fluid-coupling) ═══
    let viscosity = mix(0.92, 0.99, u.zoom_params.z);
    let mouseRadius = mix(0.03, 0.15, u.zoom_params.w);
    // HEAD fix: texel (0,0) holds the previous mouse (it used to be overwritten by
    // the fluid store, so prevMouse was ~0 and mouseVel = cursor·60 every frame).
    // The sentinel in .z also detects inherited C from a previously active shader.
    let mouseTexel = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let stateOk = abs(mouseTexel.z - 0.7317) < 0.001;
    let mousePosNorm = u.zoom_config.yz;
    let prevMouse = select(mousePosNorm, mouseTexel.xy, stateOk);
    let mvRaw = (mousePosNorm - prevMouse) * 60.0;
    let mouseVel = mvRaw * min(1.0, 4.0 / max(length(mvRaw), 1e-4));
    let mouseSpeed = length(mouseVel);

    let px = 1.0 / res;
    let screenUV = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
    let prevVel = textureLoad(dataTextureC, coord, 0).xy;

    let backUV = screenUV - prevVel * px * 2.0;
    let advected = bilinC(clamp(backUV, vec2<f32>(0.0), vec2<f32>(1.0)), res);

    // A fresh start (first frame / shader switch) begins with still water.
    let live = select(0.0, 1.0, stateOk);
    var vel = advected.xy * viscosity * live;
    var dens = advected.w * viscosity * live;

    let toMouse = (screenUV - mousePosNorm) * vec2<f32>(aspect, 1.0);
    let dist = length(toMouse);
    let influence = smoothstep(mouseRadius, 0.0, dist);
    vel = vel + mouseVel * influence * 0.5;

    let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
    let vortexStrength = 2.0;
    vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 2.0) {
            let rToMouse = (screenUV - ripple.xy) * vec2<f32>(aspect, 1.0);
            let rDist = length(rToMouse);
            let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
            let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
            vel = vel + outward * rInfluence * 0.3;
            dens = dens + rInfluence * 0.5;
        }
    }

    let edgeDist = min(min(screenUV.x, 1.0 - screenUV.x), min(screenUV.y, 1.0 - screenUV.y));
    let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
    vel = vel * edgeDamp;
    vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
    dens = clamp(dens, 0.0, 2.0);

    // Store fluid state; texel (0,0) is reserved for the mouse + sentinel.
    let isMouseTexel = gid.x == 0u && gid.y == 0u;
    textureStore(dataTextureA, coord, select(vec4<f32>(vel, vel.x - vel.y, dens), vec4<f32>(mousePosNorm, 0.7317, 1.0), isMouseTexel));

    // ═══ Raymarch Jellyfish with Fluid Coupling ═══
    // HEAD fix: orbit uses temporaries (the old code fed the already-rotated ro.x
    // into ro.z), pitch is clamped off the pole, cursor-up raises the camera.
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    var ro = vec3<f32>(0.0, 0.0, -4.0);
    let pitch = clamp(-mouse.y * 1.2, -1.2, 1.2);
    let cp = cos(pitch); let sp = sin(pitch);
    ro = vec3<f32>(ro.x, cp * ro.y - sp * ro.z, sp * ro.y + cp * ro.z);
    let yaw = mouse.x * 2.0;
    let cyw = cos(yaw); let syw = sin(yaw);
    ro = vec3<f32>(cyw * ro.x - syw * ro.z, ro.y, syw * ro.x + cyw * ro.z);
    let fv = vel * dens;

    let target_pos = vec3<f32>(0.0, 0.0, 0.0);
    let f = normalize(target_pos - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let up = cross(f, r);
    let rd = normalize(f + r * uv.x + up * uv.y);

    var t = 0.0;
    var glow = 0.0;
    var hit = false;

    for(var i = 0; i < 48; i++) {
        var p = ro + rd * t;
        var d = map(p, time, fv);
        glow += 1.0 / (1.0 + d * d * 20.0);
        if (d < 0.001) { hit = true; break; }
        if (t > 10.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    col += vec3<f32>(stars(rd));

    if (hit) {
        var p = ro + rd * t;
        let e = vec2<f32>(0.01, 0.0);
        var n = normalize(vec3<f32>(
            map(p + e.xyy, time, fv) - map(p - e.xyy, time, fv),
            map(p + e.yxy, time, fv) - map(p - e.yxy, time, fv),
            map(p + e.yyx, time, fv) - map(p - e.yyx, time, fv)
        ));
        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let base_color = vec3<f32>(0.2, 0.5, 0.8);
        col = base_color * diff * 0.5 + base_color * fresnel * 0.8;

        // ── Idea 2: translucent gel (§12.2F). Thickness behind the surface from 4
        // interior taps -> Beer-Lambert transmit (red dies first); a back light
        // scatters forward with Henyey-Greenstein (g = 0.6), so thin bell edges
        // and tentacle tips glow while the thick crown stays deep blue.
        var thick = 0.0;
        for (var k = 1; k <= 4; k = k + 1) {
            thick += clamp(-map(p + rd * (0.08 * f32(k)), time, fv), 0.0, 0.08);
        }
        let transmit = exp(-vec3<f32>(3.0, 1.6, 0.8) * thick * 4.0);
        let backLight = normalize(vec3<f32>(-0.5, 0.6, 1.0));
        let hgG = 0.6;
        let cosS = dot(backLight, rd);
        let hg = (1.0 - hgG * hgG) / pow(1.0 + hgG * hgG - 2.0 * hgG * cosS, 1.5);
        col += base_color * transmit * hg * 0.2;
    }

    let hue_shift = u.zoom_params.x;
    var glowColor = vec3<f32>(0.1, 0.4, 0.9);
    var angle = hue_shift * 6.28;
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cos_angle = cos(angle);
    glowColor = glowColor * cos_angle + cross(k, glowColor) * sin(angle) + k * dot(k, glowColor) * (1.0 - cos_angle);

    let glow_intensity = u.zoom_params.y;
    col += glow * glowColor * glow_intensity * 0.02;

    // ── Idea 3: stir-lit motes. Dinoflagellates flash where the water is being
    // stirred: the existing fluid |vel| + dens light sparse screen-space motes.
    let stir = clamp(dens * 1.5 + length(vel) * 3.0, 0.0, 1.5);
    let moteCell = floor(screenUV * vec2<f32>(aspect, 1.0) * 90.0);
    let moteH = hash(moteCell.x + moteCell.y * 57.0 + 7.0);
    let mote = step(0.97, moteH) * stir * (0.5 + 0.5 * sin(time * 4.0 + moteH * 50.0));
    col += vec3<f32>(0.1, 0.7, 0.8) * mote * 0.5 * select(1.0, 0.0, hit);

    // Fluid tint overlay
    let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.3);
    col = col * fluidTint;

    let displayCol = acesToneMap(max(col, vec3<f32>(0.0)));
    let luma = dot(displayCol, vec3<f32>(0.2126, 0.7152, 0.0722));
    let coverage = clamp(max(select(0.0, 1.0, hit), luma * 2.0), 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(displayCol, coverage));

    let depth = select(0.0, clamp(1.0 - t / 10.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
