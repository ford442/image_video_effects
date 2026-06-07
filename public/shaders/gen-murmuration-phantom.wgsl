// ═══════════════════════════════════════════════════════════════════
//  Murmuration Phantom
//  Category: generative
//  Features: curl-noise, flock-density, golden-ratio-spirals, twilight-palette, audio-reactive,
//            upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration, trail-accumulation, hue-preserve-clamp, ign-dither
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn h2(p: vec2<f32>) -> f32 {
  let q = fract(p * vec2<f32>(0.1031, 0.1030));
  return fract(dot(q, q + vec2<f32>(33.33)));
}

fn h3(p: vec3<f32>) -> f32 {
  let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  return fract(dot(q, q.yxz + vec3<f32>(33.33)));
}

fn n2(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(h2(i), h2(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(h2(i + vec2<f32>(0.0, 1.0)), h2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn n3(p: vec3<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(h3(i + vec3<f32>(0.0, 0.0, 0.0)), h3(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
                 mix(h3(i + vec3<f32>(0.0, 1.0, 0.0)), h3(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
             mix(mix(h3(i + vec3<f32>(0.0, 0.0, 1.0)), h3(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
                 mix(h3(i + vec3<f32>(0.0, 1.0, 1.0)), h3(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

fn fbm2(p: vec2<f32>) -> f32 {
  var f = 0.0; var a = 0.5; var x = p;
  for(var i = 0; i < 4; i++) { f += a * n2(x); x *= 2.03; a *= 0.5; }
  return f;
}

fn fbm3(p: vec3<f32>) -> f32 {
  var f = 0.0; var a = 0.5; var x = p;
  for(var i = 0; i < 4; i++) { f += a * n3(x); x *= 2.03; a *= 0.5; }
  return f;
}

fn pot(p: vec2<f32>, t: f32) -> f32 {
  return n3(vec3<f32>(p, t * 0.1)) + 0.5 * n3(vec3<f32>(p * 2.0, -t * 0.15)) + 0.25 * n3(vec3<f32>(p * 4.0, t * 0.2));
}

fn curl(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.008;
  let ddx = (pot(p + vec2<f32>(e, 0.0), t) - pot(p - vec2<f32>(e, 0.0), t)) / (2.0 * e);
  let ddy = (pot(p + vec2<f32>(0.0, e), t) - pot(p - vec2<f32>(0.0, e), t)) / (2.0 * e);
  return vec2<f32>(ddy, -ddx);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hue-preserve-clamp (from AGENTS.md) ═══
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return c * min(1.0, maxLum / max(l, 1e-4));
}

// ═══ CHUNK: ign-dither (from AGENTS.md) ═══
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if(f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;
  let t = u.config.x;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let flockSize = mix(0.3, 1.2, u.zoom_params.x);
  let shapeMorph = u.zoom_params.y;
  let glintIntensity = u.zoom_params.z;
  let cohesion = u.zoom_params.w;
  let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(res.x / res.y, 1.0);
  var center = vec2<f32>(sin(t * 0.2) * 0.3, cos(t * 0.15) * 0.2);
  let mDist = length(uv - mouse);
  center += normalize(uv - mouse + vec2<f32>(0.001)) * exp(-mDist * 4.0) * 0.5;
  var scatter = 0.0;
  let rc = u32(u.config.y);
  for(var i = 0; i < 50; i++) {
    if(u32(i) >= rc) { break; }
    let rp = u.ripples[i];
    let elapsed = t - rp.z;
    if(elapsed > 0.0 && elapsed < 2.0) {
      let rd = length(uv - (rp.xy - 0.5) * vec2<f32>(res.x / res.y, 1.0));
      scatter += exp(-rd * 8.0) * sin(elapsed * 10.0) * exp(-elapsed * 2.0);
    }
  }
  var p = (uv - center) / flockSize;
  let flow = curl(p, t) * 0.4;
  p += flow;
  p += curl(p * 1.7 + vec2<f32>(1.0), t * 0.8) * 0.2;
  let phi = 1.6180339887;
  let angle = atan2(p.y, p.x);
  let radius = length(p);
  let spiral = sin(angle * phi + radius * 8.0 - t * 0.5) * 0.5 + 0.5;
  let sphere = radius - 0.5;
  let torus = length(vec2<f32>(radius - 0.35, p.y * 0.3)) - 0.2;
  let wave = abs(p.y - sin(p.x * 4.0 + t * 0.3) * 0.25) - 0.12;
  let s1 = mix(sphere, torus, smoothstep(0.0, 0.33, shapeMorph));
  let s2 = mix(s1, wave, smoothstep(0.33, 0.66, shapeMorph));
  let shape = mix(s2, fbm2(p * 2.0 + t * 0.1) * 0.4 - 0.15, smoothstep(0.66, 1.0, shapeMorph));
  let mask = smoothstep(0.15, -0.05, shape) * spiral;
  let n1 = fbm3(vec3<f32>(p * 3.0, t * 0.2));
  let n2 = fbm3(vec3<f32>(p * 6.0 + flow * 3.0, t * 0.15));
  let density = (n1 * 0.7 + n2 * 0.3) * mask * cohesion * (1.0 + bass * 0.5);
  let ex = 0.01;
  let dx = fbm3(vec3<f32>((p + vec2<f32>(ex, 0.0)) * 3.0, t * 0.2)) * mask -
           fbm3(vec3<f32>((p - vec2<f32>(ex, 0.0)) * 3.0, t * 0.2)) * mask;
  let edge = abs(dx) * 25.0 * treble * glintIntensity;
  let indigo = vec3<f32>(0.098, 0.098, 0.439);
  let violet = vec3<f32>(0.541, 0.169, 0.886);
  let sunset = vec3<f32>(1.0, 0.271, 0.0);
  let silver = vec3<f32>(0.753, 0.753, 0.753);
  var col = mix(indigo, violet, density * 2.0);
  col = mix(col, sunset, smoothstep(0.4, 0.9, density + edge * 0.5));
  col += silver * edge * (1.0 + treble);
  col += violet * smoothstep(0.3, 0.8, density) * 0.3;
  let shadow = 1.0 - smoothstep(0.0, 0.5, density);
  col = mix(col, col * vec3<f32>(0.6, 0.7, 1.0), shadow * 0.5);
  col += vec3<f32>(0.8, 0.7, 0.9) * scatter * 0.5;
  // ═══ CHUNK: trail-accumulation — blend current density into persistent trail ═══
  let prevTrail = textureSampleLevel(dataTextureC, u_sampler, (vec2<f32>(coord) + 0.5) / u.config.zw, 0.0);
  let trailDecay = 0.93 - bass * 0.04;
  let trailDensity = max(density, prevTrail.a * trailDecay);
  col = mix(col, prevTrail.rgb * 0.92, 0.05 + bass * 0.01);

  let caStr = 0.003 * (1.0 + bass) + density * 0.001;
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  var outCol = acesToneMap(huePreserveClamp(col * 1.2, 2.5));
  outCol += (ign(vec2<f32>(coord)) - 0.5) / 255.0;
  let alpha = clamp(trailDensity * 1.5 + edge * 0.8 + abs(scatter) * 0.3, 0.0, 1.0);
  let a = clamp(alpha, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(outCol * a, a));
  textureStore(writeDepthTexture, coord, vec4<f32>(density * 0.5, 0.0, 0.0, 0.0));
  // State: current frame color+density for trail feedback
  textureStore(dataTextureA, coord, vec4<f32>(outCol, trailDensity));
  // Trail: accumulated density map for next-frame read
  textureStore(dataTextureB, coord, vec4<f32>(density, edge, scatter, trailDensity));
}
