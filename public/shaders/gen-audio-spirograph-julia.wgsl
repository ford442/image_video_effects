// ═══════════════════════════════════════════════════════════════════
//  Gen Audio Spirograph Julia
//  Category: advanced-hybrid
//  Features: audio-reactive, fractal, mouse-driven, procedural, temporal
//  Complexity: Very High
//  Chunks From: gen-audio-spirograph.wgsl, mouse-julia-morph.wgsl
//  Created: 2026-04-18
//  By: Agent CB-5 — Generative & Hybrid Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Audio-reactive spirograph curves that unfold into mouse-driven
//  Julia set fractals. Each harmonic ring breathes with audio while
//  the Julia constant morphs via mouse position, creating organic
//  mathematical flora that responds to both sound and touch.
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: julia (from mouse-julia-morph.wgsl) ═══
fn julia(z0: vec2<f32>, c: vec2<f32>, maxIter: i32) -> vec2<f32> {
  var z = z0;
  var i = 0;
  for (; i < maxIter; i = i + 1) {
    if (dot(z, z) > 4.0) { break; }
    z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
  }
  let smooth_i = select(f32(i), f32(i) - log2(log2(max(dot(z, z), 1.0001))) + 4.0, dot(z, z) > 1.0);
  return vec2<f32>(smooth_i, f32(maxIter));
}

// ═══ CHUNK: epitrochoid (from gen-audio-spirograph.wgsl) ═══
fn epitrochoid(t: f32, R: f32, r: f32, d: f32) -> vec2<f32> {
  let k = R / r;
  let x = (R + r) * cos(t) - d * cos((k + 1.0) * t);
  let y = (R + r) * sin(t) - d * sin((k + 1.0) * t);
  return vec2<f32>(x, y);
}

fn distToSegment(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = uv - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

fn hsl2rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
  let c = (1.0 - abs(2.0 * l - 1.0)) * s;
  let x = c * (1.0 - abs(fract(h * 6.0) * 2.0 - 1.0));
  let m = l - c * 0.5;
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  if (h < 1.0/6.0) { r = c; g = x; }
  else if (h < 2.0/6.0) { r = x; g = c; }
  else if (h < 3.0/6.0) { g = c; b = x; }
  else if (h < 4.0/6.0) { g = x; b = c; }
  else if (h < 5.0/6.0) { r = x; b = c; }
  else { r = c; b = x; }
  return vec3<f32>(r + m, g + m, b + m);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / min(resolution.x, resolution.y);
  let screen_uv = vec2<f32>(global_id.xy) / resolution;
  let t = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Parameters
  let baseFreq = mix(0.5, 3.0, u.zoom_params.x);
  let juliaMix = u.zoom_params.y;
  let trailLength = mix(0.3, 0.95, u.zoom_params.z);
  let lineThickness = mix(0.001, 0.01, u.zoom_params.w);

  // Mouse controls Julia constant
  let mousePos = u.zoom_config.yz;
  let mouseC = vec2<f32>(
    (mousePos.x - 0.5) * 2.0,
    (mousePos.y - 0.5) * 2.0
  );
  let autoC = vec2<f32>(
    cos(t * 0.3) * 0.7,
    sin(t * 0.5) * 0.4
  );
  let juliaC = mix(mouseC, autoC, 0.3);

  // Audio
  let audio = u.zoom_config.x;
  let audioMod = 1.0 + audio * 2.0;
  let bass = plasmaBuffer[0].x;

  // Background accumulation for trails
  let prevCol = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;

  let ratios = array<f32, 5>(1.0, 3.0/2.0, 4.0/3.0, 5.0/4.0, 5.0/3.0);
  let harmonics = array<f32, 5>(1.0, 2.0, 3.0, 4.0, 5.0);

  var minDist = 1000.0;
  var curveColor = vec3<f32>(0.0);
  var totalIntensity = 0.0;
  var juliaIter = 0.0;

  // Generate spirograph curves with embedded Julia patterns
  for (var i: i32 = 0; i < 5; i++) {
    let ratio = ratios[i];
    let harmonic = harmonics[i];

    let R = 0.3 * (1.0 + f32(i) * 0.1);
    let r = R / (ratio * harmonic * baseFreq);
    let d = r * 0.8 * audioMod;

    let speed = 0.5 + f32(i) * 0.1;
    let time = t * speed;

    let pos = epitrochoid(time, R, r, d);
    let prevPos = epitrochoid(time - 0.05, R, r, d);

    let dist = distToSegment(uv, pos, prevPos);

    // Julia coloring at this curve point
    let z0 = (uv - pos * 0.5) * vec2<f32>(3.0 * aspect, 3.0);
    let jResult = julia(z0, juliaC, 30);
    let jIter = jResult.x;

    let hue = fract(f32(i) * 0.2 + t * 0.05 + jIter * 0.02);
    let sat = 0.7 + audio * 0.3;
    let light = 0.5 + audio * 0.3;
    let col = hsl2rgb(hue, sat, light);

    let intensity = 1.0 / (1.0 + f32(i) * 0.5);
    if (dist < minDist) {
      minDist = dist;
      curveColor = col * intensity;
      totalIntensity = intensity;
      juliaIter = jIter;
    }
  }

  // Create glow effect
  let glow = smoothstep(lineThickness * 5.0, lineThickness, minDist);
  let core = smoothstep(lineThickness * 2.0, 0.0, minDist);

  // Julia pattern overlay
  let screenZ0 = (screen_uv - 0.5) * vec2<f32>(3.0 * aspect, 3.0);
  let screenJulia = julia(screenZ0, juliaC, i32(mix(30.0, 80.0, juliaMix)));
  let juliaValue = screenJulia.x / screenJulia.y;
  let juliaPattern = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (juliaValue + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (juliaValue + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (juliaValue + 0.67))
  ) * juliaMix * 0.3;

  // Final color
  var col = curveColor * glow + vec3<f32>(1.0) * core * 0.5;
  col = col + juliaPattern;

  // Add trail accumulation
  col = col + prevCol * trailLength * 0.9;

  // Vignette
  let vignette = 1.0 - length(uv) * 0.8;
  col = col * vignette;

  // Store for feedback
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col * 0.95, 1.0));
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
