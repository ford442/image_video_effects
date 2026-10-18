// ═══════════════════════════════════════════════════════════════════
//  Fabric of Reality — Jacobi constraint
//  Category: simulation
//  Features: audio-reactive, mouse-driven
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: shear springs; catenary tension (verlet); open weave and frayed ends (render)
//  A packing: raw (position.xy, previous.xy)
// ═══════════════════════════════════════════════════════════════════
// One Jacobi iteration. Structural springs plus bias (shear) springs.

#include "_prelude.wgsl"

const REST_LENGTH: f32 = 1.0;

fn loadState(c: vec2<i32>, size: vec2<u32>) -> vec4<f32> {
  let hi = vec2<i32>(max(i32(size.x) - 1, 0), max(i32(size.y) - 1, 0));
  return textureLoad(dataTextureC, clamp(c, vec2<i32>(0), hi), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  // Soft-cap stiffness so 4 Jacobi iters stay stable under balanced tier
  let stiffness = mix(0.12, 0.72, u.zoom_params.x);
  let tearThreshold = mix(1.5, 4.0, u.zoom_params.y);
  let selfHeal = u.zoom_params.w;

  let ic = vec2<i32>(coord);
  let state = loadState(ic, size);
  var pos = state.xy;
  let prevPos = state.zw;
  if (length(pos) < 0.001) { pos = uv; }

  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let restLen = texelSize.x * REST_LENGTH;
  let restDiag = length(texelSize) * REST_LENGTH;

  var leftPos = loadState(ic + vec2<i32>(-1, 0), size).xy;
  var rightPos = loadState(ic + vec2<i32>(1, 0), size).xy;
  var upPos = loadState(ic + vec2<i32>(0, -1), size).xy;
  var downPos = loadState(ic + vec2<i32>(0, 1), size).xy;
  var upLeft = loadState(ic + vec2<i32>(-1, -1), size).xy;
  var upRight = loadState(ic + vec2<i32>(1, -1), size).xy;
  var downLeft = loadState(ic + vec2<i32>(-1, 1), size).xy;
  var downRight = loadState(ic + vec2<i32>(1, 1), size).xy;

  if (length(leftPos) < 0.001) { leftPos = uv + vec2<f32>(-texelSize.x, 0.0); }
  if (length(rightPos) < 0.001) { rightPos = uv + vec2<f32>(texelSize.x, 0.0); }
  if (length(upPos) < 0.001) { upPos = uv + vec2<f32>(0.0, -texelSize.y); }
  if (length(downPos) < 0.001) { downPos = uv + vec2<f32>(0.0, texelSize.y); }
  if (length(upLeft) < 0.001) { upLeft = uv + vec2<f32>(-texelSize.x, -texelSize.y); }
  if (length(upRight) < 0.001) { upRight = uv + vec2<f32>(texelSize.x, -texelSize.y); }
  if (length(downLeft) < 0.001) { downLeft = uv + vec2<f32>(-texelSize.x, texelSize.y); }
  if (length(downRight) < 0.001) { downRight = uv + vec2<f32>(texelSize.x, texelSize.y); }

  // When self-heal is high, gently pull torn gaps back toward rest length
  let healBoost = select(1.0, 1.15, selfHeal > 0.5);
  let shearK = stiffness * 0.5;

  if (coord.x > 0u) {
    let delta = pos - leftPos;
    let dist = length(delta);
    let maxDist = tearThreshold * restLen;
    if (dist > restLen && (dist < maxDist || selfHeal > 0.5)) {
      let effective = select(stiffness, stiffness * healBoost * 0.35, dist >= maxDist);
      let correction = (dist - restLen) / dist * 0.5 * effective;
      pos = pos - delta * correction;
    }
  }
  if (coord.x < size.x - 1u) {
    let delta = pos - rightPos;
    let dist = length(delta);
    let maxDist = tearThreshold * restLen;
    if (dist > restLen && (dist < maxDist || selfHeal > 0.5)) {
      let effective = select(stiffness, stiffness * healBoost * 0.35, dist >= maxDist);
      let correction = (dist - restLen) / dist * 0.5 * effective;
      pos = pos - delta * correction;
    }
  }
  if (coord.y > 0u) {
    let delta = pos - upPos;
    let dist = length(delta);
    let maxDist = tearThreshold * restLen;
    if (dist > restLen && (dist < maxDist || selfHeal > 0.5)) {
      let effective = select(stiffness, stiffness * healBoost * 0.35, dist >= maxDist);
      let correction = (dist - restLen) / dist * 0.5 * effective;
      pos = pos - delta * correction;
    }
  }
  if (coord.y < size.y - 1u) {
    let delta = pos - downPos;
    let dist = length(delta);
    let maxDist = tearThreshold * restLen;
    if (dist > restLen && (dist < maxDist || selfHeal > 0.5)) {
      let effective = select(stiffness, stiffness * healBoost * 0.35, dist >= maxDist);
      let correction = (dist - restLen) / dist * 0.5 * effective;
      pos = pos - delta * correction;
    }
  }

  // ── Idea 1: shear springs ───────────────────────────────────────────
  // Bias threads. Same Jacobi correction, half stiffness, rest length on
  // the diagonal, so the cloth resists parallelogram shear.
  if (coord.x > 0u && coord.y > 0u) {
    let delta = pos - upLeft;
    let dist = length(delta);
    let maxDist = tearThreshold * restDiag;
    if (dist > restDiag && (dist < maxDist || selfHeal > 0.5)) {
      let effective = select(shearK, shearK * healBoost * 0.35, dist >= maxDist);
      let correction = (dist - restDiag) / dist * 0.5 * effective;
      pos = pos - delta * correction;
    }
  }
  if (coord.x < size.x - 1u && coord.y > 0u) {
    let delta = pos - upRight;
    let dist = length(delta);
    let maxDist = tearThreshold * restDiag;
    if (dist > restDiag && (dist < maxDist || selfHeal > 0.5)) {
      let effective = select(shearK, shearK * healBoost * 0.35, dist >= maxDist);
      let correction = (dist - restDiag) / dist * 0.5 * effective;
      pos = pos - delta * correction;
    }
  }
  if (coord.x > 0u && coord.y < size.y - 1u) {
    let delta = pos - downLeft;
    let dist = length(delta);
    let maxDist = tearThreshold * restDiag;
    if (dist > restDiag && (dist < maxDist || selfHeal > 0.5)) {
      let effective = select(shearK, shearK * healBoost * 0.35, dist >= maxDist);
      let correction = (dist - restDiag) / dist * 0.5 * effective;
      pos = pos - delta * correction;
    }
  }
  if (coord.x < size.x - 1u && coord.y < size.y - 1u) {
    let delta = pos - downRight;
    let dist = length(delta);
    let maxDist = tearThreshold * restDiag;
    if (dist > restDiag && (dist < maxDist || selfHeal > 0.5)) {
      let effective = select(shearK, shearK * healBoost * 0.35, dist >= maxDist);
      let correction = (dist - restDiag) / dist * 0.5 * effective;
      pos = pos - delta * correction;
    }
  }

  if (coord.y == 0u) {
    pos = uv;
  }

  pos = clamp(pos, vec2<f32>(-0.02), vec2<f32>(1.02));
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(pos, prevPos));
}
