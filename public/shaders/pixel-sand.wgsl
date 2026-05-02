// ═══════════════════════════════════════════════════════════════════
//  Pixel Sand — Upgraded (Interactivist)
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, temporal
//  Complexity: Medium
//  Chunks From: pixel-sand (original)
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

const GRID_W: u32 = 1280u;
const GRID_H: u32 = 720u;

fn hash(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

fn rnd(g: vec3<u32>, s: f32) -> f32 {
  return hash(f32(g.x) * 73.0 + f32(g.y) * 37.0 + s + u.config.x);
}

fn readState(cx: i32, cy: i32) -> vec4<f32> {
  return textureLoad(dataTextureC, vec2<i32>(clamp(cx, 0, i32(GRID_W) - 1), clamp(cy, 0, i32(GRID_H) - 1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let x = gid.x;
  let y = gid.y;
  if (x >= GRID_W || y >= GRID_H) { return; }

  let uv = vec2<f32>(f32(x) / f32(GRID_W), f32(y) / f32(GRID_H));
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

  // ── Spawn: mouse cursor creates a gravity-well of golden sand ──
  let mDist = distance(uv, mouse);
  let mRad = 0.015 + p3 * 0.06;
  if (mDist < mRad && (mDown || rnd(gid, 1.0) < 0.2)) {
    let glow = 1.0 + bass * 0.5;
    cell = vec4<f32>(0.9 * glow, 0.65 * glow, 0.35 * glow, 1.0);
  }

  // ── Spawn: luma-keyed video-to-sand conversion ──
  if (cell.a < 0.5 && luma > 0.5 + (1.0 - p4) * 0.4 && rnd(gid, 2.0) < 0.1) {
    cell = vec4<f32>(video.rgb * (1.0 + treble), 1.0);
  }

  // ── Spawn: ripple shockwaves deposit coloured grains ──
  for (var i = 0; i < 50; i = i + 1) {
    let rp = u.ripples[i];
    if (rp.z > 0.0 && t - rp.z > 0.0 && t - rp.z < 0.5 && distance(uv, rp.xy) < 0.025) {
      cell = vec4<f32>(0.8 + bass * 0.2, 0.5 + mids * 0.3, 0.3 + treble * 0.4, 1.0);
    }
  }

  if (cell.a < 0.5) {
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    return;
  }

  // ── Physics: gravity + temporal velocity feedback ──
  let grav = mix(0.5, 2.5, p1) + bass * 1.0;
  var vy = cell.b + grav * (0.04 + p2 * 0.08);
  var vx = cell.g;

  // Mouse gravity well: attract nearby grains toward cursor when clicked
  let toM = mouse - uv;
  if (mDown && length(toM) < 0.25) {
    vx += toM.x * 0.15;
    vy += toM.y * 0.15;
  }

  // Audio chaos: mids add turbulent jitter to horizontal drift
  vx += (rnd(gid, t) - 0.5) * mids;

  let nx = clamp(i32(x) + i32(round(vx)), 0, i32(GRID_W) - 1);
  let ny = clamp(i32(y) + i32(round(vy)), 0, i32(GRID_H) - 1);
  let by = min(i32(y) + 1, i32(GRID_H) - 1);

  let dest = readState(nx, ny);
  let below = readState(i32(x), by);
  let bL = readState(i32(x) - 1, by);
  let bR = readState(i32(x) + 1, by);

  let shade = (0.5 + depth * 0.9) * (1.0 + bass * 0.2);

  if ((nx != i32(x) || ny != i32(y)) && dest.a < 0.5) {
    cell.g = vx * 0.92;
    cell.b = vy * 0.88;
    textureStore(dataTextureB, vec2<i32>(nx, ny), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(nx, ny), vec4<f32>(cell.rgb * shade, 1.0));
  } else if (below.a < 0.5) {
    cell.g = vx * 0.4;
    cell.b = 1.0;
    textureStore(dataTextureB, vec2<i32>(i32(x), by), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(i32(x), by), vec4<f32>(cell.rgb * shade, 1.0));
  } else if (bL.a < 0.5 && rnd(gid, 3.0) < 0.5) {
    cell.g = -0.8;
    cell.b = 0.8;
    textureStore(dataTextureB, vec2<i32>(max(i32(x) - 1, 0), by), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(max(i32(x) - 1, 0), by), vec4<f32>(cell.rgb * shade, 1.0));
  } else if (bR.a < 0.5) {
    cell.g = 0.8;
    cell.b = 0.8;
    textureStore(dataTextureB, vec2<i32>(min(i32(x) + 1, i32(GRID_W) - 1), by), cell);
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), vec4<f32>(0.0));
    textureStore(writeTexture, vec2<i32>(min(i32(x) + 1, i32(GRID_W) - 1), by), vec4<f32>(cell.rgb * shade, 1.0));
  } else {
    cell.g = vx * 0.2;
    cell.b = 0.0;
    textureStore(dataTextureB, vec2<i32>(i32(x), i32(y)), cell);
    textureStore(writeTexture, vec2<i32>(i32(x), i32(y)), vec4<f32>(cell.rgb * shade, 1.0));
  }
}
