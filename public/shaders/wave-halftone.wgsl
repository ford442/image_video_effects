// ═══════════════════════════════════════════════════════════════════
//  Wave Halftone
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-08, 2026-11-01
//  Ideas: elliptical dots along wave gradient; 15-degree hex rosette; midtone dot gain; wave-compressed screen
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn acesTone(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hexCell(uv: vec2<f32>, density: f32) -> vec2<f32> {
  let s = uv * density;
  let r = vec2<f32>(1.0, 1.7320508);
  let h = r * 0.5;
  let a = fract(s) - h;
  let b = fract(s - h) - h;
  return select(a, b, dot(a, a) < dot(b, b));
}

fn hexCenter(uv: vec2<f32>, density: f32) -> vec2<f32> {
  let s = uv * density;
  let r = vec2<f32>(1.0, 1.7320508);
  let h = r * 0.5;
  let a = fract(s) - h;
  let b = fract(s - h) - h;
  let gv = select(a, b, dot(a, a) < dot(b, b));
  let id = s - gv;
  return id / density;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let dotSizeScale = 0.4 + u.zoom_params.x * 0.8;
  let gridDensity = 12.0 + u.zoom_params.y * 80.0;
  let waveAmp = u.zoom_params.z * 0.15;
  let chromaticAmt = u.zoom_params.w * 0.02;
  // Wave Speed is zoom_params.w. Scale is 1 at the saved default 0.2,
  // so the default timing matches the previous hardcoded rates.
  let speedScale = mix(0.4, 2.6, u.zoom_params.w) / 0.84;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // 2D wave equation interference from multiple oscillators
  var interference = 0.0;
  interference = interference + sin(uv.x * 12.0 + time * 2.0 * speedScale) * cos(uv.y * 10.0 - time * 1.5 * speedScale);
  interference = interference + sin((uv.x + uv.y) * 8.0 + time * 1.2 * speedScale) * 0.5;
  interference = interference + cos(uv.x * 6.0 - time * 0.8 * speedScale) * sin(uv.y * 14.0 + time * 1.1 * speedScale) * 0.3;
  interference = interference * waveAmp * (1.0 + bass * 1.5);

  // Dynamic wave sources from mouse ripples
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let d = length(uv - r.xy);
    let t = time - r.z;
    interference = interference + sin(d * 30.0 - t * 8.0) * exp(-d * 5.0) * 0.06 * mouseDown;
  }

  // Mouse cursor acts as a continuous wave source
  let mouseDist = length(uv - mousePos);
  interference = interference + sin(mouseDist * 25.0 - time * 5.0 * speedScale) * exp(-mouseDist * 4.0) * 0.08 * mouseDown;

  // ── Idea 2: wave-compressed screen
  // Local density rises with |interference|. The density slider stays the base.
  let localDensity = gridDensity * (1.0 + clamp(abs(interference) * 1.6, 0.0, 0.45));
  let hexUV = hexCell(uv, localDensity);

  // Sample image at hex cell center for color quantization
  let cellCenter = hexCenter(uv, localDensity);
  let safeCenter = clamp(cellCenter, vec2<f32>(0.001), vec2<f32>(0.999));
  let color = textureSampleLevel(readTexture, u_sampler, safeCenter, 0.0);
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Depth controls dot perspective (smaller dots for distant objects)
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let perspective = mix(0.6, 1.0, depth);

  // Dot radius modulated by luma and wave interference crests
  let waveMod = 1.0 + interference * 0.5;
  // ── Idea 1: midtone dot gain
  // Radius stays linear in luma. Midtones spread; clear paper and dense ink do not.
  let dotGain = sqrt(max(luma * (1.0 - luma), 0.0)) * 2.0;
  let radius = luma * 0.45 * dotSizeScale * waveMod * perspective * (1.0 + 0.32 * dotGain);

  // Moire patterns at high-interference nodes
  let moire = smoothstep(0.7, 1.0, abs(interference)) * 0.25;

  // Chromatic aberration on wave crests
  let crestMask = smoothstep(0.5, 1.0, abs(interference));
  let rShift = chromaticAmt * crestMask * perspective;
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(safeCenter + vec2<f32>(rShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(safeCenter - vec2<f32>(rShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  // Paper texture grain
  let paper = hash21(uv * 400.0 + time * 0.1) * 0.06 + 0.94;

  let waveGrad = vec2<f32>(
    cos(uv.x * 12.0 + time * 2.0 * speedScale) * 12.0 * cos(uv.y * 10.0 - time * 1.5 * speedScale),
    sin(uv.x * 12.0 + time * 2.0 * speedScale) * (-10.0) * sin(uv.y * 10.0 - time * 1.5 * speedScale)
  );
  let gLen = max(length(waveGrad), 0.001);
  let gN = waveGrad / gLen;
  let gT = vec2<f32>(-gN.y, gN.x);
  let stretch = 1.0 + clamp(abs(interference) * 2.4, 0.0, 0.85);
  let ellip = vec2<f32>(dot(hexUV, gN) * stretch, dot(hexUV, gT) / stretch);
  let hexDist = length(ellip);

  let c15 = 0.9659258;
  let s15 = 0.2588190;
  let uvRosette = vec2<f32>(uv.x * c15 - uv.y * s15, uv.x * s15 + uv.y * c15);
  let hexUV2 = hexCell(uvRosette, localDensity);
  let ellip2 = vec2<f32>(dot(hexUV2, gN) * stretch, dot(hexUV2, gT) / stretch);

  // Anti-aliased dot mask
  let edgeWidth = 0.08 * perspective;
  let maskA = smoothstep(radius + edgeWidth, radius - edgeWidth, hexDist);
  let maskB = smoothstep(radius * 0.82 + edgeWidth, radius * 0.82 - edgeWidth, length(ellip2));
  let mask = max(maskA, maskB * 0.58);

  let dotColor = vec3<f32>(rSample, color.g, bSample) * mask * paper;
  let moireColor = vec3<f32>(0.85, 0.92, 1.0) * moire * mask * (0.5 + treble * 0.5);

  // ACES tone mapping on final composited color
  let finalColor = acesTone(dotColor + moireColor + color.rgb * 0.04);

  // Alpha: wave interference intensity × dot_density × depth
  let interferenceIntensity = smoothstep(0.0, 1.0, abs(interference) + 0.2);
  let dotDensity = mask * luma;
  let alpha = clamp(interferenceIntensity * dotDensity * depth + mask * 0.12, 0.1, 0.9);

  let display = vec4<f32>(finalColor, alpha);
  textureStore(writeTexture, vec2<i32>(global_id.xy), display);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), display);
}
