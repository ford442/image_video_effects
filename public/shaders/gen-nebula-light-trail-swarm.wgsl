// ═══════════════════════════════════════════════════════════════════
//  Nebula Light-Trail Swarm
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Strömgren-sphere ionization stratification around the core star ([O III] teal inner zone, H-alpha red shell, [S II] ionization front; radius ∝ cube root of ionizing flux); recombination afterglow along photon trails (head ionized [O III] white-teal cooling to H-alpha red toward the tail, recombination time set by Trail Decay)
//  A packing: ACES display RGBA in A (C read back as trail history)
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Particle Speed, .y = Trail Decay, .z = Curl Strength, .w = Glow Radius
  ripples: array<vec4<f32>, 50>,
};

// --- Color Science: OkLab ---
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(2.2));
}
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(1.0 / 2.2));
}
fn linear_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        vec3<f32>(0.8189330101, 0.3618667424, -0.1288597137),
        vec3<f32>(0.0329845436, 0.9293118715, 0.0361456387),
        vec3<f32>(0.0482003018, 0.2643662691, 0.6338517070)
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0/3.0));
    return mat3x3<f32>(
        vec3<f32>(0.2104542553, 1.9779984951, 0.0259040371),
        vec3<f32>(0.7936177850, -2.4285922050, 0.7827717662),
        vec3<f32>(-0.0040720468, 0.4505937099, -0.8086757660)
    ) * lms_;
}
fn oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.3963377774, -0.1055613458, -0.0894841775),
        vec3<f32>(0.2158037573, -0.0638541728, -1.2914855480)
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        vec3<f32>(1.2270138510, -0.5577992887, 0.2812561490),
        vec3<f32>(-0.0405801784, 1.1122568696, -0.0716766787),
        vec3<f32>(-0.0763812845, -0.4214819784, 1.5861632204)
    ) * lms;
}
fn oklab_mix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear(mix(linear_to_oklab(a), linear_to_oklab(b), t));
}

// --- Blackbody Color Temperature ---
fn blackbody(t: f32) -> vec3<f32> {
    var col = vec3<f32>(1.0);
    col.y = 0.3900815787690196 * log(t) - 0.6318414437886275;
    col.z = 0.5432067891101961 * log(t) - 1.1964741063266880;
    return clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Cosine Palette (Inigo Quilez) ---
fn cosinePalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// --- HDR Tone Mapping ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(2.51); let b = vec3<f32>(0.03);
    let c = vec3<f32>(2.43); let d = vec3<f32>(0.59);
    let e = vec3<f32>(0.14);
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}
fn hash21(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.xx + p3.yz) * p3.zy);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

// Emission-line colours (linear RGB approximations of the nebular lines)
const HALPHA: vec3<f32> = vec3<f32>(1.0, 0.12, 0.18);  // H-alpha 656.3 nm
const OIII: vec3<f32> = vec3<f32>(0.1, 0.95, 0.8);     // [O III] 500.7 nm
const SII: vec3<f32> = vec3<f32>(0.75, 0.02, 0.05);    // [S II] 671.6 nm

fn loadC(p: vec2<i32>, maxC: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), maxC), 0);
}

fn trailDist(uv: vec2<f32>, p: vec2<f32>, dir: vec2<f32>, len: f32, width: f32) -> f32 {
    let toP = uv - p;
    let proj = dot(toP, dir);
    let clampedProj = clamp(proj, 0.0, len);
    let closest = p + dir * clampedProj;
    return length(uv - closest) - width;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(id.xy) / res;
    let coord = vec2<i32>(id.xy);
    let maxC = vec2<i32>(i32(res.x) - 1, i32(res.y) - 1);
    let aspect = res.x / max(res.y, 1.0);
    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let speed = u.zoom_params.x * 2.0 + 0.5;
    let curlStrength = u.zoom_params.z * 3.0;
    let glowRadius = u.zoom_params.w * 0.03 + 0.005;
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    // Mouse: uv space, y=0 top (used as-is)
    let mouse = u.zoom_config.yz;
    let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let repel = smoothstep(0.2, 0.0, mouseDist);
    // Recombination time: low Trail Decay = long-lived ionized trails
    let recombLen = mix(0.35, 0.04, u.zoom_params.y);
    var col = vec3<f32>(0.0);
    var totalGlow = 0.0;
    let numParticles = 20;
    for (var i: i32 = 0; i < numParticles; i = i + 1) {
        let fi = f32(i);
        let seed = hash21(vec2<f32>(fi, floor(time * 0.1)));
        let t = fract(time * speed * (0.3 + seed.x * 0.4) + fi * 0.1);
        let life = 1.0 - t;
        if (life < 0.01) { continue; }
        let startAngle = fi * 0.618 + seed.y * 6.28318;
        let startRadius = 0.1 + seed.x * 0.3;
        var startPos = vec2<f32>(cos(startAngle), sin(startAngle)) * startRadius + vec2<f32>(0.5);
        // Cursor deflects the swarm (repels; held = gravitational well pulls in)
        let toM = (startPos - mouse) * vec2<f32>(aspect, 1.0);
        let mInfl = smoothstep(0.35, 0.0, length(toM));
        startPos = startPos + normalize(toM + vec2<f32>(1e-4)) / vec2<f32>(aspect, 1.0) * mInfl * 0.08 * (1.0 - 2.0 * held);
        let curlPhase = time * speed * 0.5 + fi;
        let curlX = sin(curlPhase + uv.x * curlStrength) * 0.2;
        let curlY = cos(curlPhase + uv.y * curlStrength) * 0.2;
        let dir = normalize(vec2<f32>(cos(startAngle + 1.57), sin(startAngle + 1.57)) + vec2<f32>(curlX, curlY));
        let trailLen = t * 0.3 * mix(1.25, 0.7, u.zoom_params.y);
        let d = trailDist(uv, startPos, dir, trailLen, glowRadius * life);
        let glow = smoothstep(0.02, 0.0, d) * life;
        // Cosine palette + Blackbody temperature based on particle
        let hue = fi / f32(numParticles) + bass * 0.2;
        let cp = cosinePalette(hue + time * 0.05, vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.5,0.5,0.5), vec3<f32>(1.0,0.8,0.6), vec3<f32>(0.0,0.33,0.67));
        let bb = blackbody(mix(4000.0, 12000.0, fi / f32(numParticles)));
        let particleCol = oklab_mix(cp, bb, 0.3 + bass * 0.3);
        // ── IDEA 2: recombination afterglow ──
        // The photon head fully ionizes the gas it crosses ([O III] white-teal);
        // behind it, electrons recombine and cascade through H-alpha, so the
        // trail cools to red with distance from the head over recombLen.
        let along = clamp(dot(uv - startPos, dir), 0.0, max(trailLen, 1e-4));
        let behind = trailLen - along;
        let ionFrac = exp(-behind / recombLen);
        let lineCol = mix(HALPHA * 0.8, mix(OIII, vec3<f32>(1.0), 0.35), ionFrac);
        let afterglow = mix(0.35, 1.0, ionFrac);
        let trailCol = oklab_mix(particleCol, lineCol, 0.45 + treble * 0.15);
        let audioBoost = 1.0 + bass * 1.5 + treble * 0.5;
        col = col + trailCol * glow * afterglow * audioBoost;
        totalGlow = totalGlow + glow * afterglow;
    }
    // Central nebula core with Fresnel-like rim
    let coreDist = length(uv - vec2<f32>(0.5));
    let coreGlow = exp(-coreDist * coreDist * 8.0) * (0.5 + bass * 0.5);
    let coreColor = oklab_mix(vec3<f32>(0.4,0.6,1.0), blackbody(8000.0), 0.5);
    col = col + coreColor * coreGlow;
    // Secondary nebula layer (soft bloom)
    let bloomDist = length(uv - vec2<f32>(0.5) + vec2<f32>(sin(time * 0.1) * 0.1, cos(time * 0.15) * 0.1));
    let bloom = exp(-bloomDist * bloomDist * 3.0) * 0.3 * (0.5 + mids * 0.5);
    let bloomCol = oklab_mix(vec3<f32>(0.6,0.3,0.8), blackbody(6000.0), 0.5);
    col = col + bloomCol * bloom;

    // ── IDEA 1: Strömgren-sphere ionization stratification ──
    // A hot core star ionizes a sphere whose radius R_s ∝ Q^(1/3) (ionizing
    // photon rate Q, driven by bass). Inside, high-ionization [O III] glows
    // teal; H-alpha fills the outer shell; low-ionization [S II] marks the
    // thin ionization front where neutral gas begins. Clumpy gas density
    // wrinkles the front.
    let pc = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
    let rN = length(pc);
    let gas = valueNoise(pc * 6.0 + vec2<f32>(time * 0.02, -time * 0.015)) * 0.65
            + valueNoise(pc * 14.0 - vec2<f32>(time * 0.03, 0.0)) * 0.35;
    let Q = 1.0 + bass * 2.5 + held * 1.0;
    let Rs = 0.26 * pow(Q, 1.0 / 3.0) * (0.85 + gas * 0.3);
    let x = rN / Rs;
    let oiiiZone = exp(-x * x * 3.2) * (0.6 + mids * 0.4);
    let haZone = smoothstep(0.25, 0.8, x) * smoothstep(1.08, 0.9, x);
    let front = exp(-(x - 1.0) * (x - 1.0) * 180.0);
    let emissionGain = gas * 0.32 * (0.6 + mids * 0.4);
    col = col + OIII * oiiiZone * emissionGain * 0.6;
    col = col + HALPHA * haZone * emissionGain;
    col = col + SII * front * (0.4 + treble * 0.4) * gas;
    let nebulaCover = (oiiiZone * 0.6 + haZone + front * 0.8) * gas;

    // Click → light echo: a scattered-light shell racing outward through dust
    var echo = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r: u32 = 0u; r < rippleCount; r = r + 1u) {
        let rp = u.ripples[r];
        let age = time - rp.z;
        if (age > 0.0 && age < 3.0) {
            let dr = length((uv - rp.xy) * vec2<f32>(aspect, 1.0)) - age * 0.22;
            echo += exp(-dr * dr * 900.0) * exp(-age * 1.2) * (0.5 + gas);
        }
    }
    echo = min(echo, 2.0);
    col = col + mix(OIII, vec3<f32>(1.0, 0.95, 0.9), 0.5) * echo * (0.6 + bass * 0.4);
    // Cursor halo: repel field glows faintly (brighter while held)
    col = col + vec3<f32>(0.5, 0.6, 1.0) * repel * 0.08 * (1.0 + held * 2.0);

    // Starfield with blackbody temperature
    let starNoise = hash(floor(uv * 300.0));
    if (starNoise > 0.997) {
        let starBright = (starNoise - 0.997) / 0.003;
        let starTemp = mix(3000.0, 10000.0, starNoise);
        col = col + blackbody(starTemp) * starBright * (0.5 + mids * 0.5);
    }
    // Temporal feedback (exact load); Trail Decay sets persistence
    let prev = loadC(coord, maxC);
    // default (y=0.5) keeps the original 0.03 weight; y=0 -> 0.24, y=1 -> ~0.004
    let persist = 0.03 * pow(8.0, 1.0 - 2.0 * u.zoom_params.y);
    col = mix(col, prev.rgb * mix(0.95, 0.85, u.zoom_params.y), persist + bass * 0.01);
    // Chromatic dispersion with OkLab mixing (integer texel offsets)
    let cStr = 0.003 + bass * 0.005;
    let cDir = normalize(uv - vec2<f32>(0.5) + 0.001);
    let offR = vec2<i32>(round(cDir * cStr * (1.0 + mids) * res));
    let offG = vec2<i32>(round(cDir * cStr * (0.5 + treble) * res));
    let offB = vec2<i32>(round(-cDir * cStr * (0.8 + bass * 0.5) * res));
    let prevR = loadC(coord + offR, maxC).r;
    let prevG = loadC(coord + offG, maxC).g;
    let prevB = loadC(coord + offB, maxC).b;
    col.r = mix(col.r, prevR * 0.9, 0.02 + treble * 0.01);
    col.g = mix(col.g, prevG * 0.9, 0.02 + bass * 0.01);
    col.b = mix(col.b, prevB * 0.9, 0.02 + mids * 0.01);
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(3.0));
    // HDR tone mapping
    col = acesToneMap(col * 0.8);
    // Alpha = emission coverage: trails, core, bloom, ionized gas, echo; plus
    // a decaying share of the previous frame's coverage so trails keep alpha.
    let alpha = clamp(max(totalGlow * 0.5 + coreGlow + bloom + nebulaCover * 0.5 + echo * 0.5,
                          prev.a * persist * 1.5), 0.0, 1.0);
    let depth = clamp(0.5 - coreDist * 0.3 + front * gas * 0.1 + totalGlow * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(col, alpha);
    textureStore(writeTexture, id.xy, finalColor);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, finalColor);
}
