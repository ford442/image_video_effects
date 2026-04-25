// ═══════════════════════════════════════════════════════════════════
//  Sim: Slime Mold Growth + EM Field
//  Category: simulation
//  Features: simulation, agent-based, mouse-driven, electromagnetic, interactive
//  Complexity: Very High
//  Chunks From: sim-slime-mold-growth, mouse-electromagnetic-aurora
//  Created: 2026-04-18
//  By: Agent CB-4 - Mouse Physics Injector
// ═══════════════════════════════════════════════════════════════════
//  Physarum-style slime mold with mouse electromagnetic field interaction.
//  Mouse acts as a moving electric charge; agents steer along field lines.
//  Click ripples spawn opposite-polarity secondary charges.
//  Alpha channel stores EM field magnitude blended with trail density.
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

// ═══ CHUNK: hash22 (from gen_grid.wgsl) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

// ═══ CHUNK: hueShift (from stellar-plasma.wgsl) ═══
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

// ═══ CHUNK: electricField (from mouse-electromagnetic-aurora.wgsl) ═══
fn electricField(pos: vec2<f32>, chargePos: vec2<f32>, charge: f32) -> vec2<f32> {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * normalize(r) / (dist * dist);
}

// ═══ CHUNK: magneticField (from mouse-electromagnetic-aurora.wgsl) ═══
fn magneticField(pos: vec2<f32>, chargePos: vec2<f32>, velocity: vec2<f32>, charge: f32) -> f32 {
  let r = pos - chargePos;
  let dist = max(length(r), 0.001);
  return charge * (velocity.x * r.y - velocity.y * r.x) / (dist * dist * dist);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;

  // Parameters
  let sensorAngle = mix(0.2, 1.0, u.zoom_params.x);
  let decayRate = mix(0.9, 0.995, u.zoom_params.y);
  let particleCount = mix(100.0, 2000.0, u.zoom_params.z);
  let randomness = mix(0.0, 0.3, u.zoom_params.w);

  let chargeStrength = mix(0.5, 3.0, u.zoom_params.x);
  let fieldVis = mix(0.0, 1.0, u.zoom_params.y);
  let emInfluence = mix(0.0, 1.0, u.zoom_params.z);
  let rippleCharge = mix(0.5, 2.0, u.zoom_params.w);

  // Store mouse pos at (0,0) for velocity tracking next frame
  if (gid.x == 0u && gid.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  // Previous mouse for velocity
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;

  // Compute EM field at this pixel
  let eField = electricField(uv, mousePos, chargeStrength);
  let bField = magneticField(uv, mousePos, mouseVel, chargeStrength);

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
      let secondaryCharge = -rippleCharge * exp(-elapsed * 0.8);
      let secVel = vec2<f32>(-sin(orbitAngle), cos(orbitAngle)) * 2.0;
      totalE = totalE + electricField(uv, orbitPos, secondaryCharge);
      totalB = totalB + magneticField(uv, orbitPos, secVel, secondaryCharge);
    }
  }

  let fieldMag = length(totalE);
  let fieldDir = select(vec2<f32>(0.0), normalize(totalE), fieldMag > 0.0001);
  let emAngle = atan2(totalE.y, totalE.x);

  // Read trail map
  let trail = textureLoad(dataTextureC, gid.xy, 0).r;

  // Diffuse and decay trails
  var sum = 0.0;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      sum = sum + textureLoad(dataTextureC, vec2<i32>(gid.xy) + vec2<i32>(x, y), 0).r;
    }
  }
  let diffused = sum / 9.0;
  var newTrail = diffused * decayRate;

  // Simulate agent deposits with EM field steering
  var deposit = 0.0;
  let numSimulatedAgents = min(i32(particleCount / 10.0), 50);

  for (var i: i32 = 0; i < numSimulatedAgents; i = i + 1) {
    let fi = f32(i);
    let agentSeed = vec2<f32>(fi * 1.234, fi * 3.456);
    var agentPos = vec2<f32>(
      0.1 + hash12(agentSeed) * 0.8,
      0.1 + hash12(agentSeed + 1.0) * 0.8
    );
    var agentAngle = hash12(agentSeed + 2.0) * 6.28 + time * 0.5;

    for (var step: i32 = 0; step < 20; step = step + 1) {
      let leftAngle = agentAngle - sensorAngle;
      let rightAngle = agentAngle + sensorAngle;

      let leftSense = textureSampleLevel(dataTextureC, u_sampler,
        clamp(agentPos + vec2<f32>(cos(leftAngle), sin(leftAngle)) * 0.02, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
      let centerSense = textureSampleLevel(dataTextureC, u_sampler,
        clamp(agentPos + vec2<f32>(cos(agentAngle), sin(agentAngle)) * 0.02, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
      let rightSense = textureSampleLevel(dataTextureC, u_sampler,
        clamp(agentPos + vec2<f32>(cos(rightAngle), sin(rightAngle)) * 0.02, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;

      var steerAngle = 0.0;
      if (centerSense < leftSense && centerSense < rightSense) {
        steerAngle = (hash12(agentPos + time) - 0.5) * randomness;
      } else if (leftSense > rightSense) {
        steerAngle = -sensorAngle * 0.3;
      } else if (rightSense > leftSense) {
        steerAngle = sensorAngle * 0.3;
      }

      // EM field bias: steer toward field direction
      var angleDiff = emAngle - agentAngle;
      if (angleDiff > 3.14159) { angleDiff = angleDiff - 6.28318; }
      if (angleDiff < -3.14159) { angleDiff = angleDiff + 6.28318; }
      agentAngle = agentAngle + steerAngle + angleDiff * emInfluence * 0.2 + totalB * emInfluence * 0.05;

      agentPos = agentPos + vec2<f32>(cos(agentAngle), sin(agentAngle)) * 0.003;
      agentPos = fract(agentPos);

      let distToCell = length(agentPos - uv);
      if (distToCell < 0.005) {
        deposit = deposit + 0.05;
      }
    }
  }

  // Mouse direct deposit
  let mouseDist = length(uv - mousePos);
  if (mouseDist < 0.03) {
    deposit = deposit + 0.1 * (1.0 - mouseDist / 0.03);
  }

  newTrail = min(newTrail + deposit, 1.0);

  // Store trail (except at 0,0 which stores mousePos)
  if (gid.x != 0u || gid.y != 0u) {
    textureStore(dataTextureA, gid.xy, vec4<f32>(newTrail, fieldMag * 0.1, 0.0, 1.0));
  }

  // Render
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Trail color with magnetic hue shift
  let trailColor = vec3<f32>(
    newTrail * 0.2 + pow(newTrail, 3.0) * 0.8,
    newTrail * 0.8,
    newTrail * 0.9 + pow(newTrail, 2.0) * 0.1
  );
  let shiftedTrail = hueShift(trailColor, totalB * 0.5);

  var color = mix(baseColor * 0.2, shiftedTrail, newTrail * 0.9);
  color = color + vec3<f32>(0.0, newTrail * 0.3, newTrail * 0.4) * newTrail;

  // EM field line overlay
  let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
  let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
  let streamline = smoothstep(0.4, 0.6, streamNoise) * fieldVis * smoothstep(0.0, 0.5, fieldMag);
  let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
  color = mix(color, fieldColor, streamline * 0.4);

  // Core glow near mouse
  let coreDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let coreGlow = exp(-coreDist * coreDist * 400.0) * chargeStrength;
  color = color + vec3<f32>(0.6, 0.9, 1.0) * coreGlow * fieldVis;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Alpha = EM field magnitude blended with trail
  let alpha = clamp(fieldMag * 0.3 + newTrail * 0.7, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * (1.0 - newTrail * 0.2), 0.0, 0.0, 0.0));
}
