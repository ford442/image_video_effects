// ═══════════════════════════════════════════════════════════════════
//  Acoustic String Theory
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware
//  Complexity: High
//  Chunks From: noise.wgsl
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

  let strings = mix(2.0, 16.0, u.zoom_params.x);
  let tension = mix(0.5, 5.0, u.zoom_params.y);
  let harmonics = mix(1.0, 8.0, u.zoom_params.z);
  let resonance = mix(0.2, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  var stringField = 0.0;
  var harmonicField = 0.0;
  var nodeField = 0.0;

  for (var s = 0u; s < u32(strings); s = s + 1u) {
    let fs = f32(s);
    let sy = -0.9 + (fs + 0.5) / strings * 1.8;
    let pluck = sin(p.x * tension * (1.0 + fs * 0.15) - time * (2.0 + fs * 0.5) * (1.0 + bass * 0.5));
    let damp = exp(-abs(p.x - mouse.x * 0.5) * 2.0) * (0.5 + mids);
    let wave = sin((p.y - sy) * tension * 15.0) * exp(-abs(p.y - sy) * tension * 3.0);
    let amp = (0.15 + damp) * resonance * (1.0 + bass * 0.3);
    let stringLine = abs(wave + pluck * amp);
    stringField = stringField + smoothstep(0.05, 0.0, stringLine) * (0.7 + fs * 0.05);

    var harmAmp = 0.6;
    for (var h = 1u; h < u32(harmonics); h = h + 1u) {
      let fh = f32(h);
      let harmY = sy + sin(fh * 1.618) * 0.15;
      let harmWave = sin((p.y - harmY) * tension * 15.0 * fh) * exp(-abs(p.y - harmY) * tension * 5.0);
      let harmLine = abs(harmWave + pluck * amp * harmAmp);
      harmonicField = harmonicField + smoothstep(0.03, 0.0, harmLine) * 0.3;
      harmAmp = harmAmp * 0.6;
    }

    let nodeX = sin(fs * 2.7 + time * 0.3) * 0.5;
    let nodeDelta = p - vec2<f32>(nodeX, sy);
    let nodeDistSq = dot(nodeDelta, nodeDelta);
    nodeField = nodeField + exp(-nodeDistSq * 80.0) * (0.5 + treble);
  }

  // Chromatic: warm string fundamentals, cool harmonics, bright nodes
  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(0.9, 0.55, 0.2) * stringField * resonance * (1.0 + bass * 0.15);
  color = color + vec3<f32>(0.25, 0.75, 0.95) * harmonicField * (1.0 + mids * 0.2);
  color = color + vec3<f32>(1.0, 0.95, 0.85) * nodeField * (0.5 + treble * 0.3);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, 0.025 + bass * 0.01);

  let presence = saturate(stringField * 0.85 + harmonicField * 0.6 + nodeField * 0.9);
  let alpha = saturate(0.08 + presence * 0.92);
  let depth = saturate(0.92 - stringField * 0.5 - nodeField * 0.3);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(stringField, harmonicField, nodeField, alpha));
}
