// ═══════════════════════════════════════════════════════════════════
//  Chrono Slit Scan — Batch D Upgrade
//  Category: artistic
//  Features: temporal-persistence, audio-reactive, fbm-warp, sdf-composition,
//            upgraded-rgba, multi-slit
//  Complexity: Medium
//  Created: 2026-05-10
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p * vec2<f32>(0.1031, 0.1030);
  let a = dot(pp, vec2<f32>(127.1, 311.7));
  let b = dot(pp + 1.0, vec2<f32>(269.5, 183.3));
  let c = sin(vec2<f32>(a, b));
  return fract(c * 43758.5453 + pp);
}

fn fbm2(p: vec2<f32>, t: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let h = hash22(pp + t * 0.1 * f32(i + 1));
    v += a * (h.x - 0.5);
    pp = pp * 2.3 + h.yx;
    a *= 0.5;
  }
  return v;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let mids = plasmaBuffer[0].y;

  // Parameters
  let slitCountRaw = u.zoom_params.x;
  let slitCount = mix(2.0, 3.0, slitCountRaw);
  let baseWidth = u.zoom_params.y * 0.08 + 0.002;
  let slitSpeed = u.zoom_params.z * 0.6 + 0.05;
  let feather = u.zoom_params.w * 0.5 + 0.01;

  // Mids → slit speed modulation
  let audioPulse = mids * 0.3 + 1.0;
  let speed = slitSpeed * audioPulse;

  // Multi-slit using sin waves
  var dist = 1.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    if (f32(i) >= slitCount) { break; }
    let phase = f32(i) * 2.094395102;
    let slitPos = fract(time * speed * (1.0 + f32(i) * 0.3) + f32(i) * 0.618034);
    let warp = fbm2(vec2<f32>(uv.y * 3.0 + f32(i), time * 0.5), time) * 0.05;
    let sp = fract(slitPos + warp);
    let d = abs(uv.x - sp);
    dist = smin(dist, d, 0.15);
  }

  // Fractal width modulation
  let widthMod = 1.0 + fbm2(vec2<f32>(time, uv.y * 2.0), time * 0.2) * 0.5;
  let slitW = baseWidth * widthMod;

  // Feather slit edges with smoothstep
  let mask = 1.0 - smoothstep(slitW * feather, slitW, dist);

  // Sample frames
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Spatially-varying temporal decay via noise
  let decayNoise = fbm2(uv * 4.0 + time * 0.1, time * 0.05);
  let decay = mix(1.0, 0.92 + decayNoise * 0.04, 0.5);

  // Alpha: slit-age based — freshly scanned regions more opaque
  let alpha = mix(history.a * decay, current.a, mask);
  let outColor = mix(history.rgb * decay, current.rgb, mask);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(outColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
