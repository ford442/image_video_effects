// ═══════════════════════════════════════════════════════════════════
//  Apollonian Gasket
//  Category: generative
//  Features: procedural, fractal, apollonian-gasket, circle-inversion,
//            descartes-theorem, voronoi-distortion, strange-attractor,
//            audio-reactive, mouse-driven, aces-tonemap, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-07-13
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var q = p;
  for (var i = 0; i < oct; i = i + 1) {
    v = v + a * valueNoise(q);
    q = q * 2.03 + vec2<f32>(1.7, 9.2);
    a = a * 0.5;
  }
  return v;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
  return p + strength * q;
}

fn voronoi(p: vec2<f32>) -> vec2<f32> {
  let i = floor(p);
  let f = fract(p);
  var minDist = 1.0e10;
  var cellId = 0.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let point = neighbor + hash21(i + neighbor);
      let diff = point - f;
      let d = dot(diff, diff);
      let closer = f32(d < minDist);
      minDist = mix(minDist, d, closer);
      cellId = mix(cellId, hash21(i + neighbor), closer);
    }
  }
  return vec2<f32>(sqrt(minDist), cellId);
}

fn circle_inv(p: vec2<f32>, c: vec2<f32>, r: f32) -> vec2<f32> {
  let d = p - c;
  let l2 = dot(d, d) + 1e-8;
  return c + d * (r * r) / l2;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let recursion = i32(mix(3.0, 10.0, clamp(u.zoom_params.x + bass * 0.3, 0.0, 1.0)));
  let invIntensity = u.zoom_params.y;
  let circleSize = mix(0.5, 2.0, u.zoom_params.z);
  let rainbow = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 3.0 / circleSize;

  // Voronoi distortion field
  let voro = voronoi(p * 2.0 + time * 0.1);
  p = p + (voro.x - 0.3) * vec2<f32>(cos(voro.y * TAU), sin(voro.y * TAU)) * invIntensity * 0.2;

  // Descartes theorem configuration
  let circles = array<vec3<f32>, 5>(
    vec3<f32>(0.5, 0.0, 0.5),
    vec3<f32>(-0.5, 0.0, 0.5),
    vec3<f32>(0.0, 0.866, 0.5),
    vec3<f32>(0.0, 0.289, 0.155),
    vec3<f32>(0.0, -0.5, 0.3)
  );

  var q = p;
  var invCount = 0.0;

  for (var i = 0; i < recursion; i = i + 1) {
    var inverted = false;
    for (var j = 0; j < 5; j = j + 1) {
      let c = circles[j].xy;
      let r = circles[j].z;
      let inside = distance(q, c) < r;
      let invQ = circle_inv(q, c, r);
      q = select(q, invQ, inside);
      invCount = invCount + f32(inside);
      inverted = inverted || inside;
    }
    if (!inverted) { break; }
  }

  // Strange attractor mouse inversion (branchless)
  let mp = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 3.0 / circleSize;
  let mr = 0.2 + invIntensity * 0.3;
  let mouseInside = mouseDown && distance(q, mp) < mr;
  q = select(q, circle_inv(q, mp, mr), mouseInside);
  invCount = invCount + f32(mouseInside);

  var minDist = 1e9;
  for (var j = 0; j < 5; j = j + 1) {
    let d = abs(distance(q, circles[j].xy) - circles[j].z);
    minDist = min(minDist, d);
  }

  // Orbit-trap density with FBM grain
  let grain = fbm(q * 8.0 + invCount, 3);
  let density = exp(-minDist * 15.0) * (0.8 + grain * 0.4);
  let hue = fract(invCount * 0.1 + length(q) * 0.3 + time * 0.02 + voro.y * 0.2);
  let sat = 0.3 + density * 0.7;
  let val = 0.15 + density * 0.85;

  var color = vec3<f32>(
    val * (0.6 + sat * cos(hue * TAU) * 0.4),
    val * (0.6 + sat * cos((hue - 0.33) * TAU) * 0.4),
    val * (0.6 + sat * cos((hue - 0.66) * TAU) * 0.4)
  );

  // Metallic rim from orbit trap
  let rim = exp(-minDist * 5.0) * (0.5 + 0.5 * sin(invCount + time));
  color = mix(color, vec3<f32>(0.95, 0.92, 0.88), rim * 0.3);

  let ca = smoothstep(0.0, 0.4, density) * rainbow;
  color = vec3<f32>(
    color.r * (1.0 + ca * 0.2),
    color.g * (1.0 + ca * 0.05),
    color.b * (1.0 - ca * 0.1)
  );

  let alpha = density * clamp(invCount / 8.0, 0.0, 1.0) * (0.7 + bass * 0.3);
  let depth = clamp(1.0 - minDist * 2.0, 0.0, 1.0);

  // Temporal feedback
  let histUV = uv + vec2<f32>(sin(time * 0.18) * 0.001, cos(time * 0.12) * 0.001);
  let prev = textureSampleLevel(dataTextureC, u_sampler, histUV, 0.0).rgb;
  color = mix(color, prev * 0.94, 0.05);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));

  color = acesToneMap(color * 2.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
