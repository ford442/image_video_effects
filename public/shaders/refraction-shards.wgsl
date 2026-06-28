// ================================================================
//  Refraction Shards
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Chunks From: refraction-shards
//  Created: 2026-05-30
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
  zoom_params: vec4<f32>,  // x=ShardSize, y=Refraction, z=Roughness, w=PrismEffect
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec2<f32>(
    sin(dot(p, vec2<f32>(127.1, 311.7))),
    sin(dot(p, vec2<f32>(269.5, 183.3)))
  ) * 43758.5453;
  return fract(q);
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
}

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.50, 0.50, 0.52) +
         vec3<f32>(0.46, 0.42, 0.48) *
         cos(6.28318 * (vec3<f32>(1.0, 0.72, 0.53) * t + vec3<f32>(0.02, 0.32, 0.62)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
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

  let shardScale = mix(4.0, 24.0, u.zoom_params.x);
  let refraction = u.zoom_params.y * 0.06;
  let roughness = u.zoom_params.z * 0.04;
  let prism = u.zoom_params.w * 0.03 * (1.0 + audio.z * 0.6);

  let p = uv * shardScale;
  let cell = floor(p);
  let local = fract(p);

  var bestDist = 10.0;
  var bestDelta = vec2<f32>(0.0);
  for (var j = -1; j <= 1; j = j + 1) {
    for (var i = -1; i <= 1; i = i + 1) {
      let neighbor = vec2<f32>(f32(i), f32(j));
      let point = neighbor + hash22(cell + neighbor + floor(time * 0.2));
      let delta = point - local;
      let dist = dot(delta, delta);
      if (dist < bestDist) {
        bestDist = dist;
        bestDelta = delta;
      }
    }
  }

  let dir = safeNormalize(bestDelta + (uv - mouse) * vec2<f32>(aspect, 1.0) * 0.25);
  let mouseMask = 1.0 - smoothstep(0.0, 0.55, length((uv - mouse) * vec2<f32>(aspect, 1.0)));
  let wobble = hash22(cell + vec2<f32>(time, -time)) - 0.5;
  let offset = (dir * refraction + wobble * roughness) * (1.0 + audio.x * 0.7 + mouseMask * 0.4);
  let centerUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));

  var refracted = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(centerUV + dir * prism, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, centerUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(centerUV - dir * prism, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  let shardEdge = 1.0 - smoothstep(0.10, 0.22, sqrt(bestDist));
  let facet = smoothstep(0.32, 0.02, abs(local.x + local.y - 1.0)) + smoothstep(0.23, 0.015, abs(local.x - local.y));
  let crystalTint = palette(0.5 + 0.5 * dir.x + time * 0.025 + audio.y * 0.15);
  var hdr = refracted * (0.92 + shardEdge * 0.12);
  hdr = hdr + crystalTint * shardEdge * (0.24 + 0.75 * audio.z);
  hdr = hdr + vec3<f32>(1.0, 0.86, 0.56) * pow(facet, 2.2) * (0.12 + audio.x * 0.38);
  hdr = hdr + vec3<f32>(0.32, 0.62, 1.0) * mouseMask * shardEdge * 0.35;
  let radial = length(uv - vec2<f32>(0.5)) * 1.414;
  hdr = hdr * mix(1.06, 0.70, smoothstep(0.48, 1.0, radial));
  let dither = (ign(vec2<f32>(gid.xy) + time * 29.0) - 0.5) / 255.0;
  let finalColor = clamp(aces(hdr * 1.2) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, centerUV, 0.0).r;
  let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  let finalAlpha = clamp(0.16 + shardEdge * 0.34 + mouseMask * 0.10 + pow(max(0.0, luma - 0.6), 2.0) * 2.6, 0.0, 1.0);
  let depthOut = clamp(mix(baseDepth, 0.22 + shardEdge * 0.70, 0.32), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor * finalAlpha, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(shardEdge, mouseMask, abs(offset.x) + abs(offset.y), finalAlpha));
}
