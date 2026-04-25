// ═══════════════════════════════════════════════════════════════════
//  Block Distort EM
//  Category: advanced-hybrid
//  Features: mouse-driven, field-simulation, chromatic, temporal
//  Complexity: High
//  Chunks From: block-distort-interactive.wgsl, mouse-electromagnetic-aurora.wgsl
//  Created: 2026-04-18
//  By: Agent CB-9
// ═══════════════════════════════════════════════════════════════════
//  Grid blocks are pushed by mouse proximity, then distorted by EM
//  field lines. Electric field displaces UVs; magnetic field rotates
//  hue per-block. Click ripples spawn orbiting secondary charges.
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
  zoom_params: vec4<f32>,  // x=BlockSize, y=PushStrength, z=RGBSplit, w=FieldStrength
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 (from mouse-electromagnetic-aurora.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: hueShift (from mouse-electromagnetic-aurora.wgsl) ═══
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
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

  // Parameters
  let blockSize = mix(10.0, 100.0, u.zoom_params.x);
  let pushStrength = u.zoom_params.y * 2.0;
  let rgbSplit = u.zoom_params.z * 0.1;
  let fieldStrength = u.zoom_params.w * 2.0;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // ── EM Field Computation ──
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;

  // Store current mouse position for next frame
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  // Primary EM charge at mouse
  let eField = electricField(uv, mousePos, fieldStrength);
  let bField = magneticField(uv, mousePos, mouseVel, fieldStrength);

  // Secondary charges from click ripples (opposite polarity, orbiting)
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

  // ── Block Distort Logic (from block-distort-interactive) ──
  let gridUV = uv * vec2<f32>(resolution.x / blockSize, resolution.y / blockSize);
  let cellID = floor(gridUV);
  let cellCenterGrid = cellID + 0.5;
  let cellCenterUV = cellCenterGrid / vec2<f32>(resolution.x / blockSize, resolution.y / blockSize);

  // Distance from cell center to mouse
  let distVec = (cellCenterUV - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let radius = 0.5;

  // Push away from mouse
  let pushMask = smoothstep(radius, 0.0, dist);
  let pushDir = normalize(distVec);
  let blockDisplacement = pushDir * pushMask * pushStrength * 0.1;

  // EM field adds extra displacement to blocks
  let emDisplacement = fieldDir * smoothstep(0.0, 2.0, fieldMag) * 0.05;
  let totalDisplacement = blockDisplacement + emDisplacement;

  // RGB split along displacement + field direction
  let split = totalDisplacement * rgbSplit * 5.0 + fieldDir * rgbSplit * 0.05;

  let sampleR = textureSampleLevel(readTexture, u_sampler, uv - totalDisplacement + split, 0.0);
  let sampleG = textureSampleLevel(readTexture, u_sampler, uv - totalDisplacement, 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, uv - totalDisplacement - split, 0.0);

  var finalColor = vec3<f32>(sampleR.r, sampleG.g, sampleB.b);
  var finalAlpha = (sampleR.a + sampleG.a + sampleB.a) / 3.0;
  finalAlpha = mix(finalAlpha, finalAlpha * 0.9, pushMask);

  // Magnetic field rotates hue per block
  let hueRot = totalB * 0.5;
  finalColor = hueShift(finalColor, hueRot * pushMask);

  // Block edges highlighted when pushed
  let cellUV = fract(gridUV);
  let edgeDist = min(min(cellUV.x, 1.0 - cellUV.x), min(cellUV.y, 1.0 - cellUV.y));
  let edge = (1.0 - smoothstep(0.0, 0.05, edgeDist)) * pushMask;
  finalColor = finalColor + vec3<f32>(edge * 0.5);
  finalAlpha = mix(finalAlpha, 1.0, edge * 0.2);

  // Field line overlay near mouse
  let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
  let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
  let streamline = smoothstep(0.4, 0.6, streamNoise) * smoothstep(0.0, 0.5, fieldMag);
  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
  finalColor = mix(finalColor, fieldColor, streamline * 0.3);

  // Core glow near mouse
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let coreGlow = exp(-mouseDist * mouseDist * 400.0) * fieldStrength;
  finalColor = finalColor + vec3<f32>(0.6, 0.9, 1.0) * coreGlow;

  // Boost on click
  finalColor = finalColor * (1.0 + mouseDown * 0.3);

  finalAlpha = clamp(finalAlpha, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}

