// ═══ ANISOTROPIC KUWAHARA — FILTER ════════════════════════════════════════

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
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let texel = 1.0 / res;
  let flow = textureLoad(dataTextureC, pixel, 0).xy;
  let window = mix(2.0, 8.0, u.zoom_params.x);
  let aniso = mix(0.5, 2.0, u.zoom_params.y);
  let perp = vec2<f32>(-flow.y, flow.x);
  var bestVar = 1e9;
  var bestCol = vec3<f32>(0.0);
  let sectors = 8;
  for (var s = 0; s < sectors; s = s + 1) {
    let ang = f32(s) / f32(sectors) * 6.28318;
    let dir = normalize(flow * cos(ang) + perp * sin(ang) * aniso);
    var mean = vec3<f32>(0.0);
    var count = 0.0;
    let radius = i32(window);
    for (var r = -radius; r <= radius; r = r + 1) {
      let off = dir * f32(r) * texel.x;
      let c = textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
      mean += c;
      count += 1.0;
    }
    mean /= max(count, 1.0);
    var varSum = 0.0;
    for (var r2 = -radius; r2 <= radius; r2 = r2 + 1) {
      let off2 = dir * f32(r2) * texel.x;
      let c2 = textureSampleLevel(readTexture, u_sampler, clamp(uv + off2, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
      varSum += dot(c2 - mean, c2 - mean);
    }
    if (varSum < bestVar) {
      bestVar = varSum;
      bestCol = mean;
    }
  }
  textureStore(dataTextureA, pixel, vec4<f32>(bestCol, 1.0));
}
