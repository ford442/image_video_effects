// ═══════════════════════════════════════════════════════════════════
//  Sierpinski Tetrahedron
//  Category: generative
//  Features: procedural, fractal, sierpinski, tetrahedron, 3d-projection,
//            audio-reactive, mouse-driven, chromatic-aberration, aces-tonemap,
//            temporal-feedback, depth-aware
//  Complexity: High
//  Created: 2026-05-31
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

fn jewelColor(idx: f32, shade: f32) -> vec3<f32> {
  let j0 = vec3<f32>(0.0, 0.6, 0.3) * shade;   // emerald
  let j1 = vec3<f32>(0.0, 0.3, 0.7) * shade;   // sapphire
  let j2 = vec3<f32>(0.7, 0.1, 0.2) * shade;   // ruby
  let j3 = vec3<f32>(0.5, 0.2, 0.6) * shade;   // amethyst
  let f = fract(idx);
  if f < 0.33 { return mix(j0, j1, f * 3.0); }
  if f < 0.66 { return mix(j1, j2, (f - 0.33) * 3.0); }
  return mix(j2, j3, (f - 0.66) * 3.0);
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
  let mouse = u.zoom_config.yz;

  let recursion = i32(mix(4.0, 10.0, clamp(u.zoom_params.x + bass * 0.25, 0.0, 1.0)));
  let rotSpeed = mix(0.1, 0.6, u.zoom_params.y) * (1.0 + bass * 0.5);
  let persp = mix(1.5, 4.0, u.zoom_params.z);
  let caAmt = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

  // Mouse rotates the 3D view
  let yaw = (mouse.x - 0.5) * PI * 2.0 + time * rotSpeed;
  let pitch = (mouse.y - 0.5) * PI * 0.8 + sin(time * 0.3) * 0.2;

  // Depth from readDepthTexture controls perspective strength
  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.5, 1.5, depthSample);

  // Tetrahedron vertices
  let v0 = vec3<f32>(0.0, 1.0, 0.0);
  let v1 = vec3<f32>(-0.816, -0.333, 0.577);
  let v2 = vec3<f32>(0.816, -0.333, 0.577);
  let v3 = vec3<f32>(0.0, -0.333, -1.155);

  // Ray from pixel into scene (reverse IFS / orbit trap)
  var rp = vec3<f32>(p.x * persp * depthFactor, p.y * persp * depthFactor, 2.5);
  rp = rotY(rotX(rp, pitch), yaw);

  var point = rp;
  var minTrap = 1e9;
  var trapIdx = 0.0;

  for (var i = 0; i < recursion; i = i + 1) {
    let d0 = distance(point, v0);
    let d1 = distance(point, v1);
    let d2 = distance(point, v2);
    let d3 = distance(point, v3);

    var nearest = d0;
    var vi = 0.0;
    if d1 < nearest { nearest = d1; vi = 1.0; }
    if d2 < nearest { nearest = d2; vi = 2.0; }
    if d3 < nearest { nearest = d3; vi = 3.0; }

    // Orbit trap: track closest approach to any vertex
    let trap = min(min(d0, d1), min(d2, d3));
    if trap < minTrap { minTrap = trap; trapIdx = vi; }

    // Contract toward nearest vertex (IFS step)
    let tgt = select(select(select(v3, v2, nearest == d2), v1, nearest == d1), v0, nearest == d0);
    point = (point + tgt) * 0.5;
  }

  // Temporal feedback for smooth morphing
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  minTrap = mix(minTrap, prev.r, 0.03 + mids * 0.02);

  let density = exp(-minTrap * 12.0);
  let edge = exp(-abs(minTrap - 0.05) * 30.0);

  // Jewel-tone palette with metallic sheen
  var color = jewelColor(trapIdx * 0.25 + mids * 0.1, 0.7 + density * 0.6);

  // HDR specular on edges
  let spec = pow(edge, 4.0) * (0.8 + bass * 0.5);
  color = color + vec3<f32>(0.9, 0.85, 0.8) * spec;

  // Chromatic aberration on depth edges
  let caMask = smoothstep(0.0, 0.15, edge) * caAmt;
  let caR = acesToneMap(vec3<f32>(color.r * 1.12, color.g * 0.96, color.b * 0.88) * 1.3);
  let caB = acesToneMap(vec3<f32>(color.r * 0.88, color.g * 0.96, color.b * 1.12) * 1.3);
  color = mix(acesToneMap(color * 1.3), mix(caR, caB, caMask), caMask * 0.35);

  // Alpha: surface_density × recursion_level × depth
  let alpha = clamp(density * (f32(recursion) / 10.0) * depthFactor, 0.0, 1.0);
  let depthOut = clamp(0.3 + density * 0.7, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(minTrap, trapIdx, density, alpha));
}
