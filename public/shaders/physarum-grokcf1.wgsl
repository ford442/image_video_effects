// ═══════════════════════════════════════════════════════════════
//  Physarum Polycephalum (Slime Mold) grokcf1 - Advanced Simulation
//  With Alpha Scattering and Physical Light Transport
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal-feedback
//  Upgraded: 2026-11-19
//  Ideas: contour foraging (sensors smell photo edges); ectoplasm membrane rim over dark endoplasm core; shuttle-streaming reversal pulse
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

// grokcf1 personality color - cyan/green theme
fn grokcf1Color(p_type: f32, nutrient: vec3<f32>) -> vec3<f32> {
    let hue = 0.3 + p_type * 0.2; // Green to cyan range
    let base = vec3<f32>(
        0.3 + 0.3 * cos(hue * 6.28318530718),
        0.5 + 0.4 * cos(hue * 6.28318530718 + 1.0),
        0.4 + 0.4 * cos(hue * 6.28318530718 + 2.5)
    );
    return mix(base, nutrient * vec3<f32>(0.5, 1.0, 0.8), 0.3);
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
    let uv = (vec2<f32>(sc) + 0.5) / res;
    let food = length(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb);
    // Idea 1: contour foraging — the mold smells luminance edges in the photo
    let px = 2.0 / res;
    let lx = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb - textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(px.x, 0.0), 0.0).rgb, vec3<f32>(0.333));
    let ly = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb - textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, px.y), 0.0).rgb, vec3<f32>(0.333));
    return trail + food * 0.4 + min(length(vec2<f32>(lx, ly)) * 3.0, 1.0) * 0.6;
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

    // Trail: 3x3 diffuse + decay + deposit
    var sumT = 0.0;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let s = state(coord + vec2<i32>(i, j), live);
            sumT += s.x;
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
    let trail_color = grokcf1Color(bestC, nutrient_color);
    let emission = hdrEmission(trail_color, nutrient_value * trail, pulse_boost);

    let density_value = trail * 1.2;
    let trans = transmittance(density_value * 2.0);
    let cumulative_alpha = 1.0 - trans;

    // Idea 2: ectoplasm rim — gel membrane bright where the trail gradient is steep, dark sol core inside
    let tE = state(coord + vec2<i32>(1, 0), live).x;
    let tW = state(coord + vec2<i32>(-1, 0), live).x;
    let tS = state(coord + vec2<i32>(0, 1), live).x;
    let tN = state(coord + vec2<i32>(0, -1), live).x;
    let grad = length(vec2<f32>(tE - tW, tS - tN));
    let rim = smoothstep(0.02, 0.12, grad) * (1.0 + bass * 0.5);
    let core = smoothstep(0.35, 0.7, trail) * (1.0 - rim);
    // Idea 3: shuttle streaming — cytoplasm reverses direction every ~2 s; bands travel along the heading
    let hdir = vec2<f32>(cos(angle), sin(angle));
    let shuttle = sign(sin(time * 1.6));
    let band = 0.5 + 0.5 * sin(dot(pos, hdir) * 0.35 - time * 4.0 * shuttle);
    let streamCol = trail_color * band * smoothstep(0.15, 0.4, massNew) * smoothstep(0.08, 0.3, trail) * (0.5 + mids);
    let rimCol = vec3<f32>(0.35, 1.0, 0.85) * rim * 0.9;
    let halo = streamCol + rimCol;
    let coreDark = -emission * core * 0.6 * cumulative_alpha;

    var col = nutrient_color * trans + emission * cumulative_alpha + halo + coreDark + vec3<f32>(pulse_boost * 0.3, pulse_boost * 0.5, pulse_boost * 0.4) * cumulative_alpha;
    col = acesToneMapping(max(col, vec3<f32>(0.0)));
    let final_alpha = clamp(cumulative_alpha + pulse_boost * 0.3 + rim * 0.2, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(col, mix(0.35, 1.0, final_alpha)));

    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, (pos + 0.5) / res, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
