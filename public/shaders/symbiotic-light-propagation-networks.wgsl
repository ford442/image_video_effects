// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Light Propagation Networks
//  Category: generative
//  Features: light-transport, organic-networks, symbiotic-growth, audio-color, mouse-seeding,
//            chromatic-dispersion, bass-glow-pulses, temporal-accumulation, upgraded-rgba, aces-tone-map,
//            mouse-seed-ring, bass-spatial-wave, feedback-clamp
//  Complexity: High
//  Chunks From: light ray marching simulation + growth models
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
//  Upgraded: 2026-07-22 (Interactivist: seed rings, bass wave, slider rewiring, glow clamp)
//  Upgraded: 2026-10-31
//  Ideas: forward-scatter cone transport (Henyey-Greenstein 3-tap lobe per channel); Rayleigh lambda^-4 per-channel extinction (thin network blue-white, thick amber); phototropic skew of the diffusion kernel toward the drifting light
//  A packing: raw sim state (not tone-mapped) A = (S1, S2, lightG + 8.0 sentinel for inherited-C, totalDensity); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const SENTINEL_OFFSET: f32 = 8.0;
const HG_G: f32 = 0.55;
const SPORE_GRID: f32 = 7.0;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let xc = max(x, vec3<f32>(0.0));
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((xc * (a * xc + b)) / (xc * (c * xc + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Exact load of last frame's state. .b carries lightG + SENTINEL_OFFSET; anything else is
// state inherited from a previous shader and reads as empty.
fn ld(c: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    let t = textureLoad(dataTextureC, clamp(c, vec2<i32>(0), dims - vec2<i32>(1)), 0);
    let ok = t.b > SENTINEL_OFFSET - 0.5 && t.b < SENTINEL_OFFSET + 1.5;
    let v = vec4<f32>(clamp(t.r, 0.0, 3.0), clamp(t.g, 0.0, 3.0), clamp(t.b - SENTINEL_OFFSET, 0.0, 3.0), clamp(t.a, 0.0, 4.0));
    return select(vec4<f32>(0.0), v, ok);
}

// Henyey-Greenstein phase (unnormalised) for the angle between two directions
fn hgPhase(cosT: f32) -> f32 {
    return (1.0 - HG_G * HG_G) / pow(1.0 + HG_G * HG_G - 2.0 * HG_G * cosT, 1.5);
}

// Light sample: 3-tap forward-scatter cone around the upstream ray (Idea 1)
fn coneLight(pf: vec2<f32>, dir: vec2<f32>, distPx: vec2<f32>, dims: vec2<i32>) -> f32 {
    let a = 0.45;
    let ca = cos(a);
    let sa = sin(a);
    let w0 = hgPhase(1.0);
    let w1 = hgPhase(ca);
    let wn = 1.0 / (w0 + 2.0 * w1);
    let d1 = vec2<f32>(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);
    let d2 = vec2<f32>(dir.x * ca + dir.y * sa, -dir.x * sa + dir.y * ca);
    let s0 = ld(vec2<i32>(round(pf - dir * distPx)), dims);
    let s1 = ld(vec2<i32>(round(pf - d1 * distPx)), dims);
    let s2 = ld(vec2<i32>(round(pf - d2 * distPx)), dims);
    return (s0.r + s0.g) * (w0 * wn) + (s1.r + s1.g) * (w1 * wn) + (s2.r + s2.g) * (w1 * wn);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let dims = vec2<i32>(res);
    let pix = vec2<i32>(gid.xy);
    let pf = vec2<f32>(gid.xy);
    let uv = pf / res;
    let tNow = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // ── Slider wiring: each param drives a real constant of THIS algorithm ──
    let growthParam   = clamp(u.zoom_params.x, 0.0, 1.0); // Network Growth: expansion rate + diffusion
    let transmitParam = clamp(u.zoom_params.y, 0.0, 1.0); // Light Transmission: channel gain + dispersion reach
    let symParam      = clamp(u.zoom_params.z, 0.0, 1.0); // Symbiotic Strength: support vs competition
    let seedParam     = clamp(u.zoom_params.w, 0.0, 1.0); // Mouse Seeding Power: plant + ring boost

    // ── Click rings: stateless, from the engine's ripple list (HEAD kept this in extraBuffer[5..9], which is zeroed every frame) ──
    let seedStrength = 0.3 + seedParam * 1.2;
    var ringBand = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    let ringJitter = hash12(floor(uv * 32.0) + vec2<f32>(floor(tNow * 8.0))) * 0.03;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = max(tNow - rp.z, 0.0);
        let ringRadius = age * 0.22;
        let ringFade = exp(-age * 0.45) * step(age, 12.0);
        ringBand += smoothstep(0.07, 0.0, abs(length(uv - rp.xy) - ringRadius - ringJitter)) * ringFade;
    }
    ringBand = min(ringBand, 1.5);
    let ringBoost = ringBand * seedStrength;

    let prev = ld(pix, dims);

    let lightReceived = prev.a;
    // Network Growth slider: base growth rate scales 0.2x..2.2x around the old 0.015 constant
    let growth0 = (0.003 + growthParam * 0.027 + mids * 0.025) * (0.4 + lightReceived * 1.2);

    let species1 = prev.r;
    let species2 = prev.g;

    // ── Neighbour state (exact loads) ──
    let n1 = ld(pix + vec2<i32>(1, 0), dims);
    let n2 = ld(pix - vec2<i32>(1, 0), dims);
    let n3 = ld(pix + vec2<i32>(0, 1), dims);
    let n4 = ld(pix - vec2<i32>(0, 1), dims);

    // HEAD fix: growth only happens where the network already is (contact growth), along a static
    // ridge-noise nutrient field, so fronts trace veins instead of washing the screen uniformly.
    let local = max(species1 + species2, max(max(n1.r + n1.g, n2.r + n2.g), max(n3.r + n3.g, n4.r + n4.g)));
    let contact = smoothstep(0.015, 0.06, local);
    let ridge = 1.0 - abs(2.0 * vnoise(uv * 26.0 + vec2<f32>(3.1, 7.7)) - 1.0);
    let nutrient = 1.8 * smoothstep(0.35, 0.9, ridge);
    // logistic cap: the light-received feedback (0.4 + 1.2*density) is otherwise a runaway
    let room = 1.0 - clamp((species1 + species2) / 0.8, 0.0, 1.0);
    let growth = growth0 * contact * nutrient * room;

    // Symbiotic Strength slider: high = mutual support, low = raw competition
    let support = species1 * species2 * mix(0.1, 1.2, symParam);
    let compete = abs(species1 - species2) * mix(0.55, 0.05, symParam);

    // barren ground (off the nutrient ridges) lets the network die back faster, so audio-boosted growth cannot flood the frame
    let retain = mix(0.88, 0.97, smoothstep(0.2, 0.6, ridge));
    var newS1 = species1 * retain + growth * (1.0 + support - compete);
    var newS2 = species2 * retain + growth * (1.0 + support - compete * 0.8);

    // HEAD fix: spore nodes — staggered jittered cells that wake for a few seconds each, so there is always
    // something for the contact growth to spread from. Species chosen per cell.
    let cell0 = floor(uv * SPORE_GRID);
    var spore1 = 0.0;
    var spore2 = 0.0;
    for (var j = 0; j < 9; j = j + 1) {
        let c = cell0 + vec2<f32>(f32(j % 3) - 1.0, f32(j / 3) - 1.0);
        let h1 = hash12(c);
        let hx = hash12(c + vec2<f32>(17.3, 5.1));
        let hy = hash12(c + vec2<f32>(41.9, 23.7));
        let hs = step(0.5, hash12(c + vec2<f32>(3.7, 91.1)));
        let center = (c + vec2<f32>(0.2) + vec2<f32>(hx, hy) * 0.6) / SPORE_GRID;
        let awake = step(0.4, h1) * step(fract(tNow / 22.0 + h1 * 3.1), 0.12);
        let node = smoothstep(0.035, 0.0, length(uv - center)) * awake * 0.35;
        spore1 += node * (0.4 + 0.6 * hs);
        spore2 += node * (1.0 - 0.6 * hs);
    }
    newS1 += spore1;
    newS2 += spore2;

    // Direct seeding while held (gentle) + the passing ring does the real planting
    let mouseDist = length(uv - mouse);
    let mouseSeed = smoothstep(0.1, 0.0, mouseDist) * mouseDown * mix(0.2, 1.4, seedParam);
    newS1 += mouseSeed * 0.5 + ringBoost * 0.65;
    newS2 += mouseSeed * 0.4 + ringBoost * 0.5;

    // Slow organic drift of the transport direction (also the light the network leans toward)
    let driftAngle = sin(tNow * 0.11) * 0.5;
    let ca = cos(driftAngle);
    let sa = sin(driftAngle);
    let lightDir = normalize(vec2<f32>(0.6 * ca - 0.4 * sa, 0.6 * sa + 0.4 * ca));

    // ── Idea 3: phototropic skew — neighbour weights 1 + 0.6*dot(offset, lightDir); they still sum to 4 ──
    let k = 0.6;
    let wx1 = 1.0 + k * lightDir.x;
    let wx2 = 1.0 - k * lightDir.x;
    let wy1 = 1.0 + k * lightDir.y;
    let wy2 = 1.0 - k * lightDir.y;
    // Growth slider also widens the diffusion kernel weight (faster spread)
    let diffuse = mix(0.02, 0.10, growthParam);
    newS1 = newS1 * (1.0 - diffuse * 4.0) + (n1.r * wx1 + n2.r * wx2 + n3.r * wy1 + n4.r * wy2) * diffuse;
    newS2 = newS2 * (1.0 - diffuse * 4.0) + (n1.g * wx1 + n2.g * wx2 + n3.g * wy1 + n4.g * wy2) * diffuse;
    newS1 = clamp(newS1, 0.0, 3.0);
    newS2 = clamp(newS2, 0.0, 3.0);

    // Chromatic light transport: R and B light travel at different speeds
    // Light Transmission slider: channel gain 0.2..0.7 and dispersion reach 0.5x..1.5x
    let reach = mix(0.5, 1.5, transmitParam);
    let gain = mix(0.2, 0.7, transmitParam);
    // Idea 1: each channel's upstream sample is a Henyey-Greenstein forward-scatter cone
    let rLight = coneLight(pf, lightDir, res * 0.035 * reach, dims);
    let gLight = coneLight(pf, lightDir, res * 0.03 * reach, dims);
    let bLight = coneLight(pf, lightDir, res * 0.025 * reach, dims);
    let transmittedR = rLight * gain * (0.6 + treble * 0.5);
    let transmittedG = gLight * gain * (0.6 + mids * 0.5);
    let transmittedB = bLight * gain * (0.6 + bass * 0.5);

    // Idea 2: Rayleigh lambda^-4 extinction: (650/lambda)^4 = 1, 1.95, 4.35 at 650/550/450nm, scaled so G matches HEAD's 0.4
    let totalDensity = newS1 + newS2;
    let lightR = transmittedR * exp(-totalDensity * 0.2);
    let lightG = transmittedG * exp(-totalDensity * 0.4);
    let lightB = transmittedB * exp(-totalDensity * 0.89);

    textureStore(dataTextureA, pix, vec4<f32>(newS1, newS2, lightG + SENTINEL_OFFSET, totalDensity));

    // Temporal accumulation for persistent glow — feedback-clamped pre-tint at 1.2
    let prevLight = prev.b;
    let rawAccum = mix(vec3<f32>(lightR, lightG, lightB), vec3<f32>(prevLight * 0.92), 0.12);
    let accumulatedLight = clamp(rawAccum, vec3<f32>(0.0), vec3<f32>(1.2));

    let c1 = vec3<f32>(0.3, 0.8, 0.5) * newS1;
    let c2 = vec3<f32>(0.8, 0.4, 0.7) * newS2;
    let glow = vec3<f32>(0.4, 0.7, 0.9) * accumulatedLight * 1.5;

    // Bass glow as a slow radial wave propagating outward from the cursor,
    // so beats travel along the network instead of flashing globally.
    let wavePhase = mouseDist * 7.0 - tNow * 1.8;
    let bassWave = 0.5 + 0.5 * sin(wavePhase);
    let waveFalloff = exp(-mouseDist * 1.6);
    let bassGlowPulse = 1.0 + bass * 0.65 * bassWave * waveFalloff;
    // Ring itself carries a bright bioluminescent rim while it expands
    let ringRim = vec3<f32>(0.5, 0.9, 0.8) * ringBand * seedStrength * 0.8;

    let col = (c1 + c2 + glow) * bassGlowPulse + ringRim;

    let alpha = clamp(totalDensity * 0.7 + (lightR + lightG + lightB) * 0.2 + bass * 0.05 + ringBand * 0.15, 0.2, 1.0);

    // dense network self-shades (keeps saturated sliders / loud audio from flooding to white)
    let exposure = (0.95 + mids * 0.25 + ringBand * 0.3) / (1.0 + totalDensity * 0.7);
    textureStore(writeTexture, pix, vec4<f32>(acesToneMap(col * exposure), alpha));
    textureStore(writeDepthTexture, pix, vec4<f32>(totalDensity * 0.6 + lightG * 0.4, 0.0, 0.0, 0.0));
}
