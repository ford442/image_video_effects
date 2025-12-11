// Audio-Visual Spectrogram Displacement - compute skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // audio texture
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

const SPECTRUM_BANDS: u32 = 128u;
struct Uniforms {
  config: vec4<f32>,       // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=zoomTime, y=mouseX, z=mouseY, w=unused
  zoom_params: vec4<f32>,  // x=param1, y=param2, z=param3, w=param4
  ripples: array<vec4<f32>, 50>,
};
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let dim = textureDimensions(readTexture);
  let freq = f32(coord.y) / f32(dim.y) * f32(SPECTRUM_BANDS);
  let band = u32(freq) % SPECTRUM_BANDS;
  let magnitude = textureLoad(dataTextureC, vec2<i32>(i32(band), 0), 0).r;
  let src = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  var displaced_x = i32(coord.x) - i32(magnitude * src.r * 10.0);
  var displaced_xb = i32(coord.x) + i32(magnitude * src.b * 10.0);
  displaced_x = (displaced_x + i32(dim.x)) % i32(dim.x);
  displaced_xb = (displaced_xb + i32(dim.x)) % i32(dim.x);
  let disp = textureLoad(readTexture, vec2<i32>(displaced_x, i32(coord.y)), 0);
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), disp);
}
