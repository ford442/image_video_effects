// ═══════════════════════════════════════════════════════════════════
//  data-scanner-gabor
//  Category: advanced-hybrid
//  Features: mouse-driven, gabor-filter-bank, edge-detection
//  Complexity: Very High
//  Chunks From: data-scanner.wgsl, conv-gabor-texture-analyzer.wgsl
//  Created: 2026-04-18
//  By: Agent CB-17
// ═══════════════════════════════════════════════════════════════════
//  A scanning bar that analyzes texture using a Gabor filter bank.
//  Inside the scan zone, oriented textures are detected at 0, 45,
//  90, and 135 degrees, mapped to psychedelic colors. The bar
//  follows the mouse and highlights dominant orientations.
// ═══════════════════════════════════════════════════════════════════

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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn gaborResponse(uv: vec2<f32>, theta: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> f32 {
  var response = 0.0;
  let radius = i32(ceil(sigma * 3.0));
  let maxRadius = min(radius, 6);
  let cosTheta = cos(theta);
  let sinTheta = sin(theta);

  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let x = f32(dx);
      let y = f32(dy);
      let xTheta = x * cosTheta + y * sinTheta;
      let yTheta = -x * sinTheta + y * cosTheta;
      let gaussian = exp(-(xTheta*xTheta + yTheta*yTheta) / (2.0 * sigma * sigma + 0.001));
      let sinusoidal = cos(2.0 * 3.14159265 * freq * xTheta);
      let kernel = gaussian * sinusoidal;
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
      response += luma * kernel;
    }
  }
  return response;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(gid.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;

  let freq = mix(0.05, 0.3, u.zoom_params.x);
  let sigma = mix(1.5, 4.0, u.zoom_params.y);
  let responseScale = mix(0.5, 3.0, u.zoom_params.z);
  let scanWidth = mix(0.05, 0.25, u.zoom_params.w);

  var mouse = u.zoom_config.yz;
  let scan_x = mouse.x;

  let dist = abs(uv.x - scan_x);
  let in_scan = smoothstep(scanWidth, scanWidth - 0.01, dist);

  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  if (in_scan > 0.0) {
    // Gabor analysis inside scan bar
    let r0 = gaborResponse(uv, 0.0, freq, sigma, pixelSize) * responseScale;
    let r45 = gaborResponse(uv, 0.785398, freq, sigma, pixelSize) * responseScale;
    let r90 = gaborResponse(uv, 1.570796, freq, sigma, pixelSize) * responseScale;
    let r135 = gaborResponse(uv, 2.356194, freq, sigma, pixelSize) * responseScale;

    let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));
    let pal135 = palette(r135 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33));

    var analyzed = vec3<f32>(0.0);
    analyzed += pal0 * abs(r0);
    analyzed += pal45 * abs(r45);
    analyzed += pal90 * abs(r90);
    analyzed += pal135 * abs(r135);

    let totalResponse = abs(r0) + abs(r45) + abs(r90) + abs(r135) + 0.001;
    analyzed = analyzed / totalResponse;
    analyzed = analyzed * 1.3;

    // Grid overlay
    let grid_uv = fract(uv * 40.0);
    let grid = step(0.95, grid_uv.x) + step(0.95, grid_uv.y);
    let grid_color = vec3<f32>(0.0, 0.5, 0.0);
    analyzed = max(analyzed, grid_color * grid);

    // Scan bar border
    let border_line = smoothstep(scanWidth - 0.005, scanWidth, dist) * (1.0 - smoothstep(scanWidth, scanWidth + 0.005, dist));
    analyzed += vec3<f32>(1.0, 1.0, 1.0) * border_line * 4.0;

    color = mix(color, analyzed, in_scan * 0.9);
  } else {
    color *= 0.4;
  }

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
