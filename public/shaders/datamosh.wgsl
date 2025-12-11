// Motion Vector Datamoshing - compute skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // motion vectors (renderer expects RGBA storage)
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // smear buffer
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
  let coord_i = vec2<i32>(i32(gid.x), i32(gid.y));
  let cur = textureLoad(readTexture, coord_i, 0);
  // placeholder motion vector: small shift based on time
  let motion = vec2<f32>(sin(u.config.x * 0.1) * 2.0, cos(u.config.x * 0.1) * 2.0);
  textureStore(dataTextureA, coord_i, vec4<f32>(motion, 0.0, 0.0));

  // smear using the motion vector
  let smeared_x = i32(i32(coord_i.x) - i32(motion.x));
  let smeared_y = i32(i32(coord_i.y) - i32(motion.y));
  let dim = textureDimensions(readTexture);
  let x = (smeared_x + i32(dim.x)) % i32(dim.x);
  let y = (smeared_y + i32(dim.y)) % i32(dim.y);
  let smeared = textureLoad(readTexture, vec2<i32>(x, y), 0);
  let mixed = mix(cur, smeared, 0.1);
  textureStore(dataTextureB, coord_i, mixed);
  textureStore(writeTexture, coord_i, mixed);
}
