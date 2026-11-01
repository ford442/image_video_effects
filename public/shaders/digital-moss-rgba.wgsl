// ═══════════════════════════════════════════════════════════════════
//  digital-moss-rgba
//  Category: advanced-hybrid
//  Features: mouse-driven, temporal, rgba-state-machine, organic, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-12, 2026-10-31
//  Ideas: dual-species territorial ridge where B≈D; capsule stalks from high-B; isotropic 9-point Laplacian (§12.2D); cushion micro-relief and moisture dew specular
//  A packing: raw (A, B, C, D) chemistry
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn mossPalette(a: f32, b: f32, c: f32, d: f32, t: f32) -> vec3<f32> {
  let base = vec3<f32>(0.08, 0.55, 0.22) * a
    + vec3<f32>(0.9, 0.25, 0.1) * b
    + vec3<f32>(0.15, 0.95, 0.45) * c
    + vec3<f32>(0.75, 0.65, 0.15) * d;
  let irid = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (t + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.67))
  );
  return base * (0.65 + irid * 0.35);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let aspect = f32(dims.x) / f32(dims.y);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let feedParam = u.zoom_params.x;
  let killParam = u.zoom_params.y;
  let sourceMix = u.zoom_params.z;
  let growSpeed = u.zoom_params.w * (1.0 + bass * 0.25);

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

  let state = stateAt(coord, dims);
  var A = state.r;
  var B = state.g;
  var C = state.b;
  var D = state.a;

  if (time < 0.1) {
    A = 1.0; B = 0.0; C = 1.0; D = 0.0;
    let centerDist = length(uv - vec2<f32>(0.5));
    if (centerDist < 0.05) { B = 0.5; D = 0.3; }
    let seed2Dist = length(uv - vec2<f32>(0.3, 0.7));
    if (seed2Dist < 0.03) { B = 0.4; }
  }

  // ── Idea 3: isotropic 9-point Laplacian (§12.2D) for rounded bryophyte rosettes ──
  let left = stateAt(coord + vec2<i32>(-1, 0), dims);
  let right = stateAt(coord + vec2<i32>(1, 0), dims);
  let down = stateAt(coord + vec2<i32>(0, -1), dims);
  let up = stateAt(coord + vec2<i32>(0, 1), dims);
  let dl = stateAt(coord + vec2<i32>(-1, -1), dims);
  let dr = stateAt(coord + vec2<i32>(1, -1), dims);
  let ul = stateAt(coord + vec2<i32>(-1, 1), dims);
  let ur = stateAt(coord + vec2<i32>(1, 1), dims);

  let lap9 = ((left + right + down + up) * 0.20 + (dl + dr + ul + ur) * 0.05 - state) * 4.0;
  let lapA = lap9.r;
  let lapB = lap9.g;
  let lapC = lap9.b;
  let lapD = lap9.a;

  let feed = mix(0.02, 0.06, feedParam);
  let kill = mix(0.04, 0.07, killParam);
  let diffA = 0.8; let diffB = 0.3; let diffC = 0.7; let diffD = 0.25;
  let crossInhibit = sourceMix * 0.3;
  let dt = 0.8;

  let dA = diffA * lapA - A * B * B + feed * (1.0 - A) - crossInhibit * A * D;
  let dB = diffB * lapB + A * B * B - (feed + kill) * B;
  let dC = diffC * lapC - C * D * D + feed * (1.0 - C) - crossInhibit * C * B;
  let dD = diffD * lapD + C * D * D - (feed + kill) * D;

  A = clamp(A + dA * dt, 0.0, 1.0);
  B = clamp(B + dB * dt, 0.0, 1.0);
  C = clamp(C + dC * dt, 0.0, 1.0);
  D = clamp(D + dD * dt, 0.0, 1.0);

  let p_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let m_aspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let mDist = length(p_aspect - m_aspect);
  let mouseInfluence = smoothstep(0.12, 0.0, mDist);

  if (held) {
    B += mouseInfluence * 0.4;
    D += mouseInfluence * 0.25;
  } else if (u.zoom_config.w > 0.0) {
    B = max(0.0, B - mouseInfluence * 0.5);
    D = max(0.0, D - mouseInfluence * 0.3);
  }
  B = clamp(B, 0.0, 1.0);
  D = clamp(D, 0.0, 1.0);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = time - ripple.z;
    if (age < 1.5 && rDist < 0.08) {
      let strength = smoothstep(0.08, 0.0, rDist) * max(0.0, 1.0 - age * 0.7);
      B += strength * 0.5;
      D += strength * 0.3;
    }
  }
  B = clamp(B, 0.0, 1.0);
  D = clamp(D, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(A, B, C, D));

  let prevMoss = state.r;
  let seed = hash12(uv + vec2<f32>(time * 0.1, time * 0.05));
  var grown = prevMoss;

  if (luma < 0.15 && seed > 0.992 - treble * 0.01) {
    grown = 1.0;
  }

  if (grown < 0.9) {
    let angle = hash12(uv * 10.0 + time) * 6.28;
    let offset = vec2<i32>(i32(cos(angle) * 2.0), i32(sin(angle) * 2.0));
    let neighborState = stateAt(coord + offset, dims).r;
    if (neighborState > 0.5 && luma < 0.42) {
      grown = min(1.0, grown + 0.06 * growSpeed);
    }
  }

  if (luma > 0.6) {
    grown *= 0.88;
  }

  if (mDist < 0.06 && !held && u.zoom_config.w > 0.0) {
    grown = 0.0;
  }
  if (mDist < 0.08 && held) {
    grown = min(1.0, grown + 0.15 * mouseInfluence);
  }

  let mossColor = mossPalette(A, B, C, D, time * 0.04 + mids * 0.2);
  let scan = 0.82 + 0.18 * sin(uv.y * 480.0 + time * 2.0);
  let scannedMossColor = mossColor * scan;

  // ── Idea 4: cushion micro-relief normal & moisture dewdrop specular ──
  let bioL = left.g + left.a;
  let bioR = right.g + right.a;
  let bioD = down.g + down.a;
  let bioU = up.g + up.a;
  let cushionGrad = vec2<f32>(bioR - bioL, bioU - bioD);
  let lightDir = normalize(vec2<f32>(-0.6, -0.8));
  let reliefShade = clamp(1.0 + dot(cushionGrad, lightDir) * 1.35, 0.65, 1.35);
  let rhizoidShadow = smoothstep(0.05, 0.35, length(cushionGrad)) * (1.0 - min(B + D, 1.0));
  let shadowedImg = imgColor * (1.0 - rhizoidShadow * 0.32 * grown);

  var finalColor = mix(shadowedImg, scannedMossColor * reliefShade, grown * 0.88);

  let dewCell = hash12(floor(uv * 220.0));
  let dewGlint = smoothstep(0.52, 0.85, D + B * 0.5) * step(0.86, dewCell) * clamp(growSpeed, 0.0, 1.5) * grown;
  finalColor += vec3<f32>(0.75, 0.98, 0.85) * dewGlint * (0.45 + treble * 0.35);

  // Idea 1 — dual-species territorial ridge where B meets D
  let meet = 1.0 - abs(B - D);
  let ridge = smoothstep(0.78, 0.98, meet) * min(B, D) * grown;
  finalColor += vec3<f32>(0.95, 0.82, 0.28) * ridge * (0.45 + treble * 0.35);

  // Idea 2 — capsule stalks: high-B samples a short screen-up offset
  let stalkPx = i32(clamp(B * 7.0, 0.0, 8.0));
  let stalkCoord = clamp(coord + vec2<i32>(0, -stalkPx), vec2<i32>(0), dims - vec2<i32>(1));
  let stalkState = textureLoad(dataTextureC, stalkCoord, 0);
  let capsule = smoothstep(0.55, 0.88, B) * stalkState.g * grown;
  finalColor = mix(finalColor, scannedMossColor * vec3<f32>(0.85, 1.15, 0.55) + vec3<f32>(0.55, 0.35, 0.12) * capsule, capsule * 0.4);

  finalColor = acesToneMap(max(finalColor * (0.95 + bass * 0.08), vec3<f32>(0.0)));
  let alpha = clamp(mix(1.0, 0.82, grown) + B * 0.1 + ridge * 0.2 + capsule * 0.15 + dewGlint * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
