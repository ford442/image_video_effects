// ═══════════════════════════════════════════════════════════════════
//  Interactive Zoom Blur
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) {
    return;
  }
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001));

  // Audio reactivity
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Mouse Input (branchless)
  let mouse = u.zoom_config.yz;
  let center = select(vec2<f32>(0.5, 0.5), mouse, mouse.x >= 0.0);

  // Parameters
  let blurStrength = clamp(u.zoom_params.x * (1.0 + bass * 0.2), 0.0, 1.0) * 0.1;
  let samplesFloat = mix(4.0, 32.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let centerBias   = clamp(u.zoom_params.z * (1.0 + mids * 0.15), 0.0, 1.0);
  let aberration   = clamp(u.zoom_params.w * (1.0 + treble * 0.1), 0.0, 1.0) * 0.05;

  let aspect = resolution.x / max(resolution.y, 0.001);
  let uv_aspect = uv * vec2<f32>(aspect, 1.0);
  let center_aspect = center * vec2<f32>(aspect, 1.0);

  // Direction vector from pixel to mouse center
  let dir = center_aspect - uv_aspect;
  let dirUV = center - uv;

  var color = vec3<f32>(0.0);
  var totalWeight = 0.0;

  // Random dither to break banding
  let random = max(fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453), 0.001);
  let samples = i32(samplesFloat);

  for (var i = 0; i < samples; i = i + 1) {
    let t = (f32(i) + random) / max(f32(samples), 0.0001);

    // Non-linear sampling weight (branchless)
    let weight = select(1.0, max(mix(1.0, 1.0 - t, centerBias), 0.001), centerBias > 0.0);

    let percent = t * blurStrength;

    // Sample R, G, B with slight offsets for aberration (clamped)
    let sampleUV = clamp(uv + dirUV * percent, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - dirUV * aberration * t, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + dirUV * aberration * t, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    color = color + vec3<f32>(r, g, b) * weight;
    totalWeight = totalWeight + weight;
  }

  color = color / max(totalWeight, 0.001);

  // Alpha: blur haze weight — stronger blur streaks = higher compositing blend
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let blurMag = length(dirUV) * blurStrength;
  let alpha = clamp(blurMag * 4.0 + luma * 0.3 + 0.1, 0.0, 1.0);
  let finalColor = vec4<f32>(color, alpha);

  // Depth read and mandatory writes
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
