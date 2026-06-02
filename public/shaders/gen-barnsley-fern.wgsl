// ═══════════════════════════════════════════════════════════════════
//  Barnsley Fern IFS
//  Category: generative
//  Features: procedural, fractal, barnsley-ifs, audio-reactive,
//            mouse-driven, aces-tonemap, chromatic-aberration,
//            temporal-feedback, depth-aware, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-30
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn barnsleyInv(p: vec2<f32>, idx: i32) -> vec2<f32> {
  if idx == 0 {
    return vec2<f32>(0.0, p.y / 0.16);
  }
  if idx == 1 {
    let dy = p.y - 1.6;
    return vec2<f32>((0.85 * p.x - 0.04 * dy) / 0.7241, (0.04 * p.x + 0.85 * dy) / 0.7241);
  }
  if idx == 2 {
    let dy = p.y - 1.6;
    return vec2<f32>((0.22 * p.x + 0.26 * dy) / 0.1038, (-0.23 * p.x + 0.2 * dy) / 0.1038);
  }
  let dy = p.y - 0.44;
  return vec2<f32>((-0.24 * p.x + 0.28 * dy) / 0.1088, (0.26 * p.x + 0.15 * dy) / 0.1088);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if gid.x >= dims.x || gid.y >= dims.y { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let scale = mix(0.7, 1.3, u.zoom_params.x);
  let caAmt = u.zoom_params.y * 0.06;
  let brightness = mix(0.8, 2.0, u.zoom_params.z);
  let feedback = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect * 5.0, 10.0) / scale;

  // Mouse attracts frond tips
  let mouseFern = (mouse - 0.5) * vec2<f32>(aspect * 5.0, 10.0) / scale;
  let tipFactor = smoothstep(0.0, 1.0, (p.y + 3.0) / 8.0);
  let pull = exp(-length(p - mouseFern) * 0.8) * tipFactor * 0.4;
  p = mix(p, mouseFern, pull);

  // Inverse IFS Monte-Carlo coverage
  let seed = f32(gid.x) * 137.0 + f32(gid.y) * 241.0 + time * 0.05;
  let numPaths = i32(mix(2.0, 5.0, depth + bass * 0.3));
  var density = 0.0;

  for (var path = 0; path < numPaths; path = path + 1) {
    var q = p;
    var valid = 1.0;
    for (var i = 0; i < 7; i = i + 1) {
      let h = hashf(seed + f32(path) * 31.0 + f32(i) * 17.0);
      var idx = 1;
      if h < 0.01 { idx = 0; }
      else if h < 0.86 { idx = 1; }
      else if h < 0.93 { idx = 2; }
      else { idx = 3; }
      if idx == 0 && abs(q.x) > 0.18 { idx = 1; }
      q = barnsleyInv(q, idx);
      if q.x < -3.2 || q.x > 3.2 || q.y < -0.5 || q.y > 12.0 {
        valid = 0.0;
        break;
      }
    }
    density = density + valid;
  }
  density = density / f32(numPaths);

  // Natural fern palette by height
  let fy = clamp((p.y + 3.0) / 10.0, 0.0, 1.0);
  let forest = vec3<f32>(0.02, 0.18, 0.04);
  let emerald = vec3<f32>(0.05, 0.65, 0.18);
  let lime = vec3<f32>(0.45, 0.95, 0.12);
  let yellow = vec3<f32>(0.85, 0.95, 0.25);
  var color: vec3<f32>;
  if fy < 0.3 {
    color = mix(forest, emerald, fy / 0.3);
  } else if fy < 0.7 {
    color = mix(emerald, lime, (fy - 0.3) / 0.4);
  } else {
    color = mix(lime, yellow, (fy - 0.7) / 0.3);
  }

  // Sunlight filtering through fronds
  let sun = 0.3 + 0.7 * smoothstep(0.2, 0.9, density);
  color = color * sun * brightness;

  // Chromatic aberration on fern edges
  let edge = smoothstep(0.15, 0.75, density);
  color = vec3<f32>(color.r * (1.0 + edge * caAmt), color.g,
                    color.b * (1.0 - edge * caAmt * 0.4));

  color = acesToneMap(color * 1.8);

  // Temporal feedback
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  color = mix(color, prev * 0.96, 0.03 + feedback * 0.08 + bass * 0.02);

  // Audio morphs palette warmth
  let warmth = bass * 0.15;
  color = vec3<f32>(color.r * (1.0 + warmth), color.g, color.b * (1.0 - warmth * 0.3));

  let photo = smoothstep(0.0, 0.4, color.g);
  let alpha = density * photo * (0.4 + depth * 0.6);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(density * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
