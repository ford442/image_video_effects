// ═══ DLA CRYSTALS — RENDER (graph node 3 of 3) ═════════════════════════════
//  Reads the freeze mask through dataC (A → C copy before this node).
//  Upgrade ideas: (1) accretion flash — freshly frozen tips burn white-hot and
//  cool into their hue, (2) rim light on the growth front (fewer frozen
//  neighbours = brighter edge), (3) walker dust drawn as a faint blue haze,
//  (4) treble sparkle on the crystal body.
//  Audio: extraBuffer[0] bass, extraBuffer[2] treble (read only).

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

fn hue2rgb(h: f32) -> vec3<f32> {
  let k = vec3<f32>(0.0, 2.0 / 3.0, 1.0 / 3.0);
  return clamp(abs(fract(vec3<f32>(h) + k) * 6.0 - 3.0) - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn frozenNeighbours(p: vec2<i32>, resI: vec2<i32>) -> f32 {
  var count = 0.0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let q = clamp(p + vec2<i32>(dx, dy), vec2<i32>(0), resI - vec2<i32>(1));
      count += step(0.5, textureLoad(dataTextureC, q, 0).r);
    }
  }
  return count;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let bass = extraBuffer[0];
  let treble = extraBuffer[2];
  let st = textureLoad(dataTextureC, pixel, 0);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  var col = src.rgb * (0.5 + bass * 0.1);
  if (st.r > 0.5) {
    let base = hue2rgb(fract(st.b + st.a * 0.2)) * 0.85;
    let flash = exp(-st.g * 2.5);
    let rim = 1.0 - frozenNeighbours(pixel, resI) / 8.0;
    col = mix(base, vec3<f32>(1.0, 0.97, 0.9), flash * 0.85);
    col += base * rim * 0.9 + vec3<f32>(rim * 0.12);
    let sparkle = pow(hash21(uv * 1000.0 + vec2<f32>(time * 10.0)), 10.0) * (0.3 + treble * 0.6);
    col += vec3<f32>(sparkle);
  } else {
    col += vec3<f32>(0.25, 0.55, 1.0) * st.a * 0.35;
  }

  textureStore(writeTexture, pixel, vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(2.0)), 1.0));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
