// ═══════════════════════════════════════════════════════════════════
//  Islamic Geometric Tiling
//  Category: generative
//  Features: star-polygons, rosette, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: over-under strap shadow at crossings; half-angle girih dart; gold leaf specular glints; ceramic tile glaze imperfections
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;
fn rotate2(p: vec2<f32>, a: f32) -> vec2<f32> { let c=cos(a); let s=sin(a); return vec2<f32>(c*p.x-s*p.y,s*p.x+c*p.y); }
fn palette(t: f32) -> vec3<f32> { return vec3<f32>(0.5)+vec3<f32>(0.5)*cos(TAU*(vec3<f32>(t)+vec3<f32>(0.08,0.38,0.7))); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> { return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),vec3<f32>(0.0),vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv01 = (vec2<f32>(pixel) + vec2<f32>(0.5)) / res;
  let aspect = res.x / res.y;
  let p = (uv01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let points = 6.0 + floor(clamp(u.zoom_params.x, 0.0, 1.0) * 10.0 + 0.5);
  let tileScale = mix(2.5, 10.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let lineWidth = mix(0.065, 0.012, clamp(u.zoom_params.z, 0.0, 1.0));
  let ornamentDepth = 1.0 + floor(clamp(u.zoom_params.w, 0.0, 1.0) * 4.0 + 0.5);
  let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let pointerTwist = exp(-distance(p, mouse) * 5.5) * held;
  let grid = p * tileScale;
  let row = floor(grid.y);
  let offset = select(0.0, 0.5, fract(row * 0.5) > 0.25);
  var cell = fract(grid + vec2<f32>(offset, 0.0)) - vec2<f32>(0.5);
  cell = rotate2(cell, time * 0.025 + pointerTwist * 0.28 + mids * 0.025);
  let radius = length(cell);
  let angle = atan2(cell.y, cell.x);
  let starRadius = 0.27 + 0.115 * cos(angle * points);
  let starLine = exp(-abs(radius - starRadius) / max(lineWidth, 0.002));
  let interlace = exp(-abs(radius - (0.19 + 0.055 * cos(angle * points * 2.0 + 0.9))) / max(lineWidth * 0.72, 0.0015));
  let crossingMask = 0.58 + 0.42 * step(0.0, sin(angle * points + time * 0.12));
  let dartR = 0.22 + 0.08 * cos((angle + TAU / max(points * 2.0, 1.0)) * points);
  let dart = exp(-abs(radius - dartR) / max(lineWidth * 0.85, 0.0015));
  let overlap = starLine * interlace;
  let underShadow = overlap * crossingMask;

  // Idea 1: gold leaf specular glints at star vertices
  let vertexPhase = cos(angle * points);
  let glint = smoothstep(0.96, 1.0, vertexPhase) * exp(-abs(radius - starRadius) / max(lineWidth * 0.5, 0.001));

  // Idea 2: ceramic tile glaze imperfections
  let glazeNoise = (sin(grid.x * 4.1 + time * 0.2) * cos(grid.y * 3.7 - time * 0.15)) * 0.5 + 0.5;
  let glaze = glazeNoise * 0.08;

  var rosette = 0.0;
  var depthMoment = 0.0;
  for (var layer = 0; layer < 5; layer++) {
    if (f32(layer) >= ornamentDepth) { break; }
    let lf = f32(layer);
    let ring = 0.09 + lf * 0.065 + 0.018 * cos(angle * (points + lf * 2.0) - time * (0.08 + lf * 0.02));
    let band = exp(-abs(radius - ring) / max(lineWidth * (0.82 - lf * 0.08), 0.0015));
    rosette += band / (1.0 + lf * 0.25);
    depthMoment += band * (lf + 1.0) / 5.0;
  }

  var gildedWave = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age > 0.0 && age < 3.2) {
      let center = (ripple.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
      gildedWave += exp(-abs(distance(p, center) - age * 0.24) * 74.0) * exp(-age * 1.25);
    }
  }
  let starOver = starLine * crossingMask;
  let laceUnder = interlace * (1.0 - crossingMask * 0.55);
  let geometry = clamp(starOver + laceUnder * (1.0 - crossingMask * 0.3) + rosette * 0.68 + dart * 0.72, 0.0, 2.5);
  let hue = floor(grid.x + grid.y) * 0.071 + angle / TAU + mids * 0.08;
  var raw = vec3<f32>(0.012, 0.018, 0.035) + glaze * vec3<f32>(0.1, 0.15, 0.2);
  raw += palette(hue) * geometry * (0.55 + bass * 0.3);
  raw += vec3<f32>(1.65 + bass * 0.25, 0.92 + mids * 0.22, 0.25 + treble * 0.15) * (starLine * 0.45 + gildedWave * 1.15 + glint * 2.5);
  raw += palette(hue + 0.42) * interlace * treble * 0.48;
  raw += vec3<f32>(1.55, 1.05, 0.32) * dart * 0.38;
  raw *= 1.0 - underShadow * 0.42;
  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.94, raw, 0.28 + u.zoom_params.w * 0.06), vec3<f32>(0.0), vec3<f32>(7.0));
  let alpha = clamp(0.035 + geometry * 0.5 + dart * 0.12 + gildedWave * 0.2 + glint * 0.2 + glaze, 0.035, 0.98);
  let depth = clamp(geometry * 0.34 + depthMoment * 0.34 + dart * 0.12 + gildedWave * 0.18, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(raw, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(raw * 1.08), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
