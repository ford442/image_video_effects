// ═══════════════════════════════════════════════════════════════════
//  Gen Astro Orrery Blackbody
//  Category: advanced-hybrid
//  Features: generative, blackbody-radiation, audio-reactive, raymarched
//  Complexity: Very High
//  Chunks From: gen-astro-kinetic-chrono-orrery.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-5 — Generative & Hybrid Enhancer
// ═══════════════════════════════════════════════════════════════════
//  A kinetic astronomical orrery where each ring's thermal energy
//  determines its blackbody color. Rotating rings glow with physically
//  accurate star temperatures from cool red dwarfs to blazing blue giants.
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

const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 100.0;

// ═══ CHUNK: rot2D (from gen-astro-kinetic-chrono-orrery.wgsl) ═══
fn rot2D(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
  let q = vec2<f32>(length(vec2<f32>(p.x, p.z)) - t.x, p.y);
  return length(q) - t.y;
}

// ═══ CHUNK: blackbodyColor (from spec-blackbody-thermal.wgsl) ═══
fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
  let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
  var r: f32;
  var g: f32;
  var b: f32;
  if (t <= 6.5) {
    r = 1.0;
    g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
    b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
  } else {
    r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
    g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
    b = 1.0;
  }
  let radiance = pow(t / 6.5, 4.0);
  return vec3<f32>(r, g, b) * radiance;
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

// Map ring index to temperature based on orbital energy
fn ringTemperature(ringIndex: f32, complexity: f32, speed: f32, audioReact: f32, bass: f32) -> f32 {
  // Inner rings = hotter (higher orbital velocity), outer = cooler
  let baseTemp = mix(12000.0, 2000.0, ringIndex / complexity);
  // Speed increases effective temperature
  let speedBoost = speed * 3000.0 * (1.0 + ringIndex * 0.2);
  // Audio reactivity heats things up
  let audioHeat = bass * audioReact * 5000.0;
  return baseTemp + speedBoost + audioHeat;
}

fn map(p: vec3<f32>, time: f32, complexity: f32, speed: f32, audioReact: f32, bass: f32, outTemp: ptr<function, f32>) -> f32 {
  var d = MAX_DIST;
  var q = p;

  // Apply mouse rotation
  let rot_yz = rot2D(u.zoom_config.z * 3.14) * vec2<f32>(q.y, q.z);
  q.y = rot_yz.x;
  q.z = rot_yz.y;
  let rot_xz = rot2D(u.zoom_config.y * 3.14) * vec2<f32>(q.x, q.z);
  q.x = rot_xz.x;
  q.z = rot_xz.y;

  let loop_count = i32(clamp(complexity, 1.0, 10.0));
  let speed_mult = 1.0 + bass * audioReact;

  // Track which ring is closest for temperature
  var closestRing = -1.0;
  var closestD = MAX_DIST;

  for(var i = 0; i < loop_count; i++) {
    let fi = f32(i);
    let rot_xy = rot2D(time * 0.2 * speed * (fi + 1.0) * speed_mult + bass * audioReact * 3.14) * vec2<f32>(q.x, q.y);
    q.x = rot_xy.x;
    q.y = rot_xy.y;
    let rot_yz_inner = rot2D(0.5) * vec2<f32>(q.y, q.z);
    q.y = rot_yz_inner.x;
    q.z = rot_yz_inner.y;

    let ring = sdTorus(q, vec2<f32>(2.0 + fi * 0.5, 0.05));
    if (ring < closestD) {
      closestD = ring;
      closestRing = fi;
    }
    d = min(d, ring);
  }

  // Set temperature for closest ring
  if (closestRing >= 0.0) {
    *outTemp = ringTemperature(closestRing, complexity, speed, audioReact, bass);
  } else {
    *outTemp = 3000.0;
  }

  return d;
}

fn calcNormal(p: vec3<f32>, time: f32, complexity: f32, speed: f32, audioReact: f32, bass: f32, outTemp: ptr<function, f32>) -> vec3<f32> {
  let e = 0.001;
  var dummy: f32 = 0.0;
  var d = map(p, time, complexity, speed, audioReact, bass, &dummy);
  return normalize(vec3<f32>(
    map(p + vec3<f32>(e, 0.0, 0.0), time, complexity, speed, audioReact, bass, outTemp) - d,
    map(p + vec3<f32>(0.0, e, 0.0), time, complexity, speed, audioReact, bass, outTemp) - d,
    map(p + vec3<f32>(0.0, 0.0, e), time, complexity, speed, audioReact, bass, outTemp) - d
  ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let dims = vec2<f32>(textureDimensions(writeTexture));
  let uv = (vec2<f32>(id.xy) * 2.0 - dims) / dims.y;
  let screen_uv = (vec2<f32>(id.xy) + 0.5) / dims;

  let time = u.config.x;
  let complexity = u.zoom_params.x;
  let speed = u.zoom_params.y;
  let glowIntensity = u.zoom_params.z;
  let audioReact = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;

  // Ray setup
  let ro = vec3<f32>(0.0, 0.0, -5.0);
  let rd = normalize(vec3<f32>(uv, 1.0));

  var t = 0.0;
  var ringTemp = 3000.0;
  for(var i=0; i<MAX_STEPS; i++) {
    let p = ro + rd * t;
    let d = map(p, time, complexity, speed, audioReact, bass, &ringTemp);
    if(d < SURF_DIST || t > MAX_DIST) { break; }
    t += d;
  }

  var col = vec3<f32>(0.0);
  var alpha = 0.0;

  if(t < MAX_DIST) {
    let p = ro + rd * t;
    var tempForNormal: f32 = 0.0;
    let n = calcNormal(p, time, complexity, speed, audioReact, bass, &tempForNormal);
    let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));

    // Blackbody color from ring temperature
    let thermalColor = blackbodyColor(ringTemp);

    let diff = max(dot(n, lightDir), 0.0);
    let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0);

    // Thermal emission + diffuse reflection
    col = thermalColor * (diff * 0.5 + 0.2) + vec3<f32>(spec * 0.3);

    // HDR boost for hot stars
    col = col * glowIntensity;

    // Tone map
    col = toneMapACES(col);

    let falloff = 1.0 - t / MAX_DIST;
    alpha = falloff * glowIntensity;
  } else {
    // Background: faint starfield with blackbody tint
    let bgNoise = fract(sin(dot(screen_uv, vec2<f32>(12.9898, 78.233)) + time * 0.1) * 43758.5453);
    let bgTemp = mix(3000.0, 8000.0, bgNoise);
    col = blackbodyColor(bgTemp) * 0.02 * glowIntensity;
    col = toneMapACES(col);
    alpha = 0.1;
  }

  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screen_uv, 0.0).r;
  textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
