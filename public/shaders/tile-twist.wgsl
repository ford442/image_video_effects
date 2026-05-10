// ═══════════════════════════════════════════════════════════════════
//  Tile Twist
//  Category: distortion
//  Features: upgraded-rgba, mouse-driven, audio-reactive
//  Complexity: Medium
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

const PI = 3.141592653589793;
const TAU = 6.283185307179586;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
  return fract(vec2<f32>(n, n * 1.618033988749895)) * 2.0 - 1.0;
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
    mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < octaves; i = i + 1) {
    v = v + a * vnoise(pp);
    pp = pp * 2.03;
    a = a * 0.5;
  }
  return v;
}

fn sdRoundBox(p: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
  let q = abs(p) - b + r;
  return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let twistAngle = u.zoom_params.x * TAU;
  let tileSizeParam = max(0.01, u.zoom_params.y);
  let lissajousRatio = u.zoom_params.z * 3.0 + 1.0;
  let turbulence = u.zoom_params.w;

  let mids = plasmaBuffer[0].y;
  let oscillationSpeed = 1.0 + mids * 2.0;

  // Aspect-correct tile grid
  let n = 2.0 + tileSizeParam * 18.0;
  let tSize = vec2<f32>(1.0 / (n * aspect), 1.0 / n);
  let grid = uv / tSize;
  let tIdx = floor(grid);
  let tFrac = fract(grid) - 0.5;

  // Hash-based tile identity
  let tileHash = hash12(tIdx);

  // FBM turbulence for organic distortion
  let warp = vec2<f32>(
    fbm(uv * 5.0 + time * 0.1, 3),
    fbm(uv * 5.0 + vec2<f32>(5.2, 1.3) + time * 0.1, 3)
  ) * 0.12 * turbulence;
  let wuv = uv + warp;

  // Hash-jittered tile center
  let jitter = hash22(tIdx) * 0.3;
  let tCenter = (tIdx + 0.5 + jitter) * tSize;

  // Lissajous oscillation on rotation angle
  let lissA = sin(time * oscillationSpeed * lissajousRatio + tileHash * TAU);
  let lissB = sin(time * oscillationSpeed + tileHash * TAU * 0.7);
  let lissajousAngle = atan2(lissB, lissA) * 0.5;

  // Twist proportional to hash(tile_id) * zoom_params
  let tileTwist = tileHash * twistAngle * (1.0 + turbulence);
  let angle = lissajousAngle + tileTwist;

  // Rotate pixel around jittered tile center
  let rel = wuv - tCenter;
  let relA = vec2<f32>(rel.x * aspect, rel.y);
  let ca = cos(angle);
  let sa = sin(angle);
  let rotA = vec2<f32>(relA.x * ca - relA.y * sa, relA.x * sa + relA.y * ca);
  let rotUV = vec2<f32>(rotA.x / aspect, rotA.y) + tCenter;

  // SDF rounded tile edge for alpha compositing mask
  let dEdge = sdRoundBox(tFrac, vec2<f32>(0.48), 0.15);
  let edgeMask = 1.0 - smoothstep(-0.02, 0.02, dEdge);

  let src = textureSampleLevel(readTexture, u_sampler, rotUV, 0.0);
  let alpha = src.a * mix(0.6, 1.0, edgeMask);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(src.rgb, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
