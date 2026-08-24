// Liquid — canonical interactive capillary surface.
// Raw A ownership: R=height, G=velocity, B=curvature foam, A=coverage.
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
  let viscosity = u.zoom_params.x; let turbulence = u.zoom_params.y;
  let rippleStrength = u.zoom_params.z; let colorShift = u.zoom_params.w;
  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = c.a > 0.00001;
  var height = select(0.14, c.r, initialized); var velocity = select(0.0, c.g, initialized);
  let hL = select(0.14, l.r, initialized); let hR = select(0.14, r.r, initialized);
  let hD = select(0.14, d.r, initialized); let hU = select(0.14, t.r, initialized);
  let laplacian = hL + hR + hD + hU - 4.0 * height;

  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var pointer = u.zoom_config.yz; var pointerVelocity = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) { pointer = vec2<f32>(extraBuffer[133], extraBuffer[134]); pointerVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]); }
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    var p = pointer; var v = pointerVelocity; let seeded = extraBuffer[138] > 0.5;
    if (!seeded) { p = u.zoom_config.yz; v = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
    v += ((u.zoom_config.yz - p) * 180.0 - v * mix(18.0, 31.0, viscosity)) * dt; p += v * dt;
    extraBuffer[133] = p.x; extraBuffer[134] = p.y; extraBuffer[135] = v.x; extraBuffer[136] = v.y; extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }
  let mouseDelta = (uv - pointer) * aspectVec; let mouseDist = length(mouseDelta);
  let mouseMask = exp(-mouseDist * mouseDist * 72.0);
  let held = select(0.15, 1.0, u.zoom_config.w > 0.5);
  var impulse = mouseMask * held * (0.01 + rippleStrength * 0.055 + length(pointerVelocity) * 0.008);
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 3.2) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let ring = exp(-pow((dist - age * (0.16 + bass * 0.05)) * 42.0, 2.0)) * exp(-age * mix(0.85, 1.45, viscosity));
      impulse += ring * sin(age * (6.0 + mids * 3.0)) * (0.025 + rippleStrength * 0.075); clickEnergy += ring;
    }
  }
  let p = (uv - 0.5) * aspectVec;
  let capillaryNoise = sin(p.y * (10.0 + turbulence * 12.0) + time * (0.45 + bass * 0.2))
    * cos(p.x * (9.0 + turbulence * 10.0) - time * (0.38 + mids * 0.16));
  let tension = mix(0.15, 0.055, viscosity); let damping = mix(0.91, 0.986, viscosity);
  velocity = clamp(velocity * damping + laplacian * tension + (0.14 - height) * 0.014
    + capillaryNoise * turbulence * 0.0022 + impulse, -0.85, 0.85);
  height = clamp(height + velocity * mix(0.095, 0.035, viscosity), 0.01, 1.0);
  let foam = clamp(max(c.b * mix(0.9, 0.97, viscosity), abs(laplacian) * 9.0 + abs(velocity) * 0.6 + clickEnergy * 0.38), 0.0, 1.0);
  let coverage = clamp(max(c.a * 0.997, smoothstep(0.01, 0.11, height)), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, foam, coverage));

  let gradient = vec2<f32>(hL - hR, hD - hU) * (5.0 + rippleStrength * 13.0);
  let normal = normalize(vec3<f32>(gradient, 0.24 + viscosity * 0.2));
  let sourceUV = clamp(uv + normal.xy * (0.012 + height * 0.052) / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let fresnel = 0.02 + 0.98 * pow(clamp(1.0 - normal.z, 0.0, 1.0), 5.0);
  let caustic = pow(clamp(abs(laplacian) * 21.0 + clickEnergy * 0.3, 0.0, 1.0), 2.2);
  let tint = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.0, 0.19, 0.41) + colorShift + height * vec3<f32>(0.42, 0.51, 0.63)));
  let color = source.rgb * exp(-height * vec3<f32>(0.3, 0.14, 0.06))
    + tint * fresnel * (0.14 + colorShift * 0.18 + mids * 0.12)
    + vec3<f32>(0.7, 0.94, 1.12) * caustic * (0.16 + treble * 0.22)
    + vec3<f32>(0.76, 0.88, 1.0) * foam * (0.08 + bass * 0.08);
  let alpha = clamp(source.a + (1.0 - source.a) * coverage * (0.22 + height * 0.58) + fresnel * 0.07 + foam * 0.04, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.9, height * 0.28 + foam * 0.025), 0.0, 0.0, 0.0));
}
