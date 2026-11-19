// ═══════════════════════════════════════════════════════════════════
//  Pixelation Drift
//  Category: retro-glitch
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-21, 2026-11-19
//  Ideas: block area average; block colour quantisation; drift-lit tile bevel; quadtree detail split; block-ordered dither
//  A packing: ACES display RGBA (C is read as colour history)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// A mosaic block is the AVERAGE of its area. HEAD point-sampled the block's
// corner, so the tile flickered as the grid drifted across detail and the
// picture dissolved at large block sizes. Four interior taps, one bilinear
// fetch each, is enough to stabilise it without a full box reduction.
fn blockAverage(base: vec2<f32>, span: vec2<f32>) -> vec4<f32> {
  var acc = vec4<f32>(0.0);
  acc += textureSampleLevel(readTexture, u_sampler, clamp(base + span * vec2<f32>(0.25, 0.25), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  acc += textureSampleLevel(readTexture, u_sampler, clamp(base + span * vec2<f32>(0.75, 0.25), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  acc += textureSampleLevel(readTexture, u_sampler, clamp(base + span * vec2<f32>(0.25, 0.75), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  acc += textureSampleLevel(readTexture, u_sampler, clamp(base + span * vec2<f32>(0.75, 0.75), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  return acc * 0.25;
}

// Luma variance of the four interior taps of one block (green channel path).
fn blockLumaVar(base: vec2<f32>, span: vec2<f32>) -> f32 {
  let w = vec3<f32>(0.299, 0.587, 0.114);
  let a = dot(textureSampleLevel(readTexture, u_sampler, clamp(base + span * vec2<f32>(0.25, 0.25), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, w);
  let b = dot(textureSampleLevel(readTexture, u_sampler, clamp(base + span * vec2<f32>(0.75, 0.25), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, w);
  let c = dot(textureSampleLevel(readTexture, u_sampler, clamp(base + span * vec2<f32>(0.25, 0.75), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, w);
  let d = dot(textureSampleLevel(readTexture, u_sampler, clamp(base + span * vec2<f32>(0.75, 0.75), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, w);
  let m = (a + b + c + d) * 0.25;
  return ((a - m) * (a - m) + (b - m) * (b - m) + (c - m) * (c - m) + (d - m) * (d - m)) * 0.25;
}

// 4x4 Bayer threshold in [0,1).
fn bayer4(p: vec2<u32>) -> f32 {
  let m = array<f32, 16>(0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
  return (m[(p.y & 3u) * 4u + (p.x & 3u)] + 0.5) / 16.0;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Rescue: HEAD ran a spring in extraBuffer[133..138], which is re-uploaded (zeroed) every frame,
  // so it never persisted and pixel 0 raced the other invocations. Direct pointer instead.
  let smoothMouse = mouse;

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let basePixelSize = max(u.zoom_params.x, 0.01) * 100.0 * (1.0 + bass * 0.3);
  let driftSpeed = u.zoom_params.y * (1.0 + mids * 0.2);
  let colorBleed = u.zoom_params.z;
  let depthInfluence = u.zoom_params.w;

  let depthFactor = mix(1.0, 1.0 - depth * 0.7, depthInfluence);
  let mouseDeltaAspect = (uv - smoothMouse) * vec2<f32>(aspect, 1.0);
  let mouseDistance = length(mouseDeltaAspect);
  let focusLens = exp(-mouseDistance * mouseDistance * 18.0);

  var clickPixelPulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.6) {
      let clickDistance = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      clickPixelPulse += exp(-abs(clickDistance - age * 0.34) * 26.0) * exp(-age * 1.6);
    }
  }

  let heldFocus = select(1.0, 0.75, held);
  var pixelSize = max(basePixelSize * depthFactor * mix(1.0, 0.45 * heldFocus, focusLens) * (1.0 + clickPixelPulse * 0.8), 1.0);

  let regionCoord = vec2<u32>(floor(clamp(uv * 8.0, vec2<f32>(0.0), vec2<f32>(7.0))));
  let regionVoice = plasmaBuffer[(regionCoord.x + regionCoord.y) % 8u + 1u].x;

  let driftOffset = vec2<f32>(
    noise(uv * 5.0 + vec2<f32>(time * driftSpeed * 0.2, 0.0)),
    noise(uv * 5.0 + vec2<f32>(0.0, time * driftSpeed * 0.2))
  ) * 2.0 - 1.0;

  let safeMouseDir = mouseDeltaAspect / max(mouseDistance, 0.001);
  let mouseSwirl = vec2<f32>(-safeMouseDir.y / aspect, safeMouseDir.x) * focusLens * select(0.0, 0.012, held);

  let driftedUV = uv + driftOffset * 0.02 * driftSpeed * (1.0 + regionVoice * 0.3) + mouseSwirl;
  var pixelatedUV = clamp(floor(driftedUV * resolution / pixelSize) * pixelSize / resolution, vec2<f32>(0.0), vec2<f32>(1.0));

  // ── Idea 4: quadtree detail split ─────────────────────────────────
  // A tile whose interior luma variance is high (an edge or face runs through it)
  // subdivides into four half-size tiles; flat sky stays coarse. The half grid nests
  // inside the full one, so split tiles stay aligned with their neighbours. Treble
  // lowers the threshold so hi-hats shatter more tiles.
  let splitVar = blockLumaVar(pixelatedUV, vec2<f32>(pixelSize) / resolution);
  let splitThresh = 0.006 * (1.0 - treble * 0.5);
  if (pixelSize >= 4.0 && splitVar > splitThresh) {
    pixelSize = pixelSize * 0.5;
    pixelatedUV = clamp(floor(driftedUV * resolution / pixelSize) * pixelSize / resolution, vec2<f32>(0.0), vec2<f32>(1.0));
  }

  let chromaShift = pixelSize / resolution.x * treble * 0.5;
  let rUV = clamp(pixelatedUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = pixelatedUV;
  let bUV = clamp(pixelatedUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  // ── Idea 1: block area average ────────────────────────────────────
  let blockSpan = vec2<f32>(pixelSize) / resolution;
  let rAvg = blockAverage(rUV, blockSpan);
  let gAvg = blockAverage(gUV, blockSpan);
  let bAvg = blockAverage(bUV, blockSpan);
  var color = vec3<f32>(rAvg.r, gAvg.g, bAvg.b);
  var baseAlpha = gAvg.a;

  if (colorBleed > 0.01) {
    let bleedOffset = vec2<f32>(
      sin(time * 0.5 + uv.y * 10.0 + bass * 3.14),
      cos(time * 0.5 + uv.x * 10.0 + mids * 3.14)
    ) * pixelSize / resolution * colorBleed * 2.0;
    let bleedColor = textureSampleLevel(readTexture, u_sampler, clamp(pixelatedUV + bleedOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    color = mix(color, bleedColor.rgb, colorBleed * 0.3);
    baseAlpha = mix(baseAlpha, bleedColor.a, colorBleed * 0.3);
  }

  // ── Idea 2: block colour quantisation ─────────────────────────────
  // Position and colour quantise together — a bigger block also gets a
  // coarser palette, which is the low-bit mosaic the effect is reaching for
  // and which HEAD left as full-precision colour inside hard-edged tiles.
  let quantLevels = max(2.0, floor(mix(48.0, 3.0, clamp(pixelSize / 48.0, 0.0, 1.0))));
  // ── Idea 5: block-ordered dither ──────────────────────────────────
  // The coarse palette bands on gradients; a 4x4 Bayer threshold indexed by BLOCK
  // (not pixel) turns banding into a tile-scale checker dither, the 8-bit mosaic look.
  let blockIdx = vec2<u32>(vec2<i32>(floor(driftedUV * resolution / pixelSize)) + vec2<i32>(4096));
  let dith = bayer4(blockIdx) - 0.5;
  color = floor(color * quantLevels + 0.5 + dith * 0.9) / quantLevels;

  // ── Idea 3: drift-lit tile bevel ──────────────────────────────────
  // Light each tile's rim from the direction the grid is drifting, so the
  // mosaic reads as tiles being pushed rather than as a flat grid overlay
  // multiplied by a constant 1.2.
  let pixelCenter = (floor(driftedUV * resolution / pixelSize) + 0.5) * pixelSize / resolution;
  let inBlock = (driftedUV - pixelCenter) * resolution / pixelSize;
  let edgeGlow = smoothstep(pixelSize * 0.4, pixelSize * 0.5, length((driftedUV - pixelCenter) * resolution));
  let driftDir = normalize(driftOffset + vec2<f32>(1e-4, 1e-4));
  let bevel = dot(normalize(inBlock + vec2<f32>(1e-4, 1e-4)), driftDir);
  color = color * (1.0 + bevel * edgeGlow * (0.18 + driftSpeed * 0.30));

  let prev = textureLoad(dataTextureC, coord, 0);
  let persistence = clamp(0.12 + bass * 0.05 + regionVoice * 0.03, 0.0, 0.35);
  color = mix(color, prev.rgb, persistence);

  color = acesToneMap(color * (0.95 + bass * 0.04));

  let alpha = clamp(baseAlpha * (1.0 - edgeGlow * 0.2) + bass * 0.05 + clickPixelPulse * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
