// ═══════════════════════════════════════════════════════════════════
//  Gravito-Phononic Accretion v2
//  Category: generative
//  Features: SPH-density, orbital-velocity, shock-detection, blackbody,
//            audio-driven, mouse-rogue-body, ripple-perturbation
//  Complexity: Very High
//  Chunks From: inverse-square field + cubic-spline kernel + ACES tm
//  Created: 2026-05-31
//  By: 4-Agent Upgrade Swarm
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

fn cubicKernel(q: f32) -> f32 {
  let s = clamp(q, 0.0, 2.0);
  return select(0.25 * pow(2.0 - s, 3.0), 0.25 * s * s * (3.0 * s - 6.0) + 1.0, s < 1.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbody(t: f32) -> vec3<f32> {
  let kt = clamp(t, 0.0, 1.0);
  let g = mix(0.2, 1.0, smoothstep(0.15, 0.6, kt));
  let b = mix(0.0, 1.0, smoothstep(0.3, 0.9, kt));
  return vec3<f32>(kt, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x * 0.4;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  let precess = mids * 0.8;
  let g1 = vec2<f32>(0.35 + sin(time * 0.3 + precess) * 0.12, 0.42 + cos(time * 0.25) * 0.09);
  let g2 = vec2<f32>(0.68 + cos(time * 0.35 - precess) * 0.1, 0.58 + sin(time * 0.3 + precess) * 0.08);
  let mass1 = 0.9 + bass * 1.4 + p1 * 0.8;
  let mass2 = 0.8 + mids * 1.0 + p1 * 0.6;
  let mass3 = (0.7 + treble * 0.6) * mouseDown * (1.0 + p4 * 2.0);

  let d1 = length(uv - g1) + 0.06;
  let d2 = length(uv - g2) + 0.06;
  let d3 = length(uv - mouse) + 0.04;

  let v1 = vec2<f32>(-(uv.y - g1.y), uv.x - g1.x) * (mass1 / (d1 * d1)) * 0.025;
  let v2 = vec2<f32>(-(uv.y - g2.y), uv.x - g2.x) * (mass2 / (d2 * d2)) * 0.02;
  let v3 = select(vec2<f32>(0.0), vec2<f32>(-(uv.y - mouse.y), uv.x - mouse.x) * (mass3 / (d3 * d3)) * 0.04, mouseDown > 0.5);
  let vel = v1 + v2 + v3;

  let h = 0.045 + p3 * 0.04;
  var density = 0.0;
  for (var i = 0; i < 4; i = i + 1) {
    for (var j = 0; j < 4; j = j + 1) {
      let off = (vec2<f32>(f32(i), f32(j)) - 1.5) * h;
      let sp = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
      density += textureSampleLevel(dataTextureC, u_sampler, sp, 0.0).r * cubicKernel(length(off) / h);
    }
  }
  density = density * 0.25 + 0.001;

  let flowUV = clamp(uv - vel * 8.0 * (0.6 + p1), vec2<f32>(0.0), vec2<f32>(1.0));
  let flowed = textureSampleLevel(dataTextureC, u_sampler, flowUV, 0.0).r;
  let standing = sin(uv.x * 20.0 + time * 3.0) * cos(uv.y * 16.0 - time * 2.5) * treble * 0.12;

  var ripplePert = 0.0;
  let rCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rd = length(uv - rp.xy);
    let rt = time - rp.z;
    ripplePert += exp(-rd * 8.0) * sin(rt * 10.0) * 0.03 * smoothstep(3.0, 0.0, rt);
  }

  density = mix(flowed * 0.95 + density * 0.05, density, 0.3) + standing + ripplePert;

  let ps = 1.0 / res;
  let drx = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let drxm = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let dry = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let drym = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gradD = length(vec2<f32>(drx - drxm, dry - drym)) * res.x * 0.5;
  let shock = smoothstep(0.3, 1.2, gradD + length(vel) * 3.0);

  var temp = shock * 0.7 + (mass1 / (d1 * d1 * 20.0 + 1.0)) * 0.4 + (mass2 / (d2 * d2 * 20.0 + 1.0)) * 0.3;
  temp = clamp(temp, 0.0, 1.0);

  textureStore(dataTextureA, gid.xy, vec4<f32>(density, temp, shock, 0.0));

  let bb = blackbody(temp) * (1.0 + shock * 2.0);
  let scatter = smoothstep(0.02, 0.25, density) * temp * 0.6;
  let col = bb * (0.5 + density * 1.2) + vec3<f32>(0.3, 0.5, 1.0) * scatter;
  let bloom = shock * vec3<f32>(1.0, 0.9, 0.7) * 1.5;
  let tone = acesToneMap((col + bloom) * (0.8 + p2));

  let bgEmpty = smoothstep(0.15, 0.0, density);
  let alpha = clamp(density * 1.1 * temp * (1.0 - bgEmpty * 0.8) + shock * 0.5, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(density * temp * 0.7, 0.0, 0.0, 0.0));
}
