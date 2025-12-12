// Voronoi Tessellation Reconstruction - JFA-friendly skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // voronoi output
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // feature map
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
  let coord = vec2<u32>(gid.xy);
  let size = textureDimensions(readTexture);
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  
  // Mouse position as seed point
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  
  // Simple feature detection near pixel; fill features with first bright pixel
  var nearest = vec2<u32>(coord);
  var min_dist: f32 = 1e6;
  
  // Add mouse position as a feature point
  let mouse_coord = mouse_pos * vec2<f32>(f32(size.x), f32(size.y));
  let dist_to_mouse = distance(vec2<f32>(f32(coord.x), f32(coord.y)), mouse_coord);
  if (dist_to_mouse < min_dist) {
    min_dist = dist_to_mouse;
    nearest = vec2<u32>(u32(mouse_coord.x), u32(mouse_coord.y));
  }
  
  // Add ripple positions as dynamic feature centers
  for (var r = 0; r < 50; r++) {
    let ripple = u.ripples[r];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 4.0) {
        let ripple_coord = ripple.xy * vec2<f32>(f32(size.x), f32(size.y));
        let dist_to_ripple = distance(vec2<f32>(f32(coord.x), f32(coord.y)), ripple_coord);
        if (dist_to_ripple < min_dist) {
          min_dist = dist_to_ripple;
          nearest = vec2<u32>(u32(ripple_coord.x), u32(ripple_coord.y));
        }
      }
    }
  }
  
  for (var dy: i32 = -2; dy <= 2; dy = dy + 1) {
    for (var dx: i32 = -2; dx <= 2; dx = dx + 1) {
      let sx = clamp(i32(coord.x) + dx, 0, i32(size.x) - 1);
      let sy = clamp(i32(coord.y) + dy, 0, i32(size.y) - 1);
      let sample = textureLoad(readTexture, vec2<i32>(sx, sy), 0);
      let lum = dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));
      if (lum > 0.8) {
        let d = distance(vec2<f32>(f32(coord.x), f32(coord.y)), vec2<f32>(f32(sx), f32(sy)));
        if (d < min_dist) {
          min_dist = d;
          nearest = vec2<u32>(u32(sx), u32(sy));
        }
      }
    }
  }
  let color = textureLoad(readTexture, vec2<i32>(i32(nearest.x), i32(nearest.y)), 0);
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), color);
}
