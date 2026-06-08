// ═══════════════════════════════════════════════════════════════════
//  IFS Fractal Flame v3 — Interactivist Upgrade
//  Category: generative
//  Features: ifs, flame, bass-envelope, gravity-well, click-burst,
//            treble-sparkle, luma-spawn, depth-aware
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

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> vec2<f32> {
  return fract(vec2<f32>(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453,
                         sin(dot(p, vec2<f32>(269.5, 183.3))) * 43758.5453));
}

fn varSinusoidal(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(sin(p.x), sin(p.y));
}

fn varSpherical(p: vec2<f32>) -> vec2<f32> {
  let r2 = dot(p, p) + 1e-6;
  return p / r2;
}

fn varSwirl(p: vec2<f32>) -> vec2<f32> {
  let r2 = dot(p, p);
  let c = cos(r2);
  let s = sin(r2);
  return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

fn flamePalette(t: f32) -> vec3<f32> {
  let c0 = vec3<f32>(0.05, 0.0, 0.02);
  let c1 = vec3<f32>(0.6, 0.0, 0.0);
  let c2 = vec3<f32>(1.0, 0.4, 0.0);
  let c3 = vec3<f32>(1.0, 0.9, 0.2);
  let c4 = vec3<f32>(1.0, 1.0, 0.95);
  if t < 0.25 { return mix(c0, c1, t * 4.0); }
  if t < 0.5  { return mix(c1, c2, (t - 0.25) * 4.0); }
  if t < 0.75 { return mix(c2, c3, (t - 0.5) * 4.0); }
  return mix(c3, c4, (t - 0.75) * 4.0);
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.01;
    return normalize(d) * strength / dist2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;

  // Audio envelope
  let bassRaw = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let prevEnv = extraBuffer[0];
  let bass = bass_env(prevEnv, bassRaw, 0.8, 0.15);

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let iterations = i32(mix(24.0, 56.0, clamp(u.zoom_params.x + bass * 0.3, 0.0, 1.0)));
  let spread = mix(0.8, 2.2, u.zoom_params.y);
  let heat = mix(0.5, 2.0, u.zoom_params.z);
  let caAmt = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * spread;

  // Mouse gravity well + attractor
  let mAttr = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * spread * 0.4;
  let gWell = gravityWell(p, mAttr, 0.3 + mouseDown * 0.7);
  p = p - mAttr * 0.3 + gWell * 0.05;

  // Click rotation burst
  let clickBurst = mouseDown * sin(time * 10.0) * 0.1;

  // Temporal feedback seeds subtle drift
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  p = p + prev.xy * 0.015;

  // Depth from readDepthTexture
  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = clamp(depthSample * 1.5, 0.1, 1.0);

  // Video input
  let video = textureLoad(readTexture, coord, 0);
  let luma = dot(video.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let spawnMask = smoothstep(0.65, 0.9, luma);

  var accum = vec2<f32>(0.0);
  var density = 0.0;

  for (var i = 0; i < iterations; i = i + 1) {
    let seed = hash2(p + vec2<f32>(f32(i) * 1.618, time * 0.05));
    let idx = i % 4;

    var tp = p;
    if idx == 0 {
      tp = vec2<f32>(0.5 * p.x + 0.0, 0.5 * p.y + 0.25);
    } else if idx == 1 {
      tp = vec2<f32>(0.5 * p.x + 0.433, 0.5 * p.y + 0.25);
    } else if idx == 2 {
      tp = vec2<f32>(0.5 * p.x - 0.433, 0.5 * p.y + 0.25);
    } else {
      tp = vec2<f32>(0.5 * p.x, 0.5 * p.y - 0.5);
    }

    // Non-linear variation selected by seed + mids morphing
    let varSel = seed.x + mids * 0.1;
    if varSel < 0.33 {
      tp = varSinusoidal(tp * (1.0 + bass * 0.2));
    } else if varSel < 0.66 {
      tp = varSpherical(tp);
    } else {
      tp = varSwirl(tp + clickBurst);
    }

    p = tp;
    let d = length(p);
    density = density + exp(-d * d * 8.0);
    accum = accum + p;
  }

  density = density / f32(iterations) * heat;
  let flameTemp = clamp(density * 3.0, 0.0, 1.0);
  var color = flamePalette(flameTemp) * (0.3 + density * 2.5);

  // HDR bloom
  color = color + flamePalette(flameTemp * 0.7) * density * density * 0.8;

  // Treble sparkle particles
  let sparkle = hash2(uv * 300.0 + time * 5.0).x;
  let sparkleMask = smoothstep(0.96, 1.0, sparkle) * treble * 2.0;
  color = color + vec3<f32>(1.0, 0.95, 0.8) * sparkleMask;

  // Video spawn
  color = mix(color, video.rgb * 1.5, spawnMask * 0.3);

  // Chromatic aberration
  let caMask = smoothstep(0.3, 0.7, density) * caAmt;
  let caR = acesToneMap(vec3<f32>(color.r * 1.15, color.g * 0.95, color.b * 0.85) * 1.5);
  let caB = acesToneMap(vec3<f32>(color.r * 0.85, color.g * 0.95, color.b * 1.15) * 1.5);
  color = mix(acesToneMap(color * 1.5), mix(caR, caB, caMask), caMask * 0.4);

  // Depth-aware compositing
  let z = textureLoad(readDepthTexture, gid.xy, 0).r;
  let fog = 1.0 - exp(-z * 1.5);
  color = mix(color, color * 0.5, fog * 0.4);

  // Alpha: density * flameTemp * depth + interaction intensity
  let clickDist = length(uv - mouse);
  let mouseProx = smoothstep(0.25, 0.0, clickDist);
  let alpha = clamp(density * flameTemp * depthFactor + mouseProx * 0.3 + sparkleMask * 0.5, 0.0, 1.0);

  // Depth output
  let depthOut = clamp(1.0 - flameTemp * 0.8, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));

  // Persist envelope globally (only thread 0,0 writes)
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[0] = bass;
  }
}
