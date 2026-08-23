// ═══════════════════════════════════════════════════════════════════
//  Acid Lissajous 2.0 — Interactivist Upgrade
//  Category: generative
//  Features: lissajous-curves, mouse-gravity, click-burst, audio-reactive,
//            luma-spawn, depth-aware, temporal-feedback, chromatic-aberration,
//            aces-tone-map, emergent-trails
//  Complexity: Medium
//  Updated: 2026-06-29
// ═══════════════════════════════════════════════════════════════════
//  Lissajous figures drawn as glowing neon tubes with acid-trip color
//  cycling. This upgrade makes the curves live: a mouse gravity well bends
//  the strands toward the cursor, click bursts emit shockwaves, bass/mid/
//  treble drive scale/morph/sparkle, video luma spawns extra color, and
//  depth-aware temporal feedback leaves self-advecting dissolving trails.

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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const STRANDS: i32 = 5;
const SAMPLES: i32 = 96;

// ── Hash & noise ────────────────────────────────────────────────
fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
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
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum += amp * valueNoise(p * freq);
    freq *= 2.0;
    amp *= 0.5;
  }
  return sum;
}
fn organicDrift(uv: vec2<f32>, time: f32, scale: f32) -> vec2<f32> {
  let safeScale = max(scale, 0.001);
  let p = uv * safeScale;
  let slow = vec2<f32>(time * 0.11, -time * 0.08);
  let q = vec2<f32>(
    fbm(p + slow, 3),
    fbm(p * 1.37 + vec2<f32>(5.2, 1.3) - slow.yx, 3)
  );
  let r = vec2<f32>(
    fbm(p * 0.73 + q * 2.0 + vec2<f32>(1.7, 9.2), 2),
    fbm(p * 0.91 - q.yx * 2.0 + vec2<f32>(8.1, 2.8), 2)
  );
  return ((q + r * 0.5) * 2.0 - vec2<f32>(1.5)) / safeScale;
}

// ── Color & luminance ───────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let c = hsv.z * hsv.y;
  let h = hsv.x * 6.0;
  let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
  let m = hsv.z - c;
  var rgb: vec3<f32>;
  if      (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else              { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(m);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Post-processing ─────────────────────────────────────────────
fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
  let angle = atan2(uv.y - 0.5, uv.x - 0.5);
  let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
  return vec3<f32>(
    color.r * (1.0 + shift.x * 0.8),
    color.g,
    color.b * (1.0 - shift.y * 0.5)
  );
}

// ── Core entry ──────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res   = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01   = vec2<f32>(pixel) / res;
  let time   = u.config.x * 2.35;
  let aspect = res.x / max(res.y, 1.0);
  let uvCenter = (uv01 - 0.5) * vec2<f32>(aspect, 1.0);

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) { springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 8.0; let springDecay = exp(-omega * dt); let sdelta = springPos - rawMouse; let temp = (springVel + omega * sdelta) * dt;
  springVel = (springVel - omega * temp) * springDecay; springPos = rawMouse + (sdelta + temp) * springDecay;
  if (hasSpring && global_id.x == 0u && global_id.y == 0u) { extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y; extraBuffer[137] = time; extraBuffer[138] = 1.0; }
  let mouse  = springPos;
  let mouseDown = u.zoom_config.w > 0.5;

  // Parameter mapping
  let speed      = mix(0.25, 2.2, u.zoom_params.x) * (1.0 + mids * 0.5);
  let complexity = mix(2.0, 9.0, u.zoom_params.y);
  let glowWidth  = mix(0.014, 0.003, u.zoom_params.z);
  let gravStr    = u.zoom_params.z * 0.35;
  let feedback   = u.zoom_params.w;

  // Mouse gravity well (aspect-correct)
  let mousePos = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  var p = uvCenter * 2.0;
  let toMouse = mousePos - p;
  let dMouse = length(toMouse);
  let gravDir = select(vec2<f32>(0.0), toMouse / max(dMouse, 0.0001), dMouse > 0.001);
  p = p + gravDir * gravStr * (1.0 + bass) * 0.5 / (dMouse * 0.5 + 0.25);

  // Bass-driven field pulse
  let fieldScale = 1.0 + bass * 0.25;
  p = p * fieldScale;

  // ── Lissajous strands ─────────────────────────────────────────
  var totalColor = vec3<f32>(0.0);
  var totalWeight = 0.0;

  let extraStrands = i32(clamp(bass * 2.5, 0.0, 3.0));
  let clickStrands = select(0, 2, mouseDown);
  let activeStrands = min(STRANDS + extraStrands + clickStrands, 9);

  for (var si: i32 = 0; si < activeStrands; si = si + 1) {
    let sf = f32(si);
    let freqX = floor(mix(1.0, complexity, sf / max(f32(STRANDS) - 1.0, 1.0)));
    let freqY = floor(freqX + select(1.0, 0.0, si % 2 == 0));
    let phase = sf * 0.63 + time * speed * (0.7 + sf * 0.11) * (1.0 + bass * 0.3);
    let hueBase = fract(sf / f32(activeStrands) + time * 0.16 * speed + mids * 0.22);

    var minDistSq = 1e9;
    for (var ti: i32 = 0; ti < SAMPLES; ti = ti + 1) {
      let t  = f32(ti) / f32(SAMPLES - 1) * TAU;
      let cx = sin(freqX * t + phase) * (0.85 + treble * 0.12);
      let cy = sin(freqY * t) * (0.85 + bass * 0.12);
      let diff = p - vec2<f32>(cx, cy);
      let d2 = dot(diff, diff);
      minDistSq = min(minDistSq, d2);
    }
    let minDist = sqrt(minDistSq);

    let gw = glowWidth * (1.0 + bass * 0.6);
    let core  = smoothstep(gw, 0.0, minDist);
    let bloom = smoothstep(gw * 4.0, 0.0, minDist) * 0.35;
    let glow = core + bloom;
    let sat = clamp(0.8 + treble * 0.2, 0.0, 1.0);
    let val = glow * (1.5 + mids * 0.8);
    let rgb = hsv2rgb(vec3<f32>(hueBase, sat, 1.0)) * val;

    totalColor = totalColor + rgb;
    totalWeight = totalWeight + glow;
  }

  // ── Click burst shockwave ─────────────────────────────────────
  let clickBurst = select(0.0, 1.0, mouseDown)
                 * smoothstep(0.45, 0.0, dMouse)
                 * (0.6 + bass * 1.5);
  totalColor = totalColor + hsv2rgb(vec3<f32>(fract(time * 0.2), 0.9, 1.0)) * clickBurst;
  totalWeight = totalWeight + clickBurst * 0.5;

  // ── Treble sparkle ────────────────────────────────────────────
  let sparkle = hash21(p * 90.0 + time * 30.0) * treble * treble * 1.2;
  totalColor = totalColor + vec3<f32>(sparkle);

  // ── Luma-keyed video spawn ────────────────────────────────────
  let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
  let videoLuma = luma(video);
  let videoSpawn = smoothstep(0.35, 0.85, videoLuma) * (0.25 + treble * 0.25);
  totalColor = totalColor + videoSpawn
               * hsv2rgb(vec3<f32>(fract(time * 0.08 + videoLuma * 0.5), 0.75, 1.0));
  totalWeight = totalWeight + videoSpawn * 0.3;

  // ── Depth integration ─────────────────────────────────────────
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  // ── Temporal feedback / motion-vector advection ───────────────
  let drift = organicDrift(uv01, time, 5.0) * (0.015 + bass * 0.015);
  let dimsC = vec2<i32>(textureDimensions(dataTextureC));
  let fbCoord = clamp(pixel + vec2<i32>(drift * vec2<f32>(dimsC)), vec2<i32>(0), dimsC - vec2<i32>(1));
  let prev = textureLoad(dataTextureC, fbCoord, 0).rgb;
  let fbMix = feedback * 0.82;
  let decay = 0.88 + feedback * 0.11;
  totalColor = mix(totalColor, prev * decay, fbMix);

  // ── Vignette ──────────────────────────────────────────────────
  let vign = 1.0 - smoothstep(0.55, 1.25, length(uvCenter));
  totalColor = totalColor * vign;

  // ── Chromatic aberration ──────────────────────────────────────
  let caStr = 0.015 * (1.0 + bass) + depth * 0.008;
  totalColor = genChromaticShift(totalColor, uv01, caStr, time);

  // ── Tone map ──────────────────────────────────────────────────
  totalColor = acesToneMap(totalColor * (1.0 + bass * 0.2));

  // ── Semantic alpha ────────────────────────────────────────────
  let intensity = luma(totalColor);
  let alpha = clamp(intensity * 1.6 + bass * 0.05 + videoLuma * 0.15, 0.05, 0.95)
            * (0.7 + depth * 0.25);
  let outDepth = clamp(totalWeight * 0.25 + depth * 0.15, 0.0, 1.0);

  // ── Output ────────────────────────────────────────────────────
  textureStore(writeTexture,      pixel, vec4<f32>(totalColor, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      pixel, vec4<f32>(totalColor, alpha));
}
