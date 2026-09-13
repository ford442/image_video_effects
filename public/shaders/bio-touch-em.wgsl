// ═══════════════════════════════════════════════════════════════════
//  Bio Touch EM
//  Category: advanced-hybrid
//  Features: mouse-driven, field-simulation, organic, temporal, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-11
//  Ideas: mitosis twin pulse; membrane depolarization wave
//  A packing: ACES display RGBA
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let k = vec2<f32>(
    dot(p, vec2<f32>(127.1, 311.7)),
    dot(p, vec2<f32>(269.5, 183.3))
  );
  return fract(sin(k) * 43758.5453);
}

fn voronoi(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  var minDist = 1.0;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let cellId = i + neighbor;
      let point = neighbor + hash22(cellId) - f;
      let dist = length(point);
      minDist = min(minDist, dist);
    }
  }
  return minDist;
}

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn electricField(pos: vec2<f32>, chargePos: vec2<f32>, charge: f32) -> vec2<f32> {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * normalize(r) / (dist * dist);
}

fn magneticField(pos: vec2<f32>, chargePos: vec2<f32>, velocity: vec2<f32>, charge: f32) -> f32 {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * (velocity.x * r.y - velocity.y * r.x) / (dist * dist * dist);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let glowRadius = u.zoom_params.x * 0.5;
  let cellDensity = 10.0 + u.zoom_params.y * 50.0;
  let colorShift = u.zoom_params.z;
  let fieldStrength = u.zoom_params.w * 2.0;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let hasMouseBuf = arrayLength(&extraBuffer) > 134u;
  var prevMouse = mousePos;
  if (hasMouseBuf) {
    prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (global_id.x == 0u && global_id.y == 0u) {
      extraBuffer[133] = mousePos.x;
      extraBuffer[134] = mousePos.y;
    }
  }
  let mouseVel = (mousePos - prevMouse) * 60.0;

  let eField = electricField(uv, mousePos, fieldStrength);
  let bField = magneticField(uv, mousePos, mouseVel, fieldStrength);

  var totalE = eField;
  var totalB = bField;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0) {
      let orbitAngle = elapsed * 2.0 + f32(i) * 1.256;
      let orbitRadius = 0.05 + 0.1 * smoothstep(0.0, 1.0, elapsed);
      let orbitPos = mousePos + vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * orbitRadius;
      let secondaryCharge = -fieldStrength * exp(-elapsed * 0.8);
      let secVel = vec2<f32>(-sin(orbitAngle), cos(orbitAngle)) * 2.0;
      totalE = totalE + electricField(uv, orbitPos, secondaryCharge);
      totalB = totalB + magneticField(uv, orbitPos, secVel, secondaryCharge);
    }
  }

  let fieldMag = length(totalE);
  let fieldDir = select(vec2<f32>(0.0), normalize(totalE), fieldMag > 0.0001);

  let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let influence = smoothstep(glowRadius + 0.1, glowRadius, dist);

  let fieldDistort = fieldDir * smoothstep(0.0, 2.0, fieldMag) * 0.03;
  let offset = vec2<f32>(sin(time * 0.5), cos(time * 0.4)) * 0.1 + fieldDistort;
  let voronoiUV = (uv + offset) * cellDensity;
  let v = voronoi(voronoiUV);
  let glow = 1.0 - smoothstep(0.0, 0.5, v);

  // Idea 1 — mitosis twin pulse: bass triggers paired brighten on division axis
  let cellId = floor(voronoiUV);
  let divisionAxis = normalize(hash22(cellId) - vec2<f32>(0.5));
  let alongAxis = abs(dot(fract(voronoiUV) - vec2<f32>(0.5), divisionAxis));
  let twinPulse = smoothstep(0.35, 0.0, alongAxis) * smoothstep(0.25, 0.55, bass) * glow;
  let mitosisGlow = twinPulse * (0.5 + 0.5 * sin(time * 6.0 + bass * 8.0));

  // Idea 2 — membrane depolarization wave along E-field across cell walls
  let membrane = smoothstep(0.42, 0.48, v) * (1.0 - smoothstep(0.48, 0.54, v));
  let depolWave = 0.5 + 0.5 * sin(dot(uv, fieldDir) * 40.0 - time * 4.0 + fieldMag * 3.0);
  let membraneWave = membrane * depolWave * smoothstep(0.0, 0.6, fieldMag);

  let pulse = 0.5 + 0.5 * sin(time * (2.0 + u.zoom_params.w * 5.0) - dist * 10.0 + totalB * 2.0);
  let finalGlow = glow * influence * pulse * (1.0 + mouseDown * 2.0) + mitosisGlow * 0.8 + membraneWave * 0.6;

  let displacedUV = clamp(uv + fieldDistort * influence, vec2<f32>(0.0), vec2<f32>(1.0));
  let src = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

  var tint = vec3<f32>(0.2, 0.8, 0.6);
  tint = select(tint, vec3<f32>(0.8, 0.2, 0.6), colorShift > 0.3);
  tint = select(tint, vec3<f32>(0.2, 0.4, 0.9), colorShift > 0.6);
  tint = hueShift(tint, totalB * influence);

  var outColor = src.rgb + tint * finalGlow;
  outColor = outColor + vec3<f32>(0.9, 0.4, 1.0) * mitosisGlow * 0.35;
  outColor = outColor + vec3<f32>(0.3, 0.85, 1.0) * membraneWave * 0.25;

  let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
  let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
  let streamline = smoothstep(0.4, 0.6, streamNoise) * smoothstep(0.0, 0.5, fieldMag);
  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
  outColor = mix(outColor, fieldColor, streamline * 0.25 * influence);

  let coreGlow = exp(-dist * dist * 400.0) * fieldStrength;
  outColor = outColor + vec3<f32>(0.6, 0.9, 1.0) * coreGlow;

  let alpha = clamp(influence + streamline * 0.2 + mitosisGlow * 0.3 + membraneWave * 0.2 + src.a * 0.25, 0.0, 1.0);
  let displayRgb = acesToneMap(outColor);

  textureStore(writeTexture, pixel, vec4<f32>(displayRgb, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(displayRgb, alpha));

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
