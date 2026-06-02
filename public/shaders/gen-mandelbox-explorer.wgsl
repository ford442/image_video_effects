// ═══════════════════════════════════════════════════════════════════
//  Mandelbox Explorer
//  Category: generative
//  Features: procedural, fractal, mandelbox, orbit-trap, raymarched-slice,
//            audio-reactive, mouse-driven, aces-tonemap, upgraded-rgba
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

fn boxFold(v: vec3<f32>) -> vec3<f32> {
  return clamp(v, vec3<f32>(-1.0), vec3<f32>(1.0)) * 2.0 - v;
}

fn sphereFold(v: vec3<f32>) -> vec3<f32> {
  let r2 = dot(v, v);
  if (r2 < 0.25) {
    return v * 4.0;
  } else if (r2 < 1.0) {
    return v / r2;
  }
  return v;
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
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

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mouse = u.zoom_config.yz;

  let scale = mix(-2.5, 2.5, clamp(u.zoom_params.x + bass * 0.25, 0.0, 1.0));
  let maxIter = i32(mix(30.0, 90.0, u.zoom_params.y));
  let sliceThick = mix(0.0, 0.6, u.zoom_params.z);
  let specular = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 4.0;

  let angle = (mouse.x - 0.5) * 3.14159;
  let ca = cos(angle);
  let sa = sin(angle);
  p = vec2<f32>(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

  var z = vec3<f32>(p.x, p.y, sliceThick);
  let c = vec3<f32>(p.x, p.y, 0.0);
  var orbitMin = 1e9;
  var orbitAvg = 0.0;

  for (var i = 0; i < maxIter; i = i + 1) {
    z = boxFold(z);
    z = sphereFold(z);
    z = z * scale + c;
    let lz = length(z);
    orbitMin = min(orbitMin, lz);
    orbitAvg = orbitAvg + lz;
    if (dot(z, z) > 10000.0) { break; }
  }
  orbitAvg = orbitAvg / f32(maxIter);

  let ao = exp(-orbitMin * 4.0);
  let temp = fract(orbitAvg * 0.1 + 0.5);
  let warm = vec3<f32>(0.95, 0.78, 0.55);
  let cool = vec3<f32>(0.55, 0.72, 0.92);
  var color = mix(warm, cool, temp);
  color = mix(vec3<f32>(0.15, 0.18, 0.25), color, 1.0 - ao * 0.8);

  let highlight = exp(-orbitMin * orbitMin * 12.0);
  color = color + vec3<f32>(1.0, 0.95, 0.78) * highlight * specular * 3.5;

  let edge = smoothstep(0.25, 0.65, 1.0 - ao);
  color = vec3<f32>(
    color.r * (1.0 + edge * 0.12),
    color.g * (1.0 + edge * 0.04),
    color.b * (1.0 - edge * 0.1)
  );

  let histUV = uv + vec2<f32>(sin(time * 0.18) * 0.001, cos(time * 0.12) * 0.001);
  let prev = textureSampleLevel(dataTextureC, u_sampler, histUV, 0.0).rgb;
  color = mix(color, prev * 0.94, 0.05);

  color = aces_tonemap(color * 2.2);

  let density = 1.0 - ao;
  let alpha = density * clamp(orbitMin * 3.0, 0.0, 1.0);
  let depth = density * clamp(orbitMin * 2.5, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
