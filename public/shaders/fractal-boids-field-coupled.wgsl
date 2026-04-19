// ═══════════════════════════════════════════════════════════════════
//  Fractal Boids Field + Fluid Coupling
//  Category: simulation
//  Features: advanced-hybrid, boids, fractal-flow-field, mouse-driven, fluid-coupling, interactive
//  Complexity: Very High
//  Chunks From: fractal-boids-field, mouse-fluid-coupling
//  Created: 2026-04-18
//  By: Agent CB-4 - Mouse Physics Injector
// ═══════════════════════════════════════════════════════════════════
//  Flocking behavior on a fractal vector field with viscous mouse
//  fluid coupling. Mouse movement creates wakes that push boids.
//  Click ripples spawn outward shockwaves through the flock.
//  Alpha stores combined fluid density and boid presence.
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

// ═══ CHUNK: fbm2 (from gen_grid.wgsl) ═══
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * valueNoise(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

// ═══ DOMAIN WARP FBM ═══
fn domainWarpFBM(p: vec2<f32>, time: f32, audioReactivity: f32) -> vec2<f32> {
  let q = vec2<f32>(
    fbm2(p + vec2<f32>(0.0, time * 0.1 * audioReactivity), 4),
    fbm2(p + vec2<f32>(5.2, 1.3 + time * 0.1 * audioReactivity), 4)
  );
  let r = vec2<f32>(
    fbm2(p + 4.0 * q + vec2<f32>(1.7 - time * 0.15 * audioReactivity, 9.2), 4),
    fbm2(p + 4.0 * q + vec2<f32>(8.3 - time * 0.15 * audioReactivity, 2.8), 4)
  );
  return r;
}

// ═══ FLOW FIELD SAMPLE ═══
fn sampleFlowField(uv: vec2<f32>, time: f32, flowStrength: f32, audioReactivity: f32) -> vec2<f32> {
  let warped = domainWarpFBM(uv * 5.0, time * 0.1 * audioReactivity, audioReactivity);
  let angle = warped.x * 6.28 * flowStrength;
  return vec2<f32>(cos(angle), sin(angle));
}

// ═══ MOUSE FLUID VELOCITY ═══
fn sampleFluidVelocity(uv: vec2<f32>, mousePos: vec2<f32>, mouseVel: vec2<f32>, aspect: f32, mouseRadius: f32, vortexStrength: f32) -> vec2<f32> {
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let influence = smoothstep(mouseRadius, 0.0, dist);

  var vel = mouseVel * influence * 0.5;
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  let mouseSpeed = length(mouseVel);
  vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;
  return vel;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);
  let aspect = resolution.x / resolution.y;

  let audioOverall = u.zoom_config.x;
  let audioReactivity = 1.0 + audioOverall * 0.3;

  // Parameters
  let boidCount = mix(10.0, 50.0, u.zoom_params.x);
  let flowStrength = mix(0.5, 3.0, u.zoom_params.y);
  let trailPersist = u.zoom_params.z;
  let separation = mix(0.02, 0.1, u.zoom_params.w);

  let mouseRadius = mix(0.03, 0.15, u.zoom_params.y);
  let fluidInfluence = mix(0.0, 2.0, u.zoom_params.z);
  let vortexStrength = u.zoom_params.w * 2.0;
  let rippleForce = mix(0.5, 3.0, u.zoom_params.x);

  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;

  // Store current mouse position at (0,0)
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  // Base image
  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Compute mouse fluid velocity at this pixel
  let fluidVel = sampleFluidVelocity(uv, mousePos, mouseVel, aspect, mouseRadius, vortexStrength);

  // ═══ BOID SIMULATION WITH FLUID COUPLING ═══
  var boidColor = vec3<f32>(0.0);
  let hashUV = floor(uv * boidCount) / boidCount;
  let boidId = hash12(hashUV);

  // Simulated boid position (in grid cell)
  var boidPos = hashUV + vec2<f32>(
    sin(time * (1.0 + boidId * 2.0) + boidId * 10.0),
    cos(time * (1.0 + boidId * 1.5) + boidId * 10.0)
  ) * 0.5 / boidCount;

  // Get flow field at boid position
  let flow = sampleFlowField(boidPos, time, flowStrength, audioReactivity);

  // Get fluid velocity at boid position
  let boidFluidVel = sampleFluidVelocity(boidPos, mousePos, mouseVel, aspect, mouseRadius, vortexStrength);

  // Boid rules (simplified for performance)
  var sep = vec2<f32>(0.0);
  var alignment = flow;
  var cohesion = vec2<f32>(0.0);

  // Sample neighbors (simplified grid-based)
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      if (x == 0 && y == 0) { continue; }
      let neighborUV = hashUV + vec2<f32>(f32(x), f32(y)) / boidCount;
      let neighborId = hash12(neighborUV);
      let neighborPos = neighborUV + vec2<f32>(
        sin(time * (1.0 + neighborId * 2.0) + neighborId * 10.0),
        cos(time * (1.0 + neighborId * 1.5) + neighborId * 10.0)
      ) * 0.5 / boidCount;

      let diff = boidPos - neighborPos;
      let dist = length(diff);

      if (dist < separation / boidCount && dist > 0.001) {
        sep = sep + normalize(diff) / dist;
      }

      cohesion = cohesion + neighborPos;
    }
  }

  cohesion = cohesion / 8.0 - boidPos;

  // Combine forces with fluid coupling
  let velocity = normalize(sep * 1.5 + alignment * 1.0 + cohesion * 0.5 + flow * 2.0 + boidFluidVel * fluidInfluence);

  // Trail rendering
  let toBoid = uv - boidPos;
  let distToBoid = length(toBoid);
  let trailWidth = 0.003;

  if (distToBoid < trailWidth * (1.0 + boidId)) {
    let hue = atan2(velocity.y, velocity.x) / 6.28 + 0.5;
    boidColor = vec3<f32>(
      0.5 + 0.5 * cos(hue * 6.28),
      0.5 + 0.5 * cos(hue * 6.28 + 2.09),
      0.5 + 0.5 * cos(hue * 6.28 + 4.18)
    );
  }

  // Trail behind boid
  let trailDir = -velocity;
  for (var i: i32 = 1; i < 10; i = i + 1) {
    let trailPos = boidPos + trailDir * f32(i) * 0.01;
    let distToTrail = length(uv - trailPos);
    let trailIntensity = 1.0 - f32(i) / 10.0;
    if (distToTrail < trailWidth * trailIntensity) {
      let trailColor = vec3<f32>(0.8, 0.9, 1.0) * trailIntensity * 0.5;
      boidColor = max(boidColor, trailColor);
    }
  }

  // Click ripple shockwaves
  var rippleDisturbance = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      rippleDisturbance = rippleDisturbance + rInfluence * rippleForce;
    }
  }

  // Blend with background
  color = mix(color, boidColor, length(boidColor) * (0.5 + trailPersist * 0.5));

  // Add flow field visualization
  let flowVis = sampleFlowField(uv, time, flowStrength * 0.5, audioReactivity);
  let flowMag = length(flowVis);
  color = color + vec3<f32>(flowMag * 0.1, flowMag * 0.05, flowMag * 0.15) * flowStrength;

  // Add fluid wake visualization
  let fluidMag = length(fluidVel);
  color = color + vec3<f32>(fluidMag * 0.3, fluidMag * 0.2, fluidMag * 0.5) * fluidInfluence * 0.3;

  // Add ripple shockwave flash
  color = color + vec3<f32>(1.0, 0.9, 0.7) * rippleDisturbance * 0.2;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Alpha = boid density + fluid density + ripple disturbance
  let alpha = clamp(mix(0.75, 1.0, length(boidColor)) + fluidMag * 0.2 + rippleDisturbance * 0.1, 0.0, 1.0);

  textureStore(writeTexture, id, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
