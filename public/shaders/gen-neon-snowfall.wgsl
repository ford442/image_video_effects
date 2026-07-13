// ═══════════════════════════════════════════════════════════════════
//  Neon Snowfall
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, depth-parallax,
//            motion-blur-trails, palette-shift
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
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(31.2, 13.6)));
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * noise2(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
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
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  // Clamp/normalize parameter vector
  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));

  // ═══ CHUNK: bass_env smoothing (replaces raw-bass strobing) ═══
  let prevBass = extraBuffer[0];
  let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
  extraBuffer[0] = smoothBass;

  let flakeDensity = mix(20.0, 180.0, zp.x);
  let fallSpeed = mix(0.08, 2.0, zp.y);
  let chroma = mix(0.2, 2.0, zp.z);
  let blurAmt = mix(0.0, 1.0, zp.w);

  var color = vec3<f32>(0.01, 0.02, 0.05);
  var totalFlake = 0.0;
  var totalTrail = 0.0;

  // ═══ Depth parallax: three layers of falling flakes ═══
  for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
    let depth = f32(layer) * 0.5;
    let scale = 1.0 + depth * 1.5;
    let speed = fallSpeed * (0.5 + depth * 0.8);
    let density = flakeDensity * scale;
    let parallax = mouse * 0.12 * depth;
    let layerSeed = f32(layer) * 13.0;

    let gridUV = vec2<f32>(uv.x + parallax.x, uv.y + time * speed + parallax.y) * density;
    let cell = floor(gridUV);
    let local = fract(gridUV) - 0.5;
    let rnd = hash22(cell + layerSeed);
    let flakePos = rnd - 0.5 + vec2<f32>(mouse.x * 0.35 * (1.0 - depth), 0.0);
    let offset = local - flakePos * 0.9;
    let d = length(offset);

    let flake = exp(-d * d * (40.0 + smoothBass * 30.0));

    // ═══ Per-flake motion blur trail ═══
    let vel = vec2<f32>((rnd.x - 0.5) * 0.06, -0.08 - depth * 0.05) * blurAmt;
    let steps = 6;
    var trail = 0.0;
    for (var s: i32 = 0; s < steps; s = s + 1) {
      let t = f32(s) / f32(steps - 1);
      let blurPos = offset - vel * t;
      trail = trail + exp(-dot(blurPos, blurPos) * 35.0) * (1.0 - t);
    }
    trail = trail / f32(steps);

    let twinkle = 0.5 + 0.5 * sin(time * (8.0 + treble * 26.0) + rnd.x * 20.0);
    let hue = rnd.x + time * 0.03 + mids * 0.15 + depth * 0.2;
    let flakeCol = palette(hue,
      vec3<f32>(0.5, 0.5, 0.5),
      vec3<f32>(0.5, 0.5, 0.5),
      vec3<f32>(1.0, 1.0, 1.0),
      vec3<f32>(0.0, 0.33, 0.67)
    );

    let depthFade = 1.0 - depth * 0.35;
    color = color + flakeCol * flake * chroma * (0.4 + twinkle * 0.6) * depthFade;
    color = color + flakeCol * trail * chroma * 0.5 * depthFade;
    totalFlake = totalFlake + flake;
    totalTrail = totalTrail + trail;
  }

  // Temporal snowfall persistence: streaks accumulate
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, totalTrail * 0.08 + smoothBass * 0.01);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(totalFlake, totalTrail, 0.0, 1.0));
}
