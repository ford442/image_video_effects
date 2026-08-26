// Liquid v1 — clean baseline ambient height-field liquid.
// Raw A ownership: R=height, G=velocity, B=foam, A=coverage.
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

fn clampPixel(p: vec2<i32>, dims: vec2<i32>) -> vec2<i32> { return clamp(p, vec2<i32>(0), dims - vec2<i32>(1)); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let intensity = u.zoom_params.x; let speed = mix(0.25, 1.45, u.zoom_params.y);
  let scale = mix(5.0, 18.0, u.zoom_params.z); let detail = u.zoom_params.w;

  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = c.a > 0.00001;
  var height = select(0.12, c.r, initialized); var velocity = select(0.0, c.g, initialized);
  let hL = select(0.12, l.r, initialized); let hR = select(0.12, r.r, initialized);
  let hD = select(0.12, d.r, initialized); let hU = select(0.12, t.r, initialized);
  let laplacian = hL + hR + hD + hU - 4.0 * height;
  let p = (uv - 0.5) * aspectVec;
  let ambient = sin(p.x * scale + time * speed * (0.72 + bass * 0.2))
    * cos(p.y * scale * 1.21 - time * speed * (0.61 + mids * 0.16));
  let crossWave = sin((p.x + p.y) * scale * 0.67 - time * speed * 0.48) * detail;
  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec; let mouseDist = length(mouseDelta);
  let held = select(0.16, 1.0, u.zoom_config.w > 0.5);
  var impulse = exp(-mouseDist * mouseDist * 62.0) * held * (0.008 + intensity * 0.035);
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 3.0) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let ring = exp(-pow((dist - age * (0.15 + speed * 0.06)) * 38.0, 2.0)) * exp(-age * 1.1);
      impulse += ring * sin(age * 7.0) * (0.014 + intensity * 0.05); clickEnergy += ring;
    }
  }
  velocity = clamp(velocity * mix(0.93, 0.975, detail) + laplacian * mix(0.12, 0.065, detail)
    + (0.12 - height) * 0.012 + (ambient + crossWave * 0.45) * intensity * 0.0018 + impulse, -0.65, 0.65);
  height = clamp(height + velocity * mix(0.085, 0.05, detail), 0.01, 0.9);
  let foam = clamp(max(c.b * 0.94, abs(laplacian) * 8.0 + abs(velocity) * 0.55 + clickEnergy * 0.35), 0.0, 1.0);
  let coverage = clamp(max(c.a * 0.997, smoothstep(0.01, 0.1, height)), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, foam, coverage));

  let gradient = vec2<f32>(hL - hR, hD - hU) * (4.0 + intensity * 12.0);
  let normal = normalize(vec3<f32>(gradient, 0.28));
  let sourceUV = clamp(uv + normal.xy * (0.01 + intensity * 0.05) * height / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let fresnel = 0.02 + 0.98 * pow(clamp(1.0 - normal.z, 0.0, 1.0), 5.0);
  let caustic = pow(clamp(abs(laplacian) * 20.0 + clickEnergy * 0.3, 0.0, 1.0), 2.0);
  let color = source.rgb * exp(-height * vec3<f32>(0.25, 0.1, 0.04))
    + vec3<f32>(0.18, 0.52, 0.92) * fresnel * (0.18 + mids * 0.13)
    + vec3<f32>(0.7, 0.94, 1.12) * caustic * (0.14 + treble * 0.2)
    + vec3<f32>(0.75, 0.88, 1.0) * foam * bass * 0.08;
  let alpha = clamp(source.a + (1.0 - source.a) * coverage * (0.2 + height * 0.58) + fresnel * 0.06, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.92, height * 0.24 + foam * 0.025), 0.0, 0.0, 0.0));
}
