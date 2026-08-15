// ═══════════════════════════════════════════════════════════════════
//  Liquid Viscous Simple (Upgraded Batch 51)
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-15
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

fn fresnelSchlick(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  return clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn flowField(p: vec2<f32>, time: f32) -> vec2<f32> {
  let a = sin(p.y * 6.0 + time) + cos(p.x * 3.7 - time * 0.7);
  let b = cos(p.x * 5.0 - time * 0.8) - sin(p.y * 4.3 + time * 0.6);
  return vec2<f32>(a, b) * 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let texel = 1.0 / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let viscosity = mix(0.18, 0.94, u.zoom_params.x);
  let turbulence = u.zoom_params.y;
  let rippleStrength = mix(0.003, 0.045, u.zoom_params.z);
  let spectralShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let rawDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFlow = mix(1.0, 0.35, clamp(rawDepth, 0.0, 1.0));

  // Dual continuous motion: Primary vorticity flow field + Secondary convective circulation
  let ambientFlow = flowField(uv * mix(3.5, 9.5, turbulence), time * (0.18 + audio.y * 0.35));
  let convectiveShear = vec2<f32>(
    sin(uv.y * 12.0 - time * (0.9 + audio.x * 1.5)),
    cos(uv.x * 11.0 + time * (0.8 + audio.z * 1.2))
  ) * (0.0015 + turbulence * 0.003);

  var displacement = (ambientFlow * (0.003 + turbulence * 0.005) + convectiveShear) * depthFlow;
  var vortexEnergy = 0.0;

  // Interactive pointer drag / vortex circulation
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w;
  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let dragCore = exp(-mouseDist * mix(8.0, 3.5, viscosity));
  let dragTangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist;
  let dragForce = dragTangent * dragCore * (0.009 + turbulence * 0.018) * (1.0 + isMouseDown * 2.2);
  displacement += vec2<f32>(dragForce.x / aspect, dragForce.y);

  // 50-ripple shockwaves with spiral vortex tangential flow
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age > 0.0 && age < 4.2) {
      let rDelta = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let rDir = rDelta / rDist;
      let tangent = vec2<f32>(-rDir.y, rDir.x);
      let life = 1.0 - smoothstep(0.0, 4.2, age);
      let envelope = exp(-rDist * mix(5.5, 17.0, viscosity)) * life;
      let spiral = sin(rDist * 24.0 - age * (2.2 + audio.x * 5.5));
      let local = (tangent * (0.75 + viscosity) + rDir * spiral * 0.3) * envelope;

      displacement += vec2<f32>(local.x / aspect, local.y) * rippleStrength * (1.0 + audio.x * 0.65);
      vortexEnergy += envelope * abs(spiral);
    }
  }

  // 4-tap Laplace cohesion operator
  let right = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let left = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let up = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let down = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let cohesion = ((right + left + up + down) * 0.25 - center).rg;

  displacement = displacement * mix(1.25, 0.45, viscosity) + cohesion * (0.005 + viscosity * 0.01);

  // Chromatic dispersion & spectral sheen
  let chroma = (0.16 + spectralShift * 1.5 + audio.z * 0.4) * displacement;
  let uvR = clamp(uv + displacement + chroma, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + displacement - chroma, vec2<f32>(0.0), vec2<f32>(1.0));

  let sampleR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
  let sampleG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);

  // Exact-load temporal state feedback from dataTextureC
  let histCoord = clamp(vec2<i32>(floor(uvG * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  // 2.5D surface normal & Fresnel sheen
  let normal = normalize(vec3<f32>(-displacement.x * 32.0, -displacement.y * 32.0, 1.0));
  let fresnel = fresnelSchlick(max(normal.z, 0.0), 0.038);

  let sheen = clamp(vortexEnergy * 0.14 + length(displacement) * 20.0, 0.0, 1.0);
  let sheenColor = vec3<f32>(0.05, 0.12, 0.18) * sheen * (0.45 + audio.y * 0.8) + fresnel * vec3<f32>(0.12, 0.2, 0.28);
  var rgb = vec3<f32>(sampleR.r, sampleG.g, sampleB.b) + sheenColor;

  let feedbackMix = clamp((0.08 + viscosity * 0.22) * history.a, 0.04, 0.35);
  rgb = mix(rgb, history.rgb, feedbackMix);
  rgb = acesToneMapping(rgb);

  let sourceAlpha = max(sampleR.a, max(sampleG.a, sampleB.a));
  let alpha = clamp(sourceAlpha * (0.88 + viscosity * 0.12) + sheen * 0.2 + fresnel * 0.1, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvG, 0.0).r;
  let outDepth = clamp(displacedDepth + vortexEnergy * 0.03 - length(displacement) * 0.16, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
