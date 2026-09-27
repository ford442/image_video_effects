// ═══ DLA CRYSTALS — SEED + RENDER ═════════════════════════════════════════
//  Reads the frozen field after the walker pass (dataA → dataC barrier),
//  plants seeds (centre on ring re-arm, pointer, ripples), draws crystal +
//  fading walker trails, and carries the field forward in dataA.
//  A/C packing: .r frozen, .g freeze time (frozen) / last visit time (free),
//               .b hue, .a branch id

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

struct SimParams {
  stateCount: u32,
  indexCount: u32,
  frame: u32,
  truncated: u32,
};

@group(1) @binding(2) var<uniform> simParams: SimParams;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn hueToRgb(hue: f32, c: f32) -> vec3<f32> {
  let h = fract(hue) * 6.0;
  let x = c * (1.0 - abs((h % 2.0) - 1.0));
  if (h < 1.0) { return vec3<f32>(c, x, 0.0); }
  if (h < 2.0) { return vec3<f32>(x, c, 0.0); }
  if (h < 3.0) { return vec3<f32>(0.0, c, x); }
  if (h < 4.0) { return vec3<f32>(0.0, x, c); }
  if (h < 5.0) { return vec3<f32>(x, 0.0, c); }
  return vec3<f32>(c, 0.0, x);
}

fn neighborFrozen(p: vec2<i32>, resI: vec2<i32>) -> f32 {
  var maxF = 0.0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let n = textureLoad(dataTextureC, clamp(p + vec2<i32>(dx, dy), vec2<i32>(0), resI - vec2<i32>(1)), 0);
      maxF = max(maxF, n.r);
    }
  }
  return maxF;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let treble = plasmaBuffer[0].z;
  let attractStrength = mix(0.0, 0.5, u.zoom_params.y);
  var st = textureLoad(dataTextureC, pixel, 0);

  // Ring (re)armed → clear the previous shader's field and plant a centre seed.
  if (simParams.frame == 0u) {
    st = vec4<f32>(0.0);
    if (length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0)) < 0.006) {
      st = vec4<f32>(1.0, time, 0.55, 0.0);
    }
  }

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let ageR = time - rp.z;
    if (ageR > 0.0 && ageR < 0.5 && length((uv - rp.xy) * vec2<f32>(aspect, 1.0)) < 0.02 && st.r < 0.5) {
      st = vec4<f32>(1.0, time, hash21(rp.xy) * 0.3 + 0.6, f32(i) / 50.0);
    }
  }

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  if (mouseDown && length((uv - mouse) * vec2<f32>(aspect, 1.0)) < 0.012 + attractStrength * 0.02 && st.r < 0.5) {
    st = vec4<f32>(1.0, time, 0.55, 0.0);
  }

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  var col = src.rgb * 0.65;
  if (st.r > 0.5) {
    let rgb = hueToRgb(st.b + st.a * 0.2, 0.8);
    let glow = exp(-max(time - st.g, 0.0) * 0.4) * 0.4 + 0.6;
    let edge = 1.0 - neighborFrozen(pixel, resI);
    col = rgb * glow + vec3<f32>(edge * 0.35);
    let sparkle = pow(hash21(uv * 1000.0 + vec2<f32>(time * 10.0)), 8.0) * (0.35 + treble * 0.25);
    col += vec3<f32>(sparkle);
  } else if (st.g > 0.0) {
    // Walker trail: brightest where a walker just passed, fading over ~0.3 s.
    let trail = exp(-max(time - st.g, 0.0) * 8.0);
    col += hueToRgb(st.b, 0.6) * trail * 0.45;
  }

  textureStore(writeTexture, pixel, vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.5)), 1.0));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, st);
}
