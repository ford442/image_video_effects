// Melting Oil Painting (Gradient Flow) - minimal skeleton
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
  config: vec4<f32>,       // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=zoomTime, y=mouseX, z=mouseY, w=unused
  zoom_params: vec4<f32>,  // x=param1, y=param2, z=param3, w=param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let id = vec2<u32>(gid.xy);
  let coord = vec2<i32>(i32(id.x), i32(id.y));
  let dim = textureDimensions(dataTextureA);
  // 3x3 Sobel gradient sample adapted to dataTextureA
  var h: array<f32, 9>;
  var k: u32 = 0u;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let sample = textureLoad(readTexture, vec2<i32>(i32(coord.x + vec2<i32>(i,i).x), i32(coord.y + vec2<i32>(j,j).y)), 0).r;
      h[k] = sample;
      k = k + 1u;
    }
  }
  let gx = (h[2] + 2.0*h[5] + h[8]) - (h[0] + 2.0*h[3] + h[6]);
  let gy = (h[6] + 2.0*h[7] + h[8]) - (h[0] + 2.0*h[1] + h[2]);
  let flow_dir = normalize(vec2<f32>(gx, gy));
  let viscosity = 0.92;
  let last_pos = vec2<f32>(f32(coord.x), f32(coord.y)) - flow_dir * viscosity;
  let color = textureSampleLevel(readTexture, u_sampler, last_pos / vec2<f32>(dim), 0.0);
  let flow_speed = length(vec2<f32>(gx, gy));
  let hue_shift = flow_speed * 0.1 + u.config.x * 0.01;
  let shifted = vec4<f32>(color.rgb * vec3<f32>(sin(hue_shift), cos(hue_shift), 1.0), color.a);
  textureStore(dataTextureB, coord, shifted);
  let current_height = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0).r;
  textureStore(dataTextureA, coord, vec4<f32>(current_height * 0.999, 0.0, 0.0, 0.0));
  textureStore(writeTexture, id, shifted);
}
