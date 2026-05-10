// ═══════════════════════════════════════════════════════════════════
//  CRT Clear Zone
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Phase A Upgrade Swarm
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Distortion, y=Aberration, z=ClearRadius, w=ScanlineIntensity
  ripples: array<vec4<f32>, 50>,
};

fn crt_curve(uv: vec2<f32>, bend: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    let f = 1.0 + r2 * (bend * 0.5) + r2 * r2 * (bend * 0.1);
    return centered * f + 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coords = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let bendAmount = mix(0.1, 2.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let aberration = mix(0.001, 0.02, clamp(u.zoom_params.y, 0.0, 1.0));
  let clearRadius = mix(0.1, 0.4, clamp(u.zoom_params.z, 0.0, 1.0));
  let scanlineInt = mix(0.1, 0.8, clamp(u.zoom_params.w, 0.0, 1.0)) * (1.0 + bass * 0.2);

  var mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

  let crtUV = crt_curve(uv, bendAmount);

  var crtColor = vec3<f32>(0.0);
  let in_bounds = crtUV.x >= 0.0 && crtUV.x <= 1.0 && crtUV.y >= 0.0 && crtUV.y <= 1.0;
  if (in_bounds) {
      let r = textureSampleLevel(readTexture, u_sampler, crtUV + vec2<f32>(aberration, 0.0), 0.0).r;
      let g = textureSampleLevel(readTexture, u_sampler, crtUV, 0.0).g;
      let b = textureSampleLevel(readTexture, u_sampler, crtUV - vec2<f32>(aberration, 0.0), 0.0).b;
      crtColor = vec3<f32>(r, g, b);

      let scanline = sin(crtUV.y * resolution.y * 0.5 + time * 10.0) * 0.5 + 0.5;
      crtColor = crtColor * (1.0 - scanline * scanlineInt);

      let vign = 16.0 * crtUV.x * crtUV.y * (1.0 - crtUV.x) * (1.0 - crtUV.y);
      crtColor = crtColor * pow(max(vign, 0.001), 0.2);
  }

  let cleanColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  let dist = distance(uv, mouse);
  let mask = smoothstep(clearRadius, max(clearRadius - 0.05, 0.001), dist);

  let edge = smoothstep(clearRadius + 0.02, clearRadius, dist) - smoothstep(clearRadius, max(clearRadius - 0.02, 0.001), dist);
  let glowColor = vec3<f32>(0.2, 0.8, 1.0) * edge * 2.0;

  var finalColor = mix(crtColor, cleanColor, mask) + glowColor;

  let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(mask * 0.5 + (1.0 - mask) * (luma * 0.6 + f32(in_bounds) * 0.3) + edge * 0.4, 0.0, 1.0);

  textureStore(writeTexture, coords, vec4<f32>(finalColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
