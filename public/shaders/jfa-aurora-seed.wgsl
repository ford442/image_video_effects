// ═══ JFA AURORA — SEED ══════════════════════════════════════════════════════

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
  let seedStr = mix(0.05, 0.35, u.zoom_params.w + plasmaBuffer[0].x * 0.1);

  var seed = vec2<f32>(-1.0, -1.0);
  var dist2 = 1e6;
  var sid = -1.0;

  if (length(uv - mouse) < seedStr) {
    seed = mouse;
    dist2 = 0.0;
    sid = 0.0;
  }

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age > 0.0 && age < 0.6) {
      let d = length(uv - rp.xy);
      if (d < seedStr * 1.2) {
        seed = rp.xy;
        dist2 = 0.0;
        sid = f32(i) / 50.0;
      }
    }
  }

  if (seed.x < 0.0) {
    let h = hash21(uv * 97.0 + vec2<f32>(time * 0.02));
    if (h < mix(0.002, 0.02, u.zoom_params.z)) {
      seed = uv;
      dist2 = 0.0;
      sid = h;
    }
  }

  textureStore(dataTextureA, pixel, vec4<f32>(seed, dist2, sid));
}
