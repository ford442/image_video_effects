// ═══════════════════════════════════════════════════════════════════
//  Supernova Core
//  Category: generative
//  Features: generative, audio-reactive, sedov-taylor, rayleigh-taylor,
//            radioactive-decay, chromatic-aberration, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash31(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453123);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let expansion = u.zoom_params.x;
  let rayCount = 6 + i32(u.zoom_params.y * 18.0);
  let shockwaves = u.zoom_params.z;
  let chromatic = u.zoom_params.w;
  let aspect = res.x / res.y;
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let dist = length(p);
  let angle = atan2(p.y, p.x);

  // Sedov-Taylor blast wave radius
  let blastRadius = pow(time * 0.12 * (1.0 + shockwaves) * (1.0 + bass), 0.4) * 0.5 * (1.0 + expansion);

  // Asymmetric ejecta from mouse (binary companion kick)
  let mouseWorld = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let asymmetry = 1.0 + smoothstep(0.15, 0.0, length(p - mouseWorld)) * 0.6;

  var color = vec3<f32>(0.0);
  var ejectaDensity = 0.0;
  var shockTemp = 0.0;

  // Radioactive decay luminosity: 56Ni -> 56Co -> 56Fe
  let decayTime = fract(time * 0.08);
  let nickelMass = 1.0 - decayTime * 0.7;
  let cobaltLum = sin(decayTime * 6.28318530718) * 0.5 + 0.5;
  let flareTrigger = step(1.0 - treble * 0.15, hash31(vec3<f32>(floor(time * 5.0), 0.0, 0.0))) * cobaltLum;

  // Core white-hot center
  let coreTemp = 30000.0 * nickelMass * (1.0 + bass * 0.5);
  let core = smoothstep(0.025 * asymmetry, 0.0, dist) * (1.0 + flareTrigger * 2.0);
  color = color + vec3<f32>(1.0, 0.92, 0.78) * core;
  shockTemp = shockTemp + core * coreTemp;
  ejectaDensity = ejectaDensity + core;

  // Expanding shockwave rings with branchless blackbody cooling
  for (var wi = 0; wi < 4; wi = wi + 1) {
    let wf = f32(wi);
    let waveRadius = blastRadius * (0.25 + wf * 0.25);
    let waveWidth = 0.006 * (1.0 + treble * 0.5) * asymmetry;
    let wave = smoothstep(waveRadius + waveWidth, waveRadius, dist) * smoothstep(waveRadius - waveWidth, waveRadius, dist);
    let cooling = 1.0 - wf / 4.0 - dist * 0.8;
    let bb = mix(mix(vec3<f32>(1.0, 0.35, 0.15), vec3<f32>(1.0, 0.75, 0.25), smoothstep(0.0, 0.15, cooling)),
                 mix(vec3<f32>(1.0, 0.95, 0.75), vec3<f32>(0.75, 0.85, 1.0), smoothstep(0.4, 0.7, cooling)),
                 smoothstep(0.15, 0.4, cooling));
    color = color + bb * wave * (0.6 + mids * 0.5);
    shockTemp = shockTemp + wave * coreTemp * (1.0 - wf * 0.2);
    ejectaDensity = ejectaDensity + wave * 0.3;
  }

  // Rayleigh-Taylor instability fingers + iron emission lines
  let rtCoord = vec2<f32>(angle * 3.0, dist * 8.0 - time * 0.5);
  let rtFingers = smoothstep(0.45, 0.65, noise2(rtCoord * vec2<f32>(1.0, 2.0 + mids * 2.0))) * smoothstep(blastRadius + 0.05, blastRadius - 0.05, dist);
  color = color + vec3<f32>(0.55, 0.75, 0.85) * rtFingers * mids * 1.2;
  ejectaDensity = ejectaDensity + rtFingers * 0.2;

  // Neutrino-driven convection cells
  let cellMask = smoothstep(0.08, 0.0, abs(dist - blastRadius * 0.6)) * noise2(p * 6.0 + vec2<f32>(cos(time * 0.3), sin(time * 0.25)) * 0.5) * noise2(p * 13.8 + vec2<f32>(10.0, 20.0));
  color = color + vec3<f32>(0.45, 0.25, 0.65) * cellMask * 0.35;

  // Particle rays with chromatic aberration
  for (var ri = 0; ri < rayCount; ri = ri + 1) {
    let rf = f32(ri);
    let rayAngle = rf / f32(rayCount) * 6.28318530718 + hash21(vec2<f32>(rf, 0.0)) * 0.35;
    let angleDiff = abs(fract((angle - rayAngle) / 6.28318530718 + 0.5) - 0.5) * 6.28318530718;
    let rayWidth = 0.015 + hash21(vec2<f32>(rf, 1.0)) * 0.035;
    let ray = smoothstep(rayWidth, 0.0, angleDiff) * smoothstep(0.35 * (1.0 + expansion) * asymmetry, 0.0, dist) * (0.3 + hash21(vec2<f32>(rf, time)) * 0.7);
    let cs = chromatic * 0.025 * dist * (1.0 + treble);
    let rayR = smoothstep(rayWidth * 1.3, 0.0, angleDiff + cs) * ray;
    let rayB = smoothstep(rayWidth * 1.3, 0.0, angleDiff - cs) * ray;
    let h = abs(fract(vec3<f32>(fract(rf / f32(rayCount) + bass * 0.12 + decayTime * 0.2)) + vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - vec3<f32>(3.0));
    color = color + clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)) * vec3<f32>(rayR, ray, rayB) * (1.0 + treble * 0.5);
    ejectaDensity = ejectaDensity + ray * 0.08;
  }

  // Decay flares + HDR bloom on shock breakout
  color = color + vec3<f32>(0.95, 0.85, 0.55) * flareTrigger * core * 0.8;
  shockTemp = shockTemp + flareTrigger * coreTemp * 0.5;
  color = color + vec3<f32>(0.5, 0.55, 0.65) * smoothstep(0.02, 0.0, abs(dist - blastRadius)) * bass * 0.6;

  // ACES tone mapping + light echo by depth
  color = acesToneMap(color * 1.5);
  color = color + vec3<f32>(0.25, 0.20, 0.35) * smoothstep(0.0, 0.5, depth) * 0.15 * (1.0 + bass * 0.2);

  // Alpha: ejecta density * shock temperature * depth
  let tempNorm = clamp(shockTemp / 30000.0, 0.0, 1.0);
  let alpha = clamp(ejectaDensity * (0.3 + tempNorm * 0.7) * (0.5 + depth * 0.5), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(ejectaDensity * 0.5 + tempNorm * 0.3, 0.0, 0.0, 0.0));
}
