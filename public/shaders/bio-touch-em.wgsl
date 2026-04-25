// ═══════════════════════════════════════════════════════════════════
//  Bio Touch EM
//  Category: advanced-hybrid
//  Features: mouse-driven, field-simulation, organic, temporal
//  Complexity: High
//  Chunks From: bio-touch.wgsl, mouse-electromagnetic-aurora.wgsl
//  Created: 2026-04-18
//  By: Agent CB-9
// ═══════════════════════════════════════════════════════════════════
//  Bio-luminescent cellular structures are distorted by electric
//  field lines. Magnetic field rotates cell glow colors. EM field
//  lines overlay the organic pattern. Click ripples spawn orbiting
//  secondary charges that sweep through cells.
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=Density, z=ColorShift, w=FieldStrength
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash22 (from bio-touch.wgsl) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
  let k = vec2<f32>(
    dot(p, vec2<f32>(127.1, 311.7)),
    dot(p, vec2<f32>(269.5, 183.3))
  );
  return fract(sin(k) * 43758.5453);
}

// ═══ CHUNK: voronoi (from bio-touch.wgsl) ═══
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

// ═══ CHUNK: hueShift (from mouse-electromagnetic-aurora.wgsl) ═══
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

// ═══ CHUNK: hash12 (from mouse-electromagnetic-aurora.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
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
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let glowRadius = u.zoom_params.x * 0.5;
  let cellDensity = 10.0 + u.zoom_params.y * 50.0;
  let colorShift = u.zoom_params.z;
  let fieldStrength = u.zoom_params.w * 2.0;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // ── EM Field Computation ──
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;

  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

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

  // ── Bio-Touch Logic (from bio-touch) ──
  let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let influence = smoothstep(glowRadius + 0.1, glowRadius, dist);

  // EM field distorts voronoi UVs
  let fieldDistort = fieldDir * smoothstep(0.0, 2.0, fieldMag) * 0.03;
  let offset = vec2<f32>(sin(time * 0.5), cos(time * 0.4)) * 0.1 + fieldDistort;
  let v = voronoi((uv + offset) * cellDensity);
  let glow = 1.0 - smoothstep(0.0, 0.5, v);

  // Pulse modified by magnetic field
  let pulse = 0.5 + 0.5 * sin(time * (2.0 + u.zoom_params.w * 5.0) - dist * 10.0 + totalB * 2.0);
  let finalGlow = glow * influence * pulse * (1.0 + mouseDown * 2.0);

  // Sample Image
  let displacedUV = uv + fieldDistort * influence;
  let color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Color Tinting
  var tint = vec3<f32>(0.2, 0.8, 0.6);
  if (colorShift > 0.3) { tint = vec3<f32>(0.8, 0.2, 0.6); }
  if (colorShift > 0.6) { tint = vec3<f32>(0.2, 0.4, 0.9); }

  // Magnetic field rotates tint hue
  tint = hueShift(tint, totalB * influence);

  // Composite
  var outColor = color + tint * finalGlow;

  // Field line overlay on glow regions
  let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
  let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
  let streamline = smoothstep(0.4, 0.6, streamNoise) * smoothstep(0.0, 0.5, fieldMag);
  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
  outColor = mix(outColor, fieldColor, streamline * 0.25 * influence);

  // Core glow near mouse
  let coreGlow = exp(-dist * dist * 400.0) * fieldStrength;
  outColor = outColor + vec3<f32>(0.6, 0.9, 1.0) * coreGlow;

  // Alpha boosted by field influence
  let alpha = clamp(influence + streamline * 0.2, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outColor, alpha));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
