// ═══════════════════════════════════════════════════════════════════
//  ambient-liquid-coupled
//  Category: advanced-hybrid
//  Features: liquid-membrane, mouse-pressure, audio-reactive, depth-aware, temporal-feedback
//  Complexity: High
//  Chunks From: ambient-liquid.wgsl, mouse-fluid-coupling.wgsl, bass_env pattern
//  Created: 2026-04-18
//  Updated: 2026-05-31
//  By: Grok (living membrane + bass tension upgrade)
// ═══════════════════════════════════════════════════════════════════

//  Gentle ambient sine waves are driven by a real fluid velocity
//  field. The mouse drags viscous fluid that warps the image via
//  advected displacement, while ripple eddies create vortices.
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

// ═══ CHUNK: bass_env (attack/release envelope for surface tension) ═══
// High bass = high surface tension (slow healing, dramatic tears persist)
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let waveStrength = mix(0.005, 0.04, u.zoom_params.x);
  let fluidViscosity = mix(0.85, 0.99, u.zoom_params.y);
  let vortexStrength = u.zoom_params.z * 2.0;
  let brightSplit = u.zoom_params.w;

  // === FLUID VELOCITY FIELD (from mouse-fluid-coupling) ===
  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  // Store current mouse position at (0,0)
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  let px = vec2<f32>(1.0) / resolution;

  // Read previous velocity and density
  let prevVel = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).xy;
  let prevDens = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).a;

  // Advect velocity
  let backUV = uv - prevVel * px * 2.0;
  let advectedVel = textureSampleLevel(dataTextureC, u_sampler, backUV, 0.0).xy;
  let advectedDens = textureSampleLevel(dataTextureC, u_sampler, backUV, 0.0).a;

  var vel = advectedVel * fluidViscosity;
  var dens = advectedDens * fluidViscosity;

  // === LIVING MEMBRANE PRESSURE (new high-signal behavior) ===
  // Read previous membrane pressure from dataTextureB
  let prevPressure = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;
  let prevBass = textureSampleLevel(dataTextureC, u_sampler, vec2<f32>(0.0), 0.0).g; // stored bass history at origin

  // Bass-driven surface tension (high bass = high tension = slow healing)
  let bass = plasmaBuffer[0].x;
  let surfaceTension = mix(0.6, 0.97, bass * 0.7); // 0.6 = loose, 0.97 = very tight skin
  let tensionRelease = bass_env(prevBass, bass, 0.85, 0.12);

  // Mouse as "finger" pressing into the membrane
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let isPressing = u.zoom_config.w; // mouse down = active press
  let pressRadius = mix(0.04, 0.22, u.zoom_params.y * 0.6);
  let pressInfluence = smoothstep(pressRadius, 0.0, dist) * isPressing;

  // Pressure increases sharply under the finger, then slowly heals
  var pressure = prevPressure * surfaceTension;
  pressure = pressure + pressInfluence * 1.8;
  pressure = clamp(pressure, 0.0, 3.2);

  // Bass spikes make existing tears "set" (higher tension locks in deformation)
  if (bass > 0.65) {
    pressure = pressure * (1.0 + (bass - 0.65) * 0.8);
  }

  // Store updated pressure + current bass envelope at origin for next frame
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureB, vec2<i32>(0, 0), vec4<f32>(pressure, tensionRelease, bass, 0.0));
  }

  // Mouse force (now modulated by membrane pressure)
  let mouseRadius = mix(0.03f, 0.18f, 0.5f);
  let influence = smoothstep(mouseRadius, 0.0, dist);
  let membraneResistance = 1.0 - (pressure * 0.18); // high pressure = more resistant surface
  vel = vel + mouseVel * influence * 0.5 * membraneResistance;

  // Vortex force (twisting the membrane)
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * vortexStrength * mouseSpeed * (1.0 + pressure * 0.2);

  // Ripple injection (still works, but ripples now "ring" the membrane pressure)
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
      vel = vel + outward * rInfluence * 0.3;
      dens = dens + rInfluence * 0.5;
      // Ripples also locally disturb membrane pressure
      pressure = pressure + rInfluence * 0.6;
    }
  }

  // Edge damping
  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  vel = vel * edgeDamp;
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  // Store velocity state + current membrane pressure (for next frame feedback)
  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));
  // Write pressure field so the displacement stage can read it
  textureStore(dataTextureB, vec2<i32>(global_id.xy), vec4<f32>(pressure, 0.0, 0.0, 0.0));

  // === LIVING MEMBRANE DISPLACEMENT (high-signal creative upgrade) ===
  // Read the membrane pressure we just wrote (or previous frame)
  let membranePressure = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;

  let rate = 0.5;
  let waveTime = time * rate;
  let frequency = 15.0;

  // Fluid velocity warps the wave phase
  let wavePhase = vec2<f32>(vel.x * 5.0, vel.y * 5.0);

  var d1 = sin(uv.x * frequency + waveTime + wavePhase.x) * waveStrength;
  var d2 = cos(uv.y * frequency * 0.7 + waveTime + wavePhase.y) * waveStrength;

  // Mouse attractor (stronger when pressing into the membrane)
  let to_mouse = mousePos - uv;
  let dist_to_mouse = length(to_mouse);
  let pressBoost = 1.0 + membranePressure * 0.8;
  let mouse_influence = exp(-dist_to_mouse * 5.0) * 0.015 * pressBoost;
  d1 += to_mouse.x * mouse_influence;
  d2 += to_mouse.y * mouse_influence;

  // Ripple eddies
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_pos = ripple.xy;
      let ripple_age = waveTime - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 4.0) {
        let to_ripple = uv - ripple_pos;
        let ripple_dist = length(to_ripple);
        let ripple_strength = sin(ripple_dist * 20.0 - ripple_age * 5.0) * exp(-ripple_age * 0.5) * 0.01;
        d1 += to_ripple.y * ripple_strength;
        d2 -= to_ripple.x * ripple_strength;
      }
    }
  }

  // === MEMBRANE LAYER SEPARATION (the new "wow" behavior) ===
  // When membranePressure is high, the "finger" has pushed through the surface,
  // so we sample two slightly different layers and blend them based on pressure.
  let baseUV = uv + vec2<f32>(d1, d2);

  // Subsurface offset grows with pressure (the tear reveals a different "inside")
  let tearStrength = membranePressure * 0.018;
  let subsurfaceUV = baseUV + vec2<f32>(d2, -d1) * tearStrength * 1.3;

  var topLayer = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);
  var subLayer = textureSampleLevel(readTexture, u_sampler, subsurfaceUV, 0.0);

  // Bass makes the separation more chromatic (color bleeds differently across the tear)
  let bassShift = bass * 0.6;
  let layerMix = clamp(membranePressure * 0.55 + bassShift * 0.25, 0.0, 0.92);

  var color = mix(topLayer, subLayer, layerMix);

  // Bright/dark split now also respects the membrane tear
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  if (luma > 0.75 && brightSplit > 0.0) {
    let bright_time = time * 0.65;
    let bd1 = sin(uv.x * frequency + bright_time) * waveStrength;
    let bd2 = cos(uv.y * frequency * 0.7 + bright_time) * waveStrength;
    let brightDisplacedUV = baseUV + vec2<f32>(bd1, bd2);
    color = mix(color, textureSampleLevel(readTexture, u_sampler, brightDisplacedUV, 0.0), 0.25 * brightSplit);
  }

  if (luma < 0.25 && brightSplit > 0.0) {
    let dark_time = time * 0.45;
    let dd1 = sin(uv.x * frequency + dark_time) * waveStrength;
    let dd2 = cos(uv.y * frequency * 0.7 + dark_time) * waveStrength;
    let darkDisplacedUV = baseUV + vec2<f32>(dd1, dd2);
    color = mix(color, textureSampleLevel(readTexture, u_sampler, darkDisplacedUV, 0.0), 0.75 * brightSplit);
  }

  // Depth-aware alpha with membrane thickness
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let membraneThickness = 1.0 - (membranePressure * 0.12); // high pressure = thinner / more translucent
  let alpha = mix(0.65, 1.0, luma) * membraneThickness;
  let finalAlpha = mix(alpha * 0.75, alpha, depth);

  // Fluid + membrane tint: high pressure areas get a cooler, deeper hue
  let fluidTint = mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.94, 0.86), dens * 0.28);
  let pressureTint = mix(vec3<f32>(1.0), vec3<f32>(0.88, 0.95, 1.08), membranePressure * 0.22);
  let tintedColor = color.rgb * fluidTint * pressureTint;

  // Premultiplied write for clean chaining in slot 2/3
  let a = clamp(finalAlpha, 0.0, 1.0);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(tintedColor * a, a));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
