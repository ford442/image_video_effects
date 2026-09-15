// ═══════════════════════════════════════════════════════════════════
//  Warp Drive Blackbody
//  Category: advanced-hybrid
//  Features: radial-blur, blackbody-radiation, HDR, physical-color, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Chunks From: warp_drive, spec-blackbody-thermal
//  Created: 2026-04-18
//  Upgraded: 2026-09-15
//  Ideas: Alcubierre warp-bubble wall; bow/wake Doppler on the aberration axis
//  A packing: raw HDR RGB + normalized avgTemp
// ═══════════════════════════════════════════════════════════════════
//  Warp drive radial blur combined with physically-correct blackbody
//  radiation coloring. Warp velocity maps to temperature — higher speed
//  = hotter colors. The radial blur streaks glow with thermal emission.
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

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
  let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
  var r: f32;
  var g: f32;
  var b: f32;
  if (t <= 6.5) {
    r = 1.0;
    g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
    b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
  } else {
    r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
    g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
    b = 1.0;
  }
  let radiance = pow(t / 6.5, 4.0);
  return vec3<f32>(r, g, b) * radiance;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 0.001);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let intensity = u.zoom_params.x * 0.2 * (1.0 + bass * 0.4);
  let aberration = u.zoom_params.y * 0.05 * (1.0 + treble * 0.3);
  let brightness = u.zoom_params.z * 2.0;
  let samples = i32(u.zoom_params.w * 30.0 + 5.0);

  let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.z);
  let tempRangeHigh = mix(4000.0, 15000.0, u.zoom_params.w);
  let thermalIntensity = mix(0.5, 3.0, u.zoom_params.x);

  let mouse = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;

  var dir = mouse - uv;
  let dist = length(dir);

  var colorSum = vec3<f32>(0.0);
  var tempSum = 0.0;
  var alphaSum = 0.0;
  var totalWeight = 0.0;

  let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let decay = 0.95;

  for (var i = 0; i < samples; i++) {
    let percent = (f32(i) + noise) / f32(samples);
    let weight = 1.0 - percent;
    let samplePos = uv + dir * percent * intensity;

    // Idea 2 — bow/wake Doppler fused to the existing R/B aberration axis:
    // bow (toward mouse) is blue-shifted; wake (away) is red-shifted.
    let bowPos = clamp(samplePos + dir * aberration * percent, vec2<f32>(0.0), vec2<f32>(1.0));
    let midPos = clamp(samplePos, vec2<f32>(0.0), vec2<f32>(1.0));
    let wakePos = clamp(samplePos - dir * aberration * percent, vec2<f32>(0.0), vec2<f32>(1.0));

    let sampleB = textureSampleLevel(readTexture, u_sampler, bowPos, 0.0);
    let sampleG = textureSampleLevel(readTexture, u_sampler, midPos, 0.0);
    let sampleR = textureSampleLevel(readTexture, u_sampler, wakePos, 0.0);

    let sampleLuma = dot(vec3<f32>(sampleR.r, sampleG.g, sampleB.b), vec3<f32>(0.299, 0.587, 0.114));
    let bowWake = percent * 2.0 - 1.0;
    let temperature = mix(tempRangeLow, tempRangeHigh, sampleLuma * (1.0 + percent * intensity * 5.0))
      * (1.0 + bowWake * u.zoom_params.y * 0.55);
    let thermalColor = blackbodyColor(temperature) * thermalIntensity;

    let doppler = 1.0 + intensity * percent * 0.5 + max(bowWake, 0.0) * 0.35;
    let photo = vec3<f32>(sampleR.r, sampleG.g, sampleB.b);
    let sampleColor = mix(photo, thermalColor, clamp(percent * intensity * 5.0, 0.0, 1.0))
      * doppler
      * vec3<f32>(1.0 + max(-bowWake, 0.0) * 0.25, 1.0, 1.0 + max(bowWake, 0.0) * 0.35);

    let sampleAlpha = (sampleR.a + sampleG.a + sampleB.a) / 3.0;
    let blurAlpha = sampleAlpha * weight * pow(decay, f32(i)) * (0.5 + (1.0 - percent) * 0.5);

    colorSum += sampleColor * weight * blurAlpha;
    tempSum += temperature * weight;
    alphaSum += blurAlpha;
    totalWeight += weight;
  }

  let invW = 1.0 / max(totalWeight, 0.001);
  var finalColor = colorSum * invW;
  var finalAlpha = alphaSum * invW;
  let avgTemp = tempSum * invW;

  // Center glow (engine heat) — floor look, kept
  let distAspect = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));
  let glow = exp(-distAspect * 5.0) * brightness;
  let glowTemp = mix(tempRangeHigh, tempRangeHigh * 2.0, glow);
  finalColor += blackbodyColor(glowTemp) * thermalIntensity * glow * 0.3;
  finalAlpha = min(finalAlpha + glow * 0.3, 1.0);

  // Idea 1 — Alcubierre warp-bubble wall (thin annulus, not a second center glow)
  let bubbleR = mix(0.14, 0.42, u.zoom_params.x);
  let wall = exp(-pow((distAspect - bubbleR) * 16.0, 2.0));
  let wallTemp = mix(tempRangeLow * 1.4, tempRangeHigh, wall);
  finalColor += blackbodyColor(wallTemp) * thermalIntensity * wall * 0.45 * (1.0 + mids * 0.4);
  finalAlpha = min(finalAlpha + wall * 0.25, 1.0);

  // Mouse hotspot — floor look, kept
  let mouseDist = length(uv - mouse);
  let mouseHeat = exp(-mouseDist * mouseDist * 400.0) * select(0.0, 1.0, isMouseDown);
  let mouseTemp = tempRangeHigh * (1.0 + mouseHeat * 0.5);
  finalColor = mix(finalColor, blackbodyColor(mouseTemp) * thermalIntensity, mouseHeat * 0.4);

  let displayColor = toneMapACES(finalColor);
  let alpha = clamp(finalAlpha, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(displayColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, avgTemp / 15000.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
