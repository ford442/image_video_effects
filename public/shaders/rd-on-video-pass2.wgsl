// ═══════════════════════════════════════════════════════════════════
//  RD on Video (Pass 2: Turing Color Map)
//  Category: simulation
//  Features: multi-pass-2, temporal, turing-color-map
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

fn palette(t: f32) -> vec3<f32> {
  let c1 = vec3<f32>(0.04, 0.08, 0.22);
  let c2 = vec3<f32>(0.12, 0.70, 0.55);
  let c3 = vec3<f32>(0.95, 0.60, 0.22);
  let c4 = vec3<f32>(1.00, 0.92, 0.68);
  let a = smoothstep(0.0, 0.35, t);
  let b = smoothstep(0.35, 0.75, t);
  let c = smoothstep(0.75, 1.0, t);
  return mix(mix(c1, c2, a), mix(c3, c4, c), b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let coord = vec2<i32>(gid.xy);
  let maxCoord = vec2<i32>(i32(res.x) - 1, i32(res.y) - 1);

  let state = textureLoad(dataTextureC, coord, 0);
  let b = clamp(state.g, 0.0, 1.0);
  let lumaSeed = clamp(state.b, 0.0, 1.0);

  let leftB = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0, 0), maxCoord), 0).g;
  let rightB = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0, 0), maxCoord), 0).g;
  let downB = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0, 0), maxCoord), 0).g;
  let upB = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0, 0), maxCoord), 0).g;
  let edge = clamp(abs((leftB + rightB + downB + upB) - 4.0 * b) * 4.0, 0.0, 1.0);

  let concentrationGamma = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let edgeGain = mix(0.10, 0.70, clamp(u.zoom_params.y, 0.0, 1.0));
  let seedGain = mix(0.05, 0.35, clamp(u.zoom_params.z, 0.0, 1.0));
  let hueOffset = (u.zoom_params.w - 0.5) * 0.35;

  let pattern = clamp(pow(b, concentrationGamma) + edge * edgeGain + lumaSeed * seedGain, 0.0, 1.0);
  let colorized = palette(fract(pattern + hueOffset));

  textureStore(dataTextureB, coord, vec4<f32>(colorized, pattern));
  textureStore(writeTexture, coord, vec4<f32>(colorized, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
