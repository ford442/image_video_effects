// ═══════════════════════════════════════════════════════════════════
//  Fabric of Reality — strain + tear mask
//  Category: simulation
//  Features: audio-reactive, mouse-driven
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: shear springs (diagonal strain included); catenary tension (verlet); open weave and frayed ends (render)
//  A packing: does not write A. B = (strain, tear, weave phase, debris age)
// ═══════════════════════════════════════════════════════════════════
// zoom_params.y = tearThreshold, .w = selfHeal (reconnect when > ~0.35)

#include "_prelude.wgsl"

const REST_LENGTH: f32 = 1.0;

fn loadPos(c: vec2<i32>, size: vec2<u32>, fallback: vec2<f32>) -> vec2<f32> {
  let hi = vec2<i32>(max(i32(size.x) - 1, 0), max(i32(size.y) - 1, 0));
  let p = textureLoad(dataTextureC, clamp(c, vec2<i32>(0), hi), 0).xy;
  return select(p, fallback, length(p) < 0.001);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let tearThreshold = mix(1.5, 4.0, u.zoom_params.y);
  let selfHeal = u.zoom_params.w;
  let treble = plasmaBuffer[0].z;

  let ic = vec2<i32>(coord);
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let pos = loadPos(ic, size, uv);

  let restLen = texelSize.x * REST_LENGTH;
  let restDiag = length(texelSize) * REST_LENGTH;

  let leftPos = loadPos(ic + vec2<i32>(-1, 0), size, uv + vec2<f32>(-texelSize.x, 0.0));
  let upPos = loadPos(ic + vec2<i32>(0, -1), size, uv + vec2<f32>(0.0, -texelSize.y));
  let upLeft = loadPos(ic + vec2<i32>(-1, -1), size, uv + vec2<f32>(-texelSize.x, -texelSize.y));
  let upRight = loadPos(ic + vec2<i32>(1, -1), size, uv + vec2<f32>(texelSize.x, -texelSize.y));

  var totalStrain = 0.0;
  var isTorn = false;
  if (coord.x > 0u) {
    let d = length(pos - leftPos);
    totalStrain = totalStrain + abs(d - restLen) / max(restLen, 1e-5);
    if (d >= tearThreshold * restLen) { isTorn = true; }
  }
  if (coord.y > 0u) {
    let d = length(pos - upPos);
    totalStrain = totalStrain + abs(d - restLen) / max(restLen, 1e-5);
    if (d >= tearThreshold * restLen) { isTorn = true; }
  }
  // ── Idea 1: shear strain ────────────────────────────────────────────
  // The constraint pass now has bias springs. The mask has to see them
  // or a diagonal rip stays invisible. Half weight so the structural
  // strain still leads.
  if (coord.x > 0u && coord.y > 0u) {
    let d = length(pos - upLeft);
    totalStrain = totalStrain + abs(d - restDiag) / max(restDiag, 1e-5) * 0.5;
    if (d >= tearThreshold * restDiag) { isTorn = true; }
  }
  if (coord.x < size.x - 1u && coord.y > 0u) {
    let d = length(pos - upRight);
    totalStrain = totalStrain + abs(d - restDiag) / max(restDiag, 1e-5) * 0.5;
    if (d >= tearThreshold * restDiag) { isTorn = true; }
  }
  totalStrain = clamp(totalStrain * 2.0, 0.0, 1.0);

  // Prior tear mask (host copies previous frame B→C? — tear writes B fresh each frame;
  // use strain persistence via soft heal fade when selfHeal is active)
  var tearMask = select(0.0, 1.0, isTorn);

  // Self heal: gradually clear tears when springs are near rest length again
  if (selfHeal > 0.35) {
    let healRate = mix(0.88, 0.55, clamp((selfHeal - 0.35) / 0.65, 0.0, 1.0));
    if (totalStrain < 0.35) {
      tearMask = tearMask * healRate;
    } else if (selfHeal > 0.7 && totalStrain < 0.6) {
      tearMask = tearMask * mix(1.0, healRate, 0.5);
    }
  }

  // Treble sparkle on fresh tears
  let weavePhase = fract(uv.x * 12.0 + uv.y * 8.0 + time * 0.2 + treble * 0.1);
  let debrisAge = tearMask * time;

  textureStore(dataTextureB, vec2<i32>(coord),
    vec4<f32>(totalStrain, tearMask, weavePhase, debrisAge));
}
