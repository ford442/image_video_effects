// ═══ PREDATOR-PREY ECOLOGY — STEP (Lotka–Volterra CA) ═════════════════════
//  A/C packing: .r prey, .g predator, .b nutrient, .a age
//  zoom_params: .x eat rate, .y death, .z mutation, .w breed

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

fn laplaceAt(p: vec2<i32>, resI: vec2<i32>, ch: i32) -> f32 {
  let c = load(p, resI);
  let n = load(p + vec2<i32>(0, 1), resI);
  let s = load(p + vec2<i32>(0, -1), resI);
  let e = load(p + vec2<i32>(1, 0), resI);
  let w = load(p + vec2<i32>(-1, 0), resI);
  let center = select(c.g, c.r, ch == 0);
  let sum = select(n.g + s.g + e.g + w.g, n.r + s.r + e.r + w.r, ch == 0);
  return sum * 0.25 - center;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let eat = mix(0.08, 0.45, u.zoom_params.x) + mid * 0.04;
  let death = mix(0.02, 0.18, u.zoom_params.y);
  let mutate = mix(0.0, 0.12, u.zoom_params.z + bass * 0.05);
  let breed = mix(0.05, 0.35, u.zoom_params.w);

  var st = load(pixel, resI);
  var prey = st.r;
  var pred = st.g;
  var nutrient = st.b;
  var age = st.a;

  if (time < 0.08) {
    prey = 0.15 + nutrient * 0.1;
    pred = 0.05;
  }

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  nutrient = mix(nutrient, dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114)), 0.04);

  let lapP = laplaceAt(pixel, resI, 0);
  let lapPred = laplaceAt(pixel, resI, 1);

  // Lotka–Volterra style local update
  let growth = prey * (nutrient * 0.8 + 0.1 - pred * eat);
  let predGrowth = pred * (prey * eat * 1.2 - death);
  prey = clamp(prey + growth * 0.35 + lapP * 0.12 + mutate * nutrient, 0.0, 1.5);
  pred = clamp(pred + predGrowth * 0.3 + lapPred * 0.08, 0.0, 1.2);

  if (held && length(uv - mouse) < 0.08) {
    prey += breed * 0.25;
    pred += breed * 0.08;
  }

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let ageR = time - rp.z;
    if (ageR > 0.0 && ageR < 0.35 && length(uv - rp.xy) < 0.04) {
      prey += (1.0 - ageR / 0.35) * breed * 0.4;
    }
  }

  age = fract(age + 0.002 + pred * 0.001);
  textureStore(dataTextureA, pixel, vec4<f32>(prey, pred, nutrient, age));
}
