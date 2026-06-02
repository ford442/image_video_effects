// ═══════════════════════════════════════════════════════════════════
//  Opal Circuit
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-05-31
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

  let traceScale = mix(5.0, 40.0, u.zoom_params.x);
  let pulseRate = mix(0.2, 3.0, u.zoom_params.y);
  let iridescence = mix(0.1, 2.0, u.zoom_params.z);
  let bloom = mix(0.2, 2.2, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * 0.18;

  let g = p * traceScale;
  let gc = floor(g);
  let gl = fract(g) - 0.5;
  let rnd = hash21(gc);

  let hLine = smoothstep(0.09, 0.01, abs(gl.y)) * step(0.35, rnd);
  let vLine = smoothstep(0.09, 0.01, abs(gl.x)) * step(rnd, 0.65);
  let vias = exp(-dot(gl, gl) * 60.0) * step(0.7, rnd);
  let traces = max(max(hLine, vLine), vias);

  let signal = 0.5 + 0.5 * sin(time * pulseRate * (1.0 + bass * 0.8) + (gc.x + gc.y) * 0.7);

  // Chromatic opal: each signal phase gets shifted hue
  let opalR = 0.5 + 0.5 * sin(signal * 6.28318 + 0.0 + mids);
  let opalG = 0.5 + 0.5 * sin(signal * 6.28318 + 2.1 + treble + bass * 0.1);
  let opalB = 0.5 + 0.5 * sin(signal * 6.28318 + 4.2 + bass + mids * 0.05);

  var color = vec3<f32>(0.02, 0.02, 0.03);
  color = color + vec3<f32>(opalR * 1.1, opalG, opalB * 0.95) * traces * iridescence;
  color = color + vec3<f32>(0.9, 0.95, 1.0) * vias * bloom * (0.5 + treble);

  // Temporal circuit persistence: signal echoes through traces
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, 0.02 + bass * 0.01);

  let presence = sat(traces * 0.9 + vias * 0.5);
  let alpha = sat(0.08 + presence * 0.92);
  let depth = sat(0.92 - traces * 0.45 - vias * 0.3);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(traces, signal, vias, alpha));
}
