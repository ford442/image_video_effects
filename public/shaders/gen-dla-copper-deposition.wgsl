// ═══════════════════════════════════════════════════════════════════
//  Diffusion-Limited Aggregation Copper Deposition
//  Category: generative
//  Features: persistent-state, mouse-driven, click-seeded, audio-reactive,
//            upgraded-rgba, semantic-alpha, aces-tone-map
//  Complexity: High
//  Upgraded: 2026-08-23 — persistent DLA state, interactive electrodes,
//            oxidation age, tip activity, single output-only ACES pass
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
fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p;
  let k = vec3<f32>(0.3183099, 0.3678794, 0.4342945);
  pp = fract(pp * k.xy);
  pp += dot(pp, pp.yx + 19.19);
  return fract(vec2<f32>((pp.x + pp.y) * pp.x, (pp.x + pp.y) * pp.y));
}

fn noise2d(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = dot(i, vec2<f32>(127.1, 311.7));
  return mix(mix(fract(sin(n + 0.0) * 43758.5453),
                 fract(sin(n + 1.0) * 43758.5453), u.x),
             mix(fract(sin(n + 127.1) * 43758.5453),
                 fract(sin(n + 128.1) * 43758.5453), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    val += amp * noise2d(p * freq);
    freq *= 2.0;
    amp *= 0.5;
  }
  return val;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn clampCoord(p: vec2<i32>, size: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0), size - vec2<i32>(1));
}

// dataTextureC/A packing: deposit, electrolyte depletion, oxidation age,
// freshly-grown tip activity. Every history read is an exact texel load.
fn loadDla(p: vec2<i32>, size: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clampCoord(p, size), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }
  let size = vec2<i32>(i32(res.x), i32(res.y));
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let bands = plasmaBuffer[0].xyz;
  let bass = bands.x;
  let mids = bands.y;
  let treble = bands.z;

  let growthScale = mix(0.35, 1.8, u.zoom_params.x);
  let armCount = mix(3.0, 13.0, u.zoom_params.y);
  let oxidationAmount = mix(0.05, 1.0, u.zoom_params.z);
  let sparkIntensity = mix(0.1, 2.2, u.zoom_params.w);

  let previous = loadDla(coord, size);
  let n = loadDla(coord + vec2<i32>(0, -1), size).r;
  let s = loadDla(coord + vec2<i32>(0, 1), size).r;
  let e = loadDla(coord + vec2<i32>(1, 0), size).r;
  let w = loadDla(coord + vec2<i32>(-1, 0), size).r;
  let ne = loadDla(coord + vec2<i32>(1, -1), size).r;
  let nw = loadDla(coord + vec2<i32>(-1, -1), size).r;
  let se = loadDla(coord + vec2<i32>(1, 1), size).r;
  let sw = loadDla(coord + vec2<i32>(-1, 1), size).r;
  let neighborMax = max(max(max(n, s), max(e, w)), max(max(ne, nw), max(se, sw)));
  let neighborMean = (n + s + e + w + ne + nw + se + sw) * 0.125;

  // Domain-warped electrolyte probability field.
  var p = uv * (4.0 + growthScale * 3.0);
  let warp = vec2<f32>(fbm(p + vec2<f32>(0.0, 1.7), 4),
                       fbm(p + vec2<f32>(5.2, 1.3), 4));
  p += warp * (0.6 + mids * 0.5);
  let centered = uv - vec2<f32>(0.5);
  let radius = length(centered);
  let angle = atan2(centered.y, centered.x);
  let arms = 0.5 + 0.5 * sin(angle * armCount + fbm(p, 3) * 5.0 - radius * 34.0);
  let walkers = fbm(p * (1.35 + bass * 1.5) + vec2<f32>(time * 0.06, -time * 0.04), 4);
  let candidate = smoothstep(0.46 - bass * 0.08, 0.78, walkers * (0.72 + arms * 0.55));

  // The central cathode, held cursor, and finite click fronts are true growth
  // seeds. Click age is bounded so old entries cannot inject energy forever.
  var seed = 1.0 - smoothstep(0.006, 0.024, radius);
  let aspect = res.x / max(res.y, 1.0);
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  seed = max(seed, held * (1.0 - smoothstep(0.0, 0.055, mouseDist)));
  var clickEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.4) { continue; }
    let distanceToClick = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let front = exp(-abs(distanceToClick - age * 0.19) * 95.0) * exp(-age * 1.25);
    let nucleus = (1.0 - smoothstep(0.0, 0.025, distanceToClick)) * exp(-age * 2.0);
    clickEnergy += front + nucleus;
  }
  seed = max(seed, clamp(clickEnergy, 0.0, 1.0));

  let contact = smoothstep(0.03, 0.42, neighborMax + neighborMean * 0.8);
  let electrolyte = 1.0 - clamp(previous.g, 0.0, 1.0);
  let stochastic = hash22(vec2<f32>(coord) + floor(time * 24.0)).x;
  let attach = candidate * contact * electrolyte
    * smoothstep(0.82 - growthScale * 0.18 - bass * 0.12, 1.0, stochastic);
  let growth = max(seed, attach * (0.25 + mids * 0.35));
  let deposit = clamp(previous.r + (1.0 - previous.r) * growth * (0.12 + growthScale * 0.2), 0.0, 1.0);
  let freshTip = clamp((deposit - previous.r) * 7.0 + clickEnergy * 0.35, 0.0, 1.0);
  let depletion = clamp(mix(previous.g, max(previous.g, deposit * 0.78), 0.035 + growthScale * 0.02), 0.0, 1.0);
  let oxidation = clamp(previous.b + deposit * oxidationAmount * 0.0018, 0.0, 1.0);
  let activity = max(freshTip, previous.a * 0.91);

  // Metallic copper develops patina from stored oxidation, while the activity
  // channel identifies conductive tips for treble-driven discharge.
  let freshCopper = vec3<f32>(0.72, 0.45, 0.2);
  let oxidized = vec3<f32>(0.07, 0.38, 0.33);
  let bronze = vec3<f32>(0.55, 0.35, 0.15);
  let sparkHash = hash22(vec2<f32>(coord) + floor(time * 55.0)).y;
  let spark = activity * smoothstep(0.82 - treble * 0.18, 1.0, sparkHash) * sparkIntensity;
  var metal = mix(freshCopper, bronze, oxidation * 0.55);
  metal = mix(metal, oxidized, oxidation * oxidationAmount);
  metal *= deposit * (0.65 + neighborMean * 0.7);
  metal += vec3<f32>(1.2, 0.72, 0.28) * activity * (0.3 + bass * 0.5);
  metal += vec3<f32>(1.0, 0.9, 0.62) * spark * (0.6 + treble * 2.0);
  let electrolyteColor = vec3<f32>(0.008, 0.018, 0.025) + vec3<f32>(0.02, 0.08, 0.09) * depletion;
  let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let effectAlpha = clamp(deposit * 0.9 + activity * 0.25 + spark * 0.2, 0.0, 1.0);
  let hdr = mix(input.rgb, electrolyteColor + metal, clamp(0.35 + effectAlpha * 0.65, 0.0, 1.0));
  let alpha = max(input.a, effectAlpha);
  let depthIn = textureLoad(readDepthTexture, coord, 0).r;
  let depth = mix(depthIn, clamp(deposit * 0.82 + activity * 0.18, 0.0, 1.0), effectAlpha);
  let display = vec4<f32>(acesToneMap(hdr * 1.15), alpha);

  textureStore(writeTexture, coord, display);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(deposit, depletion, oxidation, activity));
}
