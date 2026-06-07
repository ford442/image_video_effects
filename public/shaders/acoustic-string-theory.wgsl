// ═══════════════════════════════════════════════════════════════════
//  Acoustic String Theory
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, feedback-loop,
//            gravity-well, shockwave, video-luma, sparkle
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
  let d = wellPos - pos;
  let dist2 = dot(d, d) + 0.01;
  return normalize(d) * strength / dist2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let rawBass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let bass = bass_env(prev.r, rawBass, 0.8, 0.15);

  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouseDown = u.zoom_config.w;

  let strings = mix(2.0, 16.0, u.zoom_params.x);
  let tension = mix(0.5, 5.0, u.zoom_params.y);
  let harmonics = mix(1.0, 8.0, u.zoom_params.z);
  let resonance = mix(0.2, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // Mouse gravity well bends string space
  let well = gravityWell(p, vec2<f32>(mouse.x * aspect, mouse.y), 0.08 + bass * 0.06);
  p = p + well;

  // Click shockwave ripple
  let mDist = length(p - vec2<f32>(mouse.x * aspect, mouse.y));
  let shock = exp(-mDist * 4.0) * mouseDown * sin(mDist * 25.0 - time * 10.0);

  // Video luma feedback boosts brightness
  let vid = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(vid, vec3<f32>(0.299, 0.587, 0.114));
  let lumaBoost = smoothstep(0.5, 1.0, luma) * 0.4;

  var stringField = 0.0;
  var harmonicField = 0.0;
  var nodeField = 0.0;

  for (var s = 0u; s < u32(strings); s = s + 1u) {
    let fs = f32(s);
    let sy = -0.9 + (fs + 0.5) / strings * 1.8;
    let pluck = sin(p.x * tension * (1.0 + fs * 0.15) - time * (2.0 + fs * 0.5) * (1.0 + bass * 0.5));
    let damp = exp(-abs(p.x - mouse.x * aspect * 0.5) * 2.0) * (0.5 + mids);
    let wave = sin((p.y - sy + shock * 0.15) * tension * 15.0) * exp(-abs(p.y - sy) * tension * 3.0);
    let amp = (0.15 + damp) * resonance * (1.0 + bass * 0.3);
    let stringLine = abs(wave + pluck * amp);
    stringField = stringField + smoothstep(0.05, 0.0, stringLine) * (0.7 + fs * 0.05);

    for (var h = 1u; h < u32(harmonics); h = h + 1u) {
      let fh = f32(h);
      let harmY = sy + sin(fh * 1.618) * 0.15;
      let harmWave = sin((p.y - harmY) * tension * 15.0 * fh) * exp(-abs(p.y - harmY) * tension * 5.0);
      let harmLine = abs(harmWave + pluck * amp * pow(0.6, fh));
      harmonicField = harmonicField + smoothstep(0.03, 0.0, harmLine) * 0.3;
    }

    let nodeX = sin(fs * 2.7 + time * 0.3) * 0.5 + well.x * 0.5;
    let nodeDist = length(p - vec2<f32>(nodeX, sy));
    nodeField = nodeField + exp(-nodeDist * nodeDist * 80.0) * (0.5 + treble);
  }

  // Treble sparkle on nodes
  let sparkle = step(0.88, hash21(uv * 150.0 + time * 10.0)) * treble * nodeField * 3.0;
  let depthSample = textureLoad(readDepthTexture, coord, 0).r;
  let ao = exp(-depthSample * 3.0);

  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(0.9, 0.55, 0.2) * stringField * resonance * (1.0 + bass * 0.15);
  color = color + vec3<f32>(0.25, 0.75, 0.95) * harmonicField * (1.0 + mids * 0.2);
  color = color + vec3<f32>(1.0, 0.95, 0.85) * nodeField * (0.5 + treble * 0.3);
  color = color + vec3<f32>(1.0, 0.9, 0.7) * sparkle;
  color = color * (1.0 + lumaBoost) * (0.6 + 0.4 * ao);

  // Temporal accumulation with bass-reactive feedback
  color = mix(color, prev.rgb * 0.94, 0.03 + bass * 0.015);

  let presence = sat(stringField * 0.85 + harmonicField * 0.6 + nodeField * 0.9);
  let mouseProx = exp(-mDist * 2.0);
  let alpha = sat(0.08 + presence * 0.65 + mouseProx * 0.2 + bass * 0.12);
  let trailAge = prev.a * 0.96;
  let finalAlpha = max(alpha, trailAge * 0.6);

  let depth = sat(0.92 - stringField * 0.5 - nodeField * 0.3);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(bass, harmonicField, nodeField, finalAlpha));
}
