/** Chore WGSL — not catalog effects. Do not register in shader_definitions/. */

export const HISTOGRAM_WGSL = /* wgsl */ `
@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var<storage, read_write> bins: array<atomic<u32>>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = textureDimensions(src);
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let c = textureLoad(src, vec2<i32>(gid.xy), 0);
  let y = dot(c.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let t = clamp(y, 0.0, 1.0);
  var bin = u32(floor(t * 256.0));
  if (bin > 255u) { bin = 255u; }
  atomicAdd(&bins[bin], 1u);
}
`;

export const REDUCE_WGSL = /* wgsl */ `
struct ReduceAcc {
  min_q: atomic<u32>,
  max_q: atomic<u32>,
  sum_q: atomic<u32>,
  count: atomic<u32>,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var<storage, read_write> acc: ReduceAcc;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = textureDimensions(src);
  let n = dims.x * dims.y;
  if (gid.x >= n) { return; }
  let x = gid.x % dims.x;
  let y = gid.x / dims.x;
  let c = textureLoad(src, vec2<i32>(i32(x), i32(y)), 0);
  let luma = clamp(dot(c.rgb, vec3<f32>(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
  let q = u32(luma * 65535.0 + 0.5);
  atomicMin(&acc.min_q, q);
  atomicMax(&acc.max_q, q);
  atomicAdd(&acc.sum_q, q);
  atomicAdd(&acc.count, 1u);
}
`;

export const LUT_WGSL = /* wgsl */ `
@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var dst: texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(2) var<storage, read> lut: array<u32>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = textureDimensions(dst);
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let srcDims = textureDimensions(src);
  let u = (f32(gid.x) + 0.5) / f32(dims.x);
  let v = (f32(gid.y) + 0.5) / f32(dims.y);
  let sx = i32(clamp(u * f32(srcDims.x), 0.0, f32(srcDims.x) - 1.0));
  let sy = i32(clamp(v * f32(srcDims.y), 0.0, f32(srcDims.y) - 1.0));
  let c = textureLoad(src, vec2<i32>(sx, sy), 0);
  let y = clamp(dot(c.rgb, vec3<f32>(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
  var bin = u32(floor(y * 256.0));
  if (bin > 255u) { bin = 255u; }
  let band = f32(lut[bin] & 255u) / 255.0;
  textureStore(dst, vec2<i32>(gid.xy), vec4<f32>(band, band, band, 1.0));
}
`;

export const DOWNSAMPLE_WGSL = /* wgsl */ `
struct DownsampleParams {
  src_size: vec2<u32>,
  dst_size: vec2<u32>,
  gain: f32,
  _pad: f32,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var dst: texture_storage_2d<rgba16float, write>;
@group(0) @binding(2) var<uniform> params: DownsampleParams;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= params.dst_size.x || gid.y >= params.dst_size.y) { return; }
  let x0 = (gid.x * params.src_size.x) / params.dst_size.x;
  let x1 = max(x0 + 1u, ((gid.x + 1u) * params.src_size.x) / params.dst_size.x);
  let y0 = (gid.y * params.src_size.y) / params.dst_size.y;
  let y1 = max(y0 + 1u, ((gid.y + 1u) * params.src_size.y) / params.dst_size.y);
  var acc = vec4<f32>(0.0);
  var n = 0.0;
  var y = y0;
  loop {
    if (y >= y1 || y >= params.src_size.y) { break; }
    var x = x0;
    loop {
      if (x >= x1 || x >= params.src_size.x) { break; }
      acc += textureLoad(src, vec2<i32>(i32(x), i32(y)), 0);
      n += 1.0;
      x = x + 1u;
    }
    y = y + 1u;
  }
  let avg = acc / max(n, 1.0);
  textureStore(dst, vec2<i32>(gid.xy), vec4<f32>(avg.rgb * params.gain, avg.a));
}
`;
