// ═══════════════════════════════════════════════════════════════════
//  Sonic Boom v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, mach-cone, prandtl-glauert,
//            shock-diamonds, condensation-fog, aces-tone-map
//  Complexity: High
//  Upgraded: 2026-05-30
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

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

const PHI: f32 = 1.61803398874989484820;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let dim = vec2<i32>(i32(u.config.z), i32(u.config.w));
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(f32(dim.x), f32(dim.y));
  let aspect = vec2<f32>(f32(dim.x) / f32(dim.y), 1.0);

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let radius   = u.zoom_params.x;
  let width    = u.zoom_params.y;
  let strength = u.zoom_params.z * (1.0 + bass * 0.6);
  let split    = u.zoom_params.w;

  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let to_pixel = (uv - mouse_pos) * aspect;
  let dist = length(to_pixel);
  let dir = to_pixel / max(dist, 1e-4);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let atmDensity = 0.5 + depth * 0.5;

  let machNum = 0.8 + strength * 1.4 + bass * 0.4;
  let machAngle = asin(clamp(1.0 / max(machNum, 1.001), 0.0, 1.0));
  let coneDist = abs(dist - radius) / max(machAngle, 0.01);

  let widthHalf = max(width * 0.5, 1e-4);
  let invWH = 1.0 / widthHalf;
  let d0 = (dist - radius) * invWH;
  let d1 = (dist - radius / PHI) * invWH;
  let d2 = (dist - radius / (PHI * PHI)) * invWH;
  let ring0 = exp(-d0 * d0 * 4.0);
  let ring1 = exp(-d1 * d1 * 6.0) * 0.55;
  let ring2 = exp(-d2 * d2 * 8.0) * 0.30;
  let ringSum = ring0 + ring1 + ring2;

  let diamondPhase = sin(coneDist * 12.0 * PHI) * 0.5 + 0.5;
  let shockDiamond = diamondPhase * ring0 * 0.4 * select(0.0, 1.0, machNum > 1.0);

  let condensation = exp(-coneDist * coneDist * 2.0) * atmDensity * (0.3 + bass * 0.4) * select(0.0, 1.0, machNum > 0.95);
  let fogScatter = condensation * 0.5 * (1.0 + mids * 0.5);

  let prevTail = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
  let ringFinal = max(ringSum, prevTail * 0.82);

  let distortion = dir * ringFinal * strength * 0.12 * (1.0 + mids * 0.3);
  let velocity = ringFinal * strength * (1.0 + bass * 0.5);
  let caStrength = split * (1.0 + velocity * 3.0);
  let doppler = (ring0 - ring2) * split * 10.0;

  let uv_r = clamp(uv - distortion * (1.0 + caStrength * 1.5 + doppler), vec2<f32>(0.0), vec2<f32>(1.0));
  let uv_g = clamp(uv - distortion, vec2<f32>(0.0), vec2<f32>(1.0));
  let uv_b = clamp(uv - distortion * (1.0 - caStrength * 1.5 - doppler), vec2<f32>(0.0), vec2<f32>(1.0));

  let c = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

  let shockFront = ring0 * (0.6 + treble * 0.4);
  let bloom = vec3<f32>(0.9, 0.95, 1.0) * shockFront * 0.35;
  let diamondColor = vec3<f32>(0.6, 0.8, 1.0) * shockDiamond * (1.0 + treble * 0.5);
  let fogColor = vec3<f32>(0.85, 0.88, 0.92) * fogScatter;

  var finalColor = vec3<f32>(r, c.g, b);
  finalColor = finalColor + bloom + diamondColor + fogColor;
  finalColor = aces_tonemap(finalColor * (1.0 + shockFront * 0.3));

  let shockIntensity = clamp(ringSum + shockDiamond + shockFront * 0.5, 0.0, 1.0);
  let alpha = clamp(shockIntensity * condensation * depth * 1.2 + abs(doppler) * 0.4 + treble * 0.06, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
