// ═══════════════════════════════════════════════════════════════════
//  RD on Video (Pass 3: Composite Over Video)
//  Category: simulation
//  Features: multi-pass-3, video-composite, luma-mask
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
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let coord = vec2<i32>(gid.xy);

  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let overlay = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let luma = dot(base.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

  let lumaGate = mix(0.15, 0.80, clamp(u.zoom_params.x, 0.0, 1.0));
  let maskSoftness = mix(0.05, 0.35, clamp(u.zoom_params.y, 0.0, 1.0));
  let glowGain = mix(0.4, 2.2, clamp(u.zoom_params.z, 0.0, 1.0));
  let blendGain = mix(0.2, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

  let lumaMask = smoothstep(lumaGate - maskSoftness, lumaGate + maskSoftness, luma);
  let simMask = clamp(overlay.a * glowGain, 0.0, 1.0);
  let blend = clamp(simMask * blendGain * lumaMask, 0.0, 1.0);

  var outColor = mix(base.rgb, base.rgb + overlay.rgb * (0.7 + simMask), blend);
  outColor = clamp(outColor, vec3<f32>(0.0), vec3<f32>(1.0));

  textureStore(writeTexture, coord, vec4<f32>(outColor, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
