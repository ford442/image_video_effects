// ═══ OPTICAL FLOW DREAM — ADVECT ═══════════════════════════════════════════
//  Reads packed flow in .a, advects dream.rgb. Repeat 2×.

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
  let st = textureLoad(dataTextureC, pixel, 0);
  let flow = unpack2x16float(bitcast<u32>(st.a));
  let mouse = u.zoom_config.yz;
  var steer = flow;
  steer += (mouse - uv) * 0.004 * u.zoom_params.x;

  let nRipple = min(u32(u.config.y), 50u);
  let time = u.config.x;
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age > 0.0 && age < 0.6) {
      let d = uv - rp.xy;
      let r = length(d) + 0.0001;
      steer += normalize(d) * 0.02 * exp(-r * 18.0) * (1.0 - age / 0.6);
    }
  }

  let srcUv = clamp(uv - steer, vec2<f32>(0.001), vec2<f32>(0.999));
  let srcPx = vec2<i32>(srcUv * res);
  let sampled = textureLoad(dataTextureC, clamp(srcPx, vec2<i32>(0), resI - vec2<i32>(1)), 0);
  let decay = mix(0.82, 0.985, u.zoom_params.y) + plasmaBuffer[0].x * 0.02;
  let cur = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var dream = mix(sampled.rgb, cur.rgb, 0.04);
  dream *= clamp(decay, 0.7, 0.995);
  let packed = bitcast<f32>(pack2x16float(clamp(flow, vec2<f32>(-4.0), vec2<f32>(4.0))));
  textureStore(dataTextureA, pixel, vec4<f32>(clamp(dream, vec3<f32>(0.0), vec3<f32>(4.0)), packed));
}
