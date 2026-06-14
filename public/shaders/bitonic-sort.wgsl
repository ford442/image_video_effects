// ═══════════════════════════════════════════════════════════════════
//  Bitonic Pixel Sort — Algorithmist Upgrade (Jun 2026 Batch F)
//  Category: simulation
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven,
//            multi-ripple, domain-warp, quasi-random, temporal-feedback,
//            aces-tone-map, chromatic-aberration, kaleidoscope, voronoi-ridges
//  Complexity: High
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=SortMix, y=NoiseMix, z=SortDir, w=NoiseOctaves
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

var<workgroup> sKey: array<f32, 256>;
var<workgroup> sCol: array<vec4<f32>, 256>;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i: i32 = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
  return p + strength * q;
}

fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
  let r = length(uv);
  var a = atan2(uv.y, uv.x);
  let seg = TAU / max(segs, 1.0);
  a = abs(((a % seg) + seg) % seg - seg * 0.5);
  return vec2<f32>(cos(a), sin(a)) * r;
}

fn voronoiF2minusF1(p: vec2<f32>) -> f32 {
  var F1 = 1e9; var F2 = 1e9;
  let ip = floor(p);
  for (var i: i32 = -2; i <= 2; i = i + 1) {
    for (var j: i32 = -2; j <= 2; j = j + 1) {
      let n = ip + vec2<f32>(f32(i), f32(j));
      let d = length(p - n - hash21(n));
      if (d < F1) { F2 = F1; F1 = d; } else if (d < F2) { F2 = d; }
    }
  }
  return F2 - F1;
}

fn halton(i: u32, base: u32) -> f32 {
  var f = 1.0; var r = 0.0; var idx = i;
  loop { if (idx == 0u) { break; }
    f = f / f32(base); r = r + f * f32(idx % base); idx = idx / base;
  }
  return r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
  let center = vec2<f32>(0.5);
  let delta = uv - center;
  let lenSq = max(dot(delta, delta), 0.000001);
  let dir = delta * inverseSqrt(lenSq);
  let offset = dir * max(amount, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>,
        @builtin(local_invocation_id) lid: vec3<u32>,
        @builtin(workgroup_id) wgid: vec3<u32>) {
  let li = lid.y * 16u + lid.x;
  let gx = wgid.x * 16u + lid.x;
  let gy = wgid.y * 16u + lid.y;
  let x = i32(gx); let y = i32(gy);
  let uv = vec2<f32>(f32(gx), f32(gy)) / u.config.zw;
  let time = u.config.x;

  let resX = u32(u.config.z); let resY = u32(u.config.w);
  let inBounds = gx < resX && gy < resY;

  let sortMix = u.zoom_params.x;
  let noiseMix = u.zoom_params.y;
  let sortDir = u.zoom_params.z;
  let octaves = max(i32(u.zoom_params.w * 6.0), 1);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let bassMod = 1.0 + bass * 0.3;

  let kSegs = 3.0 + floor(u.zoom_params.w * 7.0);
  let kUV = kaleido((uv - vec2<f32>(0.5)) * (2.0 + u.zoom_params.w * 4.0), kSegs) + vec2<f32>(0.5);
  let scale = 2.0 + u.zoom_params.w * 10.0;
  let warp = domainWarp(kUV * scale + time * 0.15, 0.25 + bass * 0.1, octaves);
  let warpedUV = clamp(mix(kUV, warp, 0.2 + u.zoom_params.w * 0.2), vec2<f32>(0.0), vec2<f32>(1.0));

  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  var d = distance(uv, mouse) - (0.1 + u.zoom_params.w * 0.2);
  for (var i: i32 = 0; i < 50; i = i + 1) {
    let rp = u.ripples[i];
    if (rp.z > 0.0) {
      let age = time - rp.z;
      if (age > 0.0 && age < 4.0) {
        let rd = distance(uv, rp.xy) - (0.15 * (1.0 - age / 4.0));
        d = smin(d, rd, 0.15);
      }
    }
  }
  let mask = 1.0 - smoothstep(-0.05, 0.05, d);

  let depth = textureLoad(readDepthTexture, vec2<i32>(x, y), 0).r;
  let prev = textureLoad(dataTextureC, vec2<i32>(x, y), 0);

  var p: vec4<f32>;
  var key: f32;
  if (inBounds) {
    p = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
    let lum = luma(p.rgb);
    let n = fbm(uv * 8.0 + time * 0.1, octaves);
    let v = voronoiF2minusF1(uv * 6.0 + time * 0.05);
    let jitter = (halton((li + u32(time * 60.0)) % 64u, 2u) - 0.5) * 0.002;
    key = lum * (1.0 - noiseMix) + (n * 0.7 + v * 0.3) * noiseMix + depth * 0.1 + jitter;
  } else {
    p = vec4<f32>(0.0);
    key = select(-1.0, 2.0, sortDir > 0.5);
  }

  sKey[li] = key;
  sCol[li] = p;

  for (var k: u32 = 2u; k <= 256u; k = k << 1u) {
    for (var j: u32 = k >> 1u; j > 0u; j = j >> 1u) {
      workgroupBarrier();
      let partner = li ^ j;
      let bit = li & k;
      let a = sKey[li];
      let b = sKey[partner];
      let globalAsc = sortDir < 0.5;
      let asc = select(bit != 0u, bit == 0u, globalAsc);
      let swap = select(a > b, a < b, asc);
      if (swap && partner > li) {
        sKey[li] = b; sKey[partner] = a;
        let ca = sCol[li];
        sCol[li] = sCol[partner]; sCol[partner] = ca;
      }
      workgroupBarrier();
    }
  }

  if (inBounds) {
    let sorted = sCol[li];
    let effectiveMix = sortMix * mask * bassMod;
    let finalRgb = mix(p.rgb, sorted.rgb, effectiveMix);
    let tone = acesToneMap(finalRgb * (0.9 + mids * 0.2));
    let caStr = 0.003 * (1.0 + bass) + 0.001 * distance(uv, vec2<f32>(0.5));
    let color = mix(tone, chromaticAberration(uv, caStr), 0.25 * effectiveMix);
    let alpha = mix(p.a, smoothstep(0.0, 0.3, luma(sorted.rgb)), effectiveMix);
    textureStore(writeTexture, vec2<i32>(x, y), vec4<f32>(color, alpha));

    textureStore(writeDepthTexture, vec2<i32>(x, y), vec4<f32>(depth, 0.0, 0.0, 0.0));

    let decay = 0.96 - u.zoom_params.w * 0.03;
    let feedback = mix(prev.rgb * decay, color, 0.15 + bass * 0.05);
    textureStore(dataTextureA, vec2<i32>(x, y), vec4<f32>(feedback, alpha));
  }
}
