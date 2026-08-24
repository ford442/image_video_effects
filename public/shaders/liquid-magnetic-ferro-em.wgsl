// Liquid Magnetic Ferro EM — persistent magnetohydrodynamic height field.
// Raw A ownership: R=height, G=velocity, B=EM potential, A=surface charge.
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
fn dipoleField(p: vec2<f32>, origin: vec2<f32>, polarity: f32) -> vec2<f32> {
  let delta = p - origin; let r2 = max(dot(delta, delta), 0.0025);
  return polarity * vec2<f32>(delta.x, -delta.y) / (r2 * sqrt(r2));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let fieldStrength = u.zoom_params.x; let sharpness = u.zoom_params.y;
  let emCoupling = u.zoom_params.z; let dipoleControl = u.zoom_params.w;
  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = dot(abs(c), vec4<f32>(1.0)) > 0.00001;
  var height = select(0.1, c.r, initialized); var velocity = select(0.0, c.g, initialized);
  var potential = select(0.0, c.b, initialized); var charge = select(0.0, c.a, initialized);
  let hL = select(0.1, l.r, initialized); let hR = select(0.1, r.r, initialized);
  let hD = select(0.1, d.r, initialized); let hU = select(0.1, t.r, initialized);
  let lapH = hL + hR + hD + hU - 4.0 * height;
  let potentialLaplacian = l.b + r.b + d.b + t.b - 4.0 * potential;

  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var magnet = u.zoom_config.yz; var magnetVelocity = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) { magnet = vec2<f32>(extraBuffer[133], extraBuffer[134]); magnetVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]); }
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    var p = magnet; var v = magnetVelocity; let seeded = extraBuffer[138] > 0.5;
    if (!seeded) { p = u.zoom_config.yz; v = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
    v += ((u.zoom_config.yz - p) * 170.0 - v * 24.0) * dt; p += v * dt;
    extraBuffer[133] = p.x; extraBuffer[134] = p.y; extraBuffer[135] = v.x; extraBuffer[136] = v.y; extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let p = uv * aspectVec; let magnetP = magnet * aspectVec;
  var field = dipoleField(p, magnetP, select(-0.25, 0.9, u.zoom_config.w > 0.5));
  let dipoleCount = 2 + i32(floor(dipoleControl * 4.0));
  for (var i = 0; i < 6; i += 1) {
    if (i < dipoleCount) {
      let fi = f32(i); let angle = time * (0.11 + mids * 0.04) + fi * TAU / f32(dipoleCount);
      let origin = (vec2<f32>(0.5) + vec2<f32>(cos(angle), sin(angle)) * (0.2 + 0.06 * sin(time * 0.17 + fi))) * aspectVec;
      field += dipoleField(p, origin, select(-0.18, 0.18, (i % 2) == 0));
    }
  }
  field *= (0.0015 + fieldStrength * 0.006) * (1.0 + bass * 0.35);
  var emWave = sin(length(p - magnetP) * (24.0 + sharpness * 18.0) - time * (3.0 + mids * 2.0));
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 2.8) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let ring = exp(-pow((dist - age * 0.22) * 42.0, 2.0)) * exp(-age * 1.1);
      let polarity = select(-1.0, 1.0, (i % 2u) == 0u);
      potential += ring * polarity * (0.08 + emCoupling * 0.16); charge += ring * polarity * 0.06; clickEnergy += ring;
    }
  }
  potential = clamp(potential * 0.972 + potentialLaplacian * 0.08 + emWave * emCoupling * 0.012, -1.5, 1.5);
  charge = clamp(charge * 0.96 + (r.b - l.b + t.b - d.b) * 0.04 + dot(field, vec2<f32>(0.7, 0.3)) * emCoupling, -1.0, 1.0);
  let fieldEnergy = min(length(field), 1.5);
  let latticeP = p * (11.0 + sharpness * 12.0) + field * 2.0;
  let hexMode = (cos(latticeP.x) + 2.0 * cos(latticeP.x * 0.5) * cos(latticeP.y * 0.8660254)) / 3.0;
  let spikeTarget = pow(clamp(hexMode * 0.5 + 0.5, 0.0, 1.0), mix(3.0, 9.0, sharpness));
  let equilibrium = 0.08 + spikeTarget * (0.03 + fieldStrength * 0.16) + abs(potential) * emCoupling * 0.025;
  velocity = clamp(velocity * mix(0.94, 0.982, sharpness) + lapH * mix(0.13, 0.06, sharpness)
    + (equilibrium - height) * 0.04 + charge * fieldEnergy * 0.025 + clickEnergy * 0.015, -0.9, 0.9);
  height = clamp(height + velocity * mix(0.08, 0.04, sharpness), 0.005, 1.2);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, potential, charge));

  let gradient = vec2<f32>(hL - hR, hD - hU) * (6.0 + sharpness * 17.0) + field * 0.2;
  let normal = normalize(vec3<f32>(gradient, 0.2)); let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let sourceUV = clamp(uv + normal.xy * (0.012 + height * 0.045) / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let fresnel = 0.35 + 0.65 * pow(clamp(1.0 - normal.z, 0.0, 1.0), 5.0);
  let fieldDir = atan2(field.y, field.x) / TAU;
  let emTint = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.0, 0.33, 0.67) + fieldDir + potential * 0.08));
  let light = normalize(vec3<f32>(-0.4, 0.5, 0.78));
  let specular = pow(max(dot(normal, normalize(viewDir + light)), 0.0), mix(26.0, 150.0, sharpness));
  let color = source.rgb * (0.2 + (1.0 - fresnel) * 0.35) + emTint * fresnel * (0.45 + emCoupling * 0.45 + mids * 0.1)
    + vec3<f32>(1.05, 0.96, 0.82) * specular * (0.75 + bass * 0.35) + vec3<f32>(0.3, 0.62, 1.1) * abs(charge) * treble * 0.16;
  let alpha = clamp(source.a * 0.35 + smoothstep(0.005, 0.16, height) * 0.56 + fresnel * 0.1 + clickEnergy * 0.05, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.76, height * 0.58 + fieldEnergy * 0.03), 0.0, 0.0, 0.0));
}
