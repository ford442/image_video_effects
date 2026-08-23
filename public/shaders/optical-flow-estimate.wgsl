// ═══ OPTICAL FLOW DREAM — FLOW ESTIMATE ════════════════════════════════════
//  Binding 13 history ring. Packs dream.rgb + pack2x16float(flow) in .a
//  extraBuffer[4] = history head (read-only). zoom_params: flow, decay, chroma, mix

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
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let head = u32(extraBuffer[4]) % HISTORY_DEPTH;
  let scale = mix(0.4, 3.2, u.zoom_params.x);
  let cur = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let prevLayer = (head + HISTORY_DEPTH - 1u) % HISTORY_DEPTH;
  let prev = textureLoad(historyTexture, pixel, prevLayer, 0);
  let older = textureLoad(historyTexture, pixel, (head + HISTORY_DEPTH - 3u) % HISTORY_DEPTH, 0);

  var flow = vec2<f32>(0.0);
  let stepPx = 2;
  let c0 = luma(prev.rgb);
  let cx = luma(textureLoad(historyTexture, clamp(pixel + vec2<i32>(stepPx, 0), vec2<i32>(0), resI - vec2<i32>(1)), prevLayer, 0).rgb);
  let cy = luma(textureLoad(historyTexture, clamp(pixel + vec2<i32>(0, stepPx), vec2<i32>(0), resI - vec2<i32>(1)), prevLayer, 0).rgb);
  let gx = cx - c0;
  let gy = cy - c0;
  let it = luma(cur.rgb) - luma(prev.rgb);
  let mag = gx * gx + gy * gy + 0.0004;
  flow = vec2<f32>(-gx, -gy) * it / mag * scale * 0.015;
  flow += (older.rg - prev.rg) * 0.08 * scale;

  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let dm = uv - mouse;
  if (held) {
    flow *= mix(0.15, 0.55, smoothstep(0.0, 0.25, length(dm)));
  }

  var dream = textureLoad(dataTextureC, pixel, 0).rgb;
  if (dot(dream, dream) < 0.0001) {
    dream = mix(cur.rgb, prev.rgb, 0.5);
  }
  let packed = bitcast<f32>(pack2x16float(clamp(flow, vec2<f32>(-4.0), vec2<f32>(4.0))));
  textureStore(dataTextureA, pixel, vec4<f32>(clamp(dream, vec3<f32>(0.0), vec3<f32>(4.0)), packed));
}
