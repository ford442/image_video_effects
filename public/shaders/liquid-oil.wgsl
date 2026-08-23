// Liquid Oil — high-viscosity film with persistent thickness and specular flow.
// Raw A ownership: R=film height, G=vertical response, B=shear, A=coverage.

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

struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };
const TAU: f32 = 6.28318530718;

fn clampPixel(p: vec2<i32>, dims: vec2<i32>) -> vec2<i32> { return clamp(p, vec2<i32>(0), dims - vec2<i32>(1)); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn schlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
  return f0 + (vec3<f32>(1.0) - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let viscosity = u.zoom_params.x; let turbulence = u.zoom_params.y;
  let rippleStrength = u.zoom_params.z; let colorShift = u.zoom_params.w;

  let center = textureLoad(dataTextureC, pixel, 0);
  let left = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let right = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let down = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let up = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = center.a > 0.00001;
  let seed = 0.18 + hash21(floor(uv * 24.0)) * 0.035;
  var height = select(seed, center.r, initialized);
  var velocity = select(0.0, clamp(center.g, -0.5, 0.5), initialized);
  var shear = select(0.0, center.b, initialized);
  let hL = select(seed, left.r, initialized); let hR = select(seed, right.r, initialized);
  let hD = select(seed, down.r, initialized); let hU = select(seed, up.r, initialized);
  let laplacian = hL + hR + hD + hU - 4.0 * height;

  let capillary = mix(0.075, 0.018, viscosity); let damping = mix(0.91, 0.985, viscosity);
  let p = (uv - 0.5) * aspectVec;
  let curl = sin(p.y * (8.0 + turbulence * 13.0) + time * (0.18 + bass * 0.12))
    * cos(p.x * (7.0 + turbulence * 11.0) - time * (0.14 + mids * 0.1));
  var acceleration = laplacian * capillary + curl * turbulence * 0.0018;
  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec; let mouseDist = length(mouseDelta);
  let held = select(0.22, 1.0, u.zoom_config.w > 0.5);
  let stir = exp(-mouseDist * mouseDist * 70.0) * held;
  let tangent = select(vec2<f32>(0.0), vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist, mouseDist > 0.001);
  acceleration += stir * (0.006 + rippleStrength * 0.02);
  shear = mix(shear, dot(tangent, vec2<f32>(0.707, 0.707)) * stir, 0.06 + turbulence * 0.05);

  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 3.6) {
      let d = length((uv - ripple.xy) * aspectVec);
      let ring = exp(-pow((d - age * 0.085) * 34.0, 2.0)) * exp(-age * (0.75 + viscosity));
      acceleration += ring * sin(age * 5.0) * (0.012 + rippleStrength * 0.055); clickEnergy += ring;
    }
  }
  velocity = clamp(velocity * damping + acceleration, -0.42, 0.42);
  height = clamp(height + velocity * mix(0.07, 0.022, viscosity), 0.025, 0.75);
  shear = clamp(shear * mix(0.94, 0.985, viscosity) + (hR - hL - hU + hD) * 0.05, -1.0, 1.0);
  let coverage = clamp(max(center.a * 0.997, smoothstep(0.025, 0.17, height) + stir * 0.08), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, shear, coverage));

  let gradient = vec2<f32>(hL - hR, hD - hU) * (5.0 + rippleStrength * 9.0);
  let normal = normalize(vec3<f32>(gradient + tangent * shear * 0.12, 0.18 + viscosity * 0.2));
  let sourceUV = clamp(uv + normal.xy * (0.012 + height * 0.055) / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let viewDir = normalize(vec3<f32>((uv - 0.5) * aspectVec * 0.3, 1.0));
  let fresnel = schlick(max(dot(normal, viewDir), 0.0), vec3<f32>(0.045));
  let halfDir = normalize(viewDir + normalize(vec3<f32>(-0.45, 0.55, 0.8)));
  let specular = pow(max(dot(normal, halfDir), 0.0), mix(26.0, 130.0, viscosity));
  let filmPhase = height * (46.0 + colorShift * 92.0) + shear * 1.8 + time * 0.018;
  let interference = 0.5 + 0.5 * cos(TAU * (vec3<f32>(1.0, 1.17, 1.36) * filmPhase + vec3<f32>(0.0, 0.2, 0.43)));
  let absorption = exp(-height * vec3<f32>(0.65, 1.05, 1.8));
  let color = source.rgb * absorption + interference * fresnel * (0.24 + colorShift * 0.5 + mids * 0.14)
    + vec3<f32>(1.0, 0.78, 0.38) * specular * (0.65 + bass * 0.35)
    + vec3<f32>(0.24, 0.46, 1.0) * clickEnergy * treble * 0.1;
  let alpha = clamp(source.a + (1.0 - source.a) * coverage * (0.34 + height * 0.55) + fresnel.g * 0.08, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.9, height * 0.28), 0.0, 0.0, 0.0));
}
