// Liquid Displacement — persistent incompressible flow and height-field warp.
// Raw A ownership: RG=velocity, B=surface height, A=activity/initialization.

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
fn schlick(cosTheta: f32, f0: f32) -> f32 { return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0); let time = u.config.x;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  // Saved slots: viscosity, pressure iterations, flow speed, turbulence.
  let viscosity = u.zoom_params.x; let pressureGain = mix(0.12, 0.48, u.zoom_params.y);
  let flowSpeed = mix(0.45, 2.2, u.zoom_params.z) * (1.0 + bass * 0.28); let turbulence = u.zoom_params.w;

  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = c.a > 0.00001;
  var velocity = select(vec2<f32>(0.0), clamp(c.rg, vec2<f32>(-1.2), vec2<f32>(1.2)), initialized);
  var height = select(0.12, c.b, initialized);
  let vL = select(vec2<f32>(0.0), l.rg, initialized); let vR = select(vec2<f32>(0.0), r.rg, initialized);
  let vD = select(vec2<f32>(0.0), d.rg, initialized); let vU = select(vec2<f32>(0.0), t.rg, initialized);
  let hL = select(0.12, l.b, initialized); let hR = select(0.12, r.b, initialized);
  let hD = select(0.12, d.b, initialized); let hU = select(0.12, t.b, initialized);
  let divergence = (vR.x - vL.x + vU.y - vD.y) * 0.5;
  let lapV = vL + vR + vD + vU - 4.0 * velocity;
  let heightGrad = vec2<f32>(hR - hL, hU - hD) * 0.5;
  let lapH = hL + hR + hD + hU - 4.0 * height;

  // Bounded global pointer spring. All pixels consume the prior completed
  // state; only invocation (0,0) advances [133..138] for the next frame.
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var pointer = u.zoom_config.yz; var pointerVelocity = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) {
    pointer = vec2<f32>(extraBuffer[133], extraBuffer[134]); pointerVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  }
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    var sPos = pointer; var sVel = pointerVelocity; let seeded = extraBuffer[138] > 0.5;
    if (!seeded) { sPos = u.zoom_config.yz; sVel = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
    let accel = (u.zoom_config.yz - sPos) * 150.0 - sVel * 22.0;
    sVel += accel * dt; sPos += sVel * dt;
    extraBuffer[133] = sPos.x; extraBuffer[134] = sPos.y; extraBuffer[135] = sVel.x; extraBuffer[136] = sVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let mouseDelta = (uv - pointer) * aspectVec; let mouseDist = length(mouseDelta);
  let mouseMask = exp(-mouseDist * mouseDist * 62.0);
  let radial = select(vec2<f32>(0.0), mouseDelta / mouseDist, mouseDist > 0.001);
  let heldScale = select(0.18, 1.0, u.zoom_config.w > 0.5);
  velocity += (pointerVelocity / aspectVec * 0.16 - radial / aspectVec * 0.055) * mouseMask * heldScale;

  var clickHeight = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 2.8) {
      let delta = (uv - ripple.xy) * aspectVec; let dist = length(delta);
      let ring = exp(-pow((dist - age * (0.18 + flowSpeed * 0.08)) * 42.0, 2.0)) * exp(-age * 1.15);
      let dir = select(vec2<f32>(0.0), delta / dist, dist > 0.001);
      velocity += dir / aspectVec * ring * (0.055 + turbulence * 0.08); clickHeight += ring;
    }
  }

  let p = (uv - 0.5) * aspectVec;
  let curl = vec2<f32>(sin(p.y * 12.0 + time * flowSpeed), -sin(p.x * 11.0 - time * flowSpeed * 0.83));
  velocity += lapV * mix(0.025, 0.13, viscosity) - heightGrad * pressureGain;
  velocity += curl * turbulence * (0.002 + mids * 0.0015);
  velocity *= mix(0.982, 0.935, viscosity);
  velocity = clamp(velocity, vec2<f32>(-1.1), vec2<f32>(1.1));
  height = clamp(height + (-divergence * 0.055 + lapH * 0.025 + clickHeight * 0.012) * flowSpeed, 0.015, 0.85);
  let activity = clamp(max(c.a * 0.996, 0.12 + length(velocity) * 0.7 + clickHeight * 0.2 + mouseMask * heldScale), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(velocity, height, activity));

  let normal = normalize(vec3<f32>((vec2<f32>(hL - hR, hD - hU) - velocity * 0.05) * (4.0 + turbulence * 5.0), 0.28));
  let refraction = (velocity * 0.014 + normal.xy * height * 0.04) / aspectVec;
  let sourceUV = clamp(uv - refraction, vec2<f32>(0.001), vec2<f32>(0.999));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let fresnel = schlick(max(normal.z, 0.0), 0.025);
  let caustic = pow(clamp(abs(lapH) * 18.0 + clickHeight * 0.4, 0.0, 1.0), 2.0);
  let absorption = exp(-height * vec3<f32>(0.32, 0.16, 0.08) * (1.0 + turbulence));
  let color = source.rgb * absorption + vec3<f32>(0.08, 0.42, 0.72) * (fresnel * (0.25 + mids * 0.18))
    + vec3<f32>(0.55, 0.9, 1.15) * caustic * (0.18 + treble * 0.22);
  let alpha = clamp(source.a + (1.0 - source.a) * activity * (0.2 + height * 0.65) + fresnel * 0.08, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.9, height * 0.32 + caustic * 0.025), 0.0, 0.0, 0.0));
}
