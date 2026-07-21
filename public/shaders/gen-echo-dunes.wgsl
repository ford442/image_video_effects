// ═══════════════════════════════════════════════════════════════════
//  Echo Dunes
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, domain-warping,
//            ridge-sdf-shadows, sunset-palette
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

fn ridgeHeight(x: f32, scale: f32, time: f32, wind: f32, bass: f32) -> f32 {
  return sin(x * scale + time * wind * (1.0 + bass)) * 0.12;
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
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[0] = smoothBass;
  }

  let duneScale = mix(1.0, 10.0, zp.x);
  let windSpeed = mix(0.05, 1.4, zp.y);
  let mirage = mix(0.0, 1.0, zp.z);
  let echo = mix(0.0, 1.0, zp.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // ═══ Domain warping: dunes distorted by low-frequency FBM ═══
  let warp = vec2<f32>(
    fbm(p * 1.5 + vec2<f32>(time * 0.1, 0.0), 4),
    fbm(p * 1.5 + vec2<f32>(3.2, 6.1) - time * 0.08, 4)
  );
  let warpedP = p + (warp - 0.5) * 0.45;

  let ridgeA = sin(warpedP.x * duneScale * 5.0 + time * windSpeed * (1.0 + smoothBass));
  let ridgeB = sin(warpedP.x * duneScale * 2.8 + warpedP.y * 3.0 - time * windSpeed * 0.7);
  let ridgeC = sin((warpedP.x + warpedP.y * 0.25) * duneScale * 7.0 + time * 0.3);
  let dunes = ridgeA * 0.5 + ridgeB * 0.35 + ridgeC * 0.15;
  let duneHeight = sat(0.5 + 0.5 * dunes);

  // ═══ Ridge SDF shadows: march toward the light, occluded by ridge height ═══
  let lightDir = normalize(vec2<f32>(0.7, 0.5));
  var shadow = 1.0;
  let shadowSteps = 10;
  for (var i: i32 = 1; i <= shadowSteps; i = i + 1) {
    let t = f32(i) * 0.04;
    let sx = p.x + lightDir.x * t;
    let sy = p.y + lightDir.y * t;
    let sh = ridgeHeight(sx, duneScale * 5.0, time, windSpeed, smoothBass);
    shadow = shadow * (0.88 + 0.12 * sat((sy - sh) * 8.0));
  }

  let shimmer = noise2(p * 14.0 + vec2<f32>(time * 0.4, -time * 0.23));
  let mirageWarp = vec2<f32>(sin(p.y * 18.0 + time * 2.0), cos(p.x * 14.0 + time * 1.6)) * mirage * 0.025;
  let warped = noise2((p + mirageWarp) * 9.0);

  let md = length((uv * 2.0 - 1.0) - mouse);
  let echoRings = sin(md * 50.0 - time * (2.0 + mids * 8.0));
  let echoField = smoothstep(0.6, 1.0, echoRings) * exp(-md * 3.0) * echo;

  // ═══ Sunset palette: warm horizon to cool zenith ═══
  let yNorm = sat(0.5 + p.y * 0.5);
  let skyColor = palette(yNorm,
    vec3<f32>(0.5, 0.4, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(0.0, 0.08, 0.18)
  );
  let sandLow = vec3<f32>(0.48, 0.26, 0.10);
  let sandHigh = vec3<f32>(0.95, 0.72, 0.35);
  let sandColor = mix(sandLow, sandHigh, duneHeight);

  let horizon = smoothstep(-0.1, 0.35, p.y);
  var color = mix(skyColor, sandColor, horizon);
  color = color * (0.55 + 0.45 * shadow);
  color = color + vec3<f32>(1.0, 0.85, 0.55) * shimmer * 0.18;
  color = color + vec3<f32>(0.4, 0.7, 1.0) * warped * mirage * 0.35 * (1.0 + treble * 0.15);
  color = color + vec3<f32>(0.65, 0.9, 1.0) * echoField * (0.4 + treble * 0.9);

  // Temporal echo persistence: rings decay slowly
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, echo * 0.06 + bass * 0.01);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(duneHeight, shadow, echoField, 1.0));
}
