// ═══════════════════════════════════════════════════════════════════
//  Magnetic Kelp
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, fbm-displacement,
//            sway-physics, bioluminescence, organic-width
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
  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));

  // ═══ CHUNK: bass_env smoothing (replaces raw-bass strobing) ═══
  let prevBass = extraBuffer[0];
  let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[0] = smoothBass;
  }

  let strandDensity = mix(6.0, 44.0, zp.x);
  let currentSpeed = mix(0.1, 2.0, zp.y);
  let magnetism = mix(0.0, 1.4, zp.z);
  let biolume = mix(0.2, 2.4, zp.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  let lanes = p.x * strandDensity;
  let laneId = floor(lanes);
  let laneLocal = fract(lanes) - 0.5;
  let seed = hash21(vec2<f32>(laneId, 13.7));
  let phase = seed * 6.28318;

  // ═══ Sway physics: layered pendulum-like modes ═══
  let yNorm = sat(0.5 + p.y * 0.5);
  let swayBase = sin(p.y * 4.0 + time * currentSpeed + phase);
  let swayHarmonic = sin(p.y * 11.0 + time * currentSpeed * 1.7 + phase * 1.3) * 0.35;
  let current = sin(p.y * 2.0 - time * currentSpeed * 0.5 + seed * 10.0) * 0.2;

  // ═══ Organic FBM displacement for non-uniform strand motion ═══
  let fbmSway = fbm(vec2<f32>(laneId * 0.1, p.y * 2.0 + time * 0.2), 4) - 0.5;
  let organicWidth = 1.0 + fbm(vec2<f32>(p.y * 3.0, laneId * 0.3), 3) * 0.5;

  let magneticPull = (mouse.x - p.x) * magnetism * exp(-abs(mouse.y - p.y) * 3.0);
  let strandOffset = (swayBase + swayHarmonic + fbmSway * 0.6 + current) * (0.25 + mids * 0.2) + magneticPull;

  let strandDist = abs(laneLocal + strandOffset);
  let strand = smoothstep(0.30, 0.02, strandDist) * organicWidth;

  // ═══ Fronds and bioluminescent tips ═══
  let frond = smoothstep(0.7, 1.0, sin((p.y + seed * 0.7) * 18.0 + time * 2.0 + smoothBass * 4.0)) * strand;
  let tipMask = smoothstep(0.18, 0.0, abs(yNorm - 0.92)) * strand;
  let tipPulse = 0.5 + 0.5 * sin(time * 3.0 + seed * 8.0 + smoothBass * 6.0);
  let tipGlow = tipMask * (0.6 + tipPulse * 0.4) * biolume;

  // Drifting spores
  let sporeUV = uv + vec2<f32>(time * 0.03, -time * 0.05);
  let spores = step(0.998 - treble * 0.03, hash21(floor(sporeUV * 280.0)));

  // Chromatic kelp: green strands, cyan fronds, glowing tips
  let tipCol = palette(seed + time * 0.02,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 0.5),
    vec3<f32>(0.0, 0.33, 0.67)
  );

  var color = vec3<f32>(0.01, 0.04, 0.06);
  color = color + vec3<f32>(0.02, 0.5, 0.32) * strand * (1.0 + smoothBass * 0.1);
  color = color + vec3<f32>(0.15, 0.95, 0.75) * frond * biolume * (1.0 + mids * 0.15);
  color = color + tipCol * tipGlow * 1.5;
  color = color + vec3<f32>(0.8, 1.0, 0.65) * spores * (0.3 + treble);

  // Temporal sway persistence: kelp remembers previous motion
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.88, 0.04 + smoothBass * 0.015);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(strand, frond, tipGlow + spores, 1.0));
}
