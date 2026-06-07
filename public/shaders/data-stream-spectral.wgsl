// ═══════════════════════════════════════════════════════════════════
//  data-stream-spectral
//  Category: advanced-hybrid
//  Features: mouse-driven, data-stream, spectral-decomposition
//  Complexity: High
//  Chunks From: data-stream.wgsl, alpha-spectral-decompose.wgsl
//  Created: 2026-04-18
//  By: Agent CB-18
// ═══════════════════════════════════════════════════════════════════
//  Matrix-style data strips carry spectrally-decomposed frequency
//  bands. Each strip samples a different frequency band (low, mid-low,
//  mid-high, high) tinted per band. Mouse turbulence scatters strips.
//  Alpha stores total spectral energy.
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;

  let speed = u.zoom_params.x;
  let density = u.zoom_params.y;
  let turbulence = u.zoom_params.z;
  let glow = u.zoom_params.w;

  let mouseDist = length(uv - mousePos);
  let interact = smoothstep(0.3, 0.0, mouseDist) * turbulence;

  let numStrips = 20.0 + density * 100.0;
  let stripIdx = floor(uv.x * numStrips);
  let rand = fract(sin(stripIdx * 12.9898) * 43758.5453);

  // Flow with mouse wake
  let flowSpeed = (rand * 0.5 + 0.5) * speed * 0.5;
  let xOffset = interact * sin(uv.y * 10.0 + time * 5.0) * 0.05;

  var sampleUV = uv;
  sampleUV.x = sampleUV.x + xOffset;
  sampleUV.y = sampleUV.y - time * flowSpeed;
  sampleUV.y = fract(sampleUV.y);

  if (rand > 0.8) {
    sampleUV.y = sampleUV.y + sin(time * 10.0) * 0.01;
  }

  // Spectral decomposition: sample at different scales per strip band
  let band = u32(stripIdx) % 4u;
  var color = vec3<f32>(0.0);
  var spectralEnergy = 0.0;

  if (band == 0u) {
    // Low frequency: large blur
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 8; i++) {
      let angle = f32(i) * 6.283185307 / 8.0;
      let off = vec2<f32>(cos(angle), sin(angle)) * 4.0 / res.x;
      acc += textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    color = acc / 8.0;
    spectralEnergy = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = color * vec3<f32>(1.0, 0.8, 0.6);
  } else if (band == 1u) {
    // Mid-low
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 6; i++) {
      let angle = f32(i) * 6.283185307 / 6.0;
      let off = vec2<f32>(cos(angle), sin(angle)) * 2.0 / res.x;
      acc += textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    color = acc / 6.0;
    spectralEnergy = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = color * vec3<f32>(0.6, 1.0, 0.7);
  } else if (band == 2u) {
    // Mid-high
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 4; i++) {
      let angle = f32(i) * 6.283185307 / 4.0;
      let off = vec2<f32>(cos(angle), sin(angle)) * 1.0 / res.x;
      acc += textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    color = acc / 4.0;
    spectralEnergy = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = color * vec3<f32>(0.5, 0.7, 1.0);
  } else {
    // High frequency: fine detail
    color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let blurred = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(1.0, 0.0) / res, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    color = color - blurred * 0.5;
    spectralEnergy = length(color);
    color = color * vec3<f32>(1.0, 1.0, 1.0);
  }

  // Digital artifacts
  let blockY = floor(uv.y * 50.0);
  let noise = fract(sin(dot(vec2<f32>(stripIdx, blockY), vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let bright = step(0.98, noise * (sin(time * 2.0 + stripIdx) * 0.5 + 0.5));

  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let digitalColor = vec3<f32>(0.0, lum * 1.5, lum * 0.2);
  let finalRGB = mix(color, digitalColor, glow);
  let outputColor = finalRGB + vec3<f32>(0.0, bright * glow, 0.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outputColor, spectralEnergy));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
