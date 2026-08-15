// ═══ GRAY-SCOTT TANK — INJECT ══════════════════════════════════════════════
//  Hold paints V; clicks seed spots; seed-mask in .a

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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let seed = mix(0.2, 1.0, u.zoom_params.w);
  var st = textureLoad(dataTextureC, pixel, 0);
  var U = st.r;
  var V = st.g;
  var mask = st.a;

  let md = length(uv - mouse);
  if (held && md < 0.045) {
    let w = smoothstep(0.045, 0.0, md) * seed;
    V = clamp(V + w * 0.55, 0.0, 1.0);
    U = clamp(U - w * 0.25, 0.0, 1.0);
    mask = max(mask, w);
  }

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age > 0.0 && age < 0.25) {
      let d = length(uv - rp.xy);
      let punch = smoothstep(0.03, 0.0, d) * seed * (1.0 - age / 0.25);
      V = clamp(V + punch * 0.8, 0.0, 1.0);
      U = clamp(U * (1.0 - punch * 0.4), 0.0, 1.0);
    }
  }

  // Sparse spontaneous seeds so the tank never dies in attract mode.
  if (hash21(uv * 17.0 + floor(time * 0.7)) > 0.997) {
    V = clamp(V + 0.35 * seed, 0.0, 1.0);
  }

  textureStore(dataTextureA, pixel, vec4<f32>(clamp(U, 0.0, 1.0), clamp(V, 0.0, 1.0), st.b, clamp(mask * 0.96, 0.0, 1.0)));
}
