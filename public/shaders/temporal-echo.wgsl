// Temporal Echo Feedback Buffer - minimal skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // feedback buffer
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // history 3D emulated by slices
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let id = vec2<u32>(gid.xy);
  let dim = textureDimensions(readTexture);
  let uv = vec2<f32>(f32(id.x), f32(id.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let time = u.config.x;
  
  let current = textureLoad(readTexture, coord, 0);
  // frame index approximated by u.config.x time (mod 60)
  let frame_idx = i32(time) % 60;
  // store current into a slice emulated via dataTextureB using y offset
  let slice_y = i32(frame_idx);
  textureStore(dataTextureB, vec2<i32>(coord.x, coord.y + slice_y), current);
  
  // Mouse-controlled history offset parameter
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let history_offset_factor = distance(uv, mouse_pos);
  
  // sample a past slice by brightness and mouse
  let brightness = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));
  var history_offset = i32(brightness * 59.0);
  history_offset = i32(f32(history_offset) * (1.0 + history_offset_factor));
  
  // Ripples pin frames into history
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 5.0) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.1) {
          history_offset = i32(ripple_age * 10.0);
        }
      }
    }
  }
  
  let past_y = clamp(slice_y - history_offset, 0, 59);
  let past = textureLoad(dataTextureC, vec2<i32>(coord.x, coord.y + past_y), 0);
  let feedback = textureLoad(dataTextureC, coord, 0);
  let new_feedback = mix(past, current, 0.05);
  textureStore(dataTextureA, coord, new_feedback);
  textureStore(writeTexture, id, new_feedback);
}
