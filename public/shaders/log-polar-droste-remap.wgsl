// ═══ LOG-POLAR DROSTE — REMAP ═════════════════════════════════════════════

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

fn drosteUv(uv: vec2<f32>, time: f32, zoom: f32, spiral: f32) -> vec2<f32> {
  let c = uv - vec2<f32>(0.5);
  let r = length(c);
  let a = atan2(c.y, c.x);
  let logR = log(max(r, 1e-4));
  let twist = spiral * 2.0;
  let lr = fract((logR - time * zoom * 0.15) / 0.35) * 0.35;
  let ang = a + lr * twist + time * 0.1;
  let nr = exp(lr);
  return clamp(vec2<f32>(0.5) + vec2<f32>(cos(ang), sin(ang)) * nr * 0.45, vec2<f32>(0.02), vec2<f32>(0.98));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let zoom = mix(0.2, 1.2, u.zoom_params.x + plasmaBuffer[0].x * 0.15);
  let spiral = mix(0.0, 2.5, u.zoom_params.y);
  let depth = mix(1.0, 4.0, u.zoom_params.z);
  var col = vec3<f32>(0.0);
  var wsum = 0.0;
  for (var i = 0; i < i32(depth); i = i + 1) {
    let t = f32(i) / max(depth - 1.0, 1.0);
    let su = drosteUv(uv, time + t * 0.2, zoom, spiral);
    let s = textureSampleLevel(readTexture, u_sampler, su, 0.0);
    let w = 1.0 / (1.0 + t * 2.0);
    col += s.rgb * w;
    wsum += w;
  }
  col /= max(wsum, 0.001);
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
}
