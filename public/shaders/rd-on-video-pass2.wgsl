// ═══════════════════════════════════════════════════════════════════
//  RD on Video (Pass 2: Turing Color Map)
//  Category: simulation
//  Features: multi-pass-2, temporal, turing-color-map, upgraded-rgba
//  Upgraded: 2026-10-17
//  Ideas: isochrone threads at one-third and two-thirds; substrate core where U is depleted
//  A packing: B = pre-ACES palette rgb + pattern. Does not write A.
//  Pass graph: reads previous-frame chemistry from dataTextureC and writes
//              the colorized field to dataTextureB.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn palette(t: f32) -> vec3<f32> {
  let c1 = vec3<f32>(0.04, 0.08, 0.22);
  let c2 = vec3<f32>(0.12, 0.70, 0.55);
  let c3 = vec3<f32>(0.95, 0.60, 0.22);
  let c4 = vec3<f32>(1.00, 0.92, 0.68);
  let a = smoothstep(0.0, 0.35, t);
  let b = smoothstep(0.35, 0.75, t);
  let c = smoothstep(0.75, 1.0, t);
  return mix(mix(c1, c2, a), mix(c3, c4, c), b);
}

fn loadNeighborB(coord: vec2<i32>, offset: vec2<i32>, maxCoord: vec2<i32>) -> f32 {
  return textureLoad(dataTextureC, clamp(coord + offset, vec2<i32>(0, 0), maxCoord), 0).g;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let coord = vec2<i32>(gid.xy);
  let maxCoord = vec2<i32>(i32(res.x) - 1, i32(res.y) - 1);

  let state = textureLoad(dataTextureC, coord, 0);
  let b = clamp(state.g, 0.0, 1.0);
  let lumaSeed = clamp(state.b, 0.0, 1.0);

  let leftB = loadNeighborB(coord, vec2<i32>(-1, 0), maxCoord);
  let rightB = loadNeighborB(coord, vec2<i32>(1, 0), maxCoord);
  let downB = loadNeighborB(coord, vec2<i32>(0, -1), maxCoord);
  let upB = loadNeighborB(coord, vec2<i32>(0, 1), maxCoord);
  let edge = clamp(abs((leftB + rightB + downB + upB) - 4.0 * b) * 4.0, 0.0, 1.0);

  let concentrationGamma = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let edgeGain = mix(0.10, 0.70, clamp(u.zoom_params.y, 0.0, 1.0));
  let seedGain = mix(0.05, 0.35, clamp(u.zoom_params.z, 0.0, 1.0));
  let hueOffset = (u.zoom_params.w - 0.5) * 0.35;

  let pattern = clamp(pow(b, concentrationGamma) + edge * edgeGain + lumaSeed * seedGain, 0.0, 1.0);
  var colorized = palette(fract(pattern + hueOffset));
  // Idea 1: isochrone threads — level sets of the Turing field, in the next stop.
  let iso = clamp(exp(-abs(pattern - 0.33) * 48.0) + exp(-abs(pattern - 0.66) * 48.0), 0.0, 1.0);
  colorized = mix(colorized, palette(fract(pattern + hueOffset + 0.12)), iso * 0.7);
  // Idea 2: substrate core — depleted U (state.r low) cools the interior of a high-V spot.
  let substrate = smoothstep(0.32, 0.62, b) * smoothstep(0.9, 0.4, state.r);
  colorized = mix(colorized, colorized * vec3<f32>(0.45, 0.72, 1.25), substrate * 0.6);

  textureStore(dataTextureB, coord, vec4<f32>(colorized, pattern));
  let shown = aces(max(colorized, vec3<f32>(0.0)));
  let alpha = clamp(state.a * 0.65 + pattern * 0.35, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(shown, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
