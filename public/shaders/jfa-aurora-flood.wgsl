// ═══ JFA AURORA — FLOOD STEP ════════════════════════════════════════════════
//  Reads/writes: (seed.xy, dist², seed_id)

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

fn load(p: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), resI - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let step = max(1.0, mix(1.0, 64.0, u.zoom_params.x));
  let jump = i32(step);

  var best = load(pixel, resI);
  var bestD2 = best.z;
  if (best.x < 0.0) { bestD2 = 1e6; }

  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let np = pixel + vec2<i32>(dx, dy) * jump;
      let n = load(np, resI);
      if (n.x < 0.0) { continue; }
      let nuv = (vec2<f32>(np) + 0.5) / res;
      let d2 = dot(uv - n.xy, uv - n.xy);
      if (d2 < bestD2) {
        bestD2 = d2;
        best = vec4<f32>(n.xy, d2, n.w);
      }
    }
  }

  textureStore(dataTextureA, pixel, vec4<f32>(best.xy, bestD2, best.w));
}
