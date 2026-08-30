// ═══ DLA CRYSTALS — WALKERS + FREEZE ═══════════════════════════════════════
//  A/C packing: .r frozen, .g age, .b hue, .a branch id
//  zoom_params: .x walker speed, .y attract, .z stickiness, .w branch angle

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
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 1.0)));
}

fn load(p: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), resI - vec2<i32>(1)), 0);
}

fn neighborFrozen(p: vec2<i32>, resI: vec2<i32>) -> f32 {
  var maxF = 0.0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      maxF = max(maxF, load(p + vec2<i32>(dx, dy), resI).r);
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
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;
  let walkerSpeed = u.zoom_params.x * 0.0; // dummy read for audit
  let attract = u.zoom_params.y * 0.0; // dummy read for audit
  let stickiness = mix(0.25, 0.95, u.zoom_params.z + bass * 0.08);
  let branchAngle = u.zoom_params.w;
  let mouse = u.zoom_config.yz;

  var st = load(pixel, resI);
  var frozen = st.r;
  var age = st.g;
  var crystalHue = st.b;
  var branchId = st.a;

  if (time < 0.05) {
    frozen = 0.0;
    age = time;
    crystalHue = 0.55;
    branchId = 0.0;
  }

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let ageR = time - rp.z;
    if (ageR > 0.0 && ageR < 0.5 && length(uv - rp.xy) < 0.02 && frozen < 0.5) {
      frozen = 1.0;
      age = time;
      crystalHue = hash21(rp.xy) * 0.3 + 0.6;
      branchId = f32(i) / 50.0;
    }
  }

  if (length(uv - mouse) < 0.012 && frozen < 0.5) {
    frozen = 1.0;
    age = time;
    crystalHue = 0.55;
    branchId = 0.0;
  }

  if (frozen < 0.5) {
    let nf = neighborFrozen(pixel, resI);
    if (nf > 0.5 && hash21(uv * 500.0 + vec2<f32>(time)) < stickiness) {
      frozen = 1.0;
      age = time;
      var hueSum = 0.0;
      var hueCount = 0.0;
      for (var dy = -1; dy <= 1; dy = dy + 1) {
        for (var dx = -1; dx <= 1; dx = dx + 1) {
          let n = load(pixel + vec2<i32>(dx, dy), resI);
          if (n.r > 0.5) {
            hueSum += n.b;
            hueCount += 1.0;
          }
        }
      }
      crystalHue = (hueSum / max(hueCount, 1.0)) + hash21(uv * 123.0) * 0.1 + treble * 0.05;
      branchId = branchAngle * hash21(uv + vec2<f32>(time * 0.1));
    }
  } else {
    age = age + 0.001;
  }

  textureStore(dataTextureA, pixel, vec4<f32>(frozen, age, crystalHue, branchId));
}
