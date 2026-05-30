// ═══════════════════════════════════════════════════════════════════
//  Lichtenberg Storm
//  Category: generative
//  Features: generative, fractal-branching, temporal-feedback, audio-reactive, mouse-driven
//  Complexity: High
//  Created: 2026-05-31
//  By: Kimi Code CLI
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

fn h12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn h13(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn n2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(h12(i + vec2<f32>(0.0, 0.0)), h12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(h12(i + vec2<f32>(0.0, 1.0)), h12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var x = p;
  for (var i = 0; i < 5; i++) {
    v += a * n2(x);
    x *= 2.0;
    a *= 0.5;
  }
  return v;
}

fn aces(c: vec3<f32>) -> vec3<f32> {
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn licht(p: vec2<f32>, seed: vec2<f32>, branches: f32, jitter: f32, t: f32) -> f32 {
  let d = p - seed;
  let r = length(d);
  let a = atan2(d.y, d.x);
  let w = fbm(d * 3.0 + t * 0.1) * jitter * 3.0;
  let dend = fbm(vec2<f32>(a * branches + w, r * 6.0));
  return max(smoothstep(0.12, 0.0, r), smoothstep(0.55, 0.45, dend) * smoothstep(0.6, 0.0, r));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  let uv = vec2<f32>(gid.xy) / res;
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let jitter = u.zoom_params.x;
  let glow = u.zoom_params.y;
  let stormFreq = u.zoom_params.z;
  let afterglow = u.zoom_params.w;
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;
  let storm = smoothstep(0.9, 1.0, sin(t * stormFreq * 3.0) * 0.5 + 0.5);
  var energy = 0.0;
  let branches = mix(8.0, 24.0, jitter);
  let numSeeds = 3u + u32(bass * 3.0);
  for (var i = 0u; i < numSeeds; i++) {
    let fi = f32(i);
    let seed = vec2<f32>(h13(vec3<f32>(fi, floor(t * 0.3 * stormFreq), 0.0)), h13(vec3<f32>(fi, floor(t * 0.3 * stormFreq), 1.0)));
    energy = max(energy, licht(uv, seed + vec2<f32>(sin(t * 0.2 + fi), cos(t * 0.15 + fi)) * 0.1, branches, jitter, t));
  }
  let bassPulse = step(0.7, bass) * storm;
  if (bassPulse > 0.0) {
    let bs = vec2<f32>(h13(vec3<f32>(t, 0.0, 0.0)), h13(vec3<f32>(t, 0.0, 1.0)));
    energy = max(energy, licht(uv, bs, branches * 1.5, jitter, t) * bassPulse);
  }
  let clickCount = u32(u.config.y);
  for (var i = 0u; i < min(clickCount, 10u); i++) {
    let rt = t - u.ripples[i].z;
    let rdecay = exp(-rt * 2.0);
    if (rdecay > 0.01) {
      energy = max(energy, licht(uv, u.ripples[i].xy, branches, jitter, t) * rdecay);
    }
  }
  let thick = mix(0.5, 2.0, mids);
  energy = smoothstep(0.0, 1.0 / thick, energy);
  energy = max(energy, prev * mix(0.7, 0.98, afterglow));
  let hot = smoothstep(0.6, 1.0, energy);
  let warm = smoothstep(0.3, 0.6, energy);
  let cool = smoothstep(0.0, 0.3, energy);
  var col = vec3<f32>(0.294, 0.0, 0.51) * cool + vec3<f32>(0.0, 1.0, 1.0) * warm + mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0), hot) * hot;
  col += vec3<f32>(0.224, 1.0, 0.078) * hot * (1.0 + bass);
  col += vec3<f32>(1.0) * energy * energy * 2.0 * glow;
  col += vec3<f32>(0.0, 1.0, 1.0) * smoothstep(0.15, 0.0, energy) * 0.3 * glow;
  col += vec3<f32>(1.0) * h12(gid.xy + fract(t * 20.0)) * treble * hot * 4.0;
  let tipBloom = hot * (1.0 + bass * 0.5 + treble * 0.8);
  col += vec3<f32>(0.8, 0.9, 1.0) * tipBloom * glow;
  let decayCol = mix(vec3<f32>(0.2, 0.0, 0.4), vec3<f32>(0.0, 0.6, 0.3), prev);
  col += decayCol * prev * afterglow * 0.3;
  let field = fbm(uv * 4.0 + t * 0.2) * 0.03;
  col += vec3<f32>(0.1, 0.0, 0.2) * field * (1.0 + storm);
  col += vec3<f32>(1.0) * storm * 0.15;
  col = aces(col * glow * 1.5);
  let ign = fract(52.9829189 * fract(dot(vec2<f32>(gid.xy), vec2<f32>(0.06711056, 0.00583715))));
  col += (ign - 0.5) / 255.0;
  let alpha = energy * (1.0 + glow * 0.5);
  let a = clamp(alpha, 0.0, 1.0);
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(col * a, a));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(energy, 0.0, 0.0, 0.0));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(energy * 0.5 + 0.2 + storm * 0.15, 0.0, 0.0, 0.0));
}
