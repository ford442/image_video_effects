// ═══════════════════════════════════════════════════════════════
//  Physarum Polycephalum (Slime Mold) with Alpha Scattering
//  Texture-guided agent simulation with physical light transport
//
//  Scientific Concepts:
//  - Particles have physical size and opacity
//  - Many small particles = cumulative alpha
//  - Scattering affects perceived transparency
//  - Motion blur affects alpha accumulation
//
//  Rescue: 2026-10-05 — HEAD kept its agents in extraBuffer[0..], which the runtime re-uploads
//          (audio + FFT) every frame, so the agents never moved; it also wrote only ~85 agent
//          pixels per frame. Now Eulerian agents, the scheme of gen-wasm-hls-physarum-swarm:
//          every texel carries agent mass + heading, gathered semi-Lagrangian with
//          winner-take-all heading and scalar mass, and a flow Jacobian that piles mass onto
//          veins. The image is the food. Agent Radius (dead at HEAD) now sets vein width
//          (trail blur). Numpy-gated: scripts/sim_models/physarum_rescue.py
//  A packing: raw sim state (trail, mx, my, 0); |m| = agent mass, m/|m| = heading
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const FLOOR: f32 = 0.07;     // mass floor: opposing streams never annihilate the field
const CAP: f32 = 0.6;
const JC: f32 = 0.6;         // convergence gain of the flow Jacobian
const DIRG: f32 = 0.05;
const RHO0: f32 = 0.15;
const WANDER: f32 = 0.15;
const SENSOR_ANGLE: f32 = 0.68;
const DEC_REF: f32 = 0.0275; // 1 - decay at the default Trail Decay slider (0.5 -> 0.9725)

fn hash32(seed: u32) -> f32 {
    var x = seed;
    x ^= x >> 16u;
    x *= 0x7feb352du;
    x ^= x >> 15u;
    x *= 0x846ca68bu;
    x ^= x >> 16u;
    return f32(x) / f32(0xffffffffu);
}

fn wrapi(c: vec2<i32>) -> vec2<i32> {
    let d = vec2<i32>(i32(u.config.z), i32(u.config.w));
    return ((c % d) + d) % d;
}

// C is zero-initialised (first frame / resize): give every texel hash mass + heading.
fn seedState(c: vec2<i32>) -> vec4<f32> {
    let id = u32(c.y) * u32(u.config.z) + u32(c.x);
    let ang = hash32(id * 3u + 2u) * 6.28318;
    let mass = RHO0 * (0.5 + hash32(id * 3u));
    return vec4<f32>(0.0, mass * cos(ang), mass * sin(ang), 0.0);
}

// Exact load of C (torus wrap); an all-zero texel is the seed state.
fn state(c: vec2<i32>) -> vec4<f32> {
    let cw = wrapi(c);
    let s = textureLoad(dataTextureC, cw, 0);
    if (dot(s, s) == 0.0) { return seedState(cw); }
    return s;
}

fn velocity(c: vec2<i32>, speed: f32) -> vec2<f32> {
    let m = state(c).yz;
    return speed * m / max(length(m), DIRG);
}

// Steer toward trail and toward the image's red channel (the food).
fn sense(pos: vec2<f32>, angle: f32, sensorDist: f32, res: vec2<f32>) -> f32 {
    let dir = vec2<f32>(cos(angle), sin(angle));
    let sc = wrapi(vec2<i32>(floor(pos + dir * sensorDist)));
    let trail = textureLoad(dataTextureC, sc, 0).r;
    let food = textureSampleLevel(readTexture, u_sampler, (vec2<f32>(sc) + 0.5) / res, 0.0).r;
    return trail + food * 1.5;
}

// Exponential transmittance for cumulative density
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// Agent deposit color with HDR emission
fn agentEmissionColor(base_color: vec3<f32>, intensity: f32) -> vec3<f32> {
    return base_color * (0.5 + intensity * 2.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }

    let coord = vec2<i32>(gid.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let pos = vec2<f32>(coord);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters (roles and ranges from HEAD; Agent Radius now drives vein width)
    let agent_radius = u.zoom_params.x;
    let deposit_opacity = mix(0.1, 0.8, u.zoom_params.y);
    let sense_distance = mix(3.0, 10.0, u.zoom_params.z);
    let trail_decay = mix(0.95, 0.995, u.zoom_params.w);

    let idx = gid.y * dims.x + gid.x;
    let frameSeed = u32(time * 1000.0);
    let turnSpeed = 0.5 + bass * 3.0 + mid * 1.5;
    let moveSpeed = 1.5 + treble * 1.0;
    let dTurn = min(turnSpeed * SENSOR_ANGLE, 0.9);
    let deposit = (0.3 + 2.0 * u.zoom_params.y) * (1.0 + bass * 2.0);

    // Semi-Lagrangian gather of agent mass / heading from p - u.
    let u0 = velocity(coord, moveSpeed);
    let sp = pos - u0;
    let sw = sp - floor(sp / res) * res;
    let f0 = floor(sw);
    let fr = sw - f0;
    let ic = vec2<i32>(f0);
    var massAdv = 0.0;
    var bestS = -1.0;
    var bestM = vec2<f32>(0.0);
    for (var k = 0; k < 4; k++) {
        let ox = k & 1;
        let oy = k >> 1;
        let wt = select(1.0 - fr.x, fr.x, ox == 1) * select(1.0 - fr.y, fr.y, oy == 1);
        let s = state(ic + vec2<i32>(ox, oy));
        let mm = length(s.yz);
        massAdv += wt * mm;                      // scalar mass average: never cancels
        if (wt * mm > bestS) { bestS = wt * mm; bestM = s.yz; }   // winner-take-all heading
    }

    // Jacobian of the agent flow: converging streams pile mass onto veins.
    let uE = velocity(coord + vec2<i32>(1, 0), moveSpeed);
    let uW = velocity(coord + vec2<i32>(-1, 0), moveSpeed);
    let uS = velocity(coord + vec2<i32>(0, 1), moveSpeed);
    let uN = velocity(coord + vec2<i32>(0, -1), moveSpeed);
    let dux_dx = 0.5 * (uE.x - uW.x);
    let dux_dy = 0.5 * (uS.x - uN.x);
    let duy_dx = 0.5 * (uE.y - uW.y);
    let duy_dy = 0.5 * (uS.y - uN.y);
    let jac = clamp((1.0 - dux_dx) * (1.0 - duy_dy) - dux_dy * duy_dx, 0.5, 2.0);

    var angle = atan2(bestM.y, bestM.x);
    if (massAdv < 1e-6) { angle = hash32(idx * 11u + frameSeed) * 6.28318; }

    let wF = sense(pos, angle, sense_distance, res);
    let wL = sense(pos, angle + SENSOR_ANGLE, sense_distance, res);
    let wR = sense(pos, angle - SENSOR_ANGLE, sense_distance, res);
    if (wF > wL && wF > wR) {
        // Straight
    } else if (wF < wL && wF < wR) {
        angle += select(-dTurn, dTurn, hash32(idx * 7u + frameSeed) > 0.5);
    } else if (wL > wR) {
        angle += dTurn;
    } else {
        angle -= dTurn;
    }
    angle += WANDER * (hash32(idx * 13u + frameSeed) - 0.5);

    // Mouse pull (HEAD: within 0.3 uv, blend 0.1), shortest arc.
    let mousePos = u.zoom_config.yz * res;
    let distToMouse = distance(pos, mousePos) / res.x;
    if (distToMouse > 0.01 && distToMouse < 0.3) {
        let desired = atan2(mousePos.y - pos.y, mousePos.x - pos.x);
        let dl = desired - angle + 3.14159265;
        angle += (dl - 6.28318531 * floor(dl / 6.28318531) - 3.14159265) * 0.1;
    }

    // Ripples twist the heading of agents near a click (HEAD behaviour).
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 2.0 && distance(pos / res, ripple.xy) < 0.05) {
            angle += (age - 1.0) * 0.5;
        }
    }

    let massNew = clamp(max(massAdv, FLOOR) * (1.0 + JC * (jac - 1.0)), FLOOR, CAP);
    let mNew = massNew * vec2<f32>(cos(angle), sin(angle));

    // Trail: blur toward the 3x3 mean by Agent Radius (vein width), decay, deposit ∝ mass.
    var sumT = 0.0;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            sumT += state(coord + vec2<i32>(i, j)).x;
        }
    }
    let centreT = state(coord).x;
    let blurred = mix(centreT, sumT / 9.0, 0.25 + 0.75 * agent_radius) * trail_decay;
    let depositScale = (1.0 - trail_decay) / DEC_REF;   // decay changes persistence, not brightness
    let trailNew = clamp(blurred + 0.05 * deposit * massNew * (1.0 - blurred) * depositScale, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(trailNew, mNew.x, mNew.y, 0.0));

    // ═══ Output with alpha scattering ═══
    let uv = (pos + 0.5) / res;
    let image = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let signal = image.r;
    // Deposit colour: inverse of the food under it, HDR-boosted where food is rich.
    let emission = agentEmissionColor(vec3<f32>(1.0) - image.rgb, signal);
    // The Eulerian trail has a floor (~0.15) wherever agent mass is spread thin: veins are what rises above it.
    let density = max(trailNew - 0.16, 0.0) * mix(4.0, 16.0, deposit_opacity);
    let cumulative_alpha = 1.0 - transmittance(density);
    let color = mix(image.rgb, emission * (1.0 + trailNew), cumulative_alpha);

    textureStore(writeTexture, coord, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.5)), max(image.a, cumulative_alpha)));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
