// ═══════════════════════════════════════════════════════════════════
//  Poincaré Tiling — Pass 2 (Conformal Möbius Layer & Geodesic Composite)
//  Category: simulation
//  Features: multi-pass, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: iterated {p, q} hyperbolic geodesic circle-inversion tessellation (Pass 1); conformal (1 - |z|^2) gilded geodesic arcs, hyperbolic-metric click waves & astrolabe bezel
//  A packing: linear composite RGB + semantic disk/arc alpha (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let d = dot(b, b);
  return vec2<f32>(dot(a, b), a.y * b.x - a.x * b.y) / max(d, 1e-6);
}

fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
  return cdiv(cmul(a, z) + b, cmul(c, z) + d);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let overallAudio = (audio.x + audio.y + audio.z) * 0.3333;

  let handoff = textureLoad(dataTextureC, pixel, 0);
  let base = handoff.rgb;
  let packedMeta = handoff.a;
  let inDisk = step(0.0, packedMeta);
  let parity = step(2.0, packedMeta) * inDisk;
  let geodesicDist = clamp((packedMeta - parity * 2.0 - 0.01) / 0.98, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let curvature = mix(0.62, 1.22, u.zoom_params.x) * (1.0 - audio.x * 0.06);
  let diskP = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * 2.04 * curvature;
  let rDisk = length(diskP);
  let safeZ = diskP / max(1.0, rDisk / 0.992);
  let conformal = clamp(1.0 - dot(safeZ, safeZ), 0.0, 1.0);

  // ── Idea 2: hyperbolic Poincaré-metric click wavefronts & counter-rotating SU(1,1) layer ──
  var metricWave = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    let isLive = f32(age >= 0.0 && age < 2.6) * inDisk;
    let safeAge = clamp(age, 0.0, 2.6);
    var w = (rp.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0) * 2.04 * curvature;
    let wLen = length(w);
    w = select(w, w * (0.92 / max(wLen, 1e-4)), wLen > 0.92);
    let num = 2.0 * dot(safeZ - w, safeZ - w);
    let den = max(conformal * max(1.0 - dot(w, w), 0.02), 0.002);
    let ch = 1.0 + num / den;
    let dHyp = log(ch + sqrt(max(ch * ch - 1.0, 0.0)));
    metricWave += isLive * exp(-abs(dHyp - safeAge * 2.2) * 3.5) * exp(-safeAge * 1.15);
  }

  let scale = mix(0.3, 0.9, u.zoom_params.w) * (1.0 + overallAudio * 0.08);
  let rot = time * mix(0.1, 0.6, u.zoom_params.z) * (1.0 + audio.z * 0.15);
  let rotPhase = vec2<f32>(cos(rot), sin(rot));
  let driftB = vec2<f32>(sin(rot * 0.63), -cos(rot * 0.63)) * (0.18 + metricWave * 0.12);
  let conjB = vec2<f32>(driftB.x, -driftB.y);
  let zRot = cmul(safeZ, rotPhase);
  let layer = mobius(zRot, vec2<f32>(1.0, 0.0), -driftB, -conjB, vec2<f32>(1.0, 0.0));
  let su = clamp(vec2<f32>(0.5) + layer * scale * 0.5, vec2<f32>(0.02), vec2<f32>(0.98));
  let layerSample = textureSampleLevel(readTexture, u_sampler, su, 0.0);

  // ── Idea 2: conformal (1 - |z|^2) gilded geodesic arcs, parity facet tint & astrolabe bezel ──
  let parityTint = mix(vec3<f32>(1.06, 1.01, 0.95), vec3<f32>(0.90, 0.97, 1.08), parity);
  let blendWeight = clamp(0.38 + u.zoom_params.w * 0.22 + audio.y * 0.12, 0.18, 0.78);
  var diskCol = mix(base * parityTint, layerSample.rgb, blendWeight * (0.55 + 0.45 * conformal));

  let arcWidth = mix(0.035, 0.095, sqrt(conformal));
  let geodesicArc = (1.0 - smoothstep(0.0, arcWidth, geodesicDist)) * inDisk;
  let goldArc = mix(vec3<f32>(1.45, 1.05, 0.42), vec3<f32>(0.48, 1.18, 1.55), 0.35 + 0.35 * sin(rDisk * 8.0 - time * 0.8));
  diskCol += goldArc * geodesicArc * (0.48 + audio.y * 0.28 + (1.0 - conformal) * 0.35);
  diskCol += vec3<f32>(0.65, 1.25, 1.65) * metricWave * (0.55 + audio.z * 0.35);

  // Ideal boundary horizon ring at |z| = 1 and recessed dark brass/obsidian astrolabe bezel outside
  let horizonRing = exp(-abs(rDisk - 0.992) * 68.0);
  let bezelGrad = 0.5 + 0.5 * cos(atan2(diskP.y, diskP.x) * 24.0);
  let bezelCol = base * 0.24 + vec3<f32>(0.07, 0.055, 0.04) * (0.75 + 0.25 * bezelGrad) * exp(-max(rDisk - 1.0, 0.0) * 3.0);
  var linearCol = mix(bezelCol, diskCol, inDisk) + vec3<f32>(1.55, 1.22, 0.62) * horizonRing * (0.65 + audio.x * 0.35);
  linearCol = max(linearCol, vec3<f32>(0.0));

  let alpha = clamp(
    mix(0.42 + layerSample.a * 0.25, 0.78 + geodesicArc * 0.18 + (1.0 - conformal) * 0.10, inDisk) + horizonRing * 0.2 + metricWave * 0.12,
    0.08,
    0.99
  );
  let domeDepth = clamp(mix(depth * 0.85, 0.25 + conformal * 0.55 + geodesicArc * 0.15, inDisk), 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(linearCol), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(domeDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(linearCol, alpha));
}
