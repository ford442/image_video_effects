// ═══════════════════════════════════════════════════════════════════
//  Luma Force v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Strategy: Luma-gradient particle advection + curl noise + spectral CA
//  Upgraded: 2026-10-05
//  Ideas: advection memory (C = accumulated displacement, relaxes back); edge-weighted creep; isoline drift near the cursor
//  A packing: raw fields, no tone map — (memDisp.xy in uv, |instant force| uv, luma contrast)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: aces_tone_map ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Smooth value noise with analytic gradient: returns (n, dn/dx, dn/dy).
// HEAD finite-differenced white noise (hash12), which gave a ~0.5 uv scramble.
fn value_noise_d(p: vec2<f32>) -> vec3<f32> {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let dw = 6.0 * f * (1.0 - f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  let n = a + (b - a) * w.x + (c - a) * w.y + (a - b - c + d) * w.x * w.y;
  let g = dw * vec2<f32>((b - a) + (a - b - c + d) * w.y, (c - a) + (a - b - c + d) * w.x);
  return vec3<f32>(n, g);
}

// 2D curl noise: divergence-free velocity field, (dn/dy, -dn/dx) of smooth noise
fn curl_noise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let s = p * 3.0 + t * 0.3;
  let n1 = value_noise_d(s);
  let n2 = value_noise_d(s * 2.03 + vec2<f32>(17.3, 5.1));
  let g = n1.yz + n2.yz * 0.5;
  return vec2<f32>(g.y, -g.x);
}

// Sample luma at UV
// Last frame's displacement memory; anything outside the stored clamp
// (NaN, or another shader's display colour) reads as zero.
fn load_mem(c: vec2<i32>) -> vec2<f32> {
  let prev = textureLoad(dataTextureC, c, 0).xy;
  return select(vec2<f32>(0.0), prev, all(abs(prev) <= vec2<f32>(0.0501)));
}

fn sample_luma(uv: vec2<f32>) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  return dot(c.rgb, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let forceMag = u.zoom_params.x * (1.0 + bass * 0.5);
  let radius = u.zoom_params.y;
  let curlWeight = u.zoom_params.z;
  let lumaWeight = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthParallax = mix(0.5, 1.5, depth);

  // Compute luma gradient from neighbors (5 taps, 6 px apart so the creep
  // follows real contours and the edge band is as wide as the creep itself)
  let px = vec2<f32>(6.0 / resolution.x, 0.0);
  let py = vec2<f32>(0.0, 6.0 / resolution.y);
  let lC = sample_luma(uv);
  let lR = sample_luma(uv + px);
  let lL = sample_luma(uv - px);
  let lU = sample_luma(uv + py);
  let lD = sample_luma(uv - py);
  let grad = vec2<f32>(lR - lL, lU - lD) * 0.5;
  let gradLen = length(grad);
  let lumaContrast = abs(lR - lL) + abs(lU - lD);

  // Physics: bright repels, dark attracts along gradient
  let repelDir = -grad / max(gradLen, 1e-4);
  // Idea 2: edge-weighted creep — force scales with |grad|, so contours ooze
  // and flat regions rest (HEAD normalized noise-level gradients to full force).
  let edgeW = smoothstep(0.004, 0.08, gradLen);
  let lumaForce = repelDir * edgeW * forceMag * lumaWeight * (lC - 0.3) * 0.15 * depthParallax;

  // Mouse vortex force
  let aspect = resolution.x / resolution.y;
  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouseAspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let toMouse = uvAspect - mouseAspect;
  let distMouse = length(toMouse);
  let vortexFalloff = 1.0 - smoothstep(0.0, max(radius, 1e-3), distMouse);   // radius = 0 guard
  let swirl = vec2<f32>(-toMouse.y, toMouse.x) / max(distMouse, 1e-4);
  // Idea 3: isoline drift — near the cursor the vortex bends onto the image's
  // own contours: the swirl blends toward the isoline tangent (perp of the
  // luma gradient), sign-matched to the swirl so the rotation sense is kept.
  // grad is per-pixel on both axes, i.e. already isotropic in aspect space
  let isoT = vec2<f32>(-grad.y, grad.x) / max(gradLen, 1e-4);
  let isoAligned = isoT * select(-1.0, 1.0, dot(isoT, swirl) >= 0.0);
  let isoMix = edgeW * vortexFalloff * 0.85;
  let vortexDir = normalize(mix(swirl, isoAligned, isoMix) + vec2<f32>(1e-5, 0.0));
  let vortexForce = vortexDir * vortexFalloff * forceMag * 0.08;
  let vortexUV = vec2<f32>(vortexForce.x / aspect, vortexForce.y);

  // Curl noise advection (divergence-free, smooth)
  let curl = curl_noise(uv, time) * curlWeight * 0.012 * (1.0 + treble * 0.5);

  // Idea 1: advection memory — C holds last frame's accumulated displacement
  // (exact load). It relaxes toward the current drive with a ~25-frame time
  // constant, so bright edges keep creeping after a change and the cursor
  // vortex leaves a fading swirl; decay + length clamp keep it bounded.
  // The previous field is read as a 5-tap average (exact loads), so the memory
  // diffuses sideways and edges ooze as a sheet instead of a doubled outline.
  let cMax = vec2<i32>(resolution) - vec2<i32>(1);
  var memPrev = load_mem(coord);
  memPrev = memPrev + load_mem(min(coord + vec2<i32>(1, 0), cMax));
  memPrev = memPrev + load_mem(max(coord - vec2<i32>(1, 0), vec2<i32>(0)));
  memPrev = memPrev + load_mem(min(coord + vec2<i32>(0, 1), cMax));
  memPrev = memPrev + load_mem(max(coord - vec2<i32>(0, 1), vec2<i32>(0)));
  memPrev = memPrev * 0.2;
  let drive = lumaForce * 1.5 + vortexUV * 0.5;
  var mem = memPrev * 0.96 + drive * 0.04;
  let memLen = length(mem);
  mem = mem * min(1.0, 0.05 / max(memLen, 1e-5));

  // Total displacement
  let totalDisp = mem + vortexUV * 0.5 + curl;
  let velMag = length(totalDisp);

  // Spectral chromatic aberration based on velocity
  let chromaShift = velMag * 0.03;
  let rUV = clamp(uv + totalDisp + vec2<f32>(chromaShift / aspect, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv + totalDisp - vec2<f32>(chromaShift / aspect, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let colR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
  let colG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
  let colB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);
  var advected = vec3<f32>(colR.r, colG.g, colB.b);

  // HDR glow on high-velocity regions
  let glow = vec3<f32>(0.6 + mids * 0.3, 0.5 + treble * 0.3, 0.8) * velMag * velMag * 3.0 * (1.0 + bass * 0.4);
  advected = advected + glow;

  let finalRGB = aces_tonemap(max(advected, vec3<f32>(0.0)));

  // Alpha: coverage of the advected image, denser where it moves on edges
  let alpha = clamp(colG.a * (0.88 + clamp(velMag * 20.0 * (0.5 + lumaContrast * 4.0), 0.0, 0.12)), 0.0, 1.0);

  // Depth travels with the advected content
  let movedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, gUV, 0.0).r;
  textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(movedDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(mem, length(drive), lumaContrast));
}
