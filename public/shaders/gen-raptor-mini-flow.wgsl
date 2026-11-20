// ═══════════════════════════════════════════════════════════════════
//  Gen Raptor Mini Flow
//  Category: advanced-hybrid
//  Features: generative, mouse-driven, flow-field, cellular, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Chunks From: gen-raptor-mini.wgsl, conv-structure-tensor-flow.wgsl
//  Created: 2026-04-18
//  By: Agent CB-5 — Generative & Hybrid Enhancer
//  Upgraded: 2026-11-20
//  Ideas: streamlined body along heading (structure-tensor orientation, §12.2A); pursuit wake (soft inverse-square, §12.2F)
//  A packing: ACES display RGBA (C is never read; A written for the contract)
// ═══════════════════════════════════════════════════════════════════
//  Predatory raptor agents navigate structure-tensor flow fields,
//  hunting along image edges and orientations. Their trails follow
//  dominant eigenvectors while audio rage pulses through the swarm.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash21 (from gen-raptor-mini.wgsl) ═══
fn hash21(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn safeNorm(v: vec2<f32>, fallback: vec2<f32>) -> vec2<f32> {
  let l2 = dot(v, v);
  return select(fallback, v * inverseSqrt(max(l2, 1e-12)), l2 > 1e-10);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
  let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
  return dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

// ═══ CHUNK: structureTensor (from conv-structure-tensor-flow.wgsl) ═══
fn structureTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  let gx =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
    -2.0 * sampleLuma(uv, pixelSize, -1,  0) +
    -1.0 * sampleLuma(uv, pixelSize, -1,  1) +
     1.0 * sampleLuma(uv, pixelSize,  1, -1) +
     2.0 * sampleLuma(uv, pixelSize,  1,  0) +
     1.0 * sampleLuma(uv, pixelSize,  1,  1);

  let gy =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
    -2.0 * sampleLuma(uv, pixelSize,  0, -1) +
    -1.0 * sampleLuma(uv, pixelSize,  1, -1) +
     1.0 * sampleLuma(uv, pixelSize, -1,  1) +
     2.0 * sampleLuma(uv, pixelSize,  0,  1) +
     1.0 * sampleLuma(uv, pixelSize,  1,  1);

  let Ix2 = gx * gx;
  let Iy2 = gy * gy;
  let Ixy = gx * gy;
  return vec4<f32>(Ix2, Iy2, Ixy, 0.0);
}

fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  var sum = vec4<f32>(0.0);
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      sum += structureTensor(uv + offset, pixelSize);
    }
  }
  return sum / 9.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  let coords = vec2<i32>(global_id.xy);
  if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

  let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
  let screen_uv = (vec2<f32>(coords) + 0.5) / vec2<f32>(dims);
  let pixelSize = 1.0 / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;

  // Parameters
  let turnSpeed = u.zoom_params.x;
  let maxSpeed = u.zoom_params.y;
  let rageDuration = u.zoom_params.z;
  let flowInfluence = u.zoom_params.w;

  // Audio rage mode
  let rage = bass * 3.0;

  // Compute structure tensor flow at this pixel
  let tensor = smoothTensor(screen_uv, pixelSize);
  let Jxx = tensor.x;
  let Jyy = tensor.y;
  let Jxy = tensor.z;

  let trace = Jxx + Jyy;
  let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
  let lambda1 = (trace + diff) * 0.5;
  let lambda2 = (trace - diff) * 0.5;

  // Dominant eigenvector (flow direction). Rescue: the principal-axis angle
  // θ = ½·atan2(2Jxy, Jxx−Jyy) is the same x ≥ 0 unit vector as the old
  // normalize(λ1−Jyy, Jxy) but never normalizes the zero vector (Jxy = 0,
  // Jxx < Jyy, i.e. gradient only in y). Flat areas still give (1, 0).
  let hasOrient = abs(Jxy) > 0.0001 || abs(Jxx - Jyy) > 0.0001;
  let eigTheta = select(0.0, 0.5 * atan2(2.0 * Jxy, Jxx - Jyy), hasOrient);
  let eigenvec = vec2<f32>(cos(eigTheta), sin(eigTheta));

  // Coherency: how strongly oriented
  let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);

  // Mouse target
  let mouse = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0) * vec2<f32>(f32(dims.x) / f32(dims.y), 1.0);

  // Raptor cellular simulation
  var col = vec3<f32>(0.0);
  var alpha = 0.0;

  let scale_pattern = 4.0;
  var st = uv * scale_pattern * 5.0;

  // Blend flow direction with mouse direction
  let toMouse = safeNorm(mouse - uv, vec2<f32>(0.0));
  let flowDir = mix(toMouse, eigenvec, flowInfluence);

  // Turn speed controls how intensely they align to flow
  let dir = mix(safeNorm(uv, vec2<f32>(0.0)), flowDir, turnSpeed);

  // Offset cells by time and flow-driven speed.
  // Rescue: HEAD added dir to the *sample* point (st += …), which moves the
  // lattice features along −dir — raptors fled the cursor. Subtracting makes
  // them travel along dir (toward the prey / along the flow).
  st -= dir * time * maxSpeed * (1.0 + coherency);

  let id = floor(st);
  let f = fract(st) - 0.5;

  let rng = hash21(id);
  let bodyRadius = 0.2 * (1.0 + rage * 0.5);

  // ── Idea 1: streamlined body (structure-tensor orientation → anisotropic kernel, §12.2A)
  // Measure the body SDF in the raptor's heading frame: stretched along dir by
  // 1 + 0.8·coherency, squeezed across by the inverse (area-preserving). Strongly
  // oriented image regions give long slim raptors, flat regions give HEAD's discs.
  // The stretch is clamped so the body never outgrows its own cell.
  let heading = safeNorm(dir, eigenvec);
  let hFrame = vec2<f32>(dot(f, heading), dot(f, vec2<f32>(-heading.y, heading.x)));
  let stretch = min(1.0 + 0.8 * coherency, max(1.0, 0.48 / bodyRadius));
  let dist = length(vec2<f32>(hFrame.x / stretch, hFrame.y * stretch)) - bodyRadius;
  let glow_radius = 0.15 + rageDuration * 0.3;

  let flowAngle = atan2(eigenvec.y, eigenvec.x) * 0.15915 + 0.5;
  let flowHue = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.67))
  );

  if(dist < 0.0) {
    // Raptor body with flow-aligned color
    col = flowHue * (0.5 + 0.5 * rng.x) + vec3<f32>(rage * 0.8, 0.0, 0.0);

    // Scale pattern on raptor
    let scale_tex = fract(length(f * rageDuration * 10.0));
    col *= scale_tex;
    alpha = 1.0;
  } else {
    // Trail / Background with flow-aligned glow
    let trail = mix(vec3<f32>(0.01, 0.02, 0.03), vec3<f32>(0.05, 0.1, 0.05), pow(max(0.0, 1.0 - length(uv - mouse)), 2.0));
    let glow = smoothstep(glow_radius, 0.0, dist);

    // Flow field visualization underneath
    let flowVis = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (coherency + 0.0)),
      0.5 + 0.5 * cos(6.28318 * (coherency + 0.33)),
      0.5 + 0.5 * cos(6.28318 * (coherency + 0.67))
    ) * 0.1 * coherency;

    col = mix(trail + flowVis, vec3<f32>(0.2, 0.8, 0.3), glow * 0.5);
    alpha = glow * 0.35;

    // ── Idea 2: pursuit wake (soft inverse-square, §12.2F) ───────────────
    // A raptor moving at max speed drags a comet tail behind it along −heading.
    // Measured from the body centre so it grows out of the body without a seam;
    // length grows with speed and coherency but is capped at 0.49 cell so it
    // never meets the cell edge. Width tapers to a point; brightness falls as
    // 1/(1+(a/a0)²) — a core radius instead of a singularity.
    let bodyRear = bodyRadius * stretch;
    let behind = max(-hFrame.x, 0.0);
    let tailLen = max(min(bodyRear + (0.12 + 0.26 * maxSpeed) * (1.0 + 0.6 * coherency), 0.49), 0.05);
    let taper = clamp(1.0 - behind / tailLen, 0.0, 1.0);
    let tailW = 1.0 * bodyRadius / stretch * taper;
    let across = exp(-hFrame.y * hFrame.y / (tailW * tailW + 0.002));
    let a0 = 0.8 * tailLen;
    let rise = smoothstep(0.0, 0.12, -hFrame.x);   // nothing ahead of the body
    let wake = rise * taper * across / (1.0 + (behind * behind) / (a0 * a0));
    col += (flowHue * 0.7 + vec3<f32>(0.3)) * wake * (2.0 + 0.5 * min(rage, 2.0));
    alpha = max(alpha, wake * 0.5);
  }

  // Floor: ACES on display RGB, A = display RGBA (C is never read here).
  let display = acesToneMap(col);
  textureStore(writeTexture, coords, vec4<f32>(display, alpha));
  textureStore(dataTextureA, coords, vec4<f32>(display, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screen_uv, 0.0).r;
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
