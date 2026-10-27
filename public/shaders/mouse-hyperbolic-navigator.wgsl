// ═══════════════════════════════════════════════════════════════════
//  mouse-hyperbolic-navigator
//  Category: interactive-mouse
//  Features: mouse-driven, geometric, infinite-tiling
//  Complexity: High
//  Chunks From: chunk-library.md (none — complex arithmetic inline)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  The image is mapped onto a Poincaré disk. Mouse movement drives
//  Möbius transformations that scroll the hyperbolic plane. Tiles
//  become smaller and more numerous toward the disk boundary.
//  Upgraded: 2026-10-27
//  Ideas: horocycle rings; tile mortar; horocycle gutter; Cauchy split on Boundary Glow (§12.2F)
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
  let tileCount = mix(3.0, 12.0, u.zoom_params.y);
  let edgeGlow = u.zoom_params.z;
  let zoomFactor = mix(0.5, 2.0, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;

  // Map mouse to disk navigation parameter a (clamped to keep inside disk)
  let a = vec2<f32>(
    (mousePos.x - 0.5) * 1.8 * navigationSpeed,
    (mousePos.y - 0.5) * 1.8 * navigationSpeed
  );

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

  let wrapSeam = abs(fract(atan2(transformed.y, transformed.x) / 6.28318 * tileCount) - 0.5);
  let mortar = 1.0 - smoothstep(0.02, 0.08, wrapSeam);
  color = mix(color, color * 0.35, mortar * 0.65);
  // ── Idea: horocycle gutter — a radial seam, separate from the angular mortar.
  let ring = fract(hDist * max(tileCount, 1.0) * 0.42);
  let ringSeam = smoothstep(0.07, 0.0, ring) + smoothstep(0.93, 1.0, ring);
  color = mix(color, color * 0.32, clamp(ringSeam, 0.0, 1.0) * 0.75);
  let horo = abs(sin(hDist * 6.0 - time * 1.1));
  color += vec3<f32>(0.25, 0.55, 1.0) * horo * 0.12 * (1.0 - distFromOrigin);

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
