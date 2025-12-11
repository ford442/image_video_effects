// Navier-Stokes Dye Injection - simplified compute skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rg32float, write>; // velocity
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // dye
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

const DT: f32 = 0.016;
fn advect_velocity(gid: vec3<u32>) {
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let vel = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0).rg;
  let pos = vec2<f32>(f32(coord.x), f32(coord.y));
  let sourcePos = pos - vel * DT;
  let dim_i = textureDimensions(readTexture);
  let dim = vec2<f32>(f32(dim_i.x), f32(dim_i.y));
  let res = textureSampleLevel(readTexture, u_sampler, sourcePos / dim, 0.0).rg;
  textureStore(dataTextureA, coord, vec4<f32>(res, 0.0, 0.0));
}

fn inject_dye(gid: vec3<u32>) {
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let src = textureLoad(readTexture, coord, 0);
  // Simple dye injection: shift saturation by velocity curl approximate
  let velL = textureLoad(readTexture, vec2<i32>(i32(coord.x - 1), i32(coord.y)), 0).rg;
  let velR = textureLoad(readTexture, vec2<i32>(i32(coord.x + 1), i32(coord.y)), 0).rg;
  let velT = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y - 1)), 0).rg;
  let velB = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y + 1)), 0).rg;
  let curl = (velR.y - velL.y) - (velB.x - velT.x);
  let hsv_saturation = min(length(vec3<f32>(curl)) * 10.0, 1.0);
  let shifted_color = vec3<f32>(src.rgb * (1.0 + hsv_saturation));
  let cur = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  textureStore(dataTextureB, coord, vec4<f32>(mix(cur.rgb, shifted_color, 0.1), 1.0));
  textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(shifted_color, 1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  advect_velocity(gid);
  inject_dye(gid);
}
