// ═══════════════════════════════════════════════════════════════════
//  Neural Raymarcher Gabor
//  Category: advanced-hybrid
//  Features: advanced-hybrid, neural-raymarching, gabor-texture, volumetric, audio-reactive
//  Complexity: Very High
//  Chunks From: neural-raymarcher.wgsl, conv-gabor-texture-analyzer.wgsl
//  Created: 2026-04-18
//  By: Agent CB-3 — Convolution Post-Processor
//  Upgraded: 2026-10-19, 2026-11-22
//  Ideas: quadrature Gabor energy (V1 complex cell); cross-orientation
//         divisive normalization of the palette weights; Gabor phase colouring
//         (odd/even polarity shifts the palette); iso-orientation surround suppression
//         (texture pop-out: the same bank pooled over a 2.5x wider patch quiets uniform texture)
//  A packing: A unused (C never read)
//  Rescue (2026-11-22): the even (cosine) kernel was not zero-mean, so every orientation channel responded
//          to plain brightness (a flat source gave alpha = 1 and a brightness-dependent colour) — the
//          kernel mean is now subtracted on the same taps; the four-orientation bank shares one 9x9 pass
//          (HEAD refetched the same 81 taps and the isotropic Gaussian four times); audio now comes from
//          plasmaBuffer[0].xyz (HEAD used extraBuffer[0] = engine bass raw as a UV offset, extraBuffer[10]
//          = FFT bin 5 as a "click"); the edge glow was inverted (a +2*depth fill, dark rims at steps)
//          and measured against the marched depth — it is now a rim from the true local depth gradient.
// ═══════════════════════════════════════════════════════════════════
//  Raymarched neural network visualization with Gabor oriented texture
//  detection applied to surfaces. Gabor responses highlight connection
//  directions and layer boundaries with psychedelic color mapping.
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Gabor-modulated neural raymarched color
//    Alpha: Dominant orientation magnitude — strength of detected
//           directional structure at each pixel
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=NetworkDepth, y=ActivationVis, z=Glow, w=CameraRotation

// ═══ CHUNK: ping_pong (from neural-raymarcher.wgsl) ═══
fn ping_pong(a: f32) -> f32 {
  return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(ping_pong(v.x), ping_pong(v.y));
}

// ═══ CHUNK: hash21 (from neural-raymarcher.wgsl) ═══
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: noise (from neural-raymarcher.wgsl) ═══
fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (vec2<f32>(3.0) - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

// ═══ CHUNK: hsv2rgb (from neural-raymarcher.wgsl) ═══
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  var rgb = vec3<f32>(0.0);
  let c = v * s;
  let h6 = h * 6.0;
  let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
  if (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(v - c);
}

// ═══ CHUNK: reconstruct_normal (from neural-raymarcher.wgsl) ═══
fn reconstruct_normal(uv: vec2<f32>, depth: f32) -> vec3<f32> {
  let resolution = u.config.zw;
  let offset = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
  let dx = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0).x
         - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(offset.x, 0.0), 0.0).x;
  let dy = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, offset.y), 0.0).x
         - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, offset.y), 0.0).x;
  return normalize(vec3<f32>(-dx, -dy, 1.0));
}

// ═══ CHUNK: schlickFresnel (from neural-raymarcher.wgsl) ═══
fn schlickFresnel(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ CHUNK: gaborBank (from conv-gabor-texture-analyzer.wgsl gaborResponse) ═══
// Idea 1 (shipped): quadrature Gabor energy. The odd (sine) kernel is accumulated on the
// same taps as the even (cosine) one; sign(even)·sqrt(even² + odd²) is the
// phase-invariant complex-cell response, so an edge reads as one ridge instead
// of a ringing double line.
// Rescue R3/R4: the four orientations share ONE 9×9 pass — the tap offsets and the isotropic
// Gaussian do not depend on θ, so HEAD's four calls fetched the same 81 luma taps four times.
// The even kernel is also made zero-mean (ZERO_MEAN = 1; 0 restores HEAD): HEAD's cosine kernel summed to ~5.7
// at σ=2.5, so every channel answered to brightness alone (flat source => alpha 1). The kernel
// mean is subtracted on the same taps: even = Σ L·g·cosφ − (Σ g·cosφ / Σ g)·Σ L·g.
const ZERO_MEAN: f32 = 1.0;
const SURROUND_SCALE: f32 = 2.5; // tap spacing of the Idea 4 surround bank
struct GaborBank { even: vec4<f32>, odd: vec4<f32> };

fn gaborBank(uv: vec2<f32>, theta0: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> GaborBank {
  let radius = i32(ceil(sigma * 3.0));
  let maxRadius = min(radius, 4);
  // 0, 45, 90, 135 degrees (+ the mouse / camera rotation offset), one lane per orientation
  let theta = theta0 + vec4<f32>(0.0, 0.785398, 1.570796, 2.356194);
  let cosT = cos(theta);
  let sinT = sin(theta);
  let invTwoSigma2 = 1.0 / (2.0 * sigma * sigma + 0.001);
  var even = vec4<f32>(0.0);
  var odd = vec4<f32>(0.0);
  var sumLG = 0.0;
  var sumG = 0.0;
  var sumGC = vec4<f32>(0.0);
  for (var dy = -maxRadius; dy <= maxRadius; dy = dy + 1) {
    for (var dx = -maxRadius; dx <= maxRadius; dx = dx + 1) {
      let x = f32(dx);
      let y = f32(dy);
      let gaussian = exp(-(x * x + y * y) * invTwoSigma2);
      let carrierPhase = 2.0 * 3.14159265 * freq * (x * cosT + y * sinT);
      let kc = gaussian * cos(carrierPhase);
      let ks = gaussian * sin(carrierPhase);
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
      even = even + luma * kc;
      odd = odd + luma * ks;
      sumLG = sumLG + luma * gaussian;
      sumG = sumG + gaussian;
      sumGC = sumGC + kc;
    }
  }
  even = even - ZERO_MEAN * (sumGC / max(sumG, 1e-4)) * sumLG;
  return GaborBank(even, odd);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: palette (from conv-gabor-texture-analyzer.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;

  // Parameters
  let networkDepth = mix(0.5, 1.0, u.zoom_params.x);
  let activationVis = u.zoom_params.y;
  let glow = u.zoom_params.z;
  let cameraRotation = u.zoom_params.w * 6.28;
  // zoom_config.x is time, so HEAD's frequency grew without bound and the bank
  // aliased into noise within seconds. Held at the legacy default (0.3).
  let gaborFreq = 0.125; // mix(0.05, 0.3, 0.3)
  let gaborSigma = mix(1.5, 4.0, u.zoom_config.y);
  let gaborScale = mix(0.5, 3.0, u.zoom_config.z);

  let zoom_time = time * networkDepth;
  let zoom_center = mousePos;
  // Rescue R1: audio = plasmaBuffer[0].xyz. HEAD read extraBuffer[10] (FFT bin 5) as a "click" and
  // extraBuffer[0] (engine bass, 0..1) raw as a UV offset. Silence = HEAD's silent picture.
  let audio = plasmaBuffer[0].xyz;
  let clickIntensity = clamp(audio.y, 0.0, 1.0);

  // ── Neural raymarcher core ──
  var accumulatedColor = vec3<f32>(0.0);
  var accumulatedDepth = 0.0;
  var totalWeight = 0.0;

  for (var i: i32 = 0; i < 5; i = i + 1) {
    let layerDepth = f32(i) / f32(4);
    let layerSpeed = mix(0.2, 1.0, layerDepth);
    let layerZoom = 1.0 + fract(zoom_time * layerSpeed) * 4.0;
    let toCenter = uv - zoom_center;
    let angle = atan2(toCenter.y, toCenter.x);
    let dist = length(toCenter);
    let vortexStrength = clickIntensity * 0.3 / (dist + 0.1);
    let spinAngle = vortexStrength * layerDepth * (1.0 - layerDepth);
    let rotatedUV = vec2<f32>(
      cos(spinAngle) * toCenter.x - sin(spinAngle) * toCenter.y,
      sin(spinAngle) * toCenter.x + cos(spinAngle) * toCenter.y
    ) + zoom_center;

    let flowUV = rotatedUV + vec2<f32>(noise(rotatedUV * 6.0 + vec2<f32>(time * 0.15, 0.0)),
                                        noise(rotatedUV * 6.0 + vec2<f32>(0.0, time * 0.15))) * 0.015 * layerDepth;
    let transformed = (flowUV - zoom_center) / vec2<f32>(layerZoom) + zoom_center;
    let sampleUV = ping_pong_v2(transformed);
    let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    let density = exp(-layerDepth * 1.5);
    let weight = density * (1.0 + sampleDepth * 0.5);
    accumulatedColor = accumulatedColor + sampleColor * weight;
    accumulatedDepth = accumulatedDepth + sampleDepth * weight;
    totalWeight = totalWeight + weight;
  }

  let baseColor = accumulatedColor / vec3<f32>(max(totalWeight, 0.0001));
  let baseDepth = accumulatedDepth / max(totalWeight, 0.0001);

  // Chromatic aberration
  let chroma = 0.02 * clamp(audio.x, 0.0, 1.0);
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chroma * baseDepth, 0.0), 0.0).x;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).y;
  let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(chroma * baseDepth, 0.0), 0.0).z;
  let chromaticColor = vec3<f32>(r, g, b);

  // Edge glow
  // Rescue R2: local depth gradient = |n.xy| / n.z from the central differences reconstruct_normal
  // takes (HEAD compared a neighbour with the *marched average* depth, and exp(-grad*30) made the
  // glow a +2*depth fill on smooth depth with dark rims at steps). Now a rim.
  let normal = reconstruct_normal(uv, baseDepth);
  let depthGrad = length(normal.xy) / max(normal.z, 0.001);
  let rim = smoothstep(0.01, 0.1, depthGrad);
  let edgeGlow = rim * baseDepth * 2.0;
  let raymarchedColor = chromaticColor + vec3<f32>(edgeGlow, edgeGlow * 0.8, edgeGlow * 0.6);

  // Volumetric fog
  let fog = exp(-baseDepth * glow * 3.0);
  let fogColor = vec3<f32>(0.02, 0.05, 0.1);
  let foggedColor = mix(raymarchedColor, fogColor, 1.0 - fog);

  // ── Gabor texture post-processing ──
  let mouseAngle = atan2(mousePos.y - 0.5, mousePos.x - 0.5);
  let mouseDist = length(uv - mousePos);
  let mouseFactor = exp(-mouseDist * mouseDist * 4.0);
  let rotationOffset = mouseAngle * mouseFactor + cameraRotation * 0.1;

  let bank = gaborBank(uv, rotationOffset, gaborFreq, gaborSigma, pixelSize);
  let energy4 = sqrt(bank.even * bank.even + bank.odd * bank.odd);
  let rAll = select(-energy4, energy4, bank.even >= vec4<f32>(0.0)) * gaborScale;
  let r0 = rAll.x;
  let r45 = rAll.y;
  let r90 = rAll.z;
  let r135 = rAll.w;

  // ── Idea 3: Gabor phase colouring. sin(phase) = odd / energy is the polarity of the feature the
  // quadrature pair found: ~0 on a line (bright or dark ridge, whose sign the palette input already
  // carries), ±1 on a step edge (up vs down). It rotates each orientation's palette phase, gated by
  // the channel's own energy, so a step edge and a ridge of the same orientation no longer share a hue.
  let eAbs = abs(rAll);
  let sinPhi = bank.odd / (energy4 + 0.0001);
  let phShift = 0.12 * sinPhi * smoothstep(vec4<f32>(0.02), vec4<f32>(0.25), eAbs);

  let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67) + vec3<f32>(phShift.x));
  let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0) + vec3<f32>(phShift.y));
  let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33) + vec3<f32>(phShift.z));
  let pal135 = palette(r135 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33) + vec3<f32>(phShift.w));

  // Idea 2: cross-orientation divisive normalization. Each channel's weight is
  // its squared energy over the pooled mean (Heeger-style), so the winning
  // orientation owns its palette instead of four blending to grey, and the
  // overlay gain saturates with local contrast.
  let energies = vec4<f32>(abs(r0), abs(r45), abs(r90), abs(r135));
  let e2 = energies * energies;
  let pooled = dot(e2, vec4<f32>(0.25));
  let normW = e2 / (0.02 + pooled);
  let totalW = dot(normW, vec4<f32>(1.0)) + 0.001;
  var gaborColor = vec3<f32>(0.0);
  gaborColor = gaborColor + pal0 * normW.x;
  gaborColor = gaborColor + pal45 * normW.y;
  gaborColor = gaborColor + pal90 * normW.z;
  gaborColor = gaborColor + pal135 * normW.w;
  gaborColor = gaborColor / totalW;
  let contrastGain = mix(0.55, 1.0, clamp(totalW * 0.25, 0.0, 1.0));
  gaborColor = gaborColor * 1.3 * contrastGain;

  // ── Idea 4: iso-orientation surround suppression (texture pop-out). A V1 cell is suppressed when
  // the surround carries the SAME orientation, so a uniform texture quiets down and the places where
  // the orientation changes (the layer boundaries the header promises) stay loud. The surround is
  // the same bank on the same 81 taps spread 2.5x wider (carrier kept at the same cycles per pixel),
  // i.e. the fine-texture energy pooled over a ~3x larger patch. iso = cosine similarity of the centre
  // and surround 4-orientation energy vectors, gated by the surround's own energy.
  let surround = gaborBank(uv, rotationOffset, gaborFreq * SURROUND_SCALE, gaborSigma, pixelSize * SURROUND_SCALE);
  let eSurround = sqrt(surround.even * surround.even + surround.odd * surround.odd) * gaborScale;
  let iso = dot(eAbs, eSurround) / (length(eAbs) * length(eSurround) + 0.0001);
  let surroundGate = smoothstep(0.02, 0.2, length(eSurround));
  gaborColor = mix(gaborColor, foggedColor, 0.65 * iso * surroundGate);   // suppressed => the photo shows through

  // Blend Gabor onto raymarched result based on activationVis
  let neuralColor = mix(foggedColor, foggedColor * 0.5 + gaborColor * 0.5, activationVis);

  // Dominant orientation magnitude for alpha
  let dominantOrientation = max(max(abs(r0), abs(r45)), max(abs(r90), abs(r135))) / gaborScale;

  let displayColor = aces_tonemap(clamp(neuralColor, vec3<f32>(0.0), vec3<f32>(4.0)));

  textureStore(writeTexture, global_id.xy, vec4<f32>(displayColor, clamp(dominantOrientation, 0.0, 1.0)));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
