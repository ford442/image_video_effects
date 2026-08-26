// ═══════════════════════════════════════════════════════════════════
//  Neural Synapse Web
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, aces-tone-map, depth-aware, interactive
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
//  Interactivist upgrade: 2026-07-22
//    - Spring-damper mouse attractor (extraBuffer state, damped overshoot)
//    - Click pulse wave: expanding ring boosts signal gain / synapse glow
//    - Treble-reactive synapse sparkle masked by signal strength
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

// Persistent spring state is restricted to guarded [133..138].
const ATTR_POS_X: u32 = 133u;
const ATTR_POS_Y: u32 = 134u;
const ATTR_VEL_X: u32 = 135u;
const ATTR_VEL_Y: u32 = 136u;
const LAST_TIME: u32 = 137u;
const STATE_INIT: u32 = 138u;

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(19.3, 53.7)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  // Mouse in shader p-space (aspect-corrected), matching node-field space.
  let mouseRaw = u.zoom_config.yz * 2.0 - 1.0;
  let mouseP = vec2<f32>(mouseRaw.x * aspect, mouseRaw.y);
  let mouseDown = u.zoom_config.w > 0.5;

  // Slider contract: nodeCount / pulseSpeed / connectivity / signalGain.
  let nodeCount = mix(3.0, 16.0, u.zoom_params.x);
  let pulseSpeed = mix(0.2, 3.0, u.zoom_params.y);
  let connectivity = mix(0.1, 1.0, u.zoom_params.z);
  let signalGain = mix(0.3, 2.0, u.zoom_params.w);

  // ── Spring-damper mouse attractor (state in extraBuffer) ─────────
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var attrPos = mouseP;
  var attrVel = vec2<f32>(0.0);
  var lastTime = time;
  var initialized = false;
  if (hasSpring) {
    attrPos = vec2<f32>(extraBuffer[ATTR_POS_X], extraBuffer[ATTR_POS_Y]);
    attrVel = vec2<f32>(extraBuffer[ATTR_VEL_X], extraBuffer[ATTR_VEL_Y]);
    lastTime = extraBuffer[LAST_TIME];
    initialized = extraBuffer[STATE_INIT] > 0.5;
  }
  if (!initialized) {
    attrPos = mouseP;
    attrVel = vec2<f32>(0.0, 0.0);
  }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);

  // Damped spring toward the mouse: fast moves overshoot, then settle.
  let springK = 18.0;
  let damping = 7.0;
  let accel = (mouseP - attrPos) * springK - attrVel * damping;
  let newVel = attrVel + accel * dt;
  let newPos = attrPos + newVel * dt;
  // One thread persists state; every thread uses the integrated values.
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[ATTR_POS_X] = newPos.x;
    extraBuffer[ATTR_POS_Y] = newPos.y;
    extraBuffer[ATTR_VEL_X] = newVel.x;
    extraBuffer[ATTR_VEL_Y] = newVel.y;
    extraBuffer[LAST_TIME] = time;
    extraBuffer[STATE_INIT] = 1.0;
  }

  // ── Bounded click pulse waves from the uniform ripple queue ──────
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + newPos * 0.15;
  var ringBoost = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var rippleIndex = 0u; rippleIndex < rippleCount; rippleIndex++) {
    let ripple = u.ripples[rippleIndex]; let ringAge = time - ripple.z;
    if (ringAge < 0.0 || ringAge > 3.0) { continue; }
    var rippleP = ripple.xy * 2.0 - 1.0; rippleP.x *= aspect;
    let ringDelta = length(p - rippleP) - ringAge * 0.75;
    ringBoost += exp(-ringDelta * ringDelta * 90.0) * exp(-ringAge * 1.1);
  }

  // Web "lunges": nodes lean toward the attractor while it moves fast.
  let lunge = sat(length(newVel) * 0.35);
  let gainBoost = 1.0 + ringBoost * 1.5;

  var nodeField = 0.0;
  var synapseField = 0.0;
  var signalField = 0.0;
  var sparkleField = 0.0;

  for (var i = 0u; i < u32(nodeCount); i = i + 1u) {
    let fi = f32(i);
    let seed = hash22(vec2<f32>(fi, 3.7));
    var nodePos = (seed - 0.5) * 1.6;
    nodePos = mix(nodePos, newPos, lunge * 0.12);
    let nodePulse = 0.5 + 0.5 * sin(time * pulseSpeed * (1.0 + seed.x * 2.0) + fi * 2.3 + bass * 5.0);
    let nd = length(p - nodePos);
    let nodeGlow = exp(-nd * nd * (40.0 + mids * 30.0)) * nodePulse * (1.0 + ringBoost * 2.0);
    nodeField = nodeField + nodeGlow;

    for (var j = i + 1u; j < u32(nodeCount); j = j + 1u) {
      if (hash21(vec2<f32>(fi, f32(j))) > connectivity) { continue; }
      let jseed = hash22(vec2<f32>(f32(j), 3.7));
      let jPos = mix((jseed - 0.5) * 1.6, newPos, lunge * 0.12);
      let along = jPos - nodePos;
      let len = length(along);
      if (len < 0.01) { continue; }
      let dir = along / len;
      let perp = vec2<f32>(-dir.y, dir.x);
      let proj = dot(p - nodePos, dir);
      let orth = abs(dot(p - nodePos, perp));
      let onLine = proj > 0.0 && proj < len;
      let lineGlow = exp(-orth * orth * 200.0) * f32(onLine);
      let sigTravel = fract((proj / len) - time * pulseSpeed * 0.3);
      let signal = smoothstep(0.85, 1.0, sigTravel) + smoothstep(0.0, 0.15, sigTravel);
      // Treble-reactive sparkle: animated grain only on firing synapses.
      let grain = hash21(floor(p * 220.0) + vec2<f32>(floor(time * 23.0), floor(time * 17.0)));
      let sparkle = lineGlow * signal * treble * smoothstep(0.55, 0.95, grain);
      synapseField = synapseField + lineGlow;
      signalField = signalField + lineGlow * signal * (0.5 + treble) * gainBoost;
      sparkleField = sparkleField + sparkle;
    }
  }

  // Chromatic: electric blue nodes, cyan synapses, white signal pulses
  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(0.2, 0.55, 1.0) * nodeField * signalGain * (1.0 + bass * 0.2);
  color = color + vec3<f32>(0.35, 0.85, 0.95) * synapseField * 0.6 * (1.0 + mids * 0.15) * (1.0 + ringBoost);
  color = color + vec3<f32>(0.9, 0.95, 1.0) * signalField * signalGain * (1.0 + treble * 0.25);
  color = color + vec3<f32>(1.0, 1.0, 1.0) * sparkleField * 1.6;
  color = color + vec3<f32>(0.45, 0.8, 1.0) * ringBoost * 0.25;

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let historyDims = vec2<i32>(textureDimensions(dataTextureC));
  let prev = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), historyDims - vec2<i32>(1)), 0);
  color = mix(source.rgb * 0.12 + color, prev.rgb * 0.94, 0.04 + bass * 0.015);

  let presence = sat(nodeField * 0.8 + synapseField * 0.6 + signalField * 0.9 + sparkleField * 0.7 + ringBoost * 0.5);
  let alpha = sat(source.a + (1.0 - source.a) * presence);
  let depth = textureLoad(readDepthTexture, coord, 0).r;

  color = acesToneMap(color * 1.1);
  let display = vec4<f32>(color, alpha);
  textureStore(writeTexture, coord, display);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, display);
}
