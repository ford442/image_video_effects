// ═══════════════════════════════════════════════════════════════════
//  Chrono Slit Scan — Optimizer Upgrade
//  Category: image
//  Features: temporal-persistence, audio-reactive, fbm-warp, sdf-composition,
//            upgraded-rgba, multi-slit, branchless-slit, depth-aware
//  Complexity: Medium
//
//  Pipeline notes:
//   - dataTextureA/B used for temporal state; dataTextureC is previous frame.
//   - writeDepthTexture passthrough preserves depth for downstream slots.
//   - Output alpha encodes slit intensity for compositing.
//
//  Recommended slots:
//   - Slot 0: image/video source
//   - Slot 1+: temporal feedback via dataTextureA/B chain
//   - Final output: writeTexture with depth passthrough
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

// ── Canonical hash & fBM ──────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < oct; i++) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

// ── Color / SDF helpers ───────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Tunable parameters mapped to zoom_params
  //   p1 = slitCount (2–3 slits), p2 = slitWidth
  //   p3 = slitSpeed, p4 = feather
  let slitCount = mix(2.0, 3.0, u.zoom_params.x);
  let baseWidth = (u.zoom_params.y * 0.08 + 0.002) * (1.0 + bass * 0.5);
  let slitSpeed = u.zoom_params.z * 0.6 + 0.05;
  let feather = (u.zoom_params.w * 0.5 + 0.01) * (1.0 + treble * 0.6);

  // Audio-reactive speed
  let speed = slitSpeed * (mids * 0.3 + 1.0);

  // Depth-aware scale (load depth, avoid textureSampleLevel on depth)
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthBoost = 1.0 + depth * 0.5;

  // Multi-slit distance field with branchless count gating
  var dist = 1.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let isActive = step(f32(i) + 0.5, slitCount);
    let offset = fract(f32(i + 1) * PHI);
    let pos = fract(time * speed * (1.0 + f32(i) * 0.3) + offset);
    let warp = fbm(vec2<f32>(uv.y * 3.0 + f32(i), time * 0.5), 3) * 0.05;
    let sp = fract(pos + warp);
    let d = abs(uv.x - sp);
    let blended = smin(dist, d, 0.15);
    dist = mix(dist, blended, isActive);
  }

  // Fractal width modulation
  let widthMod = 1.0 + fbm(vec2<f32>(time, uv.y * 2.0), 3) * 0.5;
  let slitW = baseWidth * widthMod * depthBoost;

  // Feathered slit mask
  let mask = 1.0 - smoothstep(slitW * feather, slitW, dist);

  // Sample current frame and temporal history
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Spatially-varying temporal decay
  let decayNoise = fbm(uv * 4.0 + time * 0.1, 3);
  let decay = mix(1.0, 0.92 + decayNoise * 0.04, 0.5);

  // Compose: freshly scanned regions pick up current color and intensity
  let alpha = mix(history.a * decay, saturate(luma(current.rgb) + 0.2), mask);
  let color = mix(history.rgb * decay, current.rgb, mask);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
