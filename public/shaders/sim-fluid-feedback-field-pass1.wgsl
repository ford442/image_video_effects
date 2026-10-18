// ═══════════════════════════════════════════════════════════════════
//  Sim: Fluid Feedback Field (Pass 1: Velocity Advection)
//  Category: simulation
//  Features: simulation, multi-pass-1, navier-stokes, velocity-advection
//  Complexity: Very High
//  Upgraded: 2026-10-17
//  Ideas: semi-Lagrangian self-advection of stored velocity; dye streak that warps the photo
//  A packing: raw (velX, velY, dye, 1) — display ACES is writeTexture only
//  upgraded-rgba
// ═══════════════════════════════════════════════════════════════════
//  Pass graph: Pass 1 reads the previous velocity from dataTextureC,
//              advects it with curl noise and mouse input, and writes
//              the new velocity field to dataTextureA.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Viscosity, y=Turbulence, z=MouseForce, w=Param4

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ NOISE FUNCTIONS ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ═══ CURL NOISE ═══
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.01;
    let n1 = noise(p + vec2<f32>(eps, 0.0));
    let n2 = noise(p - vec2<f32>(eps, 0.0));
    let n3 = noise(p + vec2<f32>(0.0, eps));
    let n4 = noise(p - vec2<f32>(0.0, eps));
    return vec2<f32>((n4 - n3) / (2.0 * eps), (n1 - n2) / (2.0 * eps));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ MAIN: VELOCITY ADVECTION ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let coord = vec2<i32>(gid.xy);
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Parameters — bass amplifies turbulence
    let viscosity = mix(0.9, 0.999, clamp(u.zoom_params.x, 0.0, 1.0));
    let turbulence = clamp(u.zoom_params.y, 0.0, 1.0) * 2.0 * (1.0 + bass * 0.5);
    let mouseForce = clamp(u.zoom_params.z, 0.0, 1.0);

    // Idea 1 — self-advection of the velocity stored last frame, mixed with the curl seed.
    let prev = textureLoad(dataTextureC, coord, 0);
    let backUv = clamp(uv - prev.xy * 1.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let backPx = clamp(vec2<i32>(backUv * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    let adv = textureLoad(dataTextureC, backPx, 0);
    let curl = curlNoise(uv * 5.0 + time * 0.1);
    var newVel = mix(adv.xy, curl * turbulence * 0.1, 0.55);

    // Mouse impulse — radial outward push (Gaussian)
    let toMouse = uv - mouse;
    let dM2 = dot(toMouse, toMouse);
    let mouseGate = exp(-dM2 * 60.0) * (mouseForce + mouseDown * 0.5);
    newVel = newVel + (toMouse / max(length(toMouse), 1e-4)) * 0.4 * mouseGate;

    // Apply viscosity (damping)
    newVel *= viscosity;

    // Idea 2 — dye rides the same backtrace. Glow (zoom_params.w) brightens it.
    let glow = clamp(u.zoom_params.w, 0.0, 1.0);
    var dye = max(adv.z, 0.0) * 0.985;
    dye = clamp(dye + mouseGate * 0.45, 0.0, 1.5);

    textureStore(dataTextureA, coord, vec4<f32>(newVel, dye, 1.0));

    let warpUv = clamp(uv + newVel * 0.85, vec2<f32>(0.0), vec2<f32>(1.0));
    let src = textureSampleLevel(readTexture, u_sampler, warpUv, 0.0);
    let dyeCol = vec3<f32>(0.15, 0.72, 1.0) * dye * mix(0.35, 1.4, glow);
    let rgb = acesToneMap(max(src.rgb * (1.0 - dye * 0.35) + dyeCol, vec3<f32>(0.0)));
    let alpha = clamp(src.a * 0.45 + dye * 0.4 + length(newVel) * 0.35, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * (1.0 - dye * 0.25), 0.0, 0.0, 0.0));
}
