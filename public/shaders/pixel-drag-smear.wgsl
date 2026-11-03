// ═══════════════════════════════════════════════════════════════════
//  Pixel Drag Smear
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Chunks From: pixel-drag-smear.wgsl
//  Created: 2026-05-17
//  By: WGSL Upgrade Agent
//  Ideas: bristle streak sampling; treble-split pigment bleed; bristle splay; drying (§12.2C)
//  Upgraded: 2026-11-01
//  A packing: display RGBA (unchanged)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var pp = fract(p * vec2(0.1031, 0.1030));
  pp = pp + dot(pp, pp.yx + 33.33);
  return fract((pp.x + pp.y) * pp.x);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash12(i);
  let b = hash12(i + vec2(1.0, 0.0));
  let c = hash12(i + vec2(0.0, 1.0));
  let d = hash12(i + vec2(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

fn lumaMix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  let lumaA = dot(a, vec3(0.299, 0.587, 0.114));
  let lumaB = dot(b, vec3(0.299, 0.587, 0.114));
  let deltaL = lumaB - lumaA;
  let adjust = 1.0 + deltaL * t * 0.3;
  return mix(a, b, t) * adjust;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;

  let brushRadius = mix(0.01, 0.25, u.zoom_params.x);
  let decay = mix(0.8, 0.99, u.zoom_params.z);
  let audioBass = plasmaBuffer[0].x;
  let audioMids = plasmaBuffer[0].y;
  let audioTreble = plasmaBuffer[0].z;
  let baseStrength = mix(0.1, 2.0, u.zoom_params.y);
  let clickBoost = select(0.0, 1.5, u.zoom_config.w > 0.5);
  let strength = (baseStrength + audioBass * 0.8 + clickBoost) * 0.5;
  let mode = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let dist = distance(uv * vec2(aspect, 1.0), mouse * vec2(aspect, 1.0));

  let toMouse = uv - mouse;
  let dir = select(normalize(toMouse), vec2(0.0), length(toMouse) < 0.0001);
  let influence = (1.0 - smoothstep(0.0, brushRadius, dist)) * strength;

  let jitter = (valueNoise(uv * 12.0 + u.config.x) - 0.5) * 0.04;
  let curlAngle = valueNoise(uv * 8.0 + u.config.x * 0.5) * 6.28318;
  let curlDir = vec2(cos(curlAngle), sin(curlAngle));
  let curlDisp = curlDir * influence * 0.03;

  let offset = dir * influence * 0.05 + jitter + curlDisp;

  // Idea 1: bristle streak sampling — average three taps stepped along the drag
  // offset vector so the smear reads as dragged bristles, not one soft blur tap.
  // ── Idea 3: bristle splay ──────────────────────────────────────
  // The side taps leave the drag line by a fraction of Brush Radius.
  let bristleStep = offset * 0.5;
  let dragDir = select(vec2<f32>(0.0), normalize(offset), length(offset) > 0.0001);
  let splay = vec2<f32>(-dragDir.y, dragDir.x) * brushRadius * 0.35 * influence;
  let histUV0 = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let histUV1 = clamp(uv - offset + bristleStep + splay, vec2<f32>(0.0), vec2<f32>(1.0));
  let histUV2 = clamp(uv - offset - bristleStep - splay, vec2<f32>(0.0), vec2<f32>(1.0));
  let bristle0 = textureLoad(dataTextureC, vec2<i32>(clamp(histUV0 * resolution, vec2<f32>(0.0), resolution - 1.0)), 0);
  let bristle1 = textureLoad(dataTextureC, vec2<i32>(clamp(histUV1 * resolution, vec2<f32>(0.0), resolution - 1.0)), 0);
  let bristle2 = textureLoad(dataTextureC, vec2<i32>(clamp(histUV2 * resolution, vec2<f32>(0.0), resolution - 1.0)), 0);
  let bristled = (bristle0 + bristle1 + bristle2) / 3.0;

  // Idea 2: treble-split pigment bleed — nudge R/B taps apart along the drag
  // direction by an amount keyed to audioTreble, bleeding chroma at the bristle
  // edge on treble transients (extends the existing psychedelic-color identity).
  let bleedDir = dragDir;
  let bleedAmt = audioTreble * 0.01;
  let bleedR = textureLoad(dataTextureC, vec2<i32>(clamp((histUV0 + bleedDir * bleedAmt) * resolution, vec2<f32>(0.0), resolution - 1.0)), 0).r;
  let bleedB = textureLoad(dataTextureC, vec2<i32>(clamp((histUV0 - bleedDir * bleedAmt) * resolution, vec2<f32>(0.0), resolution - 1.0)), 0).b;
  let historyColor = vec4<f32>(bleedR, bristled.g, bleedB, bristled.a);
  let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  // ── Idea 4: drying (§12.2C) ────────────────────────────────────
  // Outside the brush, old paint falls back toward the live photo.
  // Decay Rate still holds the trail inside the stroke.
  let smearGate = select(0.0, 1.0, influence > 0.001);
  let dry = clamp((1.0 - decay) * 3.0, 0.0, 1.0) * (1.0 - smearGate);
  let driedRgb = mix(historyColor.rgb, videoColor.rgb, dry * 0.65);
  let driedHist = vec4<f32>(driedRgb, historyColor.a);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let smearWeight = smearGate * 0.9;
  let baseMix = mix(videoColor.rgb, driedHist.rgb, decay);
  let smearMix = mix(baseMix, driedHist.rgb, smearWeight);
  let blended = lumaMix(baseMix, smearMix, influence);

  let velocity = length(offset) * 20.0;
  let warmTint = vec3(1.08, 1.02, 0.92);
  let coolTint = vec3(0.92, 0.98, 1.06);
  let tint = mix(warmTint, coolTint, clamp(velocity, 0.0, 1.0));
  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = max(u.config.x - event.z, 0.0);
    clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 60.0);
  }
  let comb = sin((uv.x + mode * uv.y) * (35.0 + mode * 80.0) - u.config.x * (3.0 + audioMids * 6.0));
  let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + comb * 2.0 + audioTreble * 3.0);
  let tinted = blended * tint + spectral * (abs(comb) * influence * mode * 0.08 + clickFront * 0.22);

  let toneMapped = acesToneMap(tinted);

  let alphaBoost = influence * 0.6;
  let finalAlpha = mix(videoColor.a, clamp(videoColor.a + alphaBoost, 0.0, 1.0), smoothstep(0.0, 0.005, influence));

  let finalColor = vec4(toneMapped, finalAlpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
