// ═══════════════════════════════════════════════════════════════════
//  Verlet Cloth Wind
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, depth-aware
//  Complexity: High
//  Created: 2026-05-30
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
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let coord = vec2<i32>(gid.xy);
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let windStr = mix(0.2, 2.0, u.zoom_params.x) * (1.0 + bass * 1.5);
  let gravity = mix(0.01, 0.08, u.zoom_params.y);
  let stiffness = mix(0.1, 0.8, u.zoom_params.z);
  let sheen = u.zoom_params.w;
  let gridRes = 64;
  let gCoord = vec2<i32>(gid.xy);

  if (gid.x < u32(gridRes) && gid.y < u32(gridRes)) {
    let prev = textureLoad(dataTextureC, gCoord, 0);
    var h = prev.r;
    var v = prev.g;
    if (time < 0.1) {
      h = 0.0;
      v = 0.0;
    }
    if (gCoord.y > 0) {
      let n = textureLoad(dataTextureC, clamp(gCoord + vec2<i32>(0, -1), vec2<i32>(0), vec2<i32>(gridRes - 1)), 0).r;
      let s = textureLoad(dataTextureC, clamp(gCoord + vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(gridRes - 1)), 0).r;
      let e = textureLoad(dataTextureC, clamp(gCoord + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(gridRes - 1)), 0).r;
      let w = textureLoad(dataTextureC, clamp(gCoord + vec2<i32>(-1, 0), vec2<i32>(0), vec2<i32>(gridRes - 1)), 0).r;
      let laplacian = (n + s + e + w) * 0.25 - h;
      let windX = noise(vec2<f32>(f32(gCoord.x) * 0.1, time * 0.5)) * 2.0 - 1.0;
      let windY = noise(vec2<f32>(f32(gCoord.y) * 0.1 + 50.0, time * 0.3)) * 2.0 - 1.0;
      let wind2 = noise(vec2<f32>(f32(gCoord.x) * 0.3 + 100.0, time * 1.2)) * 2.0 - 1.0;
      let wind = (windX * 0.3 + windY * 0.1 + wind2 * 0.15) * windStr;
      let mouse = u.zoom_config.yz * f32(gridRes);
      let toMouse = mouse - vec2<f32>(f32(gCoord.x), f32(gCoord.y));
      let mForce = smoothstep(8.0, 0.0, length(toMouse)) * select(0.0, 1.0, u.zoom_config.w > 0.5) * 0.5;
      let force = gravity + wind + laplacian * stiffness + mForce;
      v = v * 0.95 + force * 0.016;
      h = h + v * 0.016;
    } else {
      h = 0.0;
      v = 0.0;
    }
    textureStore(dataTextureA, gCoord, vec4<f32>(h, v, 0.0, 0.0));
  }

  let cUV = uv * f32(gridRes);
  let c0 = vec2<i32>(floor(cUV));
  let cf = fract(cUV);
  let s00 = textureLoad(dataTextureC, clamp(c0 + vec2<i32>(0, 0), vec2<i32>(0), vec2<i32>(gridRes - 1)), 0).r;
  let s10 = textureLoad(dataTextureC, clamp(c0 + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(gridRes - 1)), 0).r;
  let s01 = textureLoad(dataTextureC, clamp(c0 + vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(gridRes - 1)), 0).r;
  let s11 = textureLoad(dataTextureC, clamp(c0 + vec2<i32>(1, 1), vec2<i32>(0), vec2<i32>(gridRes - 1)), 0).r;
  let h = mix(mix(s00, s10, cf.x), mix(s01, s11, cf.x), cf.y);
  let dx = s10 - s00;
  let dy = s01 - s00;
  let normal = normalize(vec3<f32>(-dx * 2.0, -dy * 2.0, 1.0));
  let light = normalize(vec3<f32>(0.5, 0.8, 0.6));
  let diff = max(dot(normal, light), 0.0);
  let backLight = normalize(vec3<f32>(-0.3, -0.5, 0.4));
  let backDiff = max(dot(normal, backLight), 0.0) * 0.25;
  let halfDir = normalize(light + vec3<f32>(0.0, 0.0, 1.0));
  let spec = pow(max(dot(normal, halfDir), 0.0), 80.0) * sheen * (1.0 + bass * 2.0);
  let fabric = mix(vec3<f32>(0.15, 0.05, 0.25), vec3<f32>(0.6, 0.2, 0.5), diff);
  var color = fabric + vec3<f32>(0.9, 0.85, 1.0) * spec;
  color = color + fabric * backDiff;
  let sss = max(0.0, -dot(normal, light)) * 0.15;
  color = color + vec3<f32>(0.4, 0.1, 0.3) * sss;
  color = color + vec3<f32>(0.3, 0.1, 0.4) * abs(h) * windStr * 0.5;
  let weave = hash12(uv * 300.0) * 0.05;
  color = color * (1.0 + weave);
  let vignetteUV = uv * (1.0 - uv);
  let vignette = vignetteUV.x * vignetteUV.y * 15.0;
  color = color * clamp(vignette, 0.0, 1.0);
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  color = clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
  let stretch = abs(h) * 0.3;
  let density = smoothstep(-0.5, 0.5, diff);
  let alpha = clamp(density * (1.0 + stretch) * (0.5 + depth * 0.5), 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth * 0.5 + stretch * 0.3, 0.0, 0.0, 0.0));
}
