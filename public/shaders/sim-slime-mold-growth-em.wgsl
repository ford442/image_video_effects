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

fn stateAt(p: vec2<i32>, res: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);
}

fn trailAtUV(pos: vec2<f32>, res: vec2<f32>) -> f32 {
  return stateAt(vec2<i32>(floor(clamp(pos, vec2<f32>(0.0), vec2<f32>(1.0)) * res)), res).r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let sensorAngle = mix(0.2, 1.0, u.zoom_params.x);
  let decayRate = mix(0.9, 0.995, u.zoom_params.y);
  let particleCount = mix(100.0, 2000.0, u.zoom_params.z);
  let randomness = mix(0.0, 0.3, u.zoom_params.w);

  let chargeStrength = mix(0.5, 3.0, u.zoom_params.x);
  let fieldVis = mix(0.0, 1.0, u.zoom_params.y);
  let emInfluence = mix(0.0, 1.0, u.zoom_params.z);
  let rippleCharge = mix(0.5, 2.0, u.zoom_params.w);

  // Guarded pointer history lives only in the reserved six-float state window.
  let hasPointerState = arrayLength(&extraBuffer) > 138u;
  var prevMouse = mousePos;
  var mouseVel = vec2<f32>(0.0);
  if (hasPointerState && extraBuffer[138] > 0.5) {
    prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let pointerDt = clamp(time - extraBuffer[137], 0.001, 0.05);
    mouseVel = (mousePos - prevMouse) / pointerDt;
  }
  if (gid.x == 0u && gid.y == 0u && hasPointerState) {
    extraBuffer[133] = mousePos.x;
    extraBuffer[134] = mousePos.y;
    extraBuffer[135] = mouseVel.x;
    extraBuffer[136] = mouseVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Compute EM field at this pixel
  let heldGain = select(0.16, 1.0, u.zoom_config.w > 0.5);
  let eField = electricField(uv, mousePos, chargeStrength * heldGain * (1.0 + bass * 0.4));
  let bField = magneticField(uv, mousePos, mouseVel * 0.02, chargeStrength) * (1.0 + mids * 0.5);

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
      let orbitPos = ripple.xy + vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * orbitRadius;
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
  let coord = vec2<i32>(gid.xy);
  let previousState = stateAt(coord, resolution);
  let trail = previousState.r;

  // Diffuse and decay trails
  var sum = 0.0;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      sum = sum + stateAt(coord + vec2<i32>(x, y), resolution).r;
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

      let leftSense = trailAtUV(agentPos + vec2<f32>(cos(leftAngle), sin(leftAngle)) * 0.02, resolution);
      let centerSense = trailAtUV(agentPos + vec2<f32>(cos(agentAngle), sin(agentAngle)) * 0.02, resolution);
      let rightSense = trailAtUV(agentPos + vec2<f32>(cos(rightAngle), sin(rightAngle)) * 0.02, resolution);

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

      agentPos = agentPos + vec2<f32>(cos(agentAngle), sin(agentAngle)) * 0.003 * (1.0 + treble * 0.3);
      agentPos = fract(agentPos);

      let distToCell = length(agentPos - uv);
      if (distToCell < 0.005) {
        deposit = deposit + 0.05;
      }
    }
  }

  // Mouse direct deposit
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseField = smoothstep(0.09, 0.0, mouseDist);
  deposit = deposit + mouseField * (0.004 + u.zoom_config.w * 0.11) * (1.0 + bass * 0.5);

  newTrail = min(newTrail + deposit, 1.0);

  let activity = clamp(abs(newTrail - trail) * 8.0 + abs(totalB) * 0.02, 0.0, 1.0);
  textureStore(dataTextureA, coord, vec4<f32>(newTrail, clamp(fieldMag * 0.05, 0.0, 4.0), clamp(totalB * 0.05, -2.0, 2.0), activity));

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
  color = color + vec3<f32>(0.6 + bass * 0.3, 0.9 + mids * 0.2, 1.0 + treble * 0.4) * coreGlow * fieldVis;
  color = acesToneMap(color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Alpha = EM field magnitude blended with trail
  let sourceAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
  let alpha = clamp(sourceAlpha * 0.15 + fieldMag * 0.12 + newTrail * 0.72 + activity * 0.12, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * (1.0 - newTrail * 0.2), 0.0, 0.0, 0.0));
}
