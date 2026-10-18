// ═══════════════════════════════════════════════════════════════════
//  RD on Video (Pass 3: Composite Over Video)
//  Category: simulation
//  Features: multi-pass-3, video-composite, luma-mask, upgraded-rgba
//  Upgraded: 2026-10-17
//  Ideas: dye take-up toward the video hue; gate meniscus on the luma threshold
//  A packing: display ACES RGBA on writeTexture. Does not write A.
//  Pass graph: C is previous-frame feedback. A wins the copy, so C is
//              pass 1's chemistry (U, V, luma memory, activity), not pass 2's B.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let coord = vec2<i32>(gid.xy);

  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let overlay = textureLoad(dataTextureC, coord, 0);
  let luma = dot(base.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

  let lumaGate = mix(0.15, 0.80, clamp(u.zoom_params.x, 0.0, 1.0));
  let maskSoftness = mix(0.05, 0.35, clamp(u.zoom_params.y, 0.0, 1.0));
  let glowGain = mix(0.4, 2.2, clamp(u.zoom_params.z, 0.0, 1.0));
  let blendGain = mix(0.2, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

  let lumaMask = smoothstep(lumaGate - maskSoftness, lumaGate + maskSoftness, luma);
  let simMask = clamp(overlay.a * glowGain, 0.0, 1.0);
  let blend = clamp(simMask * blendGain * lumaMask, 0.0, 1.0);
  // Idea 1: dye take-up. Dense pattern picks up the video's own color.
  let stain = mix(overlay.rgb, base.rgb * (0.45 + dot(overlay.rgb, vec3<f32>(0.25))), simMask * 0.62);

  var outColor = mix(base.rgb, base.rgb + stain * (0.7 + simMask), blend);
  // Idea 2: gate meniscus. A hairline where luma crosses the gate and the pattern is present.
  let gateDist = luma - lumaGate;
  let meniscus = exp(-gateDist * gateDist / max(maskSoftness * maskSoftness, 0.0016)) * simMask;
  outColor = outColor + vec3<f32>(0.85, 0.95, 1.0) * meniscus * 0.28 * blendGain;
  let mapped = aces(max(outColor, vec3<f32>(0.0)));
  let alpha = clamp(base.a * (0.55 + 0.45 * (1.0 - blend)) + blend * 0.4 + meniscus * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
