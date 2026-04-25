// ═══════════════════════════════════════════════════════════════════
//  cyber-scan-gabor
//  Category: advanced-hybrid
//  Features: cyber-scan, gabor-filter-bank, advanced-convolution, mouse-driven
//  Complexity: Very High
//  Chunks From: cyber-scan, conv-gabor-texture-analyzer
//  Created: 2026-04-18
//  By: Agent CB-15 — Visual Effects & Distortion Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Cybernetic scanning line combined with Gabor texture analysis.
//  The scan band reveals oriented edge responses from the Gabor filter
//  bank in real-time, creating a cybernetic texture segmentation display.
//  Grid intensity maps to Gabor response magnitude.
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;

  let scanWidth = u.zoom_params.x * 0.4 + 0.05;
  let gridIntensity = u.zoom_params.y;
  let colorSpeed = u.zoom_params.z * 5.0;
  let freq = mix(0.05, 0.3, u.zoom_params.w);
  let sigma = mix(1.5, 4.0, 0.4);
  let responseScale = mix(0.5, 3.0, 0.5);

  // Scan band
  let distY = abs(uv.y - mousePos.y);
  let scanMask = 1.0 - smoothstep(scanWidth * 0.5, scanWidth, distY);

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var finalColor = baseColor;

  if (scanMask > 0.01) {
    // Gabor filter bank at this pixel
    let mouseAngle = atan2(mousePos.y - 0.5, mousePos.x - 0.5);
    let rotationOffset = mouseAngle * 0.5 + time * 0.1;

    let r0 = gaborResponse(uv, 0.0 + rotationOffset, freq, sigma, pixelSize) * responseScale;
    let r45 = gaborResponse(uv, 0.785398 + rotationOffset, freq, sigma, pixelSize) * responseScale;
    let r90 = gaborResponse(uv, 1.570796 + rotationOffset, freq, sigma, pixelSize) * responseScale;
    let r135 = gaborResponse(uv, 2.356194 + rotationOffset, freq, sigma, pixelSize) * responseScale;

    // Psychedelic palette mapping
    let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));
    let pal135 = palette(r135 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33));

    var gaborColor = vec3<f32>(0.0);
    gaborColor += pal0 * abs(r0);
    gaborColor += pal45 * abs(r45);
    gaborColor += pal90 * abs(r90);
    gaborColor += pal135 * abs(r135);
    let totalResponse = abs(r0) + abs(r45) + abs(r90) + abs(r135) + 0.001;
    gaborColor = gaborColor / totalResponse * 1.3;

    // Edge detection for cyber effect
    let stepX = 1.0 / resolution.x;
    let stepY = 1.0 / resolution.y;
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -stepY), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-stepX, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb;
    let edgeX = length(r - l);
    let edgeY = length(b - t);
    let edgeVal = length(vec2<f32>(edgeX, edgeY));

    // Cyber grid
    let gridScale = 50.0;
    let gridX = abs(sin(uv.x * gridScale * 3.14159));
    let gridY = abs(sin(uv.y * gridScale * 3.14159));
    let gridVal = smoothstep(0.95, 1.0, max(gridX, gridY));

    // Cyber color cycling
    let hue = (time * colorSpeed) % 6.28;
    let cyberColor = vec3<f32>(
      0.5 + 0.5 * sin(hue),
      0.5 + 0.5 * sin(hue + 2.09),
      0.5 + 0.5 * sin(hue + 4.18)
    );

    // Combine: Gabor responses as cyber texture, edges highlighted
    let effectColor = mix(gaborColor, cyberColor, gridVal * gridIntensity);
    let edgeColor = cyberColor * edgeVal * 3.0;
    let mixed = effectColor + edgeColor;

    // Scanlines
    let scanline = sin(uv.y * resolution.y * 0.5) * 0.1;

    let processed = mixed + scanline;
    finalColor = vec4<f32>(mix(baseColor.rgb, processed, scanMask), baseColor.a);
  } else {
    finalColor = vec4<f32>(baseColor.rgb * 0.85, baseColor.a);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
