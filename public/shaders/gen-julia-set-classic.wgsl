// ═══════════════════════════════════════════════════════════════════
//  Julia Set Classic
//  Category: generative
//  Features: escape-time, orbit-trap, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10, 2026-11-15
//  Ideas: exterior distance estimate; log|z| stripe coloring; spiral orbit traps; pseudo-3D orbit slice twist; Douady-Hubbard z/dz complex-potential 3D normal & binary external rays; Fatou interior cycle-convergence petal shells
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(TAU * (vec3<f32>(t) + vec3<f32>(0.0, 0.31, 0.67)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn cdivSafe(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let denom = max(dot(b, b), 1e-8);
  return vec2<f32>(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / denom;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = (vec2<f32>(pixel) + vec2<f32>(0.5)) / res;
  let aspect = res.x / max(res.y, 1.0);
  let screenP = (uv01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let zoom = max(u.zoom_params.z, 0.05);
  let iterations = i32(clamp(round(u.zoom_params.w), 8.0, 160.0));
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let mouseC = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(2.4, -2.4);
  let baseC = vec2<f32>(u.zoom_params.x, u.zoom_params.y);
  let c = mix(baseC + vec2<f32>(sin(time * 0.09), cos(time * 0.07)) * mids * 0.006, mouseC, held * 0.82);

  var clickWarp = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    let isLive = f32(age > 0.0 && age < 3.0);
    let safeAge = clamp(age, 0.0, 3.0);
    let center = (ripple.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
    clickWarp += isLive * exp(-abs(distance(screenP, center) - safeAge * 0.2) * 68.0) * exp(-safeAge * 1.35);
  }

  var z = screenP * (2.45 / zoom) + vec2<f32>(clickWarp * 0.015, -clickWarp * 0.01);
  var dz = vec2<f32>(1.0, 0.0);
  var zPrev = z;
  var zPrev2 = z;
  var cycleStep = 10.0;
  var cyclePhase = 0.0;
  var escaped = f32(iterations);
  var trap = 10.0;
  var orbit = 0.0;
  var stripeAcc = 0.0;

  for (var i = 0; i < 160; i++) {
    if (i >= iterations) { break; }
    let prev2 = zPrev2;
    zPrev2 = zPrev;
    zPrev = z;

    let dzx = 2.0 * (z.x * dz.x - z.y * dz.y);
    let dzy = 2.0 * (z.x * dz.y + z.y * dz.x);
    dz = vec2<f32>(dzx, dzy);
    let x = z.x * z.x - z.y * z.y + c.x;
    let y = 2.0 * z.x * z.y + c.y;
    z = vec2<f32>(x, y);

    // Idea 1 (2026-10-10): spiral orbit traps
    let spiral = abs(sin(atan2(z.y, z.x) * 3.0 + length(z) * 5.0 - time * 2.0));
    trap = min(trap, min(spiral * 0.3, abs(length(z) - 0.5)));

    // Idea 2 (2026-10-10): pseudo-3D orbit slice twist (keep dz rotation-coherent)
    let twist = sin(f32(i) * 0.1 + time) * 0.02;
    let ct = cos(twist);
    let st = sin(twist);
    z = vec2<f32>(z.x * ct - z.y * st, z.x * st + z.y * ct);
    dz = vec2<f32>(dz.x * ct - dz.y * st, dz.x * st + dz.y * ct);

    // ── Idea 4: Fatou interior attracting-cycle convergence tracking ──────
    let d1 = length(z - zPrev);
    let d2 = length(z - prev2);
    let stepD = min(d1, d2);
    let trackCycle = stepD < cycleStep && i > 6;
    let deltaCycle = select(z - prev2, z - zPrev, d1 < d2);
    cycleStep = select(cycleStep, stepD, trackCycle);
    cyclePhase = select(cyclePhase, atan2(deltaCycle.y, deltaCycle.x), trackCycle);

    let r2 = dot(z, z);
    orbit += exp(-abs(length(z) - 1.0) * 8.0) / f32(iterations);
    stripeAcc += 0.5 + 0.5 * sin(log(max(r2, 0.0001)) * 4.2);
    if (r2 > 256.0) { escaped = f32(i); break; }
  }

  let escapedMask = select(0.0, 1.0, escaped < f32(iterations));
  let smoothIter = escaped - log2(max(log2(max(dot(z, z), 1.0001)), 0.0001));
  let normalized = clamp(smoothIter / f32(iterations), 0.0, 1.0);
  let trapGlow = exp(-trap * (45.0 + treble * 24.0));
  let interior = 1.0 - escapedMask;
  let rEsc = max(length(z), 1.0001);
  let de = 0.5 * log(rEsc) * rEsc / max(length(dz), 0.0001);
  let deEdge = exp(-de * (16.0 + zoom * 5.0)) * escapedMask;
  let stripe = stripeAcc / max(escaped, 1.0);

  // ── Idea 3: Douady-Hubbard complex-potential 3D normal (z / dz) & external rays ──
  let potGrad = cdivSafe(z, dz);
  let potDir = potGrad / max(length(potGrad), 1e-5);
  let potNormal = normalize(vec3<f32>(potDir.x * 0.82, potDir.y * 0.82, 0.68));
  let keyLight = normalize(vec3<f32>(cos(time * 0.16) * 0.72, sin(time * 0.16) * 0.72, 0.74));
  let dhRelief = mix(1.0, 0.56 + 0.74 * max(dot(potNormal, keyLight), 0.0), escapedMask);
  let dhSpec = pow(max(dot(reflect(-keyLight, potNormal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 20.0) * escapedMask * (0.28 + normalized * 0.55);
  let extAngle = atan2(z.y, z.x);
  let binaryDecomp = mix(0.92, 1.08, smoothstep(-0.12, 0.12, sin(extAngle)));
  let externalRays = pow(0.5 + 0.5 * cos(extAngle * 8.0), 8.0) * smoothstep(0.03, 0.5, normalized) * escapedMask;

  // ── Idea 4: chambered Fatou interior shells & basin petals ────────────
  let logCycle = log(clamp(cycleStep, 0.00015, 4.0));
  let fatouShell = 0.5 + 0.5 * cos(logCycle * 3.6 - time * 0.45);
  let fatouPetal = 0.5 + 0.5 * cos(cyclePhase * 3.0 + logCycle * 1.4);
  let fatouBasin = palette(0.58 + fatouShell * 0.24 + mids * 0.06) * (0.06 + 0.28 * fatouShell * fatouPetal + 0.16 * orbit);

  var raw = palette(normalized * 3.2 + time * 0.012 + mids * 0.08 + stripe * 0.22) * escapedMask * (0.25 + normalized * 1.5 + bass * 0.2 + stripe * 0.35) * dhRelief * binaryDecomp;
  raw += vec3<f32>(1.15, 0.96, 0.82) * dhSpec * (0.65 + bass * 0.25);
  raw += palette(normalized * 2.0 + 0.18) * externalRays * (0.20 + mids * 0.18);
  raw += palette(trapGlow * 0.3 + 0.37) * trapGlow * (0.5 + treble * 0.9);
  raw += vec3<f32>(1.15, 0.85, 1.35) * deEdge * (0.55 + treble * 0.35);
  raw += (vec3<f32>(0.04, 0.08, 0.16) * (0.7 + orbit * 0.5) + fatouBasin) * interior;
  raw += vec3<f32>(1.1, 0.45, 1.4) * clickWarp * 0.48;

  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.935, max(raw, vec3<f32>(0.0)), 0.32 + bass * 0.025), vec3<f32>(0.0), vec3<f32>(7.0));
  let alpha = clamp(0.04 + escapedMask * normalized * 0.58 + trapGlow * 0.3 + deEdge * 0.22 + interior * (0.16 + fatouShell * 0.10) + clickWarp * 0.12, 0.04, 0.98);
  let depth = clamp(interior * (0.76 + fatouShell * 0.14) + trapGlow * 0.45 + deEdge * 0.35 + normalized * 0.25, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(raw, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(raw * 1.1), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
