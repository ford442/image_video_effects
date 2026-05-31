// ═══════════════════════════════════════════════════════════════════
//  Volcanic Ink
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-05-31
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

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var q = p;
  for (var i = 0u; i < 5u; i = i + 1u) {
    v = v + a * noise2(q);
    q = q * 2.07 + vec2<f32>(7.1, 3.4);
    a = a * 0.52;
  }
  return v;
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

  let fissureDensity = mix(1.0, 8.0, u.zoom_params.x);
  let magmaFlow = mix(0.1, 2.2, u.zoom_params.y);
  let soot = mix(0.0, 1.0, u.zoom_params.z);
  let ember = mix(0.2, 2.4, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * 0.25;

  let n0 = fbm(p * fissureDensity + vec2<f32>(time * 0.07, -time * 0.11));
  let n1 = fbm(p * fissureDensity * 2.1 - vec2<f32>(time * magmaFlow * 0.25, 0.0));
  let cracks = smoothstep(0.64, 0.9, abs(n0 - n1) * (1.0 + bass * 0.7));

  let lavaFlow = fbm(p * 2.6 + vec2<f32>(time * magmaFlow * 0.3, time * 0.17));
  let lava = smoothstep(0.55, 0.92, lavaFlow) * (1.0 - cracks * 0.7);
  let smoke = fbm(p * vec2<f32>(1.3, 2.4) - vec2<f32>(0.0, time * (0.2 + mids * 0.5)));

  let emberNoise = hash21(floor((uv + time * 0.08) * 180.0));
  let emberSpark = step(0.995 - treble * 0.02, emberNoise) * (0.5 + 0.5 * sin(time * 20.0 + emberNoise * 30.0));

  // Chromatic volcanic ink: warm lava, amber sparks, ashen smoke with blue shift
  var color = vec3<f32>(0.02, 0.01, 0.015);
  color = color + vec3<f32>(1.3, 0.45, 0.08) * lava * ember * (1.0 + bass * 0.15);
  color = color + vec3<f32>(0.35, 0.08, 0.04) * cracks * 0.5;
  color = color + vec3<f32>(0.12, 0.1, 0.15) * smoke * soot * (1.0 + treble * 0.1);
  color = color + vec3<f32>(1.0, 0.75, 0.3) * emberSpark * (0.4 + bass);

  // Temporal ink persistence: lava smears and smoke accumulates
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, smoke * soot * 0.04 + bass * 0.01);

  let presence = sat(lava * 0.95 + cracks * 0.35 + emberSpark * 0.9);
  let alpha = sat(0.2 + presence * 0.8);
  let depth = sat(0.95 - lava * 0.6 - emberSpark * 0.2 + smoke * 0.08);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(lava, cracks, emberSpark, alpha));
}
