// Liquid Mirror — sprung reflective height field with pointer push.
// Raw A ownership: R=height, G=velocity, B=surface energy, A=coverage.

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
fn schlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
  return f0 + (vec3<f32>(1.0) - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution; let time = u.config.x;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let distortion = u.zoom_params.x; let smoothness = u.zoom_params.y;
  let reflectivity = u.zoom_params.z; let pushSize = mix(0.06, 0.42, u.zoom_params.w);

  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = c.a > 0.00001;
  var height = select(0.16, c.r, initialized); var velocity = select(0.0, c.g, initialized);
  let hL = select(0.16, l.r, initialized); let hR = select(0.16, r.r, initialized);
  let hD = select(0.16, d.r, initialized); let hU = select(0.16, t.r, initialized);
  let laplacian = hL + hR + hD + hU - 4.0 * height;

  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var pointer = u.zoom_config.yz; var pointerVelocity = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) {
    pointer = vec2<f32>(extraBuffer[133], extraBuffer[134]); pointerVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  }
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    var p = pointer; var v = pointerVelocity; let seeded = extraBuffer[138] > 0.5;
    if (!seeded) { p = u.zoom_config.yz; v = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
    v += ((u.zoom_config.yz - p) * 190.0 - v * 25.0) * dt; p += v * dt;
    extraBuffer[133] = p.x; extraBuffer[134] = p.y; extraBuffer[135] = v.x; extraBuffer[136] = v.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let mouseDelta = (uv - pointer) * aspectVec; let mouseDist = length(mouseDelta);
  let pointerMask = smoothstep(pushSize, 0.0, mouseDist);
  let held = select(0.18, 1.0, u.zoom_config.w > 0.5);
  var impulse = pointerMask * held * (0.012 + distortion * 0.055 + length(pointerVelocity) * 0.018);
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 3.0) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let ring = exp(-pow((dist - age * (0.17 + bass * 0.04)) * 38.0, 2.0)) * exp(-age * 1.1);
      impulse += ring * sin(age * 7.0) * (0.02 + distortion * 0.07); clickEnergy += ring;
    }
  }
  let ambient = sin(uv.y * 18.0 + time * (0.42 + bass * 0.22)) * cos(uv.x * 15.0 - time * (0.34 + mids * 0.18));
  let tension = mix(0.16, 0.055, smoothness); let damping = mix(0.91, 0.985, smoothness);
  velocity = clamp(velocity * damping + laplacian * tension + (0.16 - height) * 0.018 + impulse + ambient * distortion * 0.0015, -0.8, 0.8);
  height = clamp(height + velocity * mix(0.095, 0.04, smoothness), 0.015, 1.0);
  let energy = clamp(max(c.b * 0.94, abs(velocity) * 1.4 + abs(laplacian) * 8.0 + clickEnergy * 0.45), 0.0, 1.0);
  let coverage = clamp(max(c.a * 0.997, smoothstep(0.015, 0.12, height)), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, energy, coverage));

  let gradient = vec2<f32>(hL - hR, hD - hU) * (5.0 + distortion * 16.0);
  let normal = normalize(vec3<f32>(gradient, 0.2 + smoothness * 0.3));
  let mirrorUV = clamp(vec2<f32>(1.0 - uv.x, uv.y) + normal.xy * (0.025 + height * 0.055) / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let reflected = textureSampleLevel(readTexture, u_sampler, mirrorUV, 0.0);
  let direct = textureSampleLevel(readTexture, u_sampler, clamp(uv - normal.xy * 0.016 / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let viewDir = normalize(vec3<f32>((uv - 0.5) * aspectVec * 0.35, 1.0));
  let f0 = mix(vec3<f32>(0.14), vec3<f32>(0.82, 0.87, 0.94), reflectivity);
  let fresnel = schlick(max(dot(normal, viewDir), 0.0), f0);
  let halfDir = normalize(viewDir + normalize(vec3<f32>(-0.52, 0.43, 0.74)));
  let specular = pow(max(dot(normal, halfDir), 0.0), mix(20.0, 190.0, smoothness));
  let steel = mix(vec3<f32>(0.12, 0.16, 0.22), vec3<f32>(0.72, 0.84, 1.0), reflected.rgb);
  let color = direct.rgb * (vec3<f32>(1.0) - fresnel) * (1.0 - reflectivity * 0.55)
    + mix(reflected.rgb, steel, reflectivity * 0.55) * fresnel * (0.9 + mids * 0.2)
    + vec3<f32>(1.05, 0.98, 0.88) * specular * (0.6 + bass * 0.5)
    + vec3<f32>(0.3, 0.64, 1.0) * energy * treble * 0.12;
  let alpha = clamp(max(direct.a, reflected.a) * (0.45 + coverage * 0.48) + fresnel.b * 0.16 + energy * 0.06, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.86, height * 0.38 + energy * 0.04), 0.0, 0.0, 0.0));
}
