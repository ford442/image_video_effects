// ═══════════════════════════════════════════════════════════════════
//  Vortex Cathedral
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map
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

  let archCount = mix(4.0, 22.0, u.zoom_params.x);
  let spin = mix(0.1, 3.0, u.zoom_params.y);
  let haze = mix(0.0, 1.0, u.zoom_params.z);
  let sanctum = mix(0.1, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p - mouse * 0.2;

  let r = max(length(p), 1e-5);
  let a = atan2(p.y, p.x);
  let spinA = a + time * spin * (1.0 + bass * 0.7) - r * (1.8 + mids);
  let sector = sin(spinA * archCount);
  let arches = smoothstep(0.75, 1.0, abs(sector));

  let rings = 0.5 + 0.5 * sin(r * 26.0 - time * (2.0 + treble * 5.0));
  let columns = arches * (0.4 + rings * 0.6);
  let centerLight = exp(-r * r * (12.0 / sanctum));
  let fog = exp(-r * 2.5) * haze;

  // Chromatic cathedral separation: R arches, G columns, B fog
  let chromaR = arches * (1.0 + treble * 0.15);
  let chromaG = columns * (1.0 + mids * 0.1);
  let chromaB = fog * (1.0 + bass * 0.1);

  var color = vec3<f32>(0.02, 0.01, 0.03);
  color = color + vec3<f32>(0.42, 0.15, 0.65) * chromaR;
  color = color + vec3<f32>(0.75, 0.55, 0.85) * chromaG;
  color = color + vec3<f32>(0.15, 0.3, 0.55) * chromaB;
  color = color + vec3<f32>(0.9, 0.7, 1.0) * centerLight * (0.5 + bass);

  // Temporal persistence: previous light bleeds for ghost cathedral
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let prevLight = prev.rgb;
  color = mix(color, prevLight * 0.92, 0.04 + mids * 0.015);

  let presence = sat(columns * 0.85 + centerLight * 0.9 + fog * 0.3);
  let alpha = sat(0.1 + presence * 0.9);
  let depth = sat(0.92 - centerLight * 0.7 - columns * 0.25 + haze * 0.1);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(arches, rings, centerLight, alpha));
}
