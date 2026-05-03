// ═══════════════════════════════════════════════════════════════════
//  Tile Twist (Algorithmist Upgrade)
//  Category: image
//  Features: mouse-driven, geometry, temporal
//  Complexity: Medium
//  Chunks From: tile-twist (original)
//  Applied: FBM domain warping, hash tile jitter, SDF edge masking
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

const PI  = 3.141592653589793;
const PHI = 1.618033988749895;
const TAU = 6.283185307179586;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
  return fract(vec2<f32>(n, n * PHI)) * 2.0 - 1.0;
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let tileParam = max(0.01, u.zoom_params.x);
  let twistAmt = u.zoom_params.y * TAU;
  let radius = max(0.001, u.zoom_params.z);
  let edgeK = 0.01 + u.zoom_params.w * 0.09;

  // FBM domain warp for organic tile distortion
  let warp = vec2<f32>(
    fbm(uv * 5.0 + time * 0.1, 3),
    fbm(uv * 5.0 + vec2<f32>(5.2, 1.3) + time * 0.1, 3)
  ) * 0.12 * tileParam;
  let wuv = uv + warp;

  // Aspect-correct tile grid
  let n = 2.0 + tileParam * 18.0;
  let tSize = vec2<f32>(1.0 / (n * aspect), 1.0 / n);
  let grid = wuv / tSize;
  let tIdx = floor(grid);
  let tFrac = fract(grid) - 0.5;

  // Hash-jittered tile center
  let jitter = hash22(tIdx) * 0.3;
  let tCenter = (tIdx + 0.5 + jitter) * tSize;

  // Mouse-distance falloff
  let diff = tCenter - mouse;
  let dist = length(diff * vec2<f32>(aspect, 1.0));
  let falloff = 1.0 - smoothstep(0.0, radius, dist);

  // FBM-animated rotation offset
  let noiseRot = fbm(tCenter * 4.0 + time * 0.15, 2) * PI * 0.5;
  let angle = falloff * twistAmt + noiseRot * falloff;

  // Rotate pixel around jittered tile center
  let rel = uv - tCenter;
  let relA = vec2<f32>(rel.x * aspect, rel.y);
  let ca = cos(angle);
  let sa = sin(angle);
  let rotA = vec2<f32>(relA.x * ca - relA.y * sa, relA.x * sa + relA.y * ca);
  let rotUV = vec2<f32>(rotA.x / aspect, rotA.y) + tCenter;

  // SDF rounded tile edge for alpha compositing mask
  let dEdge = sdRoundBox(tFrac, vec2<f32>(0.48), 0.15);
  let edgeMask = 1.0 - smoothstep(-edgeK, edgeK, dEdge);

  let color = textureSampleLevel(readTexture, u_sampler, rotUV, 0.0);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color.rgb, color.a * mix(0.5, 1.0, edgeMask)));
}
