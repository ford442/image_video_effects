// ═══════════════════════════════════════════════════════════════════
//  Spectrogram Displace – Pass 2: Displacement & Compositing
//  Category: artistic
//  Features: multi-pass-2, image-displacement, color-grading, vignette, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-28, 2026-10-18
//  Ideas: spectral shear; raster bin ticks
//  A packing: does not write A. C is pass 1's field. Display ACES is writeTexture.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let dim = textureDimensions(readTexture);
  if (coord.x >= dim.x || coord.y >= dim.y) { return; }

  let uvRaw = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let uv = clamp(uvRaw, vec2<f32>(0.0), vec2<f32>(1.0));

  let fieldCoord = vec2<i32>(i32(coord.x), i32(coord.y));
  let fieldMax = vec2<i32>(i32(dim.x) - 1, i32(dim.y) - 1);
  let field = textureLoad(dataTextureC, clamp(fieldCoord, vec2<i32>(0), fieldMax), 0);
  let spectroColor = field.rgb;
  let magnitude = max(field.a, 0.001);

  let effectiveMag = mix(0.1, 2.0, clamp(u.zoom_params.z, 0.0, 1.0));

  let bass = plasmaBuffer[0].x;
  let audioBoost = 1.0 + bass * 0.8;

  let src = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  let freqFactor = clamp(1.0 - uv.y, 0.001, 1.0);
  let horizontal_disp = u.zoom_params.x;
  let vertical_disp = u.zoom_params.y;
  let blend_disp = u.zoom_params.w;
  let displacementX = magnitude * (src.r - src.b) * 50.0 * effectiveMag * audioBoost * mix(1.0, 3.0, horizontal_disp);
  var displacementY = magnitude * (src.g - 0.5) * 30.0 * effectiveMag * freqFactor * audioBoost * mix(1.0, 3.0, vertical_disp);
  let waveDisp = sin(uv.y * 20.0 + u.config.x * 3.0) * magnitude * 10.0 * audioBoost;

  // ── Idea 1: spectral shear ──
  // Loud neighboring bins pull the photo along the frequency axis.
  let upC = clamp(fieldCoord + vec2<i32>(0, -1), vec2<i32>(0), fieldMax);
  let dnC = clamp(fieldCoord + vec2<i32>(0, 1), vec2<i32>(0), fieldMax);
  let magGradY = textureLoad(dataTextureC, dnC, 0).a - textureLoad(dataTextureC, upC, 0).a;
  displacementY = displacementY + magGradY * vertical_disp * 22.0 * effectiveMag * audioBoost;

  var displacedX = i32(coord.x) + i32(displacementX + waveDisp);
  var displacedY = i32(coord.y) + i32(displacementY);
  displacedX = (displacedX + i32(dim.x)) % i32(dim.x);
  displacedY = (displacedY + i32(dim.y)) % i32(dim.y);

  let displacedColor = textureLoad(readTexture, vec2<i32>(displacedX, displacedY), 0);

  let blendFactor = magnitude * 0.3 * audioBoost * mix(1.0, 2.0, blend_disp);
  var finalColor = displacedColor.rgb;
  finalColor = finalColor + spectroColor * magnitude * 0.5 * effectiveMag * audioBoost * blendFactor;

  let lowFreqBoost = select(1.0 + magnitude * 0.2 * audioBoost, 1.0, uv.y > 0.7);
  let highFreqBoost = select(1.0 + magnitude * 0.1 * audioBoost, 1.0, uv.y < 0.3);
  finalColor = finalColor * vec3<f32>(lowFreqBoost, 1.0, highFreqBoost);

  // ── Idea 2: raster bin ticks ──
  let binFrac = fract(uv.y * 128.0);
  let tick = (1.0 - smoothstep(0.0, 0.045, binFrac)) * magnitude * mix(0.15, 1.0, blend_disp);
  finalColor = finalColor + spectroColor * tick * 0.45;

  let vignette = clamp(1.0 - magnitude * 0.3, 0.0, 1.0);
  finalColor = finalColor * vignette;
  finalColor = acesToneMap(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(4.0)));

  let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(displacedColor.a * (magnitude * 0.6 + luma * 0.3 + 0.1), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(finalColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
