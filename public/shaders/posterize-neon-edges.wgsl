// ═══════════════════════════════════════════════════════════════════
//  Posterize Neon Edges v2
//  Category: image
//  Features: upgraded-rgba, edge-detect, neon, audio-reactive, mouse-driven
//  Complexity: High
//  Chunks From: posterize-neon-edges, fbm, aces
//  Created: 2026-05-31
//  By: 4-Agent Shader Upgrade Swarm
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var shift = vec2<f32>(1.2, 0.7);
  var pp = p;
  for (var i = 0; i < 4; i = i + 1) {
    v += a * hash12(pp);
    pp = pp * 2.03 + shift;
    a *= 0.5;
  }
  return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn neonHue(h: f32) -> vec3<f32> {
  return vec3<f32>(
    abs(sin(h * 6.28318)),
    abs(sin((h + 0.333) * 6.28318)),
    abs(sin((h + 0.666) * 6.28318))
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coords = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let texel = 1.0 / res;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let baseLevels = u.zoom_params.x;
  let edgeThreshold = u.zoom_params.y;
  let glowIntensity = u.zoom_params.z;
  let hueShift = u.zoom_params.w;

  let levels = max(baseLevels * (1.0 + bass * 0.4), 2.0);
  let focus = u.zoom_config.yz;
  let focusDist = length((uv - focus) * vec2<f32>(res.x / res.y, 1.0));
  let focusFactor = smoothstep(0.6, 0.0, focusDist);

  let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x,  texel.y), 0.0).rgb;
  let tm = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,       texel.y), 0.0).rgb;
  let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x,  texel.y), 0.0).rgb;
  let ml = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x,  0.0),      0.0).rgb;
  let mc = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let mr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x,  0.0),      0.0).rgb;
  let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb;
  let bm = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,      -texel.y), 0.0).rgb;
  let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x, -texel.y), 0.0).rgb;

  let gx = (tl + 2.0 * ml + bl) - (tr + 2.0 * mr + br);
  let gy = (tl + 2.0 * tm + tr) - (bl + 2.0 * bm + br);
  let edgeMag = length(gx) + length(gy);

  let lum = dot(mc.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let noiseBound = fbm(uv * 8.0 + time * 0.2) * 0.08;
  let bandEdge = fract(lum * levels + noiseBound);
  let quantize = select(floor(lum * levels) / levels, ceil(lum * levels) / levels, bandEdge > 0.5);

  var col = mc.rgb * (quantize / max(lum, 0.001));
  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

  let edgeMask = smoothstep(edgeThreshold * 0.4, edgeThreshold, edgeMag);
  let dynamicHue = fract(hueShift * 0.1 + edgeMag * 0.5 + mids * 0.3);
  let neonColor = neonHue(dynamicHue) * (1.5 + focusFactor * 0.5);

  let hdrEdge = neonColor * glowIntensity * (1.0 + treble * 0.6);
  col = mix(col, hdrEdge, edgeMask * glowIntensity);

  let bright = smoothstep(0.4, 0.9, lum);
  col = col + neonColor * bright * edgeMask * glowIntensity * 0.4;

  let sparkle = hash12(uv * 200.0 + time * 30.0) * treble * edgeMask * 2.0;
  col = col + vec3<f32>(sparkle);

  let shadow = smoothstep(0.5, 0.0, lum);
  let highlight = smoothstep(0.5, 1.0, lum);
  col = mix(col, vec3<f32>(0.0, 0.3, 0.4) * col, shadow * 0.35);
  col = mix(col, vec3<f32>(1.0, 0.2, 0.6) * col * 1.2, highlight * 0.25);

  col = acesToneMap(col * 1.2);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = edgeMask * (0.6 + 0.4 * depth) + mc.a * 0.3;

  textureStore(writeTexture, coords, vec4<f32>(col, clamp(alpha, 0.0, 1.0)));
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coords, vec4<f32>(col, alpha));
}
