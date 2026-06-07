// ═══════════════════════════════════════════════════════════════════
//  hyper-chromatic-delay - Spectral Multi-Tap Echo
//  Category: image
//  Features: upgraded-rgba, depth-aware, spectral-dispersion, multi-tap-temporal, lens-distortion, motion-trails, audio-reverb
//  Complexity: Very High
//  Upgraded by: Visualist Agent
//  Date: 2026-05-03
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
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,              // x=time, y=frame/mouseMode, z=resX, w=resY
  zoom_config: vec4<f32>,         // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,         // User params 1-4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  if (lambda < 440.0) { return vec3<f32>(-(lambda - 440.0) / 60.0, 0.0, 1.0); }
  else if (lambda < 490.0) { return vec3<f32>(0.0, (lambda - 440.0) / 50.0, 1.0); }
  else if (lambda < 510.0) { return vec3<f32>(0.0, 1.0, -(lambda - 510.0) / 20.0); }
  else if (lambda < 580.0) { return vec3<f32>((lambda - 510.0) / 70.0, 1.0, 0.0); }
  else if (lambda < 645.0) { return vec3<f32>(1.0, -(lambda - 645.0) / 65.0, 0.0); }
  else { return vec3<f32>(1.0, 0.0, 0.0); }
}

fn lensDistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
  let centered = uv - 0.5;
  let r2 = dot(centered, centered);
  let r4 = r2 * r2;
  let factor = 1.0 + strength * r2 + strength * 0.5 * r4;
  return centered * factor + 0.5;
}

fn sampleSpectral(uv: vec2<f32>, dispersion: f32, direction: vec2<f32>) -> vec3<f32> {
  var col = vec3<f32>(0.0);
  let baseLambda = 650.0;
  let stepSize = dispersion / 6.0;
  for (var i: i32 = 0; i < 7; i = i + 1) {
    let l = baseLambda - f32(i) * stepSize;
    let shift = direction * (l - 550.0) * 0.00002;
    let s = textureSampleLevel(readTexture, u_sampler, uv + shift, 0.0).rgb;
    col = col + s * wavelengthToRGB(l);
  }
  return col / 7.0;
}

fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let separation_strength = u.zoom_params.x * 0.1;
  let trail_decay = mix(0.5, 0.99, u.zoom_params.y);
  let hue_shift_speed = u.zoom_params.z;
  let mouse_influence = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
  let dist = distance(uv_corrected, mouse_corrected);
  let influence = smoothstep(0.5, 0.0, dist) * mouse_influence;

  let prevFrame = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;

  let motionDir = normalize(mouse_corrected - uv_corrected + vec2<f32>(0.001, 0.001));
  let motionMag = length(mouse_corrected - uv_corrected);

  var temporalAccum = vec3<f32>(0.0);
  let taps = 5;
  var totalWeight = 0.0;
  for(var t: i32 = 0; t < taps; t = t + 1) {
    let fi = f32(t);
    let tapUV = uv + motionDir * fi * 0.003 * motionMag * mouse_influence;
    let tapWeight = exp(-fi * 0.7);
    temporalAccum = temporalAccum + textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb * tapWeight;
    totalWeight = totalWeight + tapWeight;
  }
  temporalAccum = temporalAccum / max(totalWeight, 0.001);

  let lensStrengthR = mix(-0.3, 0.3, u.zoom_params.x) * 1.2;
  let lensStrengthG = mix(-0.3, 0.3, u.zoom_params.x);
  let lensStrengthB = mix(-0.3, 0.3, u.zoom_params.x) * 0.8;
  let lensUVR = lensDistort(uv, lensStrengthR + influence * 0.1);
  let lensUVG = lensDistort(uv, lensStrengthG);
  let lensUVB = lensDistort(uv, lensStrengthB - influence * 0.1);

  let dispersion = mix(0.0, 300.0, separation_strength + influence * 0.1);
  let angle = time * hue_shift_speed + dist * 10.0;
  let dir = vec2<f32>(cos(angle), sin(angle));

  let spectralR = sampleSpectral(lensUVR, dispersion, dir).r;
  let spectralG = sampleSpectral(lensUVG, dispersion, dir).g;
  let spectralB = sampleSpectral(lensUVB, dispersion, dir).b;
  var spectralColor = vec3<f32>(spectralR, spectralG, spectralB);

  let reverb = plasmaBuffer[0].x * 0.4 + plasmaBuffer[0].z * 0.2;
  let echoCount = 4;
  var echoColor = vec3<f32>(0.0);
  var echoWeight = 0.0;
  for(var e: i32 = 0; e < echoCount; e = e + 1) {
    let fi = f32(e) + 1.0;
    let echoUV = uv + dir * fi * 0.012 * (1.0 + reverb * 2.0);
    let echoSample = textureSampleLevel(readTexture, u_sampler, echoUV, 0.0).rgb;
    let w = 1.0 / (fi * fi);
    echoColor = echoColor + echoSample * w;
    echoWeight = echoWeight + w;
  }
  echoColor = echoColor / max(echoWeight, 0.001);

  var color = mix(spectralColor, temporalAccum, 0.25);
  color = mix(color, echoColor, 0.15 + reverb * 0.35);
  color = mix(color, prevFrame, trail_decay * 0.45);

  let luma = rgbToLuma(color);
  let contrast = 1.0 + u.zoom_params.x * 0.5;
  color = (color - vec3<f32>(0.5)) * contrast + vec3<f32>(0.5);
  color = color + vec3<f32>(0.02 * sin(luma * 10.0 + time));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  color = mix(color, color * (1.0 + depth * 0.4), 0.35);

  textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
