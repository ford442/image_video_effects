// ═══════════════════════════════════════════════════════════════════
//  mouse-hyperbolic-navigator
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, geometric, infinite-tiling
//  Complexity: High
//  Chunks From: chunk-library.md (none — complex arithmetic inline)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  The image is mapped onto a Poincaré disk. Mouse movement drives
//  Möbius transformations that scroll the hyperbolic plane. Tiles
//  become smaller and more numerous toward the disk boundary.
//  Upgraded: 2026-10-27, 2026-11-22
//  Ideas: horocycle rings; tile mortar; horocycle gutter; Cauchy split on Boundary Glow (§12.2F); conformal gutter (mortar of constant hyperbolic width, tapers to a hairline at the rim); Circle-Limit tile two-colouring (wedge x ring parity)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Complex arithmetic helpers
fn cMul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}
fn cDiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let denom = max(dot(b, b), 0.0001);
  return vec2<f32>(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / denom;
}
fn cConj(a: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x, -a.y);
}

// Möbius transform preserving unit disk: (z - a) / (1 - conj(a)*z)
fn mobiusDisk(z: vec2<f32>, a: vec2<f32>) -> vec2<f32> {
  let num = z - a;
  let den = vec2<f32>(1.0, 0.0) - cMul(cConj(a), z);
  return cDiv(num, den);
}

// Hyperbolic distance from origin in Poincaré disk
fn cauchyScale(bDisp: f32) -> vec3<f32> {
  let lam2 = vec3<f32>(0.650, 0.550, 0.450) * vec3<f32>(0.650, 0.550, 0.450);
  let n = vec3<f32>(1.0) + vec3<f32>(bDisp) / lam2;
  return n / n.y;
}

fn hyperbolicDistOrigin(z: vec2<f32>) -> f32 {
  let r2 = dot(z, z);
  return 0.5 * log((1.0 + r2 + 0.0001) / (1.0 - r2 + 0.0001));
}

// Wrap a point into a repeating tile for the image
fn hyperbolicTile(z: vec2<f32>, repetitions: f32) -> vec2<f32> {
  // Convert to polar-like coordinates in hyperbolic space
  let r = length(z);
  let angle = atan2(z.y, z.x);

  // Wrap angle for tiling
  let wrappedAngle = fract(angle / 6.28318 * repetitions) / repetitions * 6.28318;
  let tileZ = vec2<f32>(cos(wrappedAngle), sin(wrappedAngle)) * r;
  return tileZ;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let navigationSpeed = mix(0.2, 1.5, u.zoom_params.x);
  // Integer wedge count: fract(angle/2pi * N) only closes across the atan2 cut when N is whole
  // (a fractional N left a hard seam along -x).
  let tileCount = round(mix(3.0, 12.0, u.zoom_params.y));
  let edgeGlow = u.zoom_params.z;
  let zoomFactor = mix(0.5, 2.0, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // Map mouse to disk navigation parameter a
  var a = vec2<f32>(
    (mousePos.x - 0.5) * 1.8 * navigationSpeed,
    (mousePos.y - 0.5) * 1.8 * navigationSpeed
  );
  // Audio: the bass nudges the Mobius view point itself, so the whole tiling slides on the beat.
  a = a + vec2<f32>(cos(time * 0.37), sin(time * 0.49)) * bass * 0.12;
  // (z - a)/(1 - conj(a) z) is a disk automorphism only for |a| < 1; HEAD let |a| reach 1.08
  // (default speed, canvas corner) and 1.9 (max speed) and the picture collapsed. Soft-saturate
  // below 0.94 with a / sqrt(1 + |a|^2/0.94^2): within ~1 % of identity for |a| < 0.15 (a pointer
  // near the centre), and |a| -> 0.94 as the pointer runs to the canvas edge.
  a = a * inverseSqrt(1.0 + dot(a, a) * 1.1317);

  // Map UV to Poincaré disk coordinates (-1 to 1, corrected for aspect)
  var diskUV = (uv - 0.5) * 2.0;
  diskUV.x = diskUV.x * aspect;

  // Apply zoom
  diskUV = diskUV / zoomFactor;

  // Only render inside unit disk
  let distFromOrigin = length(diskUV);
  if (distFromOrigin > 0.999) {
    let voidColor = vec3<f32>(0.01, 0.0, 0.02);
    let display = vec4<f32>(voidColor, 0.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), display);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), display);
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
    return;
  }

  // Apply Möbius navigation
  let transformed = mobiusDisk(diskUV, a);

  // Hyperbolic tiling: repeat pattern toward boundary
  let tiled = hyperbolicTile(transformed, tileCount);

  // Map back to UV space for image sampling
  let sampleUV = clamp(tiled * 0.5 + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let hDist = hyperbolicDistOrigin(transformed);
  let magnify = 1.0 + hDist * 0.3;
  let magnifiedUV = clamp((sampleUV - 0.5) * magnify + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  // ── Idea: Cauchy split along the conformal scale. Boundary Glow at 0 leaves red and blue together (§12.2F).
  let mag = cauchyScale(edgeGlow * 0.035);
  let pivot = vec2<f32>(0.5);
  let uvR = clamp((magnifiedUV - pivot) * mag.x + pivot, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp((magnifiedUV - pivot) * mag.z + pivot, vec2<f32>(0.0), vec2<f32>(1.0));
  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, magnifiedUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
  );
  let srcA = textureSampleLevel(readTexture, u_sampler, magnifiedUV, 0.0).a;

  // Wedge coordinate of the navigated point. HEAD measured the mortar from fract == 0.5 (the middle
  // of each wedge) while the image discontinuity sits where fract wraps; the mortar now rides the seam.
  let tileAng = atan2(transformed.y, transformed.x) / 6.28318 * tileCount;
  let wedgeF = fract(tileAng);
  let seamDist = min(wedgeF, 1.0 - wedgeF);
  let rr = length(transformed);
  // ── Idea 1: conformal gutter ────────────────────────────────────────
  // Poincare metric ds = 2|dz|/(1-|z|^2): a gutter of constant HYPERBOLIC width spans
  // N/(4 pi) * W * (1-r^2)/r of a wedge, i.e. it narrows toward the rim and ends as a hairline
  // (Circle Limit). HEAD's constant angular width fanned out wider toward the rim instead.
  // Capped at HEAD's 0.08 so the centre keeps its old weight.
  let gutterHalf = clamp(0.084 * tileCount * 0.0796 * (1.0 - rr * rr) / max(rr, 0.02), 0.006, 0.08);
  // ── Idea 2: Circle-Limit two-colouring ──────────────────────────────
  // fract() above throws the integer wedge/ring index away; keep it. Adjacent tiles (across a wedge
  // seam or a ring gutter) alternate value and warm/cool tint like an Escher tessellation. The tint
  // steps coincide with the mortar/ring gutters, so they read as tile identity, not new lines.
  let wedgeId = floor(tileAng);
  let wedgeMod = wedgeId - tileCount * floor(wedgeId / tileCount);
  let ringId = floor(hDist * max(tileCount, 1.0) * 0.42);
  let parity = select(0.0, 1.0, fract((wedgeMod + ringId) * 0.5) > 0.25);
  color = color * (1.0 + (parity - 0.5) * 0.16) * mix(vec3<f32>(1.04, 1.0, 0.96), vec3<f32>(0.96, 1.0, 1.04), parity);
  let mortar = 1.0 - smoothstep(gutterHalf * 0.25, gutterHalf, seamDist);
  color = mix(color, color * 0.35, mortar * 0.65);
  // ── Idea: horocycle gutter — a radial seam, separate from the angular mortar.
  let ring = fract(hDist * max(tileCount, 1.0) * 0.42);
  let ringSeam = smoothstep(0.07, 0.0, ring) + smoothstep(0.93, 1.0, ring);
  color = mix(color, color * 0.32, clamp(ringSeam, 0.0, 1.0) * 0.75);
  let horo = abs(sin(hDist * 6.0 - time * 1.1));
  color += vec3<f32>(0.25, 0.55, 1.0) * horo * 0.12 * (1.0 + treble * 1.5) * (1.0 - distFromOrigin);

  // Ripple distortions: clicks create hyperbolic waves
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0) {
      let rPos = vec2<f32>(
        (ripple.x - 0.5) * 2.0 * aspect,
        (ripple.y - 0.5) * 2.0
      );
      let rDist = length(diskUV - rPos);
      let wave = sin(rDist * 20.0 - elapsed * 6.0) * exp(-elapsed * 1.2) * smoothstep(1.0, 0.0, rDist);
      color = color + vec3<f32>(0.2, 0.4, 0.6) * wave * 0.5;
    }
  }

  // Edge glow: highlight boundary of unit disk
  let edgeProximity = smoothstep(0.999, 0.85, distFromOrigin);
  let boundaryGlow = (1.0 - edgeProximity) * edgeGlow;
  color = mix(color, vec3<f32>(0.3, 0.6, 1.0), boundaryGlow * 0.4);

  // Ripple lobes can push dark pixels below zero; the catalog ACES fit maps negatives to bright.
  color = max(color, vec3<f32>(0.0));

  // Hyperbolic distance as alpha
  let aa = 2.51; let bb = 0.03; let cc = 2.43; let dd = 0.59; let ee = 0.14;
  let mapped = clamp((color * (aa * color + bb)) / (color * (cc * color + dd) + ee), vec3<f32>(0.0), vec3<f32>(1.0));
  let alpha = clamp(hDist / 3.0, 0.0, 1.0) * srcA;
  let display = vec4<f32>(mapped, alpha);
  textureStore(writeTexture, vec2<i32>(global_id.xy), display);
  textureStore(dataTextureA, vec2<i32>(global_id.xy), display);

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
