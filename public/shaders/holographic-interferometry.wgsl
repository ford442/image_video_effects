// ═══════════════════════════════════════════════════════════════════
//  Holographic Interferometry — Batch 58C
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal,
//            interference-patterns, holography, phase-coloring
//  Complexity: High
//  Upgraded: 2026-08-23
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn speckleNoise(uv: vec2<f32>, coherence: f32, t: f32) -> f32 {
  let scale = mix(50.0, 500.0, coherence);
  var s = 0.0;
  for (var i = 0; i < 4; i = i + 1) {
    let fi = f32(i);
    s += hash12(uv * scale + vec2<f32>(fi * 13.7, fi * 42.3) + t * 0.07);
  }
  return s / 4.0;
}

fn interferencePattern(uv: vec2<f32>, depth: f32, fringeDensity: f32, angle: f32, packetPhase: f32) -> f32 {
  let objectPhase = depth * fringeDensity * 10.0;
  let refPhase = (uv.x * cos(angle) + uv.y * sin(angle)) * fringeDensity * 50.0;
  let phaseDiff = objectPhase + refPhase + packetPhase;
  return 0.5 + 0.5 * cos(phaseDiff);
}

fn reconstructHologram(uv: vec2<f32>, intensity: f32, phase: f32, angle: f32) -> vec3<f32> {
  let reconPhase = (uv.x * cos(angle + 0.5) + uv.y * sin(angle + 0.5)) * 20.0;
  let totalPhase = phase + reconPhase;
  let hue = fract(totalPhase / TAU);
  let sat = 0.7 + intensity * 0.3;
  let val = 0.5 + intensity * 0.5;
  let c = val * sat;
  let h = hue * 6.0;
  let x = c * (1.0 - abs(fract(h * 0.5) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  let hi = u32(h);
  rgb = select(rgb, vec3<f32>(c, x, 0.0), hi == 0u);
  rgb = select(rgb, vec3<f32>(x, c, 0.0), hi == 1u);
  rgb = select(rgb, vec3<f32>(0.0, c, x), hi == 2u);
  rgb = select(rgb, vec3<f32>(0.0, x, c), hi == 3u);
  rgb = select(rgb, vec3<f32>(x, 0.0, c), hi == 4u);
  rgb = select(rgb, vec3<f32>(c, 0.0, x), hi == 5u);
  return rgb + vec3<f32>(val - c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let bandVoice = plasmaBuffer[(u32(hash12(uv + time * 0.01) * 8.0) % 8u) + 1u].x;

  let fringeDensity = mix(10.0, 100.0, u.zoom_params.x);
  let coherence = u.zoom_params.y;
  let reconAngleBase = u.zoom_params.z * PI;
  let saturation = mix(0.5, 1.5, u.zoom_params.w);

  let mouseTilt = (mouse - 0.5) * vec2<f32>(0.8, 0.5);
  let reconAngle = reconAngleBase + mouseTilt.x + mouseTilt.y * 0.6 + bass * 0.15;

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let luma = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let prev = textureLoad(dataTextureC, pixel, 0);

  let packetPhase = sin(time * (1.2 + mids * 0.8) + depth * fringeDensity * 0.05 + bandVoice * 4.0) * (0.4 + treble * 0.3);
  let interference = interferencePattern(uv, depth, fringeDensity, reconAngle, packetPhase);
  let phase = acos(clamp(interference * 2.0 - 1.0, -1.0, 1.0));

  var holoColor = reconstructHologram(uv, luma, phase, reconAngle);
  let speckle = speckleNoise(uv + time * 0.01 * (1.0 + bass * 0.5), coherence, time);
  let boil = mix(0.75, 1.25, speckle * coherence * (1.0 - held * 0.25));
  let hologram = holoColor * luma * boil * saturation;

  let fringes = sin(phase * fringeDensity + packetPhase * 2.0) * 0.5 + 0.5;
  let fringeColor = vec3<f32>(fringes * 0.5, fringes * 0.3, fringes * 0.7);

  var color = mix(sourceColor.rgb * 0.3, hologram + fringeColor * 0.2, 0.8);

  let parallax = depth * 0.02 * (1.0 + held * 0.5);
  let parallaxUV = clamp(uv + vec2<f32>(cos(reconAngle), sin(reconAngle)) * parallax, vec2<f32>(0.0), vec2<f32>(1.0));
  let parallaxColor = textureSampleLevel(readTexture, u_sampler, parallaxUV, 0.0).rgb;
  color = mix(color, parallaxColor * holoColor, depth * 0.3);

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = max(time - ripple.z, 0.0);
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    clickFront += exp(-age * 1.6) * exp(-abs(rDist - age * 0.45) * 55.0);
  }

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseFocus = (1.0 - smoothstep(0.0, 0.35, mouseDist)) * (0.25 + held * 0.45);
  color = mix(color, color * 1.15 + fringeColor * 0.1, mouseFocus);
  color += holoColor * clickFront * 0.35;

  color = mix(color, prev.rgb * 0.9, 0.08 * coherence);
  color = acesToneMap(color * (1.0 + mids * 0.15));

  let alpha = clamp(luma * 0.5 + interference * 0.35 + mouseFocus * 0.1 + clickFront * 0.12, 0.2, 0.98);
  let finalPixel = vec4<f32>(color, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalPixel);
}
