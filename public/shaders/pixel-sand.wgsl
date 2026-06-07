// ═══════════════════════════════════════════════════════════════════
//  Pixel Sand — Batch D Upgraded
//  Category: simulation
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware, temporal
//  Complexity: Medium
//  Chunks From: pixel-sand
//  Created: 2026-05-02
//  Upgraded: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

fn rnd(g: vec3<u32>, s: f32) -> f32 {
  return hash(f32(g.x) * 73.0 + f32(g.y) * 37.0 + s + u.config.x);
}

fn noise2D(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = noise2D(i);
  let b = noise2D(i + vec2<f32>(1.0, 0.0));
  let c = noise2D(i + vec2<f32>(0.0, 1.0));
  let d = noise2D(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn curlForce(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.05;
  let n1 = valueNoise(p * 3.0 + vec2<f32>(eps, 0.0) + t * 0.1);
  let n2 = valueNoise(p * 3.0 - vec2<f32>(eps, 0.0) + t * 0.1);
  let n3 = valueNoise(p * 3.0 + vec2<f32>(0.0, eps) + t * 0.1);
  let n4 = valueNoise(p * 3.0 - vec2<f32>(0.0, eps) + t * 0.1);
  let dx = (n1 - n2) / (2.0 * eps);
  let dy = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dy, -dx);
}

fn readState(cx: i32, cy: i32) -> vec4<f32> {
  let gw = i32(u.config.z);
  let gh = i32(u.config.w);
  return textureLoad(dataTextureC, vec2<i32>(clamp(cx, 0, gw - 1), clamp(cy, 0, gh - 1)), 0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let x = global_id.x;
  let y = global_id.y;
  let gridW = u32(u.config.z);
  let gridH = u32(u.config.w);

  let uv = vec2<f32>(f32(x) / f32(gridW), f32(y) / f32(gridH));
  let t = u.config.x;
  let mouse = u.zoom_config.yz;
  let mDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let video = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(video.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  var cell = readState(i32(x), i32(y));

  // Spawn: mouse cursor creates golden sand
  let mDist = distance(uv, mouse);
  let mRad = 0.015 + p3 * 0.06;
  if (mDist < mRad && (mDown || rnd(global_id, 1.0) < 0.2)) {
    let glow = 1.0 + bass * 0.5;
    cell = vec4<f32>(0.9 * glow, 0.65 * glow, 0.35 * glow, 1.0);
  }

  // Spawn: luma-keyed video-to-sand conversion
  if (cell.a < 0.5 && luma > 0.5 && rnd(global_id, 2.0) < p2 * 0.3) {
    cell = vec4<f32>(video.rgb * (1.0 + treble), 1.0);
  }

  // Spawn: ripple shockwaves deposit coloured grains
  for (var i: i32 = 0; i < 50; i = i + 1) {
    let rp = u.ripples[i];
    if (rp.z > 0.0 && t - rp.z > 0.0 && t - rp.z < 0.5 && distance(uv, rp.xy) < 0.025) {
      cell = vec4<f32>(0.8 + bass * 0.2, 0.5 + mids * 0.3, 0.3 + treble * 0.4, 1.0);
    }
  }

  if (cell.a < 0.5) {
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeDepthTexture, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0, 0.0, 0.0, 0.0));
    return;
  }

  // Height-field: bright pixels are heavier
  let particleLuma = dot(cell.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let heightWeight = 0.5 + particleLuma;

  // Bass → gravity pulse
  let grav = mix(0.5, 2.5, p1) * (1.0 + bass * 0.5) * heightWeight;
  var vy = cell.b + grav * (0.04 + p2 * 0.08);
  var vx = cell.g;

  // Curl noise secondary force field
  let curl = curlForce(uv * 5.0, t) * p3 * 0.5;
  vx += curl.x;
  vy += curl.y;

  // Mouse gravity well
  let toM = mouse - uv;
  if (mDown && length(toM) < 0.25) {
    vx += toM.x * 0.15;
    vy += toM.y * 0.15;
  }

  // Audio chaos
  vx += (rnd(global_id, t) - 0.5) * mids;

  let nx = clamp(i32(x) + i32(round(vx)), 0, i32(gridW) - 1);
  let ny = clamp(i32(y) + i32(round(vy)), 0, i32(gridH) - 1);
  let by = min(i32(y) + 1, i32(gridH) - 1);

  let dest = readState(nx, ny);
  let below = readState(i32(x), by);
  let bL = readState(i32(x) - 1, by);
  let bR = readState(i32(x) + 1, by);

  let shade = (0.5 + depth * 0.9) * (1.0 + bass * 0.2);
  let bounceDamping = 0.3 + p4 * 0.5;

  if ((nx != i32(x) || ny != i32(y)) && dest.a < 0.5) {
    cell.g = vx * 0.92;
    cell.b = vy * 0.88;
    textureStore(dataTextureB, vec2<i32>(nx, ny), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(nx, ny), vec4<f32>(cell.rgb * shade, cell.a));
    textureStore(writeDepthTexture, vec2<i32>(nx, ny), vec4<f32>(depth * cell.a, 0.0, 0.0, 0.0));
  } else if (below.a < 0.5) {
    cell.g = vx * 0.4;
    cell.b = 1.0;
    textureStore(dataTextureB, vec2<i32>(i32(x), by), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(i32(x), by), vec4<f32>(cell.rgb * shade, cell.a));
    textureStore(writeDepthTexture, vec2<i32>(i32(x), by), vec4<f32>(depth * cell.a, 0.0, 0.0, 0.0));
  } else if (bL.a < 0.5 && rnd(global_id, 3.0) < 0.5) {
    cell.g = -0.8;
    cell.b = 0.8;
    textureStore(dataTextureB, vec2<i32>(max(i32(x) - 1, 0), by), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(max(i32(x) - 1, 0), by), vec4<f32>(cell.rgb * shade, cell.a));
    textureStore(writeDepthTexture, vec2<i32>(max(i32(x) - 1, 0), by), vec4<f32>(depth * cell.a, 0.0, 0.0, 0.0));
  } else if (bR.a < 0.5) {
    cell.g = 0.8;
    cell.b = 0.8;
    textureStore(dataTextureB, vec2<i32>(min(i32(x) + 1, i32(gridW) - 1), by), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(min(i32(x) + 1, i32(gridW) - 1), by), vec4<f32>(cell.rgb * shade, cell.a));
    textureStore(writeDepthTexture, vec2<i32>(min(i32(x) + 1, i32(gridW) - 1), by), vec4<f32>(depth * cell.a, 0.0, 0.0, 0.0));
  } else {
    cell.g = vx * -bounceDamping;
    cell.b = vy * -bounceDamping;
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), cell);
    textureStore(writeTexture, vec2<i32>(i32(x), i32(y)), vec4<f32>(cell.rgb * shade, cell.a));
    textureStore(writeDepthTexture, vec2<i32>(i32(x), i32(y)), vec4<f32>(depth * cell.a, 0.0, 0.0, 0.0));
  }
}
