// ================================================================
//  Block Distort — Lighting & Glow Enhanced
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, volumetric-glow, rim-lighting
//  Complexity: Medium-High
//  Chunks From: block-distort-interactive
//  Created: 2026-05-30
//  Enhanced: 2026-06-28
//  Upgraded: 2026-11-10
//  Ideas: macroblock chroma-from-tile-centre, quantised, luma stays per pixel (§12.2B block quantization, 4:2:0 flavour); elastic recoil (pushed tiles relax with lag through exact C at the tile centre)
//  A packing: per-tile field A=(latched influence, gridLine, volGlow, 40+alpha); C read exactly at the tile-centre texel (r only); the 40+alpha band (40.3..41.05) is a validity marker no other shader uses, so a stale/foreign C is ignored
//  Output: NO ACES (it re-graded the whole photo). HEAD's additive lighting is kept as is and a soft shoulder (identity below 0.8, tanh knee up to 1.0) rolls off only the overshoot of the lit colour, so un-lit / pass-through pixels read exactly as at HEAD; premultiplied
// ================================================================

#include "_prelude.wgsl"
// zoom_params: x=BlockSize, y=PushStrength, z=RGBSplit, w=Radius

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

// ═══ Volumetric Light Accumulation ═══
fn volumetricGlow(uv: vec2<f32>, lightPos: vec2<f32>, intensity: f32, radius: f32, time: f32) -> f32 {
  let d = length(uv - lightPos);
  let core = exp(-d * d * (15.0 / radius));
  // Scattering halo with noise modulation
  let noise = hash21(uv * 8.0 + time * 0.5);
  let halo = exp(-d * 3.0) * (0.6 + noise * 0.4);
  return (core * 0.7 + halo * 0.3) * intensity;
}

// ═══ Rim Lighting on Grid Edges ═══
fn rimLight(viewDir: vec2<f32>, edgeNormal: vec2<f32>, strength: f32) -> f32 {
  let rim = 1.0 - max(dot(viewDir, edgeNormal), 0.0);
  return pow(rim, 3.0) * strength;
}

fn lumaOf(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Identity below the knee, tanh roll-off above it, never exceeds 1.0.
// (Replaces a display ACES, which lifted blacks and capped whites of the photo.)
fn softShoulder(x: vec3<f32>) -> vec3<f32> {
  let knee = 0.8;
  let over = max(x - vec3<f32>(knee), vec3<f32>(0.0));
  return min(x, vec3<f32>(knee)) + (1.0 - knee) * tanh(min(over / (1.0 - knee), vec3<f32>(8.0)));
}

// ═══ Bloom-weighted alpha ═══
fn bloomAlpha(rgb: vec3<f32>, baseAlpha: f32) -> f32 {
  let luma = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
  let bloomWeight = pow(max(0.0, luma - 0.5), 2.0) * 2.5;
  return clamp(baseAlpha + bloomWeight, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let blockScale = mix(8.0, 72.0, u.zoom_params.x);
  let pushStrength = u.zoom_params.y * 0.20;
  let rgbSplit = u.zoom_params.z * 0.03;
  let radius = mix(0.05, 0.75, u.zoom_params.w);

  let grid = floor(uv * blockScale);
  let cellCenter = (grid + 0.5) / blockScale;
  let delta = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(delta);
  let influenceNow = 1.0 - smoothstep(0.0, radius, dist);
  // ── Idea 2: elastic recoil (native pointer memory) ──────────────────
  // A.r already carried `influence` but nothing read it. Read it back
  // EXACTLY at this tile's centre texel (tile-constant by construction) and
  // let a pushed tile relax with lag instead of snapping back when the cursor
  // leaves. A.a = 40 + alpha (band 40.3..41.05; glitch-reveal uses 10..11.5,
  // cyber-lens 0.7371) is a validity marker so a stale / foreign C (shader
  // switch) is ignored. Below 0.004 the latch is exactly 0 so an rgba16float
  // A cannot stall on a denormal tail.
  let tilePx = clamp(vec2<i32>(cellCenter * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
  let prevTile = textureLoad(dataTextureC, tilePx, 0);
  let prevValid = prevTile.a > 40.3 && prevTile.a < 41.05;
  let prevLatch = select(0.0, clamp(prevTile.r, 0.0, 1.0), prevValid);
  let latchRaw = max(influenceNow, prevLatch * 0.95);
  let influence = select(0.0, latchRaw, latchRaw > 0.004);
  let direction = safeNormalize(delta + vec2<f32>(0.0005, 0.0));
  let shove = direction * pushStrength * influence * (1.0 + bass * 0.8);
  let wobble = vec2<f32>(sin(time * 2.0 + grid.y), cos(time * 1.7 + grid.x)) * 0.01 * treble;
  let sampleUV = clamp(uv + shove + wobble, vec2<f32>(0.0), vec2<f32>(1.0));

  let splitVec = safeNormalize(direction + vec2<f32>(0.0005, 0.0005)) * rgbSplit * influence;
  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + splitVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - splitVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  // ── Idea 1: macroblock chroma subsampling (§12.2B block quantization) ──
  // A codec block carries ONE chroma for the whole tile while luma stays per
  // pixel. Inside shoved tiles the chroma of the (unsplit) sample is replaced
  // by the tile-centre sample's chroma, quantised to a few levels (fewer the
  // harder the tile is shoved). The RGB-split fringe is kept as a residual.
  let tileSampleUV = clamp(cellCenter + shove + wobble, vec2<f32>(0.0), vec2<f32>(1.0));
  let tileColor = textureSampleLevel(readTexture, u_sampler, tileSampleUV, 0.0).rgb;
  let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let chromaLevels = mix(24.0, 4.0, influence);
  let tileChroma = tileColor - vec3<f32>(lumaOf(tileColor));
  let tileChromaQ = floor(tileChroma * chromaLevels + 0.5) / chromaLevels;
  let pixelChroma = baseColor - vec3<f32>(lumaOf(baseColor));
  let subW = smoothstep(0.04, 0.55, influence) * 0.9;
  finalColor = finalColor + (tileChromaQ - pixelChroma) * subW;

  // ── Base vs added light ─────────────────────────────────────────────────
  // `base` is the photo (resampled, split, chroma-subsampled). Everything below
  // ADDS light on top of it, exactly as at HEAD.
  let base = max(finalColor, vec3<f32>(0.0));
  var light = vec3<f32>(0.0);

  let gridLine = 1.0 - smoothstep(0.46, 0.50, max(abs(fract(uv * blockScale) - 0.5).x, abs(fract(uv * blockScale) - 0.5).y));
  let prismTint = mix(vec3<f32>(0.10, 0.9, 1.0), vec3<f32>(1.0, 0.30, 0.8), 0.5 + 0.5 * sin(time + grid.x * 0.3));
  light = light + prismTint * (gridLine * 0.10 + influence * 0.12 * mids);

  // ═══ VOLUMETRIC LIGHTING ═══
  // Light source at mouse position, pulsing with bass
  let lightIntensity = 1.0 + bass * 1.5 + sin(time * 4.0) * 0.3;
  let volGlow = volumetricGlow(uv, mouse, lightIntensity, radius * 1.5, time);
  // Warm key light color (5600K approx: warm white with slight gold)
  let keyLightColor = vec3<f32>(1.0, 0.92, 0.78);
  light = light + keyLightColor * volGlow * influence * 0.6;

  // Secondary fill glow from cell centers (cool blue 3200K)
  let fillGlow = volumetricGlow(uv, cellCenter, 0.5 + mids * 0.8, 0.15, time + 1.0);
  let fillColor = vec3<f32>(0.65, 0.75, 1.0);
  light = light + fillColor * fillGlow * gridLine * 0.4;

  // ═══ RIM LIGHTING ON GRID EDGES ═══
  let viewDir = safeNormalize(uv - mouse + vec2<f32>(0.0001));
  // Grid edge normal approximation: direction away from cell center
  let cellEdge = abs(fract(uv * blockScale) - 0.5);
  let edgeFactor = smoothstep(0.48, 0.50, max(cellEdge.x, cellEdge.y));
  let edgeNormal = safeNormalize(uv - cellCenter);
  let rim = rimLight(viewDir, edgeNormal, 1.0 + bass * 2.0);
  // Hot rim light color (7000K: bluish white)
  let rimColor = vec3<f32>(0.85, 0.90, 1.0);
  light = light + rimColor * rim * edgeFactor * influence * 0.8;

  // ═══ AUDIO-REACTIVE LIGHT PULSE ═══
  // Bass drives a pulsing glow ring around the mouse
  let pulseRing = smoothstep(0.02, 0.0, abs(dist - radius * 0.5 - bass * 0.2));
  let pulseColor = mix(vec3<f32>(1.0, 0.4, 0.1), vec3<f32>(0.2, 0.6, 1.0), mids);
  light = light + pulseColor * pulseRing * bass * 0.5;

  // Treble-driven sparkle on grid intersections
  let sparkle = hash21(grid + time * 0.1) * treble * gridLine * 0.3;
  light = light + vec3<f32>(1.0, 0.95, 0.8) * sparkle;

  // Light attenuation: falloff from mouse (HEAD's far-field dimming, kept)
  let falloff = 1.0 / (1.0 + 2.0 * dist + 4.0 * dist * dist);
  let atten = 0.7 + falloff * 0.3;

  // HEAD's lit colour (photo + additive light, far-field dimmed). Below the knee
  // it is written unchanged; only the overshoot rolls off (no re-grade).
  let headSum = (base + light) * atten;
  let displayColor = softShoulder(headSum);

  // ═══ ENHANCED ALPHA WITH BLOOM WEIGHT ═══
  let finalAlpha = bloomAlpha(headSum, clamp(0.70 + influence * 0.18 + gridLine * 0.08 + volGlow * 0.2, 0.42, 0.98));
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.22 + influence * 0.68 + volGlow * 0.15, 0.30), 0.0, 1.0);

  // Premultiplied alpha writeback. A is the per-tile field (latched influence,
  // gridLine, volGlow, 40+alpha) — never tone-mapped.
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(displayColor * finalAlpha, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(influence, gridLine, volGlow, 40.0 + finalAlpha));
}
