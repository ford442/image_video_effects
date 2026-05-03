// ═══════════════════════════════════════════════════════════════════
//  mosaic-reveal - HDR mosaic reveal with atmospheric tile lighting
//  Category: image
//  Features: upgraded-rgba, depth-aware, mosaic, interactive-reveal,
//            mouse-driven, hdr, tone-mapped, atmospheric
//  Upgraded: 2026-05-03
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

fn toLinear(s: vec3<f32>) -> vec3<f32> { return pow(s, vec3<f32>(2.2)); }
fn toGamma(l: vec3<f32>) -> vec3<f32> { return pow(l, vec3<f32>(1.0 / 2.2)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let aspectVec = vec2<f32>(res.x / res.y, 1.0);
  let time = u.config.x;

  let mosaicSize = mix(20.0, 200.0, u.zoom_params.x);
  let radius = u.zoom_params.y * 0.5;
  let softness = u.zoom_params.z;
  let atmosphere = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

  let tileUV = uv * mosaicSize;
  let uvPix = floor(tileUV) / mosaicSize;
  let uvCenter = uvPix + (0.5 / mosaicSize);
  let fracTile = fract(tileUV);

  let colMosaic = toLinear(textureSampleLevel(readTexture, non_filtering_sampler, uvCenter, 0.0).rgb);
  let colFull = toLinear(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let mask = 1.0 - smoothstep(radius, radius + 0.1 + softness * 0.2, dist);

  // HDR tile bevel with animated shimmer
  let edgeDist = abs(fracTile - 0.5) * 2.0;
  let edgeFactor = max(edgeDist.x, edgeDist.y);
  let shimmer = 0.92 + 0.08 * sin(time * 2.0 + edgeFactor * 12.0 + dot(uvPix, vec2<f32>(17.0, 31.0)));
  let bevel = pow(1.0 - edgeFactor, 3.0) * 0.5 * shimmer;
  let rim = pow(edgeFactor, 4.0) * 0.6 * shimmer;
  let litMosaic = colMosaic * (1.0 + bevel) + vec3<f32>(1.0, 0.82, 0.55) * rim;

  var color = mix(litMosaic, colFull, mask);

  // Golden transition rim glow
  let rimMask = smoothstep(0.35, 0.5, mask) * smoothstep(0.65, 0.5, mask);
  color = color + vec3<f32>(1.0, 0.78, 0.25) * rimMask * atmosphere * 3.0;

  // Atmospheric depth haze
  let haze = depth * atmosphere * 0.4;
  color = mix(color, color * vec3<f32>(0.6, 0.75, 1.0) + vec3<f32>(0.1, 0.14, 0.2), haze);

  // Subtle vignette
  let vig = 1.0 - dot((uv - 0.5) * 1.3, (uv - 0.5) * 1.3);
  color = color * mix(0.85, 1.0, clamp(vig, 0.0, 1.0));

  // Split-tone color grading
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let tint = mix(vec3<f32>(0.78, 0.88, 1.0), vec3<f32>(1.08, 1.0, 0.88), smoothstep(0.15, 0.55, luma));
  color = color * tint;

  // ACES tone map + gamma
  let finalColor = toGamma(acesToneMap(color));

  let baseAlpha = mix(0.85, 1.0, mask);
  let finalAlpha = mix(baseAlpha * 0.8, baseAlpha, depth);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
