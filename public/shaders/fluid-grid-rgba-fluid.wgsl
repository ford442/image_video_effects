// ═══════════════════════════════════════════════════════════════════
//  fluid-grid-rgba-fluid
//  Category: advanced-hybrid
//  Features: fluid-simulation, grid-distortion, rgba-state-machine, mouse-driven
//  Complexity: Very High
//  Chunks From: fluid-grid.wgsl, alpha-fluid-simulation-paint.wgsl
//  Created: 2026-04-18
//  By: Agent CB-21 — Distortion & Material Enhancer
// ═══════════════════════════════════════════════════════════════════
//  A quantized grid where tile displacement is driven by a live
//  Navier-Stokes fluid simulation. Velocity advects grid offsets,
//  pressure creates bulges, and dye density tints the tile edges.
//  The fluid state is stored in dataTextureA for temporal evolution.
//
//  Upgraded: 2026-11-09
//  Ideas: tangential stirring in the pointer force; vorticity confinement from exact C loads (§12.2D); vorticity-spun tiles
//  A packing: raw sim state (vel.xy, pressure, density) — HEAD's, unchanged
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let h = hsv.x * 6.0;
    let s = hsv.y;
    let v = hsv.z;
    let c = v * s;
    let x = c * (1.0 - abs(h - floor(h / 2.0) * 2.0 - 1.0));
    let m = v - c;
    var rgb: vec3<f32>;
    if (h < 1.0) { rgb = vec3(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3(x, 0.0, c); }
    else { rgb = vec3(c, 0.0, x); }
    return rgb + vec3(m);
}

// History is read with exact loads (rgba32float history must never go through
// the filtering sampler). This reproduces the sampler's addressing exactly —
// texel centres at +0.5, clamp-to-edge, bilinear — so the picture is HEAD's.
fn loadC(uv: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
    let p = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * res - vec2<f32>(0.5);
    let i0 = floor(p);
    let f = p - i0;
    let a = vec2<i32>(i0);
    let hi = vec2<i32>(res) - vec2<i32>(1);
    let c00 = textureLoad(dataTextureC, clamp(a, vec2<i32>(0), hi), 0);
    let c10 = textureLoad(dataTextureC, clamp(a + vec2<i32>(1, 0), vec2<i32>(0), hi), 0);
    let c01 = textureLoad(dataTextureC, clamp(a + vec2<i32>(0, 1), vec2<i32>(0), hi), 0);
    let c11 = textureLoad(dataTextureC, clamp(a + vec2<i32>(1, 1), vec2<i32>(0), hi), 0);
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

// Curl of the stored velocity at a texel, in 1/s of uv space (exact loads).
fn curlAt(p: vec2<i32>, res: vec2<f32>) -> f32 {
    let hi = vec2<i32>(res) - vec2<i32>(1);
    let r = textureLoad(dataTextureC, clamp(p + vec2<i32>(1, 0), vec2<i32>(0), hi), 0).g;
    let l = textureLoad(dataTextureC, clamp(p + vec2<i32>(-1, 0), vec2<i32>(0), hi), 0).g;
    let t = textureLoad(dataTextureC, clamp(p + vec2<i32>(0, 1), vec2<i32>(0), hi), 0).r;
    let b = textureLoad(dataTextureC, clamp(p + vec2<i32>(0, -1), vec2<i32>(0), hi), 0).r;
    return 0.5 * ((r - l) * res.x - (t - b) * res.y);
}

const CONFINEMENT: f32 = 0.0008;   // velocity added per frame per unit |ω| (|ω| ≤ 40)
const TILE_SPIN: f32 = 0.04;       // tile rotation (rad) per unit ω at the tile centre

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let ps = 1.0 / resolution;
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let time = u.config.x;

    let gridSize = 10.0 + u.zoom_params.x * 90.0;
    let viscosity = u.zoom_params.y;
    let dyeIntensity = u.zoom_params.z;
    let decayRate = mix(0.990, 0.999, u.zoom_params.w);

    // Read previous fluid state
    let prevState = textureLoad(dataTextureC, coord, 0);
    var vel = prevState.rg;
    var pressure = prevState.b;
    var density = prevState.a;

    let maxVel = 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // Semi-Lagrangian advection
    let dt = 0.016;
    let backtraceUV = clamp(uv - vel * dt, vec2<f32>(0.0), vec2<f32>(1.0));
    let advected = loadC(backtraceUV, resolution);
    vel = advected.rg;
    density = advected.a;

    // Diffusion
    let visc = viscosity * 0.001 + 0.0001;
    let left = loadC(uv - vec2<f32>(ps.x, 0.0), resolution);
    let right = loadC(uv + vec2<f32>(ps.x, 0.0), resolution);
    let down = loadC(uv - vec2<f32>(0.0, ps.y), resolution);
    let up = loadC(uv + vec2<f32>(0.0, ps.y), resolution);
    vel += visc * (left.rg + right.rg + down.rg + up.rg - 4.0 * vel);

    // Single Jacobi pressure projection
    let pL = left.b; let pR = right.b; let pD = down.b; let pU = up.b;
    let divergence = ((pR - pL) / (2.0 * ps.x) + (pU - pD) / (2.0 * ps.y));
    pressure = (pL + pR + pD + pU - divergence * ps.x * ps.x * 4.0) * 0.25;
    pressure = clamp(pressure, -2.0, 2.0);
    vel -= vec2<f32>((pR - pL) / (2.0 * ps.x), (pU - pD) / (2.0 * ps.y)) * 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // Mouse force
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.15, 0.0, mouseDist);
    let mouseDir = normalize(uv - mousePos + vec2<f32>(0.0001));
    let mouseForce = mouseDir * mouseInfluence * -0.3 * mouseDown;
    // ── Idea 1: stirring component ───────────────────────────────────────
    // HEAD's pointer force is purely radial (a sink), which is curl-free: the
    // flow never rotates, so there is nothing for vorticity to describe. A
    // hand or spoon in a fluid also imparts swirl; add the tangential part of
    // the same force, same falloff, same hold gate.
    let stirForce = vec2<f32>(-mouseDir.y, mouseDir.x) * mouseInfluence * 0.2 * mouseDown;
    vel += (mouseForce + stirForce) * dt * 15.0;

    // ── Idea 2: vorticity confinement (§12.2D, D1) ──────────────────────
    // Bilinear semi-Lagrangian advection smears small swirls away. The curl of
    // the stored velocity and the gradient of its magnitude give a unit vector
    // N pointing at the eddy core; the force N × ω (2D: perp(N)·ω) spins the
    // velocity back up around it. ω is clamped and the step is a fraction of a
    // frame's worth of velocity so it can re-seed eddies but not run away.
    let w0 = curlAt(coord, resolution);
    let wR = curlAt(coord + vec2<i32>(1, 0), resolution);
    let wL = curlAt(coord + vec2<i32>(-1, 0), resolution);
    let wU = curlAt(coord + vec2<i32>(0, 1), resolution);
    let wD = curlAt(coord + vec2<i32>(0, -1), resolution);
    let gradW = vec2<f32>(abs(wR) - abs(wL), abs(wU) - abs(wD)) * 0.5;
    let coreN = gradW / max(length(gradW), 1e-4);
    vel += vec2<f32>(coreN.y, -coreN.x) * clamp(w0, -40.0, 40.0) * CONFINEMENT;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // Ripple dye injection
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 2.0 && rippleDist < 0.08) {
            let inject = smoothstep(0.08, 0.0, rippleDist) * max(0.0, 1.0 - age * 0.5);
            density += inject * 0.5;
            let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
            vel += dir * inject * 0.1;
        }
    }

    // Decay
    density *= decayRate;
    density = clamp(density, 0.0, 5.0);

    // Store fluid state
    textureStore(dataTextureA, coord, vec4<f32>(vel, pressure, density));

    // Grid distortion driven by fluid velocity
    let aspect = resolution.x / resolution.y;
    let tileUV = floor(uv * gridSize) / gridSize;
    let tileCenter = tileUV + vec2<f32>(0.5 / gridSize, 0.5 / gridSize);

    // Sample fluid at tile center for displacement
    let fluidAtTile = loadC(tileCenter, resolution);
    let tileVel = fluidAtTile.rg;
    let tilePressure = fluidAtTile.b;

    // Displace tile by fluid velocity + pressure bulge
    let push = length(tileVel) * 0.3 + abs(tilePressure) * 0.1;
    let offsetDir = normalize(tileVel + vec2<f32>(0.0001));
    let uvOffset = vec2<f32>(offsetDir.x / aspect, offsetDir.y) * push;

    // ── Idea 3: vorticity-spun tiles ────────────────────────────────────
    // The tile is displaced by the flow (HEAD); it also turns about its own
    // centre by the curl measured there, so tiles rotate like gyros inside
    // eddies and stay square-on in laminar flow.
    let tileOmega = curlAt(vec2<i32>(tileCenter * resolution), resolution);
    let spin = clamp(tileOmega * TILE_SPIN, -0.9, 0.9);
    let spinC = cos(spin);
    let spinS = sin(spin);
    let localP = (uv - tileCenter) * vec2<f32>(aspect, 1.0);
    let spunP = vec2<f32>(localP.x * spinC - localP.y * spinS, localP.x * spinS + localP.y * spinC);
    let sampleUV = tileCenter + spunP / vec2<f32>(aspect, 1.0) - uvOffset;
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Grid lines tinted by fluid dye
    let gridLine = fract(uv * gridSize);
    let lineWeight = 0.05 * (1.0 - viscosity);
    let speed = length(tileVel);
    let hue = atan2(tileVel.y, tileVel.x) / 6.283185307 + 0.5;
    let sat = smoothstep(0.0, 0.02, speed) * 0.8;
    let val = min(density * dyeIntensity * 1.5 + 0.15, 1.0);
    let dyeColor = hsv2rgb(vec3<f32>(hue, sat, val));

    if (gridLine.x < lineWeight || gridLine.y < lineWeight) {
        // semantic alpha: lines are as opaque as the dye under them
        color = mix(color, vec4<f32>(dyeColor, 0.55 + 0.45 * clamp(density * dyeIntensity, 0.0, 1.0)), 0.5);
    }

    textureStore(writeTexture, coord, color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
