// ═══════════════════════════════════════════════════════════════════
//  Chroma Shift Grid
//  Category: interactive-mouse
//  Features: mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-17, 2026-10-31
//  Ideas: Cauchy channel split (§12.2F); pointer-local gain
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn cauchyScale(b: f32) -> vec3<f32> {
  let lam2 = vec3<f32>(0.650, 0.550, 0.450) * vec3<f32>(0.650, 0.550, 0.450);
  let n = vec3<f32>(1.0) + b / lam2;
  return n / max(n.y, 1e-4);
}

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5; var s = 0.0; var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * valueNoise(q);
        q = q * 2.02; a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0*q + vec2<f32>(1.7, 9.2)), fbm(p + 4.0*q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0*r);
}

// ── Voronoi F2-F1 ────────────────────────────────────────────
fn voronoiF2minusF1(p: vec2<f32>) -> f32 {
    var F1 = 1e9; var F2 = 1e9;
    let ip = floor(p);
    for (var i = -2; i <= 2; i = i + 1) { for (var j = -2; j <= 2; j = j + 1) {
        let n = ip + vec2<f32>(f32(i), f32(j));
        let d = length(p - n - hash21(n));
        if (d < F1) { F2 = F1; F1 = d; } else if (d < F2) { F2 = d; }
    }}
    return F2 - F1;
}

// ── Spectral Tint ────────────────────────────────────────────
fn wavelengthToRGB(w: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(vec3<f32>(w, w + 2.09, w + 4.18));
}

// ── Cell Energy Modulation ───────────────────────────────────
fn cellEnergy(pattern: f32, activity: f32) -> f32 {
  return pattern * activity * (1.0 + activity * 2.0);
}

// ── Grid Lens Distortion ─────────────────────────────────────
fn distortByGrid(uv: vec2<f32>, cellCenter: vec2<f32>, strength: f32) -> vec2<f32> {
  let local = uv - cellCenter;
  let dist = length(local);
  let k = strength * 0.5;
  let factor = 1.0 + k * dist * dist * 20.0;
  return cellCenter + local * factor;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let mode = i32(clamp(u.zoom_params.x * 2.0 + 0.5, 0.0, 2.0));
  let animSpeed = u.zoom_params.y;
  let distortStr = u.zoom_params.z;
  let chromaStr = u.zoom_params.w;

  // ── Idea 2: pointer-local gain ──────────────────────────────────
  // distortStr and chromaStr stay global controls. Near the cursor
  // both amounts rise; nothing else is added.
  let aspect = resolution.x / max(resolution.y, 1.0);
  let mouse = u.zoom_config.yz;
  let pointer = exp(-dot((uv - mouse) * vec2<f32>(aspect, 1.0), (uv - mouse) * vec2<f32>(aspect, 1.0)) * 10.0);

  let gridSize = 16.0;
  let gridUV = floor(uv * gridSize);
  let cellCenter = (gridUV + 0.5) / gridSize;
  let localUV = uv - cellCenter;

  // Voronoi F2-F1 for cell pattern variation
  let cellPattern = voronoiF2minusF1(gridUV * 0.3 + time * 0.1);
  let cellActivity = smoothstep(0.0, 0.5, cellPattern);
  let energy = cellEnergy(cellPattern, cellActivity);

  // Domain-warped FBM for organic displacement
  let warp = warpedFBM(cellCenter * 6.0, time * 0.2);
  let warpAngle = warp * 6.2831 + time * animSpeed * 3.0;

  // Single smooth displacement direction
  let angleOffset = select(0.0, 0.5, mode == 1) + select(0.0, warpAngle, mode == 2);
  let dispDir = vec2<f32>(cos(warpAngle + angleOffset), sin(warpAngle + angleOffset));

  // Grid lens distortion. Pointer raises the existing lens amount locally.
  let dist = length(localUV);
  let k = distortStr * 0.5 * (1.0 + energy) * (1.0 + pointer * 0.85);
  let factor = 1.0 + k * dist * dist * 20.0;
  let distortedUV = cellCenter + localUV * factor;

  // Animated chromatic strength, same local gain.
  let animatedStr = chromaStr * (0.7 + 0.3 * sin(time * animSpeed * 5.0)) * (1.0 + pointer * 0.65);

  // Single displacement offset scaled by strength and cell activity
  let smoothOffset = dispDir * animatedStr * 0.04 * cellActivity;

  // Displacement magnitude for alpha encoding
  let displacementMagnitude = length(smoothOffset) / 0.04;

  // Alpha = grid distortion strength * cell activity
  let alpha = clamp(displacementMagnitude * cellActivity * 2.0, 0.0, 1.0);

  // ── Idea 1: Cauchy channel split (§12.2F) ───────────────────────
  // The offset above is unchanged. Each channel travels a different
  // optical distance along it. chromaStr still sets the amount.
  let spread = cauchyScale(0.015 + chromaStr * 0.05);
  let rUV = clamp(distortedUV + smoothOffset * spread.x, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(distortedUV + smoothOffset * spread.y, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(distortedUV + smoothOffset * spread.z, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
  );

  // Spectral tint via mix, NOT per-channel sampling
  let spectralTint = wavelengthToRGB(time * 0.4 + cellActivity * 4.0 + f32(mode));
  let tintStrength = animatedStr * cellActivity;
  let color = mix(baseColor, baseColor * spectralTint, alpha * tintStrength);

  // Grid edge visualization
  let f = fract(uv * gridSize);
  let edgeDist = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
  let gridAlpha = smoothstep(0.0, 0.15, edgeDist);

  // Final alpha blends grid structure and distortion energy
  let finalAlpha = mix(alpha * 0.5, alpha, gridAlpha);

  // Depth pass-through
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

  let outRgb = aces(max(color, vec3<f32>(0.0)));
  let outCol = vec4<f32>(outRgb, finalAlpha);
  textureStore(writeTexture, global_id.xy, outCol);
  textureStore(dataTextureA, global_id.xy, outCol);
}
