// ═══════════════════════════════════════════════════════════════════
//  Liquid Viscous Nebula (Upgraded Batch 51)
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(41.7, 289.1))) * 45758.5453);
}

fn noise21(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x),
    w.y
  );
}

fn fbm(p0: vec2<f32>) -> f32 {
  var p = p0;
  var value = 0.0;
  var amp = 0.5;
  for (var i = 0; i < 4; i = i + 1) {
    value += noise21(p) * amp;
    p = mat2x2<f32>(1.6, 1.2, -1.2, 1.6) * p;
    amp *= 0.5;
  }
  return value;
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  return clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let viscosity = mix(0.18, 0.94, u.zoom_params.x);
  let turbulence = u.zoom_params.y;
  let nebulaGlow = u.zoom_params.z;
  let spectralShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let rawDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(1.0, 0.35, clamp(rawDepth, 0.0, 1.0));

  // Dual continuous motion: Multi-octave FBM domain warp + helical conveyor
  let pAspect = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let warpA = fbm(pAspect * mix(3.0, 8.5, turbulence) + vec2<f32>(time * 0.09, -time * 0.07));
  let warpB = fbm(pAspect * 4.5 + vec2<f32>(warpA, -warpA) * 2.6 - time * 0.05);

  let helicalFlow = vec2<f32>(
    sin(pAspect.y * 7.0 + warpA * 3.0 + time * (0.8 + audio.x * 1.5)),
    cos(pAspect.x * 6.5 - warpB * 3.0 - time * (0.7 + audio.y * 1.2))
  ) * (0.0025 + turbulence * 0.005) * depthFactor;

  var totalDisp = vec2<f32>(warpA - 0.5, warpB - 0.5) * (0.005 + turbulence * 0.022) * depthFactor + helicalFlow;
  var vortexEnergy = 0.0;

  // Interactive pointer drag / viscous vortex shear
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w;
  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let dragCore = exp(-mouseDist * mix(8.5, 3.8, viscosity));
  let dragTangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist;
  let dragForce = dragTangent * dragCore * (0.009 + turbulence * 0.016) * (1.0 + isMouseDown * 2.2);
  totalDisp += vec2<f32>(dragForce.x / aspect, dragForce.y);

  // 50-ripple shockwaves with viscous vortex tangential advection
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age > 0.0 && age < 6.0) {
      let rDelta = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let rDir = rDelta / rDist;
      let tangent = vec2<f32>(-rDir.y, rDir.x);
      let life = exp(-age * mix(0.38, 0.14, viscosity));
      let falloff = exp(-rDist * mix(8.5, 3.2, viscosity));
      let pulse = sin(rDist * 22.0 - age * (2.2 + audio.x * 3.5));
      let flow = (tangent * (0.85 + viscosity) + rDir * pulse * 0.28) * life * falloff;

      totalDisp += vec2<f32>(flow.x / aspect, flow.y) * (0.007 + turbulence * 0.024) * (1.0 + audio.x * 0.55);
      vortexEnergy += life * falloff;
    }
  }

  let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

  // Exact-load temporal state feedback from dataTextureC
  let histCoord = clamp(vec2<i32>(floor((uv - totalDisp * 0.3) * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  // Nebula ionization & filament veins
  let density = smoothstep(0.22, 0.88, warpA * 0.55 + warpB * 0.55 + vortexEnergy * 0.1);
  let paletteA = vec3<f32>(0.06, 0.22, 0.55);
  let paletteB = vec3<f32>(0.8, 0.18, 0.75);
  let nebulaHue = mix(paletteA, paletteB, fract(warpB + spectralShift + time * 0.03 + audio.y * 0.25));
  let veins = pow(clamp(1.0 - abs(warpA - warpB) * 3.2, 0.0, 1.0), 4.5);

  var rgb = baseColor.rgb + nebulaHue * density * nebulaGlow * (0.4 + audio.x * 0.85) + veins * vec3<f32>(0.28, 0.6, 1.0) * (0.22 + audio.z * 1.1);

  let trailMix = clamp((0.14 + viscosity * 0.32) * history.a, 0.05, 0.52);
  rgb = mix(rgb, history.rgb, trailMix);
  rgb = acesToneMapping(rgb);

  let finalAlpha = clamp(baseColor.a * 0.78 + density * 0.24 + veins * 0.14 + history.a * trailMix * 0.12, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, finalAlpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, displacedUV, 0.0).r;
  let outDepth = clamp(displacedDepth + density * 0.05 - length(totalDisp) * 0.18, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
