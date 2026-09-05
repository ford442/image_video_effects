// Islamic Geometric Tiling — interlaced star polygons, rosettes, and gilded waves
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };
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
  let geometry = clamp(starLine * crossingMask + interlace * (1.0 - crossingMask * 0.3) + rosette * 0.68, 0.0, 2.5);
  let hue = floor(grid.x + grid.y) * 0.071 + angle / TAU + mids * 0.08;
  var raw = vec3<f32>(0.012, 0.018, 0.035);
  raw += palette(hue) * geometry * (0.55 + bass * 0.3);
  raw += vec3<f32>(1.65 + bass * 0.25, 0.92 + mids * 0.22, 0.25 + treble * 0.15) * (starLine * 0.45 + gildedWave * 1.15);
  raw += palette(hue + 0.42) * interlace * treble * 0.48;
  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.94, raw, 0.28 + u.zoom_params.w * 0.06), vec3<f32>(0.0), vec3<f32>(7.0));
  let alpha = clamp(0.035 + geometry * 0.5 + gildedWave * 0.2, 0.035, 0.98);
  let depth = clamp(geometry * 0.34 + depthMoment * 0.34 + gildedWave * 0.18, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(raw, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(raw * 1.08), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
