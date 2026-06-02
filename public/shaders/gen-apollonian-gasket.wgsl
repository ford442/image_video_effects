// ═══════════════════════════════════════════════════════════════════
//  Apollonian Gasket
//  Category: generative
//  Features: procedural, fractal, apollonian-gasket, circle-inversion,
//            descartes-theorem, audio-reactive, mouse-driven, aces-tonemap, upgraded-rgba
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

fn circle_inv(p: vec2<f32>, c: vec2<f32>, r: f32) -> vec2<f32> {
  let d = p - c;
  let l2 = dot(d, d) + 1e-8;
  return c + d * (r * r) / l2;
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let recursion = i32(mix(3.0, 10.0, clamp(u.zoom_params.x + bass * 0.3, 0.0, 1.0)));
  let invIntensity = u.zoom_params.y;
  let circleSize = mix(0.5, 2.0, u.zoom_params.z);
  let rainbow = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 3.0 / circleSize;

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
      if (distance(q, c) < r) {
        q = circle_inv(q, c, r);
        invCount = invCount + 1.0;
        inverted = true;
        break;
      }
    }
    if (!inverted) { break; }
  }

  if (mouseDown) {
    let mp = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 3.0 / circleSize;
    let mr = 0.2 + invIntensity * 0.3;
    if (distance(q, mp) < mr) {
      q = circle_inv(q, mp, mr);
      invCount = invCount + 1.0;
    }
  }

  var minDist = 1e9;
  for (var j = 0; j < 5; j = j + 1) {
    let d = abs(distance(q, circles[j].xy) - circles[j].z);
    minDist = min(minDist, d);
  }

  let density = exp(-minDist * 15.0);
  let hue = fract(invCount * 0.1 + length(q) * 0.3 + time * 0.02);
  let sat = 0.3 + density * 0.7;
  let val = 0.15 + density * 0.85;

  var color = vec3<f32>(
    val * (0.6 + sat * cos(hue * 6.283) * 0.4),
    val * (0.6 + sat * cos((hue - 0.33) * 6.283) * 0.4),
    val * (0.6 + sat * cos((hue - 0.66) * 6.283) * 0.4)
  );

  let ca = smoothstep(0.0, 0.4, density) * rainbow;
  color = vec3<f32>(
    color.r * (1.0 + ca * 0.2),
    color.g * (1.0 + ca * 0.05),
    color.b * (1.0 - ca * 0.1)
  );

  color = aces_tonemap(color * 2.0);

  let alpha = density * clamp(invCount / 8.0, 0.0, 1.0) * (0.7 + bass * 0.3);
  let depth = clamp(1.0 - minDist * 2.0, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
