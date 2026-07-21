// ═══════════════════════════════════════════════════════════════════
//  Bitonic Pixel Sort — Phase B Multi-Pass-Architect Upgrade
//  Optimizer pass: bass-reactive sort threshold & span length, param
//  driven pre-sort domain warp, and sorted-span edge-glow highlights.
//  Focus: bank-conflict-free shared memory, single-sided branchless
//  compare-and-swap, and clearly separated load/sort/store passes.
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
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=SortThresh, y=WarpAmp, z=EdgeGlow, w=SortLength
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

// Fixed blend constants (formerly noise-mix / octave sliders, now re-scoped).
const NOISE_MIX: f32 = 0.3;
const SORT_MIX_BASE: f32 = 0.9;
const FEEDBACK_DECAY: f32 = 0.955;
const FIXED_OCTAVES: i32 = 4;

// Workgroup layout: 16x16 threads = 256 logical elements.
const WG_X: u32 = 16u;
const WG_Y: u32 = 16u;
const WG_N: u32 = 256u;

// Pad the physical stride so 2^N threads do not all alias the same banks.
// A 17-word stride scatters consecutive x-thread accesses across different
// shared-memory banks, eliminating the worst-case conflicts of a 16-word row.
const PAD_X: u32 = 17u;
const PHYS_N: u32 = WG_Y * PAD_X; // 272

var<workgroup> sKey: array<f32, PHYS_N>;
var<workgroup> sCol: array<vec4<f32>, PHYS_N>;

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

// Warm amber -> cool cyan ramp for the sorted-span boundary glow, keyed by
// the normalized sort key so the highlight inherits local tonal structure.
fn edgeGlowColor(t: f32) -> vec3<f32> {
  let k = clamp(t, 0.0, 1.0);
  let warm = vec3<f32>(1.00, 0.55, 0.20);
  let cool = vec3<f32>(0.25, 0.70, 1.00);
  return mix(warm, cool, k * k);
}

// Map a logical 0..255 element index to its padded physical shared-memory index.
fn phys(i: u32) -> u32 {
  return (i >> 4u) * PAD_X + (i & 15u);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>,
        @builtin(local_invocation_id) lid: vec3<u32>,
        @builtin(workgroup_id) wgid: vec3<u32>) {
  let li = lid.y * WG_X + lid.x;
  let pi = lid.y * PAD_X + lid.x;
  let gx = wgid.x * WG_X + lid.x;
  let gy = wgid.y * WG_Y + lid.y;
  let x = i32(gx); let y = i32(gy);
  let uv = vec2<f32>(f32(gx), f32(gy)) / u.config.zw;
  let time = u.config.x;

  let resX = u32(u.config.z); let resY = u32(u.config.w);
  let inBounds = gx < resX && gy < resY;

  // ── Slider params (re-scoped per Optimizer brief) ────────────────
  let sortThresh = clamp(u.zoom_params.x, 0.0, 1.0); // Sort Threshold
  let warpAmp    = clamp(u.zoom_params.y, 0.0, 1.0); // Warp Amplitude
  let edgeGlow   = clamp(u.zoom_params.z, 0.0, 1.0); // Edge Glow
  let sortLen    = clamp(u.zoom_params.w, 0.0, 1.0); // Sort Length
  let octaves    = FIXED_OCTAVES;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let bassMod = 1.0 + bass * 0.3;

  // Audio-reactive thresholds: bass smoothly lowers the sort threshold so
  // more of the image joins the sorted run on beats, and breathes the
  // sorted-span length wider within each workgroup.
  let thresh = clamp(sortThresh * (1.0 - bass * 0.45), 0.02, 1.0);
  let span = clamp(sortLen * (1.0 + bass * 0.40) + 0.05, 0.05, 1.0);

  // Sort direction: ascending by default, mouse-press flips to descending
  // (preserves the old direction toggle without spending a slider on it).
  let globalAsc = u.zoom_config.w < 0.5;
  let sentinelKey = select(2.0, -1.0, !globalAsc);

  // ── PASS 1: Build per-pixel sort key and load color into workgroup memory.
  let kSegs = 6.0;
  let kUV = kaleido((uv - vec2<f32>(0.5)) * 4.0, kSegs) + vec2<f32>(0.5);
  let scale = 7.0;
  // Subtle pre-sort domain warp; warpAmp = 0 dials it exactly to zero.
  let warpStrength = warpAmp * (0.35 + bass * 0.15);
  let warp = domainWarp(kUV * scale + time * 0.15, warpStrength, octaves);
  let warpedUV = clamp(mix(kUV, warp, clamp(warpAmp * 1.4, 0.0, 1.0)), vec2<f32>(0.0), vec2<f32>(1.0));

  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  var d = distance(uv, mouse) - 0.2;
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
    let rawKey = lum * (1.0 - NOISE_MIX) + (n * 0.7 + v * 0.3) * NOISE_MIX + depth * 0.1 + jitter;
    // Threshold gate (pixel-sorter style): pixels whose luma falls below the
    // bass-lowered threshold bow out of the sort and drift to the tail of the
    // workgroup run as an unsorted region, marked by a sentinel key.
    let participates = lum >= thresh;
    key = select(sentinelKey, rawKey, participates);
  } else {
    p = vec4<f32>(0.0);
    key = sentinelKey;
  }

  sKey[pi] = key;
  sCol[pi] = p;

  // ── PASS 2: Workgroup bitonic sort network. (UNTOUCHED — the bank-
  // conflict-free padded structure and stage order must stay intact.)
  // Each thread only writes its own slot; the partner slot is updated by the
  // partner thread, eliminating double-writes and the need for a divergent if.
  for (var k: u32 = 2u; k <= WG_N; k = k << 1u) {
    for (var j: u32 = k >> 1u; j > 0u; j = j >> 1u) {
      workgroupBarrier();

      let partner = li ^ j;
      let pp = phys(partner);
      let a = sKey[pi];
      let b = sKey[pp];

      let bit = li & k;
      let asc = select(bit != 0u, bit == 0u, globalAsc);
      let swap = select(a > b, a < b, asc);
      // Each thread writes only its own slot; the partner updates its slot in
      // parallel, so the pair exchanges values without double-writes or divergence.
      let doSwap = (partner > li) == swap;

      sKey[pi] = select(a, b, doSwap);
      let ca = sCol[pi];
      let cb = sCol[pp];
      sCol[pi] = select(ca, cb, doSwap);

      workgroupBarrier();
    }
  }

  // ── PASS 3: Write sorted result, depth, edge glow, and temporal feedback.
  if (inBounds) {
    let sorted = sCol[pi];
    let sortedKey = sKey[pi];

    // Sorted-span gating: only the first `span` fraction of the workgroup's
    // sorted run contributes; bass breathes the span wider on beats.
    let spanT = f32(li) / f32(WG_N - 1u);
    let spanMask = 1.0 - smoothstep(span - 0.06, span + 0.06, spanT);

    // A slot holds a real sorted element only when its key is not a sentinel.
    let isSentinel = select(sortedKey > 1.5, sortedKey < -0.5, !globalAsc);
    let elemMask = 1.0 - f32(isSentinel);

    // Boundary detection: compare this slot's key with the next slot's key.
    // A sorted<->sentinel transition (or a sharp key jump) marks the edge
    // between the sorted span and the unsorted tail.
    let nextLi = min(li + 1u, WG_N - 1u);
    let nextKey = sKey[phys(nextLi)];
    let nextSentinel = select(nextKey > 1.5, nextKey < -0.5, !globalAsc);
    let spanEdge = abs(f32(isSentinel) - f32(nextSentinel));
    let keyJump = smoothstep(0.06, 0.30, abs(sortedKey - nextKey));
    let edgeMask = max(spanEdge, keyJump * spanMask) * mask;

    let effectiveMix = clamp(SORT_MIX_BASE * mask * bassMod * spanMask * elemMask, 0.0, 1.0);
    let finalRgb = mix(p.rgb, sorted.rgb, effectiveMix);
    let tone = acesToneMap(finalRgb * (0.9 + mids * 0.2));
    let caStr = 0.003 * (1.0 + bass) + 0.001 * distance(uv, vec2<f32>(0.5));
    var color = mix(tone, chromaticAberration(uv, caStr), 0.25 * effectiveMix);

    // Restrained edge glow on sorted-span boundaries; pulses gently with bass.
    let glowCol = edgeGlowColor(sortedKey);
    color += glowCol * edgeMask * edgeGlow * (0.35 + bass * 0.30);
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    let alpha = mix(p.a, smoothstep(0.0, 0.3, luma(sorted.rgb)), effectiveMix);
    textureStore(writeTexture, vec2<i32>(x, y), vec4<f32>(color, alpha));

    textureStore(writeDepthTexture, vec2<i32>(x, y), vec4<f32>(depth, 0.0, 0.0, 0.0));

    let feedback = mix(prev.rgb * FEEDBACK_DECAY, color, 0.15 + bass * 0.05);
    textureStore(dataTextureA, vec2<i32>(x, y), vec4<f32>(feedback, alpha));
  }
}
