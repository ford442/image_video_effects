// ═══════════════════════════════════════════════════════════════════
//  Bioreactor Bloom
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, cell-sdf,
//            nutrient-tendrils, pulsing-bloom, fbm-warp
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-28
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

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.1, 29.6)));
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value += amplitude * noise(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return value;
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

fn nutrientTendril(uv: vec2<f32>, time: f32, cell: vec2<f32>, seed: vec2<f32>, lengthScale: f32) -> f32 {
  var d = 1e3;
  let segments = 6;
  var prev = cell + (seed - 0.5) * 0.6;
  for (var i: i32 = 1; i <= segments; i = i + 1) {
    let fi = f32(i);
    let wave = vec2<f32>(
      sin(time * 0.7 + seed.x * 5.0 + fi * 0.9),
      cos(time * 0.6 + seed.y * 5.0 + fi * 0.7)
    );
    let next = cell + (seed - 0.5) * 0.6 + wave * 0.25 * lengthScale + vec2<f32>(fi * 0.08, sin(fi + time) * 0.05);
    d = min(d, sdSegment(uv, prev, next));
    prev = next;
  }
  return smoothstep(0.03, 0.0, d);
}

fn pulseBloom(uv: vec2<f32>, time: f32, center: vec2<f32>, radius: f32, speed: f32) -> f32 {
  let d = length(uv - center);
  let ring = abs(d - radius * (0.7 + 0.3 * sin(time * speed)));
  return exp(-ring * ring * 80.0) * smoothstep(radius * 1.5, 0.0, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;

  let prevBass = extraBuffer[0];
  let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[0] = smoothBass;
  }
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;

  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
<<<<<<< HEAD
  let cellScale = mix(6.0, 52.0, zp.x);
  let mitosis = mix(0.0, 1.0, zp.y);
  let reactivity = mix(0.2, 2.2, zp.z);
  let toxicity = mix(0.0, 1.0, zp.w);
=======
  let cellScale = mix(6.0, 52.0, u.zoom_params.x);
  let mitosis = mix(0.0, 1.0, u.zoom_params.y);
  let reactivity = mix(0.2, 2.2, u.zoom_params.z);
  let toxicity = mix(0.0, 1.0, u.zoom_params.w);
>>>>>>> origin/main

  let warpedUV = uv + vec2<f32>(
    fbm(uv * 2.0 + vec2<f32>(time * 0.05, 0.0), 3) - 0.5,
    fbm(uv * 2.0 + vec2<f32>(0.0, time * 0.04), 3) - 0.5
  ) * 0.03 * (1.0 + mids);

  let gridUV = warpedUV * cellScale + vec2<f32>(time * (0.08 + smoothBass * 0.18), -time * 0.06);
  let cell = floor(gridUV);
  let local = fract(gridUV) - 0.5;
  let seed = hash22(cell);
  let center = (seed - 0.5) * (0.7 + mitosis * 0.5);

  let d = length(local - center);
  let nucleus = exp(-d * d * (18.0 + reactivity * 22.0));
  let membrane = smoothstep(0.25, 0.05, abs(sdCircle(local - center, 0.22 + seed.x * 0.18)));
  let pulse = 0.5 + 0.5 * sin(time * (2.5 + mids * 6.0) + seed.y * 9.0 + d * 18.0);

  let colony = nucleus * (0.7 + pulse * 0.7) + membrane * 0.5;

  var tendrils = 0.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let fi = f32(i);
    let tseed = hash22(cell + fi * 31.7);
    let tcell = local + (tseed - 0.5) * 0.5;
    tendrils += nutrientTendril(local, time + fi, cell, tseed, 1.0 + smoothBass);
  }
  tendrils = sat(tendrils) * (0.6 + reactivity * 0.5);

  var bloomLayers = 0.0;
  for (var i: i32 = 0; i < 2; i = i + 1) {
    let fi = f32(i);
    let bloomCenter = uv + (hash22(cell + fi * 17.3) - 0.5) * 0.4;
    let bloomSpeed = 0.8 + hash21(cell + fi * 9.1) * 1.5;
    bloomLayers += pulseBloom(uv, time, bloomCenter, 0.12 + fi * 0.08, bloomSpeed);
  }
  bloomLayers = sat(bloomLayers) * (0.5 + mids * 0.5);

  let poisonCloud = exp(-length(uv - mouse) * (4.0 + toxicity * 12.0)) * toxicity;
  let spores = step(0.994 - treble * 0.03, hash21(floor((warpedUV + time * 0.03) * 300.0)));

  var color = vec3<f32>(0.02, 0.05, 0.03);
  color += vec3<f32>(0.1, 0.95, 0.5) * colony * (0.6 + reactivity * 0.7) * (1.0 + smoothBass * 0.1);
  color += vec3<f32>(0.5, 1.0, 0.85) * nucleus * pulse * 0.6 * (1.0 + mids * 0.1);
  color += vec3<f32>(0.3, 0.9, 1.0) * tendrils * 0.8 * (1.0 + treble * 0.2);
  color += vec3<f32>(0.2, 0.85, 0.4) * bloomLayers * 0.7 * (1.0 + smoothBass * 0.15);
  color += vec3<f32>(0.65, 0.05, 0.15) * poisonCloud * (1.0 + treble * 0.15);
  color += vec3<f32>(0.9, 1.0, 0.75) * spores * (0.3 + treble);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, 0.03 + smoothBass * 0.01);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(nucleus, membrane, tendrils, bloomLayers));
}
