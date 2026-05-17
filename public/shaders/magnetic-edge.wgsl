// ═══════════════════════════════════════════════════════════════════
//  Magnetic Edge
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let pullStrength = (0.05 + u.zoom_params.x * 0.2) * (1.0 + bass * 0.3);
  let radius = 0.3 + u.zoom_params.y * 0.5;
  let edgeThreshold = 0.1 + u.zoom_params.z * 0.4;
  let glow = u.zoom_params.w * (1.0 + mids);

  let texel = 1.0 / resolution.x;
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let cl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel, 0.0), 0.0).rgb;
  let cr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel, 0.0), 0.0).rgb;
  let ct = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel), 0.0).rgb;
  let cb = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel), 0.0).rgb;

  let dX = length(cr - cl);
  let dY = length(cb - ct);
  let edge = sqrt(dX*dX + dY*dY);

  let aspect = resolution.x / resolution.y;
  let dVec = mouse - uv;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  let isEdge = edge > edgeThreshold;
  let isNear = dist < radius;
  let influence = smoothstep(radius, 0.0, dist);
  let clickBoost = select(1.0, 2.0, mouseDown);

  let displacement = select(vec2<f32>(0.0), dVec * influence * pullStrength * clickBoost, isEdge && isNear && mouse.x >= 0.0);
  let finalUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));

  var finalColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

  let glowMask = select(0.0, glow * (1.0 - dist / radius) * influence, glow > 0.0 && isEdge && isNear);
  finalColor += vec4<f32>(glowMask, glowMask * 0.5, 0.0, 0.0);

  let alpha = clamp(finalColor.a + glowMask * 0.3 + influence * 0.2, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(finalColor.rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalColor.rgb, alpha));
}
