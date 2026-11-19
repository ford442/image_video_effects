// ═══════════════════════════════════════════════════════════════
//  Physarum Polycephalum (Slime Mold) Gemini - Advanced Simulation
//  With Alpha Scattering and Physical Light Transport
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal-feedback
//  Upgraded: 2026-11-19
//  Ideas: forward-scatter halo through the trail; caste contact seams; caste-synchronised pulse flashes
//  A packing: raw sim state (trail density, mx, my, caste); corner texel (0,0).r = -0.6875 sentinel
//  Rescue: HEAD kept agents in extraBuffer (re-uploaded every frame) and wrote writeTexture only at
//          agent texels → Eulerian agents in A (|m| = mass, m/|m| = heading), full-frame display.
//
//  Scientific Concepts:
//  - Particles have physical size and opacity
//  - Many small particles = cumulative alpha
//  - Scattering affects perceived transparency
//  - Motion blur affects alpha accumulation
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const SENTINEL: f32 = -0.6875;
const FLOOR: f32 = 0.07;
const JC: f32 = 0.6;
const DIRG: f32 = 0.05;
const RHO0: f32 = 0.15;

// Soft particle alpha based on distance
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 2.5);
}

// Exponential transmittance for cumulative density
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// HDR emission calculation
fn hdrEmission(base: vec3<f32>, intensity: f32, pulse: f32) -> vec3<f32> {
    return base * (0.3 + intensity * 3.0 + pulse * 2.0);
}

// Personality-based color
fn personalityColor(p_type: f32, nutrient: vec3<f32>) -> vec3<f32> {
    let hue = p_type * 0.8 + 0.1;
    let base = vec3<f32>(
        0.5 + 0.5 * cos(hue * 6.28318530718),
        0.5 + 0.5 * cos(hue * 6.28318530718 + 2.094),
        0.5 + 0.5 * cos(hue * 6.28318530718 + 4.189)
    );
    return mix(base, nutrient, 0.4);
}

fn acesToneMapping(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash32(seed: u32) -> f32 {
    var x = seed;
    x ^= x >> 16u; x *= 0x7feb352du;
    x ^= x >> 15u; x *= 0x846ca68bu;
    x ^= x >> 16u;
    return f32(x) / f32(0xffffffffu);
}

fn wrapi(c: vec2<i32>) -> vec2<i32> {
    let d = vec2<i32>(i32(u.config.z), i32(u.config.w));
    return ((c % d) + d) % d;
}

// Seed: hashed mass, heading and personality (caste).
fn seedState(c: vec2<i32>) -> vec4<f32> {
    let id = u32(c.y) * u32(u.config.z) + u32(c.x);
    let ang = hash32(id * 3u + 2u) * 6.28318;
    let mass = RHO0 * (0.5 + hash32(id * 3u));
    let caste = floor(hash32(id * 5u + 1u) * 3.0) / 3.0;
    return vec4<f32>(0.0, mass * cos(ang), mass * sin(ang), caste);
}

// Exact C load; until our sentinel is present C holds another shader's frame → seed.
fn state(c: vec2<i32>, live: bool) -> vec4<f32> {
    let cw = wrapi(c);
    if (!live || (cw.x == 0 && cw.y == 0)) { return seedState(cw); }
    return textureLoad(dataTextureC, cw, 0);
}

fn velocity(c: vec2<i32>, live: bool, speed: f32) -> vec2<f32> {
    let s = state(c, live);
    let m = s.yz;
    // HEAD: personality changes speed (1 + p_type * 0.5)
    return speed * (1.0 + s.w * 0.5) * m / max(length(m), DIRG);
}

fn sense(pos: vec2<f32>, angle: f32, dist: f32, res: vec2<f32>, live: bool) -> f32 {
    let sc = wrapi(vec2<i32>(floor(pos + vec2<f32>(cos(angle), sin(angle)) * dist)));
    let trail = state(sc, live).x;
    let food = length(textureSampleLevel(readTexture, u_sampler, (vec2<f32>(sc) + 0.5) / res, 0.0).rgb);
    return trail + food * 0.6;
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
    let mids = plasmaBuffer[0].y;
    let live = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).x == SENTINEL;

    // Parameters (roles kept)
    let agent_radius = mix(1.5, 5.0, u.zoom_params.x);
    let deposit_opacity = mix(0.1, 0.9, u.zoom_params.y) * (1.0 + bass * 0.4);
    let sensor_dist = mix(5.0, 15.0, u.zoom_params.z);
    let decay_rate = mix(0.002, 0.02, 1.0 - u.zoom_params.w);
    let keep = 1.0 - decay_rate * 3.0;
    let cap = 0.35 + agent_radius * 0.08;
    let sensor_angle = 0.5;
    let turn = 0.2 * (1.0 + mids * 1.5);

    let idx = gid.y * dims.x + gid.x;
    let fseed = u32(time * 1000.0);

    // Nutrient interaction: move faster in nutrient-rich areas (HEAD rule, in px/frame)
    let nutrient_color = textureSampleLevel(readTexture, u_sampler, (pos + 0.5) / res, 0.0).rgb;
    let nutrient_value = length(nutrient_color);
    let speed = 0.6 + nutrient_value * 0.8;

    // Semi-Lagrangian gather of agent mass; winner-take-all heading + caste
    let sp = pos - velocity(coord, live, speed);
    let sw = sp - floor(sp / res) * res;
    let f0 = floor(sw);
    let fr = sw - f0;
    let ic = vec2<i32>(f0);
    var massAdv = 0.0;
    var bestS = -1.0;
    var bestM = vec2<f32>(1.0, 0.0);
    var bestC = 0.0;
    for (var k = 0; k < 4; k++) {
        let o = vec2<i32>(k & 1, k >> 1);
        let wt = select(1.0 - fr.x, fr.x, o.x == 1) * select(1.0 - fr.y, fr.y, o.y == 1);
        let s = state(ic + o, live);
        let mm = length(s.yz);
        massAdv += wt * mm;
        if (wt * mm > bestS) { bestS = wt * mm; bestM = s.yz; bestC = s.w; }
    }
    // Flow Jacobian: converging streams thicken into veins
    let uE = velocity(coord + vec2<i32>(1, 0), live, speed);
    let uW = velocity(coord + vec2<i32>(-1, 0), live, speed);
    let uS = velocity(coord + vec2<i32>(0, 1), live, speed);
    let uN = velocity(coord + vec2<i32>(0, -1), live, speed);
    let jac = clamp((1.0 - 0.5 * (uE.x - uW.x)) * (1.0 - 0.5 * (uS.y - uN.y)) - 0.25 * (uS.x - uN.x) * (uE.y - uW.y), 0.5, 2.0);

    var angle = atan2(bestM.y, bestM.x);
    let fS = sense(pos, angle, sensor_dist, res, live);
    let lS = sense(pos, angle - sensor_angle, sensor_dist, res, live);
    let rS = sense(pos, angle + sensor_angle, sensor_dist, res, live);
    if (fS > lS && fS > rS) {
        // Continue straight
    } else if (lS > rS) {
        angle -= turn;
    } else if (rS > lS) {
        angle += turn;
    }
    // Random turn (HEAD: 5% chance)
    if (hash32(idx * 7u + fseed) > 0.95) { angle += (hash32(idx * 13u + fseed) - 0.5) * 2.0; }

    var massNew = clamp(max(massAdv, FLOOR) * (1.0 + JC * (jac - 1.0)), FLOOR, cap);
    // Mouse-driven agent spawning
    let mpx = u.zoom_config.yz * res;
    let md = distance(pos, mpx) / (0.06 * res.y);
    if (u.zoom_config.w > 0.5 && md < 1.0) {
        massNew = cap;
        angle = atan2(pos.y - mpx.y, pos.x - mpx.x);
    }

    // Trail: 3x3 diffuse + decay + deposit; gather caste neighbourhood for seams
    var sumT = 0.0;
    var cMin = 1.0;
    var cMax = 0.0;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let s = state(coord + vec2<i32>(i, j), live);
            sumT += s.x;
            if (length(s.yz) > 0.12) { cMin = min(cMin, s.w); cMax = max(cMax, s.w); }
        }
    }
    let trail = clamp(sumT / 9.0 * keep + 0.05 * deposit_opacity * massNew * (1.0 - sumT / 9.0), 0.0, 1.0);
    var aOut = vec4<f32>(trail, massNew * cos(angle), massNew * sin(angle), bestC);
    if (coord.x == 0 && coord.y == 0) { aOut.x = SENTINEL; }
    textureStore(dataTextureA, coord, aOut);

    // ═══════════════════════════════════════════════════════════════
    //  OUTPUT WITH ALPHA SCATTERING
    // ═══════════════════════════════════════════════════════════════
    // Caste-synchronised pulse (HEAD pulse, now a soft flash per caste)
    let pulse = sin(time * 5.0 + bestC * 6.28) * 0.5 + 0.5;
    let pulse_boost = smoothstep(0.85, 0.97, pulse) * smoothstep(0.1, 0.3, massNew);
    let trail_color = personalityColor(bestC, nutrient_color);
    let emission = hdrEmission(trail_color, nutrient_value * trail, pulse_boost);

    let density_value = trail * 1.2;
    let trans = transmittance(density_value * 2.0);
    let cumulative_alpha = 1.0 - trans;

    // Idea 1: forward-scatter halo — light from upper-left scatters forward through the trail,
    // so the down-light side of each vein glows (HG-style lobe, 2 taps along the light path)
    let ldir = normalize(vec2<f32>(-0.6, -0.8));
    let up1 = state(coord + vec2<i32>(ldir * 3.0), live).x;
    let up2 = state(coord + vec2<i32>(ldir * 7.0), live).x;
    let inscatter = (0.6 * up1 + 0.4 * up2) * trans * (1.0 + bass * 0.5);
    let halo = trail_color * inscatter * 1.4;

    // Idea 2: caste contact seams — where two personalities meet the membrane fuses and brightens
    let seam = smoothstep(0.2, 0.34, cMax - cMin) * smoothstep(0.05, 0.25, trail);
    let seamCol = vec3<f32>(1.0, 0.95, 0.85) * seam * (0.6 + mids * 0.6);

    var col = nutrient_color * trans + emission * cumulative_alpha + halo + seamCol + vec3<f32>(pulse_boost * 0.5) * cumulative_alpha;
    col = acesToneMapping(max(col, vec3<f32>(0.0)));
    let final_alpha = clamp(cumulative_alpha + pulse_boost * 0.3 + seam * 0.2, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(col, mix(0.35, 1.0, final_alpha)));

    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, (pos + 0.5) / res, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
