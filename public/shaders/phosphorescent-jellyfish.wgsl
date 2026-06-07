// ═══════════════════════════════════════════════════════════════════
//  Phosphorescent Jellyfish
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, chromatic, depth-aware
//  Complexity: High
//  Description: Glowing jellyfish with trailing tentacle bioluminescence.
//               Bass pulses the bell contraction, mids create tentacle wave
//               motion, treble adds individual photophore sparkles.
//               Mouse attracts the jellyfish swarm.
//  Created: 2026-05-30
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

const PI: f32 = 3.14159265;

fn hash21(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

// Jellyfish bell SDF — hemisphere with flattened bottom
fn sdBell(p: vec2<f32>, radius: f32, pulse: f32) -> f32 {
  let r = radius * (1.0 + pulse * 0.15);
  let d = length(p);
  let bell = d - r;
  let bottom = p.y + r * 0.3;
  return max(bell, bottom);
}

// Tentacle glow field
fn tentacleGlow(p: vec2<f32>, origin: vec2<f32>, time: f32, waveStrength: f32, count: f32) -> f32 {
  let rel = p - origin;
  let dist = length(rel);
  var glow = 0.0;
  let tCount = max(count, 3.0);
  for (var i: i32 = 0; i < 8; i++) {
    if (f32(i) >= tCount) { break; }
    let fi = f32(i);
    let jHash = hash22(vec2<f32>(origin.x + fi * 7.3, origin.y + fi * 13.1));
    let tAngle = (fi / tCount) * PI * 2.0 + jHash.x * 0.5;
    let wave = sin(dist * 8.0 - time * 3.0 + tAngle * 3.0 + jHash.y * 6.28318) * waveStrength * 0.3;
    let tentacleX = sin(tAngle) * (dist * 0.5 + 0.1) + wave;
    let tentacleY = -cos(tAngle) * (dist * 0.5 + 0.1) + abs(wave) * 0.5;
    let tPos = vec2<f32>(tentacleX, tentacleY);
    let tDist = length(rel - tPos);
    glow += exp(-tDist * tDist * 80.0) * 0.5;
  }
  return glow;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv01 = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let uv = (uv01 - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mousePos = vec2<f32>(mouse.x * aspect, mouse.y);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let swarmCount  = mix(1.0, 5.0, u.zoom_params.x);
  let bellSize    = mix(0.08, 0.2, u.zoom_params.y);
  let trailPersistence = mix(0.85, 0.99, u.zoom_params.z);
  let glowIntensity    = mix(0.5, 3.0, u.zoom_params.w);

  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var depthVal = 0.0;

  // Deep abyss background
  let abyss = vec3<f32>(0.01, 0.02, 0.05) * (1.0 - length(uv) * 0.5);
  col = abyss;

  let nJelly = i32(clamp(swarmCount, 1.0, 5.0));

  for (var j: i32 = 0; j < nJelly; j++) {
    let fj = f32(j);
    let jHash = hash22(vec2<f32>(fj, fj * 3.7));

    // Orbital motion
    let orbitRadius = 0.2 + jHash.x * 0.3;
    let orbitSpeed = 0.3 + jHash.y * 0.4;
    let angle = time * orbitSpeed + fj * 1.25;
    var jPos = vec2<f32>(cos(angle) * orbitRadius, sin(angle) * orbitRadius * 0.6);

    // Mouse attraction
    let toMouse = mousePos - jPos;
    let distToMouse = length(toMouse);
    jPos += normalize(toMouse + vec2<f32>(0.001)) * (1.0 / (1.0 + distToMouse * 3.0)) * 0.15;

    // Bass-driven bell pulse
    let pulse = sin(time * 3.0 + fj) * bass * 0.5;
    let size = bellSize * (0.8 + jHash.y * 0.4);

    // Bell distance and glow
    let bellDist = sdBell(uv - jPos, size, pulse);
    let bellGlow = exp(-bellDist * bellDist * 200.0) * glowIntensity;

    // Photophore sparkles driven by treble
    let sparkleUV = floor((uv - jPos) * 40.0 + time * 10.0 * treble);
    let sparkle = step(0.97, hash21(sparkleUV)) * treble * 2.0;
    let sparkleGlow = exp(-bellDist * bellDist * 100.0) * sparkle * glowIntensity;

    // Tentacle bioluminescence driven by mids
    let tentGlow = tentacleGlow(uv, jPos, time + fj, mids, 4.0 + jHash.x * 4.0) * glowIntensity;

    // Per-jellyfish hue (cyan → violet)
    let hue = fj / 5.0 + 0.55;
    let bellCol = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
    );

    col += bellCol * bellGlow * 0.8;
    col += bellCol * sparkleGlow;
    col += bellCol * tentGlow * 0.6;
    alpha += bellGlow + tentGlow * 0.5 + sparkleGlow;
    depthVal = max(depthVal, bellGlow + tentGlow);
  }

  // ═══ Chromatic dispersion on temporal feedback ═══
  let cStr = 0.004 + bass * 0.006;
  let cDir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));

  let prevR = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (1.0 + mids), 0.0).r;
  let prevG = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (0.7 + bass * 0.5), 0.0).g;
  let prevB = textureSampleLevel(dataTextureC, u_sampler, uv01 - cDir * cStr * (1.2 + treble), 0.0).b;
  var prevCol = vec3<f32>(prevR, prevG, prevB);

  // Temporal feedback blend
  col = mix(col, prevCol * trailPersistence, 0.2 + bass * 0.05);

  // Chromatic dispersion on current frame elements
  let dispersed = vec3<f32>(
    col.r + mids * 0.05,
    col.g + bass * 0.03,
    col.b + treble * 0.08
  );
  col = mix(col, dispersed, 0.3);

  alpha = clamp(alpha, 0.0, 1.0);
  let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
}
