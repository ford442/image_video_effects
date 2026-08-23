// Ambient Liquid Coupled — two persistent height layers joined by a membrane.
// Raw A ownership: R=top height, G=top velocity, B=lower height, A=lower velocity.
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
  let waveStrength = u.zoom_params.x; let viscosity = u.zoom_params.y;
  let vortexStrength = u.zoom_params.z; let layerSeparation = u.zoom_params.w;
  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = dot(abs(c), vec4<f32>(1.0)) > 0.00001;
  var topHeight = select(0.1, c.r, initialized); var topVelocity = select(0.0, c.g, initialized);
  var lowerHeight = select(0.08, c.b, initialized); var lowerVelocity = select(0.0, c.a, initialized);
  let topL = select(0.1, l.r, initialized); let topR = select(0.1, r.r, initialized);
  let topD = select(0.1, d.r, initialized); let topU = select(0.1, t.r, initialized);
  let lowL = select(0.08, l.b, initialized); let lowR = select(0.08, r.b, initialized);
  let lowD = select(0.08, d.b, initialized); let lowU = select(0.08, t.b, initialized);
  let lapTop = topL + topR + topD + topU - 4.0 * topHeight;
  let lapLower = lowL + lowR + lowD + lowU - 4.0 * lowerHeight;

  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var pointer = u.zoom_config.yz; var pointerVelocity = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) { pointer = vec2<f32>(extraBuffer[133], extraBuffer[134]); pointerVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]); }
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    var p = pointer; var v = pointerVelocity; let seeded = extraBuffer[138] > 0.5;
    if (!seeded) { p = u.zoom_config.yz; v = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
    v += ((u.zoom_config.yz - p) * 130.0 - v * mix(18.0, 30.0, viscosity)) * dt; p += v * dt;
    extraBuffer[133] = p.x; extraBuffer[134] = p.y; extraBuffer[135] = v.x; extraBuffer[136] = v.y; extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let mouseDelta = (uv - pointer) * aspectVec; let mouseDist = length(mouseDelta);
  let mouseMask = exp(-mouseDist * mouseDist * 58.0); let held = select(0.12, 1.0, u.zoom_config.w > 0.5);
  let tangent = select(vec2<f32>(0.0), vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist, mouseDist > 0.001);
  let pointerTwist = dot(pointerVelocity, tangent / aspectVec) * mouseMask * vortexStrength;
  var topImpulse = mouseMask * held * (0.012 + waveStrength * 0.05) + pointerTwist * 0.012;
  var lowerImpulse = -mouseMask * held * layerSeparation * 0.025 - pointerTwist * 0.007;
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 3.2) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let ring = exp(-pow((dist - age * (0.14 + bass * 0.06)) * 40.0, 2.0)) * exp(-age * 1.0);
      topImpulse += ring * sin(age * 6.5) * (0.02 + waveStrength * 0.055);
      lowerImpulse -= ring * cos(age * 5.2) * (0.012 + layerSeparation * 0.035); clickEnergy += ring;
    }
  }
  let p = (uv - 0.5) * aspectVec;
  let ambientTop = sin(p.x * 11.0 + time * (0.42 + bass * 0.16)) * cos(p.y * 9.0 - time * 0.31);
  let ambientLower = cos(p.x * 7.0 - time * (0.24 + mids * 0.12)) * sin(p.y * 13.0 + time * 0.27);
  let coupling = (lowerHeight - topHeight + 0.02) * (0.035 + layerSeparation * 0.12);
  let damping = mix(0.91, 0.986, viscosity);
  topVelocity = clamp(topVelocity * damping + lapTop * mix(0.13, 0.055, viscosity) + coupling
    + ambientTop * waveStrength * 0.0018 + topImpulse, -0.8, 0.8);
  lowerVelocity = clamp(lowerVelocity * damping + lapLower * mix(0.1, 0.045, viscosity) - coupling
    + ambientLower * waveStrength * 0.0015 + lowerImpulse, -0.7, 0.7);
  topHeight = clamp(topHeight + topVelocity * mix(0.085, 0.038, viscosity), 0.005, 0.9);
  lowerHeight = clamp(lowerHeight + lowerVelocity * mix(0.072, 0.032, viscosity), 0.005, 0.8);
  textureStore(dataTextureA, pixel, vec4<f32>(topHeight, topVelocity, lowerHeight, lowerVelocity));

  let topGradient = vec2<f32>(topL - topR, topD - topU) * (5.0 + waveStrength * 10.0);
  let lowGradient = vec2<f32>(lowL - lowR, lowD - lowU) * (4.0 + layerSeparation * 8.0);
  let topNormal = normalize(vec3<f32>(topGradient, 0.28)); let lowerNormal = normalize(vec3<f32>(lowGradient, 0.34));
  let topUV = clamp(uv + topNormal.xy * (0.012 + topHeight * 0.045) / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let lowerUV = clamp(uv - lowerNormal.xy * (0.01 + lowerHeight * 0.055) / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let topLayer = textureSampleLevel(readTexture, u_sampler, topUV, 0.0);
  let lowerLayer = textureSampleLevel(readTexture, u_sampler, lowerUV, 0.0);
  let separation = clamp(abs(topHeight - lowerHeight) * (2.0 + layerSeparation * 4.0) + clickEnergy * 0.18, 0.0, 1.0);
  let membrane = smoothstep(0.02, 0.35, abs(topHeight - lowerHeight));
  let spectral = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.0, 0.32, 0.67) + topHeight * 0.5 - lowerHeight * 0.35 + time * 0.012));
  let fresnel = 0.025 + 0.975 * pow(clamp(1.0 - topNormal.z, 0.0, 1.0), 5.0);
  let color = mix(topLayer.rgb, lowerLayer.rgb * vec3<f32>(0.78, 0.9, 1.08), separation * layerSeparation)
    + spectral * membrane * (0.08 + mids * 0.1) + vec3<f32>(0.42, 0.72, 1.0) * fresnel * (0.13 + treble * 0.1);
  let alpha = clamp(max(topLayer.a, lowerLayer.a * separation) + membrane * 0.09 + fresnel * 0.06, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.88, topHeight * 0.3 + lowerHeight * 0.18 + membrane * 0.03), 0.0, 0.0, 0.0));
}
