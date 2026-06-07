// ═══════════════════════════════════════════════════════════════════
//  Neural Synapse Web
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, aces-tone-map, depth-aware
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
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
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let nodeCount = mix(3.0, 16.0, u.zoom_params.x);
  let pulseSpeed = mix(0.2, 3.0, u.zoom_params.y);
  let connectivity = mix(0.1, 1.0, u.zoom_params.z);
  let signalGain = mix(0.3, 2.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * 0.15;

  var nodeField = 0.0;
  var synapseField = 0.0;
  var signalField = 0.0;

  for (var i = 0u; i < u32(nodeCount); i = i + 1u) {
    let fi = f32(i);
    let seed = hash22(vec2<f32>(fi, 3.7));
    let nodePos = (seed - 0.5) * 1.6;
    let nodePulse = 0.5 + 0.5 * sin(time * pulseSpeed * (1.0 + seed.x * 2.0) + fi * 2.3 + bass * 5.0);
    let nd = length(p - nodePos);
    let nodeGlow = exp(-nd * nd * (40.0 + mids * 30.0)) * nodePulse;
    nodeField = nodeField + nodeGlow;

    for (var j = i + 1u; j < u32(nodeCount); j = j + 1u) {
      if (hash21(vec2<f32>(fi, f32(j))) > connectivity) { continue; }
      let jseed = hash22(vec2<f32>(f32(j), 3.7));
      let jPos = (jseed - 0.5) * 1.6;
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
      synapseField = synapseField + lineGlow;
      signalField = signalField + lineGlow * signal * (0.5 + treble);
    }
  }

  // Chromatic: electric blue nodes, cyan synapses, white signal pulses
  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(0.2, 0.55, 1.0) * nodeField * signalGain * (1.0 + bass * 0.2);
  color = color + vec3<f32>(0.35, 0.85, 0.95) * synapseField * 0.6 * (1.0 + mids * 0.15);
  color = color + vec3<f32>(0.9, 0.95, 1.0) * signalField * signalGain * (1.0 + treble * 0.25);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, 0.03 + bass * 0.01);

  let presence = sat(nodeField * 0.8 + synapseField * 0.6 + signalField * 0.9);
  let alpha = sat(0.1 + presence * 0.9);
  let depth = sat(0.92 - nodeField * 0.5 - synapseField * 0.35);

  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(nodeField, synapseField, signalField, alpha));
}
