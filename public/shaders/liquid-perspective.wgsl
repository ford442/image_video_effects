// ═══════════════════════════════════════════════════════════════════
//  Liquid Perspective (Upgraded Batch 51)
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

fn minDepth3x3(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
  var result = 1.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let sampleUV = clamp(uv + vec2<f32>(f32(x), f32(y)) * texel, vec2<f32>(0.0), vec2<f32>(1.0));
      result = min(result, textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r);
    }
  }
  return result;
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

  let speed = mix(0.2, 1.5, u.zoom_params.x);
  let density = mix(2.0, 9.0, u.zoom_params.y);
  let intensity = mix(0.003, 0.055, u.zoom_params.z);
  let colorShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let rawDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let nearestDepth = minDepth3x3(uv, texel);
  let foreground = 1.0 - smoothstep(0.40, 0.65, nearestDepth);
  let edgeSilhouette = smoothstep(0.005, 0.09, abs(rawDepth - nearestDepth));

  // Perspective-compressed Gerstner sheet. Crests tighten toward the horizon,
  // while the derivative terms form a parallax Jacobian instead of a flat warp.
  let pAspect = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let perspectiveTilt = 1.0 + (1.0 - uv.y) * 2.1;
  var gerstner = vec2<f32>(0.0);
  var jacobian = vec2<f32>(0.0);
  let waveDirs = array<vec2<f32>, 3>(normalize(vec2<f32>(1.0,0.32)), normalize(vec2<f32>(-0.44,1.0)), normalize(vec2<f32>(0.72,-0.69)));
  for (var waveIndex = 0; waveIndex < 3; waveIndex = waveIndex + 1) {
    let wf = f32(waveIndex);
    let direction = waveDirs[waveIndex];
    let frequency = (density + wf * 2.7) * perspectiveTilt;
    let phase = dot(pAspect, direction) * frequency - time * speed * (1.0 + wf * 0.31) + audio.x * 1.5;
    let amplitude = intensity / (1.0 + wf * 0.7);
    gerstner += direction * cos(phase) * amplitude;
    jacobian += abs(direction) * abs(sin(phase)) * frequency * amplitude;
  }
  let secondaryShear = vec2<f32>(sin(pAspect.y * density * 1.7 - time * speed * 0.73), cos(pAspect.x * density * 1.3 + time * speed * 0.61)) * intensity * (0.2 + audio.y * 0.35);
  let parallaxFlow = (gerstner + secondaryShear) * mix(1.2, 0.25, rawDepth) / (vec2<f32>(1.0) + jacobian * 0.35);

  var totalDisp = parallaxFlow;
  var waveElevation = 0.0;

  // Interactive pointer gravity well & drag displacement
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w;
  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let mousePull = exp(-mouseDist * 5.2) * (1.0 + isMouseDown * 2.5);
  let dragVector = (mouseDelta / mouseDist) * mousePull * intensity * 1.5 * (1.0 + audio.x * 0.5);
  totalDisp += vec2<f32>(dragVector.x / aspect, dragVector.y);

  // 50-ripple shockwaves with perspective depth attenuation
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age < 0.0 || age > 3.2) { continue; }
    {
      let rDelta = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let rDir = rDelta / rDist;
      let life = 1.0 - smoothstep(0.0, 3.2, age);
      let kWave = sin(rDist * (22.0 + density * 2.5) - age * (3.5 + speed * 3.5));
      let envelope = exp(-rDist * 7.5) * life;
      let rDisp = rDir * kWave * envelope * intensity * (1.0 + audio.x * 0.6);

      totalDisp += vec2<f32>(rDisp.x / aspect, rDisp.y);
      waveElevation += pow(max(kWave, 0.0), 3.0) * envelope * 8.0;
    }
  }

  // 2.5D surface normal & Snell refraction angle
  let normal = normalize(vec3<f32>(-totalDisp.x * 35.0, -totalDisp.y * 35.0, 1.0));
  let fresnel = fresnelSchlick(max(normal.z, 0.0), 0.04);

  // Snell refraction chromatic divergence
  let dispMag = length(totalDisp);
  let chromaticSplit = totalDisp * (0.35 + colorShift * 2.8 + audio.y * 0.6);

  let warpedUV = clamp(uv + totalDisp * foreground + totalDisp * (1.0 - foreground) * 0.45, vec2<f32>(0.0), vec2<f32>(1.0));
  let redUV = clamp(warpedUV + chromaticSplit, vec2<f32>(0.0), vec2<f32>(1.0));
  let blueUV = clamp(warpedUV - chromaticSplit, vec2<f32>(0.0), vec2<f32>(1.0));

  let redSample = textureSampleLevel(readTexture, u_sampler, redUV, 0.0);
  let greenSample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
  let blueSample = textureSampleLevel(readTexture, u_sampler, blueUV, 0.0);

  // Exact-load temporal state feedback from dataTextureC
  let histCoord = clamp(vec2<i32>(floor(warpedUV * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  // Bioluminescent depth edge scattering
  let biolumeHue = mix(vec3<f32>(0.0, 0.85, 0.7), vec3<f32>(0.65, 0.15, 1.0), colorShift);
  let biolume = biolumeHue * edgeSilhouette * (0.35 + audio.z * 0.85);

  let refractedRGB = vec3<f32>(redSample.r, greenSample.g, blueSample.b) + biolume + fresnel * vec3<f32>(0.12, 0.18, 0.25);
  let blendFactor = clamp(0.28 + foreground * 0.72 + dispMag * 5.0, 0.0, 1.0);
  var finalRGB = mix(baseColor.rgb, refractedRGB, blendFactor);

  let feedbackMix = clamp(0.12 * history.a, 0.03, 0.28);
  finalRGB = mix(finalRGB, history.rgb, feedbackMix);
  finalRGB = acesToneMapping(finalRGB);

  let sourceAlpha = max(baseColor.a, max(redSample.a, blueSample.a));
  let sheetSlope = clamp(length(jacobian), 0.0, 1.0);
  let finalAlpha = clamp(sourceAlpha * 0.82 + edgeSilhouette * 0.2 + dispMag * 3.5 + sheetSlope * 0.12, 0.0, 1.0);
  let outputColor = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let outDepth = clamp(rawDepth + waveElevation * 0.03 - dispMag * 0.15, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
