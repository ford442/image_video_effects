// Motion Vector Datamoshing - compute skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // motion vectors
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // smear buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

fn optical_flow_impl(gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let cur = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  let dim = textureDimensions(readTexture);
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let time = u.config.x;
  
  // Mouse-influenced search offsets
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let to_mouse = mouse_pos - uv;
  let mouse_offset = to_mouse * 5.0;
  
  // placeholder motion vector: small shift based on time + mouse influence
  var motion = vec2<f32>(sin(time * 0.1) * 2.0, cos(time * 0.1) * 2.0);
  motion += mouse_offset;
  
  textureStore(dataTextureA, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(motion, 0.0, 0.0));
}

@compute @workgroup_size(8, 8, 1)
fn apply_smear(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let motion = textureLoad(dataTextureC, vec2<i32>(i32(coord.x), i32(coord.y)), 0).rg;
  let dim = textureDimensions(readTexture);
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let time = u.config.x;
  
  // Trigger local smear accumulation on ripple events
  var smear_strength = 0.1;
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 3.0) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.15) {
          smear_strength = 0.5 * (1.0 - ripple_age / 3.0);
        }
      }
    }
  }
  
  let smeared_coord = vec2<i32>(i32(coord.x) - i32(motion.x), i32(coord.y) - i32(motion.y));
  let x = (smeared_coord.x + i32(dim.x)) % i32(dim.x);
  let y = (smeared_coord.y + i32(dim.y)) % i32(dim.y);
  let smeared = textureLoad(readTexture, vec2<i32>(x, y), 0);
  let cur = textureLoad(dataTextureC, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  let mixed = mix(cur, smeared, smear_strength);
  textureStore(dataTextureB, vec2<i32>(i32(coord.x), i32(coord.y)), mixed);
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), mixed);
}

// Main entrypoint for compatibility - run primary optical flow pass
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  optical_flow_impl(gid);
}
