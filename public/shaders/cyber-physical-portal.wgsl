// ================================================================
//  Cyber Physical Portal
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, portal
//  Complexity: Medium
//  Chunks From: cyber-physical-portal
//  Created: 2026-05-31
//  By: Copilot
// ================================================================

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
  zoom_params: vec4<f32>,  // x=PortalRadius, y=SwirlAmount, z=GridDensity, w=Glow
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let portalRadius = mix(0.06, 0.45, u.zoom_params.x);
  let swirlAmount = mix(0.0, 3.4, u.zoom_params.y);
  let gridDensity = mix(6.0, 44.0, u.zoom_params.z);
  let glow = mix(0.05, 0.7, u.zoom_params.w);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let mask = 1.0 - smoothstep(portalRadius, portalRadius + 0.03, dist);
  let swirl = swirlAmount * mask * (1.0 - dist / max(portalRadius, 1e-4));
  let portalUV = clamp(mouse + rotate(centered, swirl) / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let portalSrc = textureSampleLevel(readTexture, u_sampler, portalUV, 0.0).rgb;
  let grid = abs(fract(vec2<f32>(atan2(centered.y, centered.x) * 1.5, dist) * gridDensity + vec2<f32>(time * 0.2, -time * 0.5)) - 0.5);
  let ring = 1.0 - smoothstep(0.0, 0.04, min(grid.x, grid.y));
  let core = 1.0 - smoothstep(0.0, portalRadius * 0.55, dist);
  let portalTint = mix(vec3<f32>(0.12, 0.95, 1.0), vec3<f32>(0.95, 0.25, 1.0), 0.5 + 0.5 * sin(time * 1.2 + dist * 16.0));

  var portalColor = mix(portalSrc, portalSrc * vec3<f32>(0.35, 1.0, 0.65) + portalTint * 0.35, 0.55);
  portalColor = portalColor + portalTint * (ring * 0.18 + core * (glow + audio.x * 0.18));
  let finalColor = mix(src.rgb, portalColor, mask);
  let finalAlpha = clamp(mix(src.a, 0.74 + ring * 0.12 + core * 0.10, mask), 0.06, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, portalUV, 0.0).r;
  let outDepth = clamp(mix(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, baseDepth, mask), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(mask, ring, core, finalAlpha));
}
