// Motion Vector Datamoshing - compute skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rg32float, write>; // motion vectors
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // smear buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

@compute @workgroup_size(8, 8, 1)
fn optical_flow(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let cur = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  // placeholder motion vector: small shift based on time
  let motion = vec2<f32>(sin(u.config.x * 0.1) * 2.0, cos(u.config.x * 0.1) * 2.0);
  textureStore(dataTextureA, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(motion, 0.0, 0.0));
}

@compute @workgroup_size(8, 8, 1)
fn apply_smear(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let motion = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0).rg;
  let smeared_coord = vec2<i32>(i32(coord.x) - i32(motion.x), i32(coord.y) - i32(motion.y));
  let dim = textureDimensions(readTexture);
  let x = (smeared_coord.x + i32(dim.x)) % i32(dim.x);
  let y = (smeared_coord.y + i32(dim.y)) % i32(dim.y);
  let smeared = textureLoad(readTexture, vec2<i32>(x, y), 0);
  let cur = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  let mixed = mix(cur, smeared, 0.1);
  textureStore(dataTextureB, vec2<i32>(i32(coord.x), i32(coord.y)), mixed);
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), mixed);
}
