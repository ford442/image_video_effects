// ═══════════════════════════════════════════════════════════════════
//  Tile Twist (Algorithmist Upgrade)
//  Category: distortion
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware,
//            temporal-feedback, aces-tone-map, chromatic-aberration
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash & noise ──────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
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
  for (var i = 0; i < oct; i = i + 1) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
  let r = vec2<f32>(
    fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2), oct),
    fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8), oct)
  );
  return p + strength * r;
}

fn voronoiF2minusF1(p: vec2<f32>) -> f32 {
  var F1 = 1e9;
  var F2 = 1e9;
  let ip = floor(p);
  for (var i = -2; i <= 2; i = i + 1) {
    for (var j = -2; j <= 2; j = j + 1) {
      let n = ip + vec2<f32>(f32(i), f32(j));
      let d = length(p - n - hash22(n));
      if (d < F1) { F2 = F1; F1 = d; } else if (d < F2) { F2 = d; }
    }
  }
  return F2 - F1;
}

fn sdRoundBox(p: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
  let q = abs(p) - b + r;
  return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

fn rot2(angle: f32) -> mat2x2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let twist = u.zoom_params.x * TAU;
  let tileSize = max(0.01, u.zoom_params.y);
  let radius = max(0.01, u.zoom_params.z);
  let edgeSmooth = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Audio-driven oscillation speed
  let oscSpeed = 1.0 + mids * 2.0 + bass * 0.5;

  // Aspect-correct tile grid with double-domain warp
  let n = 2.0 + tileSize * 18.0;
  let aspect = res.x / res.y;
  let tSize = vec2<f32>(1.0 / (n * aspect), 1.0 / n);
  let grid = uv01 / tSize;
  let tIdx = floor(grid);
  let tFrac = fract(grid) - 0.5;

  let warp = domainWarp(uv01 * 4.0 + time * 0.12, 0.08 + edgeSmooth * 0.12, 3);
  let wuv = uv01 + warp * (0.5 + treble);

  // Voronoi ridge identity per tile
  let ridge = voronoiF2minusF1(uv01 * n * 0.7 + hash22(tIdx));
  let tileHash = hash21(tIdx);

  // Mouse proximity falloff (uses previously-unused radius param)
  let mouseDist = length(uv01 - mouse);
  let influence = smoothstep(radius, radius * 0.2, mouseDist) * (0.5 + 0.5 * f32(mouseDown));

  // Hash-jittered tile center
  let jitter = hash22(tIdx) * 0.25 * (1.0 + ridge);
  let tCenter = (tIdx + 0.5 + jitter) * tSize;

  // Lissajous + hash + mouse-driven twist angle
  let lissA = sin(time * oscSpeed * 2.0 + tileHash * TAU);
  let lissB = sin(time * oscSpeed + tileHash * TAU * 0.7);
  let lissajousAngle = atan2(lissB, lissA) * 0.5;
  let tileTwist = tileHash * twist * (1.0 + ridge + influence * 2.0 + treble);
  let angle = lissajousAngle + tileTwist;

  // Rotate pixel around jittered tile center
  let rel = wuv - tCenter;
  let relA = vec2<f32>(rel.x * aspect, rel.y);
  let rotA = rot2(angle) * relA;
  let rotUV = vec2<f32>(rotA.x / aspect, rotA.y) + tCenter;

  // SDF rounded tile edge mask
  let dEdge = sdRoundBox(tFrac, vec2<f32>(0.48), 0.12);
  let softness = 0.01 + edgeSmooth * 0.06;
  let edgeMask = 1.0 - smoothstep(-softness, softness, dEdge);

  // Source sample + chromatic aberration driven by bass & mouse influence
  let src = textureSampleLevel(readTexture, u_sampler, rotUV, 0.0);
  let caDir = normalize(rotUV - vec2<f32>(0.5) + vec2<f32>(0.001));
  let caStr = 0.002 * (1.0 + bass) + influence * 0.005;
  let r = textureSampleLevel(readTexture, u_sampler, clamp(rotUV + caDir * caStr, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(rotUV - caDir * caStr * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r, src.g, b);

  // ACES tone map and semantic alpha
  color = acesToneMap(color * (0.9 + mids * 0.2));
  let alpha = src.a * mix(0.55, 1.0, edgeMask) * (0.7 + influence * 0.3);

  // Temporal feedback trail
  let prev = textureLoad(dataTextureC, pixel, 0);
  let decay = 0.96 - edgeSmooth * 0.03;
  let trail = mix(prev.rgb * decay, color, 0.25 + bass * 0.1);
  textureStore(dataTextureA, pixel, vec4<f32>(trail, prev.a));

  // Depth passthrough
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
