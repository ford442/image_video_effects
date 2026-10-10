// ═══ LOG-POLAR DROSTE — REMAP ═════════════════════════════════════════════
//  Pass 1 of 2 (graph: remap -> grade, see multipassRegistry "log-polar-droste")
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-10-05
//  Ideas: 1) true Droste scale — r1..r2 log-period around an aspect-correct
//            mouse centre; Recursion Depth = number of nested frame copies
//            composited (outermost copy that fits wins);
//         2) integer branch arms — each arm staggers the ring phase so the
//            rings become an N-strand helix, seamless at the atan2 cut;
//         3) recursion grading — ring level written to A.a, graded in grade.
//  A packing: (linear source rgb, ring level / 6) — read by grade via dataTextureC
//             in the same frame (dataA -> dataC handoff); NOT display RGBA.
// ══════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;
// Idea 1: Droste period. Inner ring radius r1 and per-ring scale r2/r1
// (z-space: frame half-height = 1). Each ring holds the frame shrunk 2.5x.
const DROSTE_R1: f32 = 0.18;
const DROSTE_SCALE: f32 = 2.5;
const LEVEL_NORM: f32 = 6.0;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let zoom = mix(0.2, 1.2, u.zoom_params.x);
  let spiral = mix(0.0, 2.5, u.zoom_params.y);
  // Idea 1: Recursion Depth = how many nested copies are composited (1..3).
  let layers = 1 + i32(clamp(u.zoom_params.z, 0.0, 1.0) * 2.999);
  // Idea 2: integer arm count (0 = plain concentric rings).
  let arms = floor(mix(0.0, 6.0, u.zoom_params.w) + 1e-3);

  // Idea 1: aspect-correct centre that follows the mouse (0.5,0.5 untouched).
  let aspectV = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let cz = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0 * aspectV;
  let z = (uv - vec2<f32>(0.5)) * 2.0 * aspectV - cz;
  let r = length(z);
  let a = atan2(z.y, z.x);
  let logR = log(max(r, 1e-4));
  let period = log(DROSTE_SCALE);
  let logR1 = log(DROSTE_R1);

  // Idea 2: arm index along the angle. Arm k's rings are pushed out by
  // k/arms of a period (plus the continuous in-arm fraction), so a full turn
  // shifts by exactly `arms` periods -> the wrap below hides the atan2 cut.
  let aw = a + select(0.0, TAU, a < 0.0);
  let armPos = select(0.0, aw / (TAU / max(arms, 1.0)), arms >= 1.0);
  let armShift = (floor(armPos) + fract(armPos)) * period;

  // Zoom phase: audio nudges the phase additively (never scales time).
  let phase = time * zoom * 0.4 + bass * 0.08;
  let g = (logR - phase - armShift - logR1) / period;
  let ringN = floor(g);
  let rhoW = logR1 + (g - ringN) * period;

  // Spiral twist on the unwrapped radius keeps ring boundaries continuous.
  let ang = a + logR * spiral * 0.75 + time * 0.1;
  let dir = vec2<f32>(cos(ang), sin(ang));

  // Idea 1: composite nested copies front-to-back, largest scale first; a
  // copy only counts where its sample lands inside the frame, so with enough
  // depth the ring boundary disappears (true Droste), with less it shows.
  var col = vec3<f32>(0.0);
  var acc = 0.0;
  for (var k = 0; k < 3; k = k + 1) {
    if (k >= layers) { break; }
    let kk = f32(layers - 1 - k);
    let q = cz + dir * exp(rhoW + kk * period);
    let su = (q / aspectV) * 0.5 + vec2<f32>(0.5);
    let edge = min(min(su.x, 1.0 - su.x), min(su.y, 1.0 - su.y));
    let m = select(smoothstep(0.0, 0.015, edge), 1.0, kk < 0.5);
    let s = textureSampleLevel(readTexture, u_sampler, clamp(su, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    col += (1.0 - acc) * m * s.rgb;
    acc += (1.0 - acc) * m;
  }

  // Idea 3: ring level — uniform within a ring, 0 at the frame edge, +1 per
  // nested generation inward; drifts smoothly with the zoom (no pops).
  let gEdge = (0.0 - phase - armShift - logR1) / period;   // log(1.0) = 0
  let level = max(gEdge - ringN, 0.0);
  textureStore(dataTextureA, pixel, vec4<f32>(col, clamp(level / LEVEL_NORM, 0.0, 1.0)));
}
