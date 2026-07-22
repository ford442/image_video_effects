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

// extraBuffer slots (0..4 reserved by engine — never touch):
//   [5] seed uv.x   [6] seed uv.y   [7] seed plant time   [8] seed strength   [9] prev mouseDown
const SEED_X: i32 = 5;
const SEED_Y: i32 = 6;
const SEED_T: i32 = 7;
const SEED_S: i32 = 8;
const SEED_PREV: i32 = 9;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.3;

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

    // ── Mouse-down rising edge: plant a frame-stamped seed (single writer thread) ──
    if (gid.x == 0u && gid.y == 0u) {
        if (mouseDown > 0.5 && extraBuffer[SEED_PREV] <= 0.5) {
            extraBuffer[SEED_X] = mouse.x;
            extraBuffer[SEED_Y] = mouse.y;
            extraBuffer[SEED_T] = u.config.x;
            extraBuffer[SEED_S] = 0.3 + seedParam * 1.2;
        }
        extraBuffer[SEED_PREV] = mouseDown;
    }

    let seedPos = vec2<f32>(extraBuffer[SEED_X], extraBuffer[SEED_Y]);
    let seedAge = max(u.config.x - extraBuffer[SEED_T], 0.0);
    let seedStrength = extraBuffer[SEED_S];
    let seedDist = length(uv - seedPos);

    // ── Expanding growth ring from the planted seed ──
    // Ring sweeps outward and locally boosts network growth where it passes.
    let ringRadius = seedAge * 0.22;
    let ringJitter = hash12(floor(uv * 32.0) + vec2<f32>(floor(u.config.x * 8.0))) * 0.03;
    let ringFade = exp(-seedAge * 0.45) * step(seedAge, 12.0);
    let ringBand = smoothstep(0.07, 0.0, abs(seedDist - ringRadius - ringJitter)) * ringFade;
    let ringBoost = ringBand * seedStrength;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    let lightReceived = prev.a;
    // Network Growth slider: base growth rate scales 0.2x..2.2x around the old 0.015 constant
    let growth = (0.003 + growthParam * 0.027 + mids * 0.025) * (0.4 + lightReceived * 1.2);

    let species1 = prev.r;
    let species2 = prev.g;

    // Symbiotic Strength slider: high = mutual support, low = raw competition
    let support = species1 * species2 * mix(0.1, 1.2, symParam);
    let compete = abs(species1 - species2) * mix(0.55, 0.05, symParam);

    var newS1 = species1 * 0.97 + growth * (1.0 + support - compete);
    var newS2 = species2 * 0.97 + growth * (1.0 + support - compete * 0.8);

    // Direct seeding while held (gentle) + the passing ring does the real planting
    let mouseDist = length(uv - mouse);
    let mouseSeed = smoothstep(0.1, 0.0, mouseDist) * mouseDown * mix(0.2, 1.4, seedParam);
    newS1 += mouseSeed * 0.5 + ringBoost * 0.65;
    newS2 += mouseSeed * 0.4 + ringBoost * 0.5;

    let ps = 1.0 / res;
    let n1 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0);
    let n2 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(ps.x, 0.0), 0.0);
    let n3 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, ps.y), 0.0);
    let n4 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, ps.y), 0.0);

    // Growth slider also widens the diffusion kernel weight (faster spread)
    let diffuse = mix(0.12, 0.24, growthParam);
    newS1 = newS1 * (1.0 - diffuse * 4.0) + (n1.r + n2.r + n3.r + n4.r) * diffuse;
    newS2 = newS2 * (1.0 - diffuse * 4.0) + (n1.g + n2.g + n3.g + n4.g) * diffuse;

    // Chromatic light transport: R and B light travel at different speeds
    // Light Transmission slider: channel gain 0.2..0.7 and dispersion reach 0.5x..1.5x
    // Slow organic drift of the transport direction keeps the network feeling alive
    let driftAngle = sin(u.config.x * 0.11) * 0.5;
    let ca = cos(driftAngle);
    let sa = sin(driftAngle);
    let lightDir = normalize(vec2<f32>(0.6 * ca - 0.4 * sa, 0.6 * sa + 0.4 * ca));
    let reach = mix(0.5, 1.5, transmitParam);
    let gain = mix(0.2, 0.7, transmitParam);
    let rLightSample = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - lightDir * 0.035 * reach, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let bLightSample = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - lightDir * 0.025 * reach, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let gLightSample = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - lightDir * 0.03 * reach, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let transmittedR = (rLightSample.r + rLightSample.g) * gain * (0.6 + treble * 0.5);
    let transmittedG = (gLightSample.r + gLightSample.g) * gain * (0.6 + mids * 0.5);
    let transmittedB = (bLightSample.r + bLightSample.g) * gain * (0.6 + bass * 0.5);

    let totalDensity = newS1 + newS2;
    let lightR = transmittedR * (1.0 - totalDensity * 0.4);
    let lightG = transmittedG * (1.0 - totalDensity * 0.4);
    let lightB = transmittedB * (1.0 - totalDensity * 0.4);

    textureStore(dataTextureA, gid.xy, vec4<f32>(newS1, newS2, lightG, totalDensity));

    // Temporal accumulation for persistent glow — feedback-clamped pre-tint at 1.2
    // (luma-echo-warp lesson: clamp the accumulator so glow trails stabilize, not saturate)
    let prevLight = prev.b;
    let rawAccum = mix(vec3<f32>(lightR, lightG, lightB), vec3<f32>(prevLight * 0.92), 0.12);
    let accumulatedLight = clamp(rawAccum, vec3<f32>(0.0), vec3<f32>(1.2));

    let c1 = vec3<f32>(0.3, 0.8, 0.5) * newS1;
    let c2 = vec3<f32>(0.8, 0.4, 0.7) * newS2;
    let glow = vec3<f32>(0.4, 0.7, 0.9) * accumulatedLight * 1.5;

    // Bass glow as a slow radial wave propagating outward from the seed point,
    // so beats travel along the network instead of flashing globally.
    let wavePhase = seedDist * 7.0 - u.config.x * 1.8;
    let bassWave = 0.5 + 0.5 * sin(wavePhase);
    let waveFalloff = exp(-seedDist * 1.6);
    let bassGlowPulse = 1.0 + bass * 0.65 * bassWave * waveFalloff;
    // Ring itself carries a bright bioluminescent rim while it expands
    let ringRim = vec3<f32>(0.5, 0.9, 0.8) * ringBand * seedStrength * 0.8;

    let col = (c1 + c2 + glow) * bassGlowPulse + ringRim;

    let alpha = clamp(totalDensity * 0.7 + (lightR + lightG + lightB) * 0.2 + bass * 0.05 + ringBand * 0.15, 0.2, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    let exposure = 0.95 + mids * 0.25 + ringBand * 0.3;
    textureStore(writeTexture, gid.xy, vec4<f32>(acesToneMap(col * exposure), a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(totalDensity * 0.6 + lightG * 0.4, 0.0, 0.0, 0.0));
}
