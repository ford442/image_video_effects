// ═══════════════════════════════════════════════════════════════════
//  liquid-tensor-vortex
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, tensor-field
//  Complexity: High
//  Chunks From: warpedFBM, curl2D, hue_preserve_clamp, bass_env
//  Created: 2026-05-31
//  By: Kimi Code CLI (weekly swarm)
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash2(p: vec2<f32>) -> vec2<f32> {
  var pp = fract(p * vec2(0.1031, 0.1030));
  pp += dot(pp, pp.yx + 33.33);
  return fract((pp.xy + pp.yx) * pp.yx);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash2(i).x, hash2(i + vec2(1.0, 0.0)).x, u.x),
             mix(hash2(i + vec2(0.0, 1.0)).x, hash2(i + vec2(1.0, 1.0)).x, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 5; i++) {
    v += a * vnoise(pp);
    pp = pp * 2.1 + vec2(3.3, 1.7);
    a *= 0.5;
  }
  return v;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
  let q = vec2(fbm(p + vec2(0.0)), fbm(p + vec2(5.2, 1.3)));
  let r = vec2(fbm(p + 3.0 * q + vec2(1.7, 9.2) + 0.15 * t), fbm(p + 3.0 * q + vec2(8.3, 2.8) + 0.126 * t));
  return fbm(p + 3.0 * r);
}

fn curlFlow(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.008;
  let n = warpedFBM(p, t);
  let nx = warpedFBM(p + vec2(eps, 0.0), t);
  let ny = warpedFBM(p + vec2(0.0, eps), t);
  return vec2(-(ny - n), nx - n) / eps;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3(0.0), vec3(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<f32>(u.config.zw);
  let uv = vec2<f32>(gid.xy) / dims;
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let env = 1.0 + bass * 2.0;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;
  let aspect = dims.x / dims.y;
  let mouse = (u.zoom_config.yz - 0.5) * vec2(aspect, 1.0);
  let p = (uv - 0.5) * vec2(aspect, 1.0);
  let md = length(p - mouse);
  let vortex = select(0.0, 1.0, u.zoom_config.w > 0.5) * smoothstep(0.4, 0.0, md);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  var flow = curlFlow(p * 2.0 * (p1 + 0.5), t * 0.2) * 0.3;
  flow += curlFlow(p * 4.0 * (p1 + 0.5) + flow, t * 0.15) * 0.15;
  flow += normalize(p - mouse + 0.001) * vortex * env * 2.0;
  let rc = u32(u.config.y);
  for (var i = 0u; i < rc; i = i + 1u) {
    let rp = u.ripples[i].xy;
    let rt = t - u.ripples[i].z;
    let rpd = length(p - (rp - 0.5) * vec2(aspect, 1.0));
    flow += normalize(p - (rp - 0.5) * vec2(aspect, 1.0) + 0.001) * exp(-rpd * 4.0) * sin(rpd * 20.0 - rt * 5.0) * 0.02;
  }
  let advect = p + flow * (0.12 + 0.08 * bass);
  let w1 = warpedFBM(advect * 2.0, t * 0.1);
  let w2 = warpedFBM(advect * 3.5 + w1, t * 0.08);
  let w3 = warpedFBM(advect * 7.0 + w2 * 0.3, t * 0.06);
  let surf = w1 + w2 * 0.5 + w3 * 0.25;
  let tension = 1.0 + bass * 3.0 + p2;
  let folds = pow(abs(surf - 0.5) * 2.0, tension);
  let silver = vec3(0.95, 0.96, 0.98);
  let gold = vec3(0.85, 0.65, 0.13);
  let bronze = vec3(0.8, 0.5, 0.2);
  let dark = vec3(0.01, 0.01, 0.02);
  let metal = mix(silver, mix(gold, bronze, surf * 0.3 + mids * 0.2), folds);
  var col = mix(dark, metal, folds);
  let div = pow(abs(flow.x), 1.5) + pow(abs(flow.y), 1.5);
  col += vec3(1.0, 0.97, 0.92) * div * 0.4 * env * p3;
  let aniso = dot(flow, normalize(p + 0.001));
  col += vec3(0.9, 0.85, 0.7) * pow(abs(aniso), 4.0) * 0.3 * env;
  let edge = pow(1.0 - abs(dot(normalize(p), vec2(0.0, 1.0))), 2.0);
  col += vec3(0.6, 0.5, 0.3) * edge * 0.2 * env;
  col = mix(col, dark, pow(folds, 3.0) * 0.5);
  let ab = vortex * 0.02;
  let r = textureSampleLevel(readTexture, u_sampler, uv + flow * ab, 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, uv - flow * ab, 0.0).b;
  let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let bgAb = vec3(r, bg.g, b);
  let alpha = mix(0.2, 0.95, folds) * (1.0 - depth * (0.4 + p4 * 0.4)) * (1.0 - vortex * 0.4);
  let lum = dot(col, vec3(0.299, 0.587, 0.114));
  col = max(clamp(col, vec3(0.0), vec3(1.0)), lum * vec3(0.3, 0.25, 0.2));
  col = aces(col * 1.4);
  col += (ign(vec2<f32>(gid.xy)) - 0.5) / 256.0;
  let out = col * alpha + bgAb * (1.0 - alpha);
  textureStore(writeTexture, gid.xy, vec4(out, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4(depth * 0.5 + alpha * 0.5, 0.0, 0.0, 1.0));
}
