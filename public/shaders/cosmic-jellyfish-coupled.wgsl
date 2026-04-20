// ═══════════════════════════════════════════════════════════════════
//  cosmic-jellyfish-coupled
//  Category: advanced-hybrid
//  Features: raymarching, fluid-coupling, mouse-driven, bioluminescent
//  Complexity: Very High
//  Chunks From: cosmic-jellyfish.wgsl, mouse-fluid-coupling.wgsl
//  Created: 2026-04-18
//  By: Agent CB-16 — Generative & Cosmic Enhancer
// ═══════════════════════════════════════════════════════════════════
//  A majestic cosmic jellyfish whose tentacles and bell are distorted
//  by a real-time fluid velocity field. Mouse movement stirs the fluid
//  which advects the raymarched SDF, creating organic viscous motion.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
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

        p_t.y += 1.0;
        var h = 2.0;
        p_t.y = clamp(p_t.y, 0.0, h);
        let d_t = length(p_t) - 0.05 * (1.0 - p_t.y / h);
        d_tentacles = min(d_tentacles, d_t);
    }

    return smin(bell_final, d_tentacles, 0.2);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = (vec2<f32>(gid.xy) - res * 0.5) / res.y;
    let time = u.config.x;
    let aspect = res.x / res.y;

    // ═══ Fluid Simulation (simplified from mouse-fluid-coupling) ═══
    let viscosity = mix(0.92, 0.99, u.zoom_params.z);
    let mouseRadius = mix(0.03, 0.15, u.zoom_params.w);
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
    let mousePosNorm = u.zoom_config.yz;
    let mouseVel = (mousePosNorm - prevMouse) * 60.0;
    let mouseSpeed = length(mouseVel);

    if (gid.x == 0u && gid.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePosNorm, 0.0, 0.0));
    }

    let px = 1.0 / res;
    let screenUV = vec2<f32>(gid.xy) / res;
    let prevVel = textureSampleLevel(dataTextureC, u_sampler, screenUV, 0.0).xy;
    let prevDens = textureSampleLevel(dataTextureC, u_sampler, screenUV, 0.0).a;

    let backUV = screenUV - prevVel * px * 2.0;
    let advectedVel = textureSampleLevel(dataTextureC, u_sampler, clamp(backUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).xy;
    let advectedDens = textureSampleLevel(dataTextureC, u_sampler, clamp(backUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).a;

    var vel = advectedVel * viscosity;
    var dens = advectedDens * viscosity;

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

    // Store fluid state
    textureStore(dataTextureA, coord, vec4<f32>(vel, vel.x - vel.y, dens));

    // ═══ Raymarch Jellyfish with Fluid Coupling ═══
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    var ro = vec3<f32>(0.0, 0.0, -4.0);
    var cam_rot = rot(mouse.x * 2.0);
    ro.x = cam_rot[0][0] * ro.x + cam_rot[0][1] * ro.z;
    ro.z = cam_rot[1][0] * ro.x + cam_rot[1][1] * ro.z;
    cam_rot = rot(mouse.y * 2.0);
    ro.y = cam_rot[0][0] * ro.y + cam_rot[0][1] * ro.z;
    ro.z = cam_rot[1][0] * ro.y + cam_rot[1][1] * ro.z;

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
        var d = map(p, time, vel * dens);
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
            map(p + e.xyy, time, vel * dens) - map(p - e.xyy, time, vel * dens),
            map(p + e.yxy, time, vel * dens) - map(p - e.yxy, time, vel * dens),
            map(p + e.yyx, time, vel * dens) - map(p - e.yyx, time, vel * dens)
        ));
        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let base_color = vec3<f32>(0.2, 0.5, 0.8);
        col = base_color * diff * 0.5 + base_color * fresnel * 0.8;
    }

    let hue_shift = u.zoom_params.x;
    var glowColor = vec3<f32>(0.1, 0.4, 0.9);
    var angle = hue_shift * 6.28;
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cos_angle = cos(angle);
    glowColor = glowColor * cos_angle + cross(k, glowColor) * sin(angle) + k * dot(k, glowColor) * (1.0 - cos_angle);

    let glow_intensity = u.zoom_params.y;
    col += glow * glowColor * glow_intensity * 0.02;

    // Fluid tint overlay
    let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.3);
    col = col * fluidTint;

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screenUV, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
