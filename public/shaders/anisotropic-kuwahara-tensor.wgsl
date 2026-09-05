// ═══ ANISOTROPIC KUWAHARA — STRUCTURE TENSOR ═══════════════════════════════

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

fn lum(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let texel = 1.0 / res;
  var gx = 0.0;
  var gy = 0.0;
  let sobelX = array<f32, 9>(-1.0, 0.0, 1.0, -2.0, 0.0, 2.0, -1.0, 0.0, 1.0);
  let sobelY = array<f32, 9>(-1.0, -2.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 1.0);
  var idx = 0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let s = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(f32(dx), f32(dy)) * texel, 0.0);
      let l = lum(s.rgb);
      gx += l * sobelX[idx];
      gy += l * sobelY[idx];
      idx += 1;
    }
  }
  let a = gx * gx;
  let b = gx * gy;
  let d = gy * gy;
  let trace = a + d;
  let det = a * d - b * b;
  let disc = sqrt(max(trace * trace * 0.25 - det, 0.0));
  let l2 = trace * 0.5 - disc;
  var flow = vec2<f32>(1.0, 0.0);
  if (abs(b) > 0.0001) { flow = normalize(vec2<f32>(l2 - d, b)); }
  let mouse = u.zoom_config.yz;
  let toM = uv - mouse;
  let md = length(toM);
  let flowStr = u.zoom_params.w;
  if (md < 0.15 && md > 0.001) {
    flow = mix(flow, vec2<f32>(-toM.y, toM.x) / md, (1.0 - md / 0.15) * flowStr);
  }
  textureStore(dataTextureA, pixel, vec4<f32>(flow.x, flow.y, length(flow), 1.0));
}
