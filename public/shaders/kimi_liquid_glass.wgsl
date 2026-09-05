// Kimi Liquid Glass — refractive thickness field with caustic optics.
// Raw A ownership: R=height, G=velocity, B=thickness, A=coverage.

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
fn schlick(cosTheta: f32, f0: f32) -> f32 { return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution; let time = u.config.x;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  // Saved slots: intensity, speed, scale, detail.
  let intensity = u.zoom_params.x; let speed = mix(0.25, 1.55, u.zoom_params.y);
  let scale = mix(3.0, 13.0, u.zoom_params.z); let detail = u.zoom_params.w;

  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = c.a > 0.00001;
  let cells = floor(uv * scale * vec2<f32>(aspectVec.x, 1.0));
  let seedHeight = 0.14 + hash21(cells) * 0.035;
  var height = select(seedHeight, c.r, initialized); var velocity = select(0.0, c.g, initialized);
  var thickness = select(0.22, c.b, initialized);
  let hL = select(seedHeight, l.r, initialized); let hR = select(seedHeight, r.r, initialized);
  let hD = select(seedHeight, d.r, initialized); let hU = select(seedHeight, t.r, initialized);
  let laplacian = hL + hR + hD + hU - 4.0 * height;

  let p = (uv - 0.5) * aspectVec;
  let modal = sin(p.x * scale + time * speed * (0.42 + bass * 0.22))
    * cos(p.y * scale * 1.17 - time * speed * (0.36 + mids * 0.18));
  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec; let mouseDist = length(mouseDelta);
  let held = select(0.16, 1.0, u.zoom_config.w > 0.5);
  let lensPush = exp(-mouseDist * mouseDist * mix(80.0, 26.0, intensity)) * held;
  var impulse = lensPush * (0.012 + intensity * 0.045);
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 2.7) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let ring = exp(-pow((dist - age * (0.16 + speed * 0.06)) * (36.0 + detail * 18.0), 2.0)) * exp(-age * 1.05);
      impulse += ring * sin(age * 8.0) * (0.018 + intensity * 0.06); clickEnergy += ring;
    }
  }
  velocity = clamp(velocity * mix(0.94, 0.982, detail) + laplacian * mix(0.12, 0.055, detail)
    + (seedHeight - height) * 0.014 + modal * intensity * 0.0018 + impulse, -0.75, 0.75);
  height = clamp(height + velocity * mix(0.085, 0.045, detail), 0.015, 0.95);
  thickness = clamp(mix(thickness, height * (0.8 + detail * 0.55) + abs(laplacian) * 2.5, 0.055) + lensPush * 0.012, 0.01, 1.0);
  let coverage = clamp(max(c.a * 0.997, smoothstep(0.015, 0.13, thickness)), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, thickness, coverage));

  let gradient = vec2<f32>(hL - hR, hD - hU) * (5.0 + intensity * 15.0 + detail * 5.0);
  let normal = normalize(vec3<f32>(gradient, 0.26));
  let ior = mix(1.31, 1.58, detail); let eta = 1.0 / ior;
  let refracted = refract(vec3<f32>(0.0, 0.0, -1.0), normal, eta);
  let offset = (refracted.xy + normal.xy * 0.35) * thickness * (0.025 + intensity * 0.075) / aspectVec;
  let dispersion = (0.001 + detail * 0.006 + treble * 0.0025) * normal.xy / aspectVec;
  let centerUV = clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999));
  let sourceR = textureSampleLevel(readTexture, u_sampler, clamp(centerUV + dispersion, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let sourceG = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);
  let sourceB = textureSampleLevel(readTexture, u_sampler, clamp(centerUV - dispersion, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let source = vec4<f32>(sourceR.r, sourceG.g, sourceB.b, max(sourceR.a, max(sourceG.a, sourceB.a)));
  let f0 = pow((ior - 1.0) / (ior + 1.0), 2.0); let fresnel = schlick(max(normal.z, 0.0), f0);
  let curvature = abs(laplacian) * (22.0 + detail * 38.0);
  let caustic = pow(clamp(curvature + clickEnergy * 0.36, 0.0, 1.0), 2.2);
  let interference = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.88, 1.0, 1.14) * (thickness * 2.2 + time * 0.012) + vec3<f32>(0.0, 0.21, 0.43)));
  let absorption = exp(-thickness * vec3<f32>(0.22, 0.09, 0.035) * (0.6 + intensity));
  let color = source.rgb * absorption + vec3<f32>(0.36, 0.66, 1.0) * fresnel * (0.18 + mids * 0.14)
    + interference * caustic * (0.12 + detail * 0.3 + treble * 0.12) + vec3<f32>(1.0, 0.82, 0.48) * lensPush * bass * 0.08;
  let alpha = clamp(source.a + (1.0 - source.a) * coverage * (0.16 + thickness * 0.6) + fresnel * 0.08, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.91, thickness * 0.24 + caustic * 0.03), 0.0, 0.0, 0.0));
}
