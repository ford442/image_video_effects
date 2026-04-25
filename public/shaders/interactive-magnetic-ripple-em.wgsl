// ═══════════════════════════════════════════════════════════════════
//  interactive-magnetic-ripple-em
//  Category: advanced-hybrid
//  Features: mouse-driven, field-simulation, chromatic, ripple
//  Complexity: High
//  Chunks From: interactive-magnetic-ripple.wgsl, mouse-electromagnetic-aurora.wgsl
//  Created: 2026-04-18
//  By: Agent CB-25
// ═══════════════════════════════════════════════════════════════════
//  Magnetic field distortion meets electromagnetic aurora physics.
//  Mouse acts as an electric charge generating EM fields while also
//  creating magnetic ripples. Electric fields displace UVs; magnetic
//  fields rotate hue. Ripple waves modulate the displacement.
//  Secondary orbiting charges spawn from click ripples.
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

// ═══ CHUNK: hueShift (from stellar-plasma.wgsl) ═══
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
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let fieldStrength = u.zoom_params.x * 2.0;
  let rippleFreq = u.zoom_params.y * 50.0;
  let damping = u.zoom_params.z;
  let colorRotation = u.zoom_params.w * 3.14159;

  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mousePos = u.zoom_config.yz;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseDown = u.zoom_config.w;

  // Store current mouse position for next frame
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  // Primary EM field from mouse
  let eField = electricField(uv, mousePos, fieldStrength);
  let bField = magneticField(uv, mousePos, mouseVel, fieldStrength);

  // Secondary charges from ripples
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

  // Magnetic ripple modulation (from interactive-magnetic-ripple)
  var totalDisplacement = vec2<f32>(0.0);
  if (mousePos.x >= 0.0) {
    let diff = mousePos - uv;
    let diffAspect = vec2<f32>(diff.x * aspect, diff.y);
    let dist = length(diffAspect);
    let dir = normalize(diff);
    let mag = fieldStrength / (dist + 0.1);
    let ripple = cos(dist * rippleFreq - time * 5.0) * exp(-dist * damping * 5.0);
    totalDisplacement = dir * (mag * 0.1 + ripple * 0.05);
  }

  // Combine electric field displacement with magnetic ripple
  let displacedUV = uv + fieldDir * smoothstep(0.0, 2.0, fieldMag) * 0.15 + totalDisplacement;

  // Chromatic aberration from magnetic ripple
  let aberration = 0.03;
  let rUV = displacedUV - totalDisplacement * (1.0 + aberration);
  let gUV = displacedUV - totalDisplacement;
  let bUV = displacedUV - totalDisplacement * (1.0 - aberration);

  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var color = vec3<f32>(r, g, b);

  // Hue rotation from magnetic field
  let hueRot = totalB * colorRotation * 0.5;
  color = hueShift(color, hueRot);

  // Streamline overlay
  let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
  let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
  let streamline = smoothstep(0.4, 0.6, streamNoise) * smoothstep(0.0, 0.5, fieldMag);
  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
  color = mix(color, fieldColor, streamline * 0.3);

  // Core glow near mouse
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let coreGlow = exp(-mouseDist * mouseDist * 400.0) * fieldStrength;
  color = color + vec3<f32>(0.6, 0.9, 1.0) * coreGlow * 0.5;

  let alpha = clamp(totalB * 0.5 + 0.5, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
